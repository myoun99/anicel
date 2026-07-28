import Cocoa
import FlutterMacOS

/// Anicel pen sidecar (pen program, PEN-4 — macOS).
///
/// Flutter's macOS embedder does not deliver tablet pressure/tilt from
/// external tablets (flutter/flutter#146387): Wacom-style drivers
/// synthesize mouse events whose NSEvent carries `.tabletPoint` data the
/// embedder drops. This monitor restores it: a LOCAL event monitor (this
/// app's events only — no accessibility permission involved) forwards
/// pressure/tilt onto the 'qa_pen/macos' event channel, the same
/// pressure-sidecar contract as the Windows Wintab bridge.
///
/// UNVERIFIED-ON-DEVICE: authored on the Windows workstation; needs one
/// macOS build + a tablet pass (the input inspector's 'mac p=' line is
/// the check). Runner-owned so no plugin registrant churn.
class PenSidecarStreamHandler: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var monitor: Any?

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = events
    // Tablet-capable events: dedicated tabletPoint events AND the mouse
    // events that carry a tablet subtype (how most drivers deliver).
    let mask: NSEvent.EventTypeMask = [
      .tabletPoint, .leftMouseDown, .leftMouseDragged,
    ]
    monitor = NSEvent.addLocalMonitorForEvents(matching: mask) {
      [weak self] event in
      self?.forward(event)
      return event
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let monitor = monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
    sink = nil
    return nil
  }

  private func forward(_ event: NSEvent) {
    guard let sink = sink else { return }
    let isTablet =
      event.type == .tabletPoint || event.subtype == .tabletPoint
    guard isTablet else { return }
    sink([
      "pressure": Double(event.pressure),
      "tiltX": Double(event.tilt.x),
      "tiltY": Double(event.tilt.y),
      "timeMs": event.timestamp * 1000.0,
      "eraser": false,
    ])
  }
}

class MainFlutterWindow: NSWindow {
  private let penStreamHandler = PenSidecarStreamHandler()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // The pen sidecar stream (PEN-4).
    let penChannel = FlutterEventChannel(
      name: "qa_pen/macos",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    penChannel.setStreamHandler(penStreamHandler)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
