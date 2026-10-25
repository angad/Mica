import AppKit
import Testing

@testable import Mica

@Suite @MainActor struct MeterInteractionTests {
  @Test func everyVisibleComponentDispatchesItsOwnIdentity() throws {
    _ = NSApplication.shared
    var sample = Snapshot()
    sample.cores = Array(repeating: CoreLoad(user: 0.3, system: 0.1), count: 8)
    for compact in [false, true] {
      var prefs = Preferences()
      prefs.enabled = Set(Meter.allCases)
      prefs.compact = compact
      let image = MeterPainter.image(sample, prefs, dark: false)
      for height: CGFloat in [22, 24, 37] {
        let bar = MeterBarView(
          frame: NSRect(x: 0, y: 0, width: image.size.width + 2, height: height))
        bar.update(image: image, regions: MeterPainter.regions(sample, prefs))
        bar.layoutSubtreeIfNeeded()
        var selected: Meter?
        bar.onSelect = { selected = $0 }
        for meter in Meter.allCases {
          let button = try #require(bar.buttons[meter])
          let point = NSPoint(x: button.frame.midX, y: button.frame.midY)
          let hit = try #require(bar.hitTest(point) as? MeterComponentButton)
          #expect(hit.meter == meter)
          hit.performClick(nil)
          #expect(selected == meter)
          #expect(hit.accessibilityLabel() == meter.title)
        }
        // Every pixel of the compact bar is assigned to a meter, including gaps.
        for x in stride(from: 0.5, to: bar.bounds.width, by: 1) {
          for y: CGFloat in [0.5, height / 2, height - 0.5] {
            #expect(bar.hitTest(NSPoint(x: x, y: y)) is MeterComponentButton)
          }
        }
      }
    }
  }

  @Test func hiddenComponentsLoseTheirTargetsAndSinglePowerUsesFullHeight() throws {
    _ = NSApplication.shared
    let sample = Snapshot()
    var prefs = Preferences()
    let bar = MeterBarView(frame: NSRect(x: 0, y: 0, width: 400, height: 24))
    bar.update(
      image: MeterPainter.image(sample, prefs, dark: false),
      regions: MeterPainter.regions(sample, prefs))
    prefs.enabled = [.consumption]
    bar.update(
      image: MeterPainter.image(sample, prefs, dark: false),
      regions: MeterPainter.regions(sample, prefs))
    bar.layoutSubtreeIfNeeded()
    #expect(Set(bar.buttons.keys) == [.consumption])
    let output = try #require(bar.buttons[.consumption])
    #expect(output.frame == bar.bounds)
    prefs.enabled = []
    bar.update(image: MeterPainter.image(sample, prefs, dark: false), regions: [])
    #expect(bar.buttons.isEmpty)
  }
}
