import AppKit

struct MeterRegion {
  let meter: Meter
  let rect: NSRect
}
struct MeterPainter {
  static func groupedCores(_ cores: [CoreLoad]) -> [CoreLoad] {
    guard cores.count > 32 else { return cores }
    let size = Int(ceil(Double(cores.count) / 32))
    return stride(from: 0, to: cores.count, by: size).map { start in
      let group = cores[start..<min(cores.count, start + size)]
      return CoreLoad(
        user: group.map(\.user).reduce(0, +) / Double(group.count),
        system: group.map(\.system).reduce(0, +) / Double(group.count))
    }
  }
  static func regions(_ s: Snapshot, _ p: Preferences) -> [MeterRegion] {
    var x: CGFloat = 3
    let gap: CGFloat = p.compact ? 2 : 4
    var output: [MeterRegion] = []
    for meter in Meter.allCases
    where p.enabled.contains(meter) && meter != .input && meter != .consumption {
      let width: CGFloat
      switch meter {
      case .memory: width = p.memoryPercent ? 37 : 10
      case .network: width = p.compact ? 82 : 88
      case .disk: width = p.diskRates ? 79 : 16
      case .temperature: width = 50
      case .battery: width = 44
      case .cpu:
        width =
          p.cpuPercent
          ? 37
          : CGFloat(p.cpuPerCore ? min(32, max(1, s.cores.count)) : 1) * (p.compact ? 7 : 8) - 3
      case .input, .consumption: continue
      }
      output.append(MeterRegion(meter: meter, rect: NSRect(x: x, y: 0, width: width, height: 24)))
      x += width + gap
    }
    let input = p.enabled.contains(.input)
    let outputPower = p.enabled.contains(.consumption)
    let stacked = input && outputPower
    if input {
      output.append(
        MeterRegion(
          meter: .input,
          rect: NSRect(x: x, y: stacked ? 12 : 0, width: 74, height: stacked ? 12 : 24)))
    }
    if outputPower {
      output.append(
        MeterRegion(
          meter: .consumption, rect: NSRect(x: x, y: 0, width: 74, height: stacked ? 12 : 24)))
    }
    return output
  }
  static func region(at point: NSPoint, in regions: [MeterRegion]) -> MeterRegion? {
    regions.first(where: { $0.rect.contains(point) })
      ?? regions.min {
        hypot($0.rect.midX - point.x, $0.rect.midY - point.y)
          < hypot($1.rect.midX - point.x, $1.rect.midY - point.y)
      }
  }
  static func image(_ s: Snapshot, _ p: Preferences, dark: Bool) -> NSImage {
    let regions = regions(s, p)
    let width = regions.last.map { $0.rect.maxX + 3 } ?? 27
    let image = NSImage(size: NSSize(width: width, height: 24), flipped: false) { _ in
      let foreground: NSColor = dark ? .white : .labelColor
      func color(_ hex: String) -> NSColor { p.monochrome ? foreground : NSColor(hex: hex) }
      func text(
        _ value: String, _ rect: NSRect, _ tint: NSColor, size: CGFloat = 11,
        weight: NSFont.Weight = .medium
      ) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byClipping
        (value as NSString).draw(
          in: rect,
          withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
            .foregroundColor: tint, .paragraphStyle: style,
          ])
      }
      func bar(_ rect: NSRect, _ pieces: [(Double, NSColor)]) {
        let track = NSBezierPath(roundedRect: rect, xRadius: 1.8, yRadius: 1.8)
        foreground.withAlphaComponent(0.13).setFill()
        track.fill()
        NSGraphicsContext.saveGraphicsState()
        track.addClip()
        var y = rect.minY
        for (fraction, tint) in pieces {
          let height = min(rect.maxY - y, max(0, rect.height * fraction))
          tint.setFill()
          NSRect(x: rect.minX, y: y, width: rect.width, height: height).fill()
          y += height
        }
        NSGraphicsContext.restoreGraphicsState()
        foreground.withAlphaComponent(dark ? 0.7 : 0.4).setStroke()
        track.lineWidth = 0.65
        track.stroke()
      }
      if regions.isEmpty {
        text("◉", NSRect(x: 5, y: 3, width: 20, height: 20), foreground, size: 15)
      }
      for region in regions {
        let r = region.rect
        let x = r.minX
        switch region.meter {
        case .memory:
          if p.memoryPercent {
            text(
              String(format: "%.0f%%", s.memoryFraction * 100),
              NSRect(x: x, y: 5, width: r.width, height: 16), color("#AC64F5"))
          } else {
            let total = max(1, s.memoryTotal)
            bar(
              NSRect(x: x + 1, y: 3, width: 9, height: 18),
              [
                (s.compressed / total, color("#935BFF")), (s.active / total, color("#97DE40")),
                (s.wired / total, color("#A81D52")),
              ])
          }
        case .network:
          text(
            "Tx: " + (s.networkAvailable ? rate(s.upload, bits: p.networkBits) : "—"),
            NSRect(x: x, y: 12, width: r.width, height: 12), color(p.transmit), size: 10.5)
          text(
            "Rx: " + (s.networkAvailable ? rate(s.download, bits: p.networkBits) : "—"),
            NSRect(x: x, y: 0, width: r.width, height: 12), color(p.receive), size: 10.5)
        case .disk:
          if p.diskRates {
            text(
              "R: " + (s.diskAvailable ? rate(s.diskRead) : "—"),
              NSRect(x: x, y: 12, width: r.width, height: 12), color(p.transmit), size: 10)
            text(
              "W: " + (s.diskAvailable ? rate(s.diskWrite) : "—"),
              NSRect(x: x, y: 0, width: r.width, height: 12), color(p.receive), size: 10)
          } else {
            for (dy, active, tint) in [
              (13.0, s.diskRead > 0, color(p.transmit)), (5.0, s.diskWrite > 0, color(p.receive)),
            ] {
              tint.withAlphaComponent(active ? 1 : 0.23).setFill()
              NSBezierPath(
                roundedRect: NSRect(x: x, y: dy, width: 16, height: 5), xRadius: 1.7,
                yRadius: 1.7
              ).fill()
            }
          }
        case .temperature:
          text(
            temperatureText(s.temperature, fahrenheit: p.fahrenheit),
            NSRect(x: x, y: 5, width: r.width, height: 16), color("#FF5349"), size: 11.5)
        case .battery:
          text(
            s.battery?.chargePercent.map { String(format: "%.0f%%", $0) } ?? "—%",
            NSRect(x: x, y: 5, width: r.width, height: 16), color("#32D74B"))
        case .cpu:
          if p.cpuPercent {
            text(
              String(format: "%.0f%%", s.cpu * 100), NSRect(x: x, y: 5, width: r.width, height: 16),
              color(p.cpuUser))
          } else {
            let cores =
              p.cpuPerCore
              ? groupedCores(s.cores)
              : [
                CoreLoad(
                  user: s.cores.map(\.user).reduce(0, +) / Double(max(1, s.cores.count)),
                  system: s.cores.map(\.system).reduce(0, +) / Double(max(1, s.cores.count)))
              ]
            for (i, core) in cores.enumerated() {
              bar(
                NSRect(
                  x: x + CGFloat(i) * (p.compact ? 7 : 8), y: 3, width: p.compact ? 4 : 5,
                  height: 18), [(core.system, color(p.cpuSystem)), (core.user, color(p.cpuUser))])
            }
          }
        case .input, .consumption:
          let input = region.meter == .input
          text(
            (input ? "In: " : "Out: ") + watts(input ? s.inputWatts : s.systemWatts),
            NSRect(x: x, y: r.height == 12 ? r.minY : 6, width: r.width, height: 12),
            color(input ? "#34CDB5" : "#F3A536"), size: 10.5)

        }
      }
      return true
    }
    image.isTemplate = false
    return image
  }
}
