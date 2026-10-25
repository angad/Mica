#include "Hardware.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/ps/IOPSKeys.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include <mach/mach.h>
#include <mach/processor_info.h>
#include <sys/sysctl.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/route.h>
#include <ifaddrs.h>
#include <string.h>
#include <dlfcn.h>
#include <math.h>
#include <stdlib.h>
#include <stdio.h>
#include <time.h>
#include <limits.h>

// The default IOKit port is MACH_PORT_NULL on both old Intel and current Macs.
// Avoid a link-time dependency on the macOS 12 default-port symbol.
#define GM_IO_PORT ((mach_port_t)0)

static double number(CFDictionaryRef d, CFStringRef key, double fallback) {
    if (!d) return fallback;
    CFTypeRef value = CFDictionaryGetValue(d, key);
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID()) return fallback;
    double result = fallback; CFNumberGetValue(value, kCFNumberDoubleType, &result); return result;
}
static CFDictionaryRef dictionary(CFDictionaryRef d, CFStringRef key) {
    CFTypeRef value = d ? CFDictionaryGetValue(d, key) : NULL;
    return value && CFGetTypeID(value) == CFDictionaryGetTypeID() ? value : NULL;
}
static int boolean(CFDictionaryRef d, CFStringRef key) {
    CFTypeRef value = d ? CFDictionaryGetValue(d, key) : NULL;
    return value && CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue(value);
}
static void read_cpu(GMSample *s) {
    processor_info_array_t info = NULL; mach_msg_type_number_t count = 0; natural_t cores = 0;
    if (host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cores, &info, &count) != KERN_SUCCESS) return;
    s->core_count = cores > GM_MAX_CORES ? GM_MAX_CORES : (int)cores; s->cpu_valid = 1;
    for (int i = 0; i < s->core_count; i++) {
        s->cores[i] = (GMCore){(uint32_t)info[i*CPU_STATE_MAX+CPU_STATE_USER], (uint32_t)info[i*CPU_STATE_MAX+CPU_STATE_SYSTEM], (uint32_t)info[i*CPU_STATE_MAX+CPU_STATE_IDLE], (uint32_t)info[i*CPU_STATE_MAX+CPU_STATE_NICE]};
    }
    vm_deallocate(mach_task_self(), (vm_address_t)info, count * sizeof(integer_t));
}
static void read_memory(GMSample *s) {
    size_t size = sizeof(s->memory_total); sysctlbyname("hw.memsize", &s->memory_total, &size, NULL, 0);
    vm_statistics64_data_t vm = {0}; mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    vm_size_t page = 0; host_page_size(mach_host_self(), &page);
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vm, &count) != KERN_SUCCESS) return;
    s->memory_valid = 1; s->memory_active = (uint64_t)vm.active_count * page;
    s->memory_wired = (uint64_t)vm.wire_count * page;
    s->memory_compressed = (uint64_t)vm.compressor_page_count * page;
    s->memory_inactive = (uint64_t)vm.inactive_count * page;
    s->memory_free = (uint64_t)(vm.free_count + vm.speculative_count) * page;
    struct xsw_usage swap = {0}; size = sizeof(swap);
    if (!sysctlbyname("vm.swapusage", &swap, &size, NULL, 0)) s->swap_used = swap.xsu_used;
    size = sizeof(s->pressure); sysctlbyname("kern.memorystatus_vm_pressure_level", &s->pressure, &size, NULL, 0);
}
static void read_network(GMSample *s) {
    CFDictionaryRef state = SCDynamicStoreCopyValue(NULL, CFSTR("State:/Network/Global/IPv4"));
    if (!state) state = SCDynamicStoreCopyValue(NULL, CFSTR("State:/Network/Global/IPv6"));
    if (state) {
        CFStringRef primary = CFDictionaryGetValue(state, CFSTR("PrimaryInterface"));
        if (primary && CFGetTypeID(primary) == CFStringGetTypeID()) CFStringGetCString(primary, s->primary_interface, sizeof(s->primary_interface), kCFStringEncodingUTF8);
        CFRelease(state);
    }
    // NET_RT_IFLIST2 supplies 64-bit byte counters. getifaddrs' if_data counters
    // can wrap after only 4 GiB, even when the caller is a 64-bit process.
    int mib[] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0};
    size_t length = 0;
    if (sysctl(mib, 6, NULL, &length, NULL, 0) == 0 && length > 0 && length < 32 * 1024 * 1024) {
        char *buffer = malloc(length);
        if (buffer && sysctl(mib, 6, buffer, &length, NULL, 0) == 0) {
            for (char *cursor = buffer; cursor + sizeof(struct if_msghdr) <= buffer + length;) {
                struct if_msghdr *header = (struct if_msghdr *)cursor;
                if (header->ifm_msglen < sizeof(*header) || cursor + header->ifm_msglen > buffer + length) break;
                if (header->ifm_type == RTM_IFINFO2 && header->ifm_msglen >= sizeof(struct if_msghdr2)
                    && (header->ifm_flags & IFF_UP) && !(header->ifm_flags & IFF_LOOPBACK)
                    && s->interface_count < GM_MAX_INTERFACES) {
                    struct if_msghdr2 *message = (struct if_msghdr2 *)cursor;
                    GMInterface *entry = &s->interfaces[s->interface_count];
                    if (if_indextoname(message->ifm_index, entry->name)) {
                        entry->incoming = message->ifm_data.ifi_ibytes;
                        entry->outgoing = message->ifm_data.ifi_obytes;
                        s->interface_count++;
                    }
                }
                cursor += header->ifm_msglen;
            }
        }
        free(buffer);
        if (s->interface_count > 0) return;
    }
    struct ifaddrs *addresses = NULL;
    if (getifaddrs(&addresses) != 0) return;
    for (struct ifaddrs *p = addresses; p && s->interface_count < GM_MAX_INTERFACES; p = p->ifa_next) {
        if (!p->ifa_addr || p->ifa_addr->sa_family != AF_LINK || !p->ifa_data || !(p->ifa_flags & IFF_UP) || (p->ifa_flags & IFF_LOOPBACK)) continue;
        struct if_data *data = p->ifa_data;
        GMInterface *entry = &s->interfaces[s->interface_count++];
        strlcpy(entry->name, p->ifa_name, sizeof(entry->name));
        entry->incoming = data->ifi_ibytes; entry->outgoing = data->ifi_obytes;
    }
    freeifaddrs(addresses);
}
static void read_disk(GMSample *s) {
    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(GM_IO_PORT, IOServiceMatching("IOBlockStorageDriver"), &iterator) != KERN_SUCCESS) return;
    io_object_t entry;
    while ((entry = IOIteratorNext(iterator))) {
        CFDictionaryRef stats = IORegistryEntryCreateCFProperty(entry, CFSTR("Statistics"), kCFAllocatorDefault, 0);
        if (stats && CFGetTypeID(stats) == CFDictionaryGetTypeID()) {
            double read = number(stats, CFSTR("Bytes (Read)"), -1), write = number(stats, CFSTR("Bytes (Write)"), -1);
            if (read >= 0 && write >= 0) { s->disk_read += (uint64_t)read; s->disk_write += (uint64_t)write; s->disk_valid = 1; }
        }
        if (stats) CFRelease(stats); IOObjectRelease(entry);
    }
    IOObjectRelease(iterator);
}
// Apple IOHID temperature events. Resolve optional symbols at runtime so a future OS
// without this interface reports unavailable rather than failing to launch.
static double monotonic_seconds(void) {
    struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec + now.tv_nsec / 1e9;
}
int gm_sensor_rank(const char *name, const char *selection) {
    if (!selection || !strcmp(selection, "Automatic") || !strcmp(selection, "SOC MTR Temp Sensor0")) {
        if (!strcmp(name, "SOC MTR Temp Sensor0")) return 0;
        if (strcasestr(name, "CPU die")) return 1;
        if (strcasestr(name, "CPU")) return 2;
        if (strcasestr(name, "SOC")) return 3;
        return -1;
    }
    if (!strcmp(selection, "CPU average"))
        return strcasestr(name, "pACC") || strcasestr(name, "eACC") || strcasestr(name, "CPU") ? 0 : -1;
    return !strcmp(name, selection) ? 0 : -1;
}
static int selected_sensor(const GMSensor *sensors, int count, const char *selection) {
    int selected = -1, best = INT_MAX;
    for (int i = 0; i < count; i++) {
        int rank = gm_sensor_rank(sensors[i].name, selection);
        if (rank < 0 || !isfinite(sensors[i].celsius)) continue;
        if (rank < best || (rank == best && selected >= 0 && strcmp(sensors[i].name, sensors[selected].name) < 0)) {
            best = rank; selected = i;
        }
    }
    return selected;
}
static void read_temperature(GMSample *s, const char *selection, int detailed) {
    typedef CFTypeRef (*Create)(CFAllocatorRef);
    typedef void (*SetMatching)(CFTypeRef, CFDictionaryRef);
    typedef CFArrayRef (*CopyServices)(CFTypeRef);
    typedef CFTypeRef (*CopyProperty)(CFTypeRef, CFStringRef);
    typedef CFTypeRef (*CopyEvent)(CFTypeRef, int64_t, int32_t, int64_t);
    typedef double (*FloatValue)(CFTypeRef, int32_t);
    static int initialized = 0; static CFTypeRef client = NULL;
    static CopyServices services; static CopyProperty property; static CopyEvent event; static FloatValue value;
    static CFArrayRef all = NULL;
    static CFTypeRef handles[GM_MAX_SENSORS];
    static GMSensor cached[GM_MAX_SENSORS]; static int count = 0;
    static double discovery = 0, full_read = 0;
    if (!initialized) {
        initialized = 1;
        Create create = (Create)dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientCreate");
        SetMatching match = (SetMatching)dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientSetMatching");
        services = (CopyServices)dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientCopyServices");
        property = (CopyProperty)dlsym(RTLD_DEFAULT, "IOHIDServiceClientCopyProperty");
        event = (CopyEvent)dlsym(RTLD_DEFAULT, "IOHIDServiceClientCopyEvent");
        value = (FloatValue)dlsym(RTLD_DEFAULT, "IOHIDEventGetFloatValue");
        if (!create || !match || !services || !property || !event || !value) return;
        client = create(kCFAllocatorDefault); if (!client) return;
        int page = 0xff00, usage = 5;
        CFNumberRef pageNumber = CFNumberCreate(NULL, kCFNumberIntType, &page), usageNumber = CFNumberCreate(NULL, kCFNumberIntType, &usage);
        const void *keys[] = {CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage")}, *values[] = {pageNumber, usageNumber};
        CFDictionaryRef matching = CFDictionaryCreate(NULL, keys, values, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        match(client, matching); CFRelease(matching); CFRelease(pageNumber); CFRelease(usageNumber);
    }
    if (!client) return;
    double now = monotonic_seconds();
    if (!all || now - discovery >= 60) {
        if (all) CFRelease(all);
        all = services(client); count = 0; discovery = now; detailed = 1;
        if (!all) return;
        for (CFIndex i = 0; i < CFArrayGetCount(all) && count < GM_MAX_SENSORS; i++) {
            CFTypeRef service = CFArrayGetValueAtIndex(all, i), name = property(service, CFSTR("Product"));
            if (name && CFGetTypeID(name) == CFStringGetTypeID()) {
                handles[count] = service;
                CFStringGetCString(name, cached[count].name, sizeof(cached[count].name), kCFStringEncodingUTF8);
                cached[count++].celsius = NAN;
            }
            if (name) CFRelease(name);
        }
    }
    int full = detailed || now - full_read >= 30;
    int selected = selected_sensor(cached, count, selection);
    int average = selection && !strcmp(selection, "CPU average");
    for (int pass = 0; pass < 2; pass++) {
        for (int i = 0; i < count; i++) {
            int wanted = average ? gm_sensor_rank(cached[i].name, selection) >= 0
                : selected >= 0 && !strcmp(cached[i].name, cached[selected].name);
            if (!full && !wanted) continue;
            CFTypeRef reading = event(handles[i], 15, 0, 0);
            double celsius = reading ? value(reading, 15 << 16) : NAN;
            if (reading) CFRelease(reading);
            cached[i].celsius = isfinite(celsius) && celsius > 0 && celsius <= 130 ? celsius : NAN;
        }
        if (full) { full_read = now; break; }
        if (selected >= 0 && !average && !isfinite(cached[selected].celsius)) {
            full = 1; discovery = 0;
        } else break;
    }
    for (int i = 0; i < count; i++)
        if (isfinite(cached[i].celsius)) s->sensors[s->sensor_count++] = cached[i];
}
// Read-only SMC protocol: 80-byte request, metadata command 9 and read command 5.
// Offsets are the driver's wire ABI, not a reused third-party implementation.
// There is intentionally no write-command path.
static io_connect_t smc_connection = 0;
static uint32_t smc_key(const char key[4]) {
    return ((uint32_t)(uint8_t)key[0] << 24) | ((uint32_t)(uint8_t)key[1] << 16)
        | ((uint32_t)(uint8_t)key[2] << 8) | (uint8_t)key[3];
}
double gm_decode_smc(const char *type, const uint8_t *bytes, uint32_t length) {
    if (!type || !bytes) return NAN;
    if (memcmp(type, "sp78", 4) == 0 && length == 2) {
        int16_t raw = (int16_t)(((uint16_t)bytes[0] << 8) | bytes[1]);
        return (double)raw / 256.0;
    }
    if (memcmp(type, "flt ", 4) == 0 && length == 4) {
        float value; memcpy(&value, bytes, sizeof(value));
        return isfinite(value) ? value : NAN;
    }
    if (memcmp(type, "fpe2", 4) == 0 && length == 2)
        return (double)(((uint16_t)bytes[0] << 8) | bytes[1]) / 4.0;
    if (memcmp(type, "ui32", 4) == 0 && length == 4)
        return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16)
            | ((uint32_t)bytes[2] << 8) | bytes[3];
    return NAN;
}
static double smc_read(const char *key) {
    if (!smc_connection) {
        io_service_t service = IOServiceGetMatchingService(GM_IO_PORT, IOServiceMatching("AppleSMC"));
        if (!service) return NAN;
        kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &smc_connection);
        IOObjectRelease(service);
        if (result != KERN_SUCCESS) { smc_connection = 0; return NAN; }
    }
    uint8_t request[80] = {0}, response[80] = {0};
    uint32_t code = smc_key(key); memcpy(request, &code, 4); request[42] = 9;
    size_t size = sizeof(response);
    kern_return_t result = IOConnectCallStructMethod(smc_connection, 2, request, sizeof(request), response, &size);
    if (result != KERN_SUCCESS) {
        IOServiceClose(smc_connection); smc_connection = 0; return NAN;
    }
    if (size != sizeof(response) || response[40] != 0) return NAN;
    uint32_t count, type; memcpy(&count, response + 28, 4); memcpy(&type, response + 32, 4);
    if (count < 1 || count > 32) return NAN;
    memset(request, 0, sizeof(request)); memcpy(request, &code, 4);
    memcpy(request + 28, &count, 4); request[42] = 5; size = sizeof(response);
    if (IOConnectCallStructMethod(smc_connection, 2, request, sizeof(request), response, &size) != KERN_SUCCESS
        || size != sizeof(response) || response[40] != 0) return NAN;
    char encoding[5] = {(char)(type >> 24), (char)(type >> 16), (char)(type >> 8), (char)type, 0};
    return gm_decode_smc(encoding, response + 48, count);
}
static void read_smc_temperature(GMSample *s) {
    if (s->sensor_count) return;
    static char discovered[GM_MAX_SENSORS][5];
    static int discovered_count = 0, enumerated = 0;
    if (!enumerated) {
        double total = smc_read("#KEY");
        if (isfinite(total) && total > 0 && total <= 8192) {
            // Cache only the sensor keys, never their readings. Bound unknown firmware.
            enumerated = 1;
            uint32_t limit = total < 2048 ? (uint32_t)total : 2048;
            for (uint32_t index = 0; index < limit && discovered_count < GM_MAX_SENSORS; index++) {
                uint8_t request[80] = {0}, response[80] = {0}; size_t size = sizeof(response);
                request[42] = 8; memcpy(request + 44, &index, 4);
                if (IOConnectCallStructMethod(smc_connection, 2, request, sizeof(request), response, &size) != KERN_SUCCESS
                    || size != sizeof(response) || response[40] != 0) continue;
                uint32_t key; memcpy(&key, response, 4);
                char name[5] = {(char)(key >> 24), (char)(key >> 16), (char)(key >> 8), (char)key, 0};
                if (name[0] != 'T') continue;
                double value = smc_read(name);
                if (isfinite(value) && value > 0 && value <= 130)
                    strlcpy(discovered[discovered_count++], name, 5);
            }
        }
    }
    for (int i = 0; i < discovered_count && s->sensor_count < GM_MAX_SENSORS; i++) {
        double value = smc_read(discovered[i]);
        if (!isfinite(value) || value <= 0 || value > 130) continue;
        const char *kind = discovered[i][1] == 'C' ? "CPU" : discovered[i][1] == 'G' ? "GPU"
            : discovered[i][1] == 'B' ? "Battery" : "Temperature";
        GMSensor *sensor = &s->sensors[s->sensor_count++];
        snprintf(sensor->name, sizeof(sensor->name), "%s (%s)", kind, discovered[i]); sensor->celsius = value;
    }
    if (s->sensor_count) return;
    const char *keys[] = {"TC0P", "TC0D", "TC0E", "TC0F", "TG0P", "TG0D", "TB0T", "TA0P", "Tm0P"};
    const char *names[] = {"CPU proximity", "CPU die", "CPU core", "CPU package", "GPU proximity", "GPU die", "Battery", "Ambient", "Memory"};
    for (size_t i = 0; i < sizeof(keys)/sizeof(keys[0]) && s->sensor_count < GM_MAX_SENSORS; i++) {
        double value = smc_read(keys[i]);
        if (!isfinite(value) || value <= 0 || value > 130) continue;
        GMSensor *sensor = &s->sensors[s->sensor_count++];
        snprintf(sensor->name, sizeof(sensor->name), "%s (%s)", names[i], keys[i]);
        sensor->celsius = value;
    }
}
static void read_power(GMSample *s) {
    s->charger_watts = s->system_watts = s->adapter_watts = s->battery_percent = NAN;
    CFTypeRef sourceInfo = IOPSCopyPowerSourcesInfo();
    if (sourceInfo) {
        CFStringRef type = IOPSGetProvidingPowerSourceType(sourceInfo);
        s->external_power = type && CFEqual(type, CFSTR(kIOPSACPowerValue));
        CFArrayRef sources = IOPSCopyPowerSourcesList(sourceInfo);
        if (sources) {
            for (CFIndex i = 0; i < CFArrayGetCount(sources); i++) {
                CFDictionaryRef d = IOPSGetPowerSourceDescription(sourceInfo, CFArrayGetValueAtIndex(sources, i));
                CFTypeRef typeValue = d ? CFDictionaryGetValue(d, CFSTR(kIOPSTypeKey)) : NULL;
                if (!typeValue || !CFEqual(typeValue, CFSTR(kIOPSInternalBatteryType))) continue;
                double current = number(d, CFSTR(kIOPSCurrentCapacityKey), NAN), maximum = number(d, CFSTR(kIOPSMaxCapacityKey), NAN);
                if (maximum > 0 && current >= 0 && current <= maximum) s->battery_percent = current / maximum * 100;
                s->charging = boolean(d, CFSTR(kIOPSIsChargingKey));
            }
            CFRelease(sources);
        }
        CFRelease(sourceInfo);
    }
    io_service_t battery = IOServiceGetMatchingService(GM_IO_PORT, IOServiceMatching("AppleSmartBattery"));
    if (battery) {
        CFMutableDictionaryRef props = NULL;
        if (IORegistryEntryCreateCFProperties(battery, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS) {
            s->external_power = boolean(props, CFSTR("ExternalConnected")); s->charging = boolean(props, CFSTR("IsCharging"));
            double current = number(props, CFSTR("CurrentCapacity"), NAN), maximum = number(props, CFSTR("MaxCapacity"), NAN);
            if (maximum > 0 && current >= 0 && current <= maximum) s->battery_percent = current / maximum * 100;
            CFDictionaryRef telemetry = dictionary(props, CFSTR("PowerTelemetryData")), adapter = dictionary(props, CFSTR("AdapterDetails"));
            s->adapter_watts = number(adapter, CFSTR("Watts"), NAN);
            s->charger_watts = s->external_power ? number(telemetry, CFSTR("SystemPowerIn"), NAN) / 1000.0 : 0;
            s->system_watts = number(telemetry, CFSTR("SystemLoad"), NAN) / 1000.0;
            if (!s->external_power && (!isfinite(s->system_watts) || s->system_watts <= 0)) {
                double amps = number(props, CFSTR("InstantAmperage"), NAN);
                if (amps > INT32_MAX && amps <= UINT32_MAX) amps = (int32_t)(uint32_t)amps;
                double volts = number(props, CFSTR("Voltage"), NAN);
                if (isfinite(amps) && fabs(amps) < 100000 && volts > 0) s->system_watts = fabs(amps * volts) / 1e6;
            }
            CFRelease(props);
        }
        IOObjectRelease(battery);
    }
    // PSTR is whole-system SMC power; CPU-only keys must not be relabeled as total draw.
    if (!isfinite(s->system_watts)) s->system_watts = smc_read("PSTR");
    if (s->system_watts < 0 || s->system_watts > 2000) s->system_watts = NAN;
    if (s->charger_watts < 0 || s->charger_watts > 2000) s->charger_watts = NAN;
}
static void read_smc_selected(GMSample *s, const char *selection, int detailed) {
    if (s->sensor_count) return;
    static GMSensor cached[GM_MAX_SENSORS]; static int count = 0;
    static double last_full = -100;
    double now = monotonic_seconds();
    if (!count || detailed || now - last_full >= 30) {
        read_smc_temperature(s); count = s->sensor_count;
        memcpy(cached, s->sensors, count * sizeof(GMSensor)); last_full = now;
        return;
    }
    int selected = selected_sensor(cached, count, selection);
    int average = selection && !strcmp(selection, "CPU average");
    for (int i = 0; i < count; i++) {
        int wanted = average ? gm_sensor_rank(cached[i].name, selection) >= 0
            : selected >= 0 && !strcmp(cached[i].name, cached[selected].name);
        if (!wanted) continue;
        const char *start = strrchr(cached[i].name, '(');
        if (!start || strlen(start) != 6) continue;
        char key[5] = {0}; memcpy(key, start + 1, 4);
        double value = smc_read(key);
        cached[i].celsius = isfinite(value) && value > 0 && value <= 130 ? value : NAN;
    }
    for (int i = 0; i < count; i++)
        if (isfinite(cached[i].celsius)) s->sensors[s->sensor_count++] = cached[i];
}
void gm_sample_selected(GMSample *s, const char *selection, int detailed) {
    memset(s, 0, sizeof(*s));
    read_cpu(s); read_memory(s); read_network(s); read_disk(s);
    read_temperature(s, selection, detailed); read_smc_selected(s, selection, detailed); read_power(s);
}
void gm_sample(GMSample *s) { gm_sample_selected(s, "Automatic", 1); }
