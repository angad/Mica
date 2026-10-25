import AppKit

// Each visible meter is a native button carrying its own identity. Drawing and
// hit targets share one coordinate system, independent of the status item's cell.
final class MeterBarView: NSView {
  var onSelect: ((Meter) -> Void)?
  var onContextMenu: ((NSEvent, NSView) -> Void)?
  private(set) var buttons: [Meter: MeterComponentButton] = [:]
  private var image: NSImage?
  private var regions: [MeterRegion] = []

  override var isFlipped: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  func update(image: NSImage, regions: [MeterRegion]) {
    let layoutChanged = self.regions != regions || self.image?.size != image.size
    self.image = image
    self.regions = regions
    let visible = Set(regions.map(\.meter))
    for meter in Array(buttons.keys) where !visible.contains(meter) {
      buttons.removeValue(forKey: meter)?.removeFromSuperview()
    }
    for region in regions where buttons[region.meter] == nil {
      let button = MeterComponentButton(meter: region.meter)
      button.target = self
      button.action = #selector(selectMeter(_:))
      button.onContextMenu = { [weak self] event, view in self?.onContextMenu?(event, view) }
      buttons[region.meter] = button
      addSubview(button)
    }
    if layoutChanged { needsLayout = true }
    needsDisplay = true
  }

  private var imageFrame: NSRect {
    guard let image, image.size.width > 0, image.size.height > 0 else { return .zero }
    let scale = min(1, bounds.width / image.size.width, bounds.height / image.size.height)
    let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    return NSRect(
      x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
      width: size.width, height: size.height)
  }

  override func draw(_ dirtyRect: NSRect) {
    image?.draw(in: imageFrame)
  }

  override func layout() {
    super.layout()
    guard let image, image.size.width > 0 else { return }
    let drawing = imageFrame
    let scale = drawing.width / image.size.width
    for region in regions {
      // Divide inter-meter spacing at the midpoint, including the outer margins.
      let previous = regions.filter { $0.rect.maxX <= region.rect.minX }.map(\.rect.maxX).max()
      let next = regions.filter { $0.rect.minX >= region.rect.maxX }.map(\.rect.minX).min()
      let left = previous.map { drawing.minX + ($0 + region.rect.minX) / 2 * scale } ?? bounds.minX
      let right = next.map { drawing.minX + ($0 + region.rect.maxX) / 2 * scale } ?? bounds.maxX
      let bottom = region.rect.minY == 0 ? bounds.minY : drawing.minY + region.rect.minY * scale
      let top =
        region.rect.maxY == image.size.height
        ? bounds.maxY : drawing.minY + region.rect.maxY * scale
      buttons[region.meter]?.frame = NSRect(
        x: left, y: bottom, width: right - left, height: top - bottom)
    }
  }

  @objc private func selectMeter(_ sender: MeterComponentButton) { onSelect?(sender.meter) }

  override func rightMouseDown(with event: NSEvent) { onContextMenu?(event, self) }
}

final class MeterComponentButton: NSButton {
  let meter: Meter
  var onContextMenu: ((NSEvent, NSView) -> Void)?

  init(meter: Meter) {
    self.meter = meter
    super.init(frame: .zero)
    title = ""
    isBordered = false
    setButtonType(.momentaryChange)
    setAccessibilityLabel(meter.title)
    toolTip = "\(meter.title) · Click for details"
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func rightMouseDown(with event: NSEvent) { onContextMenu?(event, self) }
  override func mouseDown(with event: NSEvent) {
    if event.modifierFlags.contains(.control) {
      onContextMenu?(event, self)
    } else {
      super.mouseDown(with: event)
    }
  }
  override func draw(_ dirtyRect: NSRect) {
    if isHighlighted {
      NSColor.labelColor.withAlphaComponent(0.12).setFill()
      NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
    }
  }
}
