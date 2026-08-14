import 'package:flutter/foundation.dart';

/// The imperative view-control channel for the editor canvas (P8): the
/// app-level shortcut dispatch (R/Shift+R rotate, H flip) calls in, and
/// the mounted [BrushCanvasPanel] binds the handlers — the panel owns the
/// viewport interaction math and the viewport-center anchor. Unbound
/// calls are no-ops (no canvas panel on screen).
class CanvasViewCommands {
  void Function(double degrees)? _rotateBy;
  VoidCallback? _toggleFlipHorizontal;
  VoidCallback? _toggleFlipVertical;
  VoidCallback? _resetRotation;
  Object? _owner;

  /// ⚠️Owner-scoped — see `TimelineLayerNavCommands.bind` for the failure
  /// an unconditional `unbind()` produced (유저 #13, 2026-08-14).
  void bind(
    Object owner, {
    required void Function(double degrees) rotateBy,
    required VoidCallback toggleFlipHorizontal,
    VoidCallback? toggleFlipVertical,
    VoidCallback? resetRotation,
  }) {
    _owner = owner;
    _rotateBy = rotateBy;
    _toggleFlipHorizontal = toggleFlipHorizontal;
    _toggleFlipVertical = toggleFlipVertical;
    _resetRotation = resetRotation;
  }

  void unbind(Object owner) {
    if (!identical(_owner, owner)) {
      return;
    }
    _owner = null;
    _rotateBy = null;
    _toggleFlipHorizontal = null;
    _toggleFlipVertical = null;
    _resetRotation = null;
  }

  /// Rotates the canvas VIEW by [degrees] (clockwise positive) around the
  /// viewport center.
  void rotateBy(double degrees) => _rotateBy?.call(degrees);

  /// Toggles the horizontal view mirror around the viewport center.
  void toggleFlipHorizontal() => _toggleFlipHorizontal?.call();

  /// Toggles the vertical view mirror around the viewport center
  /// (UI-R18 #19).
  void toggleFlipVertical() => _toggleFlipVertical?.call();

  /// Straightens the view rotation back to 0° (UI-R18 #20), keeping
  /// zoom/pan/flips.
  void resetRotation() => _resetRotation?.call();
}
