import 'package:flutter/foundation.dart';

/// The imperative view-control channel for the editor canvas (P8): the
/// app-level shortcut dispatch (R/Shift+R rotate, H flip) calls in, and
/// the mounted [BrushCanvasPanel] binds the handlers — the panel owns the
/// viewport interaction math and the viewport-center anchor. Unbound
/// calls are no-ops (no canvas panel on screen).
class CanvasViewCommands {
  void Function({required bool clockwise})? _rotateStep;
  VoidCallback? _toggleFlipHorizontal;
  VoidCallback? _toggleFlipVertical;
  VoidCallback? _resetRotation;
  void Function({required bool zoomIn})? _zoomStep;
  VoidCallback? _fit;
  VoidCallback? _resetView;
  Object? _owner;

  /// ⚠️Owner-scoped — see `TimelineLayerNavCommands.bind` for the failure
  /// an unconditional `unbind()` produced (유저 #13, 2026-08-14).
  void bind(
    Object owner, {
    required void Function({required bool clockwise}) rotateStep,
    required VoidCallback toggleFlipHorizontal,
    VoidCallback? toggleFlipVertical,
    VoidCallback? resetRotation,
    void Function({required bool zoomIn})? zoomStep,
    VoidCallback? fit,
    VoidCallback? resetView,
  }) {
    _owner = owner;
    _rotateStep = rotateStep;
    _toggleFlipHorizontal = toggleFlipHorizontal;
    _toggleFlipVertical = toggleFlipVertical;
    _resetRotation = resetRotation;
    _zoomStep = zoomStep;
    _fit = fit;
    _resetView = resetView;
  }

  void unbind(Object owner) {
    if (!identical(_owner, owner)) {
      return;
    }
    _owner = null;
    _rotateStep = null;
    _toggleFlipHorizontal = null;
    _toggleFlipVertical = null;
    _resetRotation = null;
    _zoomStep = null;
    _fit = null;
    _resetView = null;
  }

  /// One press of the canvas bar's zoom in / out — the same step the
  /// buttons take (I-19: Shift+. and Shift+, press them).
  void zoomStep({required bool zoomIn}) => _zoomStep?.call(zoomIn: zoomIn);

  /// One press of the canvas bar's rotate left / right — the same step the
  /// buttons take, on the rotation snap's grid (F-391). ↩️The keys turned
  /// the view by a 15° of their own (`rotateBy`).
  void rotateStep({required bool clockwise}) =>
      _rotateStep?.call(clockwise: clockwise);

  /// Toggles the horizontal view mirror around the viewport center.
  void toggleFlipHorizontal() => _toggleFlipHorizontal?.call();

  /// Toggles the vertical view mirror around the viewport center
  /// (UI-R18 #19).
  void toggleFlipVertical() => _toggleFlipVertical?.call();

  /// Straightens the view rotation back to 0° (UI-R18 #20), keeping
  /// zoom/pan/flips.
  void resetRotation() => _resetRotation?.call();

  /// The pill's fit — the same framing its button lands (I-40).
  void fit() => _fit?.call();

  /// The pill's 1:1 (I-40).
  void resetView() => _resetView?.call();
}
