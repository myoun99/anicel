import 'package:flutter/foundation.dart';

/// What the view keys press on a canvas: each one of its bar's view
/// buttons, null where the bar has no such button or it is off — the key
/// does then what the missing button would (I-19 · I-40: the keys press
/// the buttons).
typedef CanvasViewPresses = ({
  void Function({required bool zoomIn})? zoomStep,
  VoidCallback? fit,
  VoidCallback? resetView,
  void Function({required bool clockwise})? rotateStep,
  VoidCallback? resetRotation,
  VoidCallback? flipHorizontal,
  VoidCallback? flipVertical,
});

/// The imperative view-control channel (P8): the app-level shortcut
/// dispatch (R/Shift+R rotate, H flip, the zoom steps, fit, 1:1) calls in,
/// and the canvas panel LYING ON THE FLOOR binds its presses — the panel
/// owns the viewport interaction math and the viewport-center anchor.
/// Unbound calls are no-ops (no canvas panel on the floor).
///
/// 🗣️F-623 (유저 2026-11-19: 「바닥에 깔린 패널에 단축키 적용되도록. 예를들어
/// 화면 확대 축소 단축키같은거. 바닥에 깔린 타임시트패널이나 콘티패널같은데서
/// 적용되도록」) — so the floor hands it to whichever panel lies there
/// (`CanvasFloorInsets.viewCommands`). ↩️The editor's canvas was handed it
/// down its constructors, and a sheet or the viewer laid on the floor took
/// no key at all.
class CanvasViewCommands {
  CanvasViewPresses Function()? _presses;
  Object? _owner;

  /// [presses] is asked at each key, so a panel whose buttons come and go
  /// (no file to view · a host that never turns the view) binds once.
  ///
  /// ⚠️Owner-scoped — see `TimelineLayerNavCommands.bind` for the failure
  /// an unconditional `unbind()` produced (유저 #13, 2026-08-14).
  void bind(Object owner, CanvasViewPresses Function() presses) {
    _owner = owner;
    _presses = presses;
  }

  void unbind(Object owner) {
    if (!identical(_owner, owner)) {
      return;
    }
    _owner = null;
    _presses = null;
  }

  /// One press of the canvas bar's zoom in / out — the same step the
  /// buttons take (I-19: Shift+. and Shift+, press them).
  void zoomStep({required bool zoomIn}) =>
      _presses?.call().zoomStep?.call(zoomIn: zoomIn);

  /// One press of the canvas bar's rotate left / right — the same step the
  /// buttons take, on the rotation snap's grid (F-391). ↩️The keys turned
  /// the view by a 15° of their own (`rotateBy`).
  void rotateStep({required bool clockwise}) =>
      _presses?.call().rotateStep?.call(clockwise: clockwise);

  /// Toggles the horizontal view mirror around the viewport center.
  void toggleFlipHorizontal() => _presses?.call().flipHorizontal?.call();

  /// Toggles the vertical view mirror around the viewport center
  /// (UI-R18 #19).
  void toggleFlipVertical() => _presses?.call().flipVertical?.call();

  /// Straightens the view rotation back to 0° (UI-R18 #20), keeping
  /// zoom/pan/flips.
  void resetRotation() => _presses?.call().resetRotation?.call();

  /// The pill's fit — the same framing its button lands (I-40).
  void fit() => _presses?.call().fit?.call();

  /// The pill's 1:1 (I-40).
  void resetView() => _presses?.call().resetView?.call();
}
