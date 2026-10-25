#ifndef MICA_HARDWARE_H
#define MICA_HARDWARE_H
#include <stdint.h>
#define GM_MAX_CORES 256
#define GM_MAX_SENSORS 128
#define GM_MAX_INTERFACES 32
typedef struct { uint64_t user, system, idle, nice; } GMCore;
typedef struct { char name[96]; double celsius; } GMSensor;
typedef struct { char name[32]; uint64_t incoming, outgoing; } GMInterface;
typedef struct {
    int core_count, cpu_valid; GMCore cores[GM_MAX_CORES];
    uint64_t memory_total, memory_active, memory_wired, memory_compressed, memory_inactive, memory_free, swap_used;
    int memory_valid, pressure;
    int interface_count; GMInterface interfaces[GM_MAX_INTERFACES]; char primary_interface[32];
    uint64_t disk_read, disk_write; int disk_valid;
    int sensor_count; GMSensor sensors[GM_MAX_SENSORS];
    double charger_watts, system_watts, adapter_watts, battery_percent;
    int external_power, charging;
} GMSample;
void gm_sample(GMSample *sample);
void gm_sample_selected(GMSample *sample, const char *selection, int detailed);
int gm_sensor_rank(const char *name, const char *selection);
double gm_decode_smc(const char *type, const uint8_t *bytes, uint32_t length);
#endif
