import 'package:flutter/foundation.dart';

import '../../models/working_panel.dart';

/// The verbs of the panel-bar buttons whose state the WORKSPACE holds
/// (I-40): each panel's frame-axis zoom, the timeline's ⇄ and the camera
/// view — what a key presses when it presses one of those buttons. The
/// mounted `EditorWorkspace` binds them; the shell's key funnel calls in.
/// Unbound calls are no-ops.
///
/// A verb that takes a [WorkingPanel] is that panel's own button: the panel
/// answers it, and a panel whose bar has no such button answers nothing —
/// as a legend row the working panel's header does not show does nothing.
class WorkspaceBarCommands {
  void Function(WorkingPanel panel, {required bool zoomIn})? _zoomStep;
  void Function(WorkingPanel panel)? _toggleOrientation;
  VoidCallback? _toggleCameraView;
  Object? _owner;

  /// ⚠️Owner-scoped — see `TimelineLayerNavCommands.bind` for the failure
  /// an unconditional `unbind()` produced (유저 #13, 2026-08-14).
  void bind(
    Object owner, {
    required void Function(WorkingPanel panel, {required bool zoomIn})
    zoomStep,
    required void Function(WorkingPanel panel) toggleOrientation,
    required VoidCallback toggleCameraView,
  }) {
    _owner = owner;
    _zoomStep = zoomStep;
    _toggleOrientation = toggleOrientation;
    _toggleCameraView = toggleCameraView;
  }

  void unbind(Object owner) {
    if (!identical(_owner, owner)) {
      return;
    }
    _owner = null;
    _zoomStep = null;
    _toggleOrientation = null;
    _toggleCameraView = null;
  }

  /// One press of [panel]'s zoom − or +.
  void zoomStep(WorkingPanel panel, {required bool zoomIn}) =>
      _zoomStep?.call(panel, zoomIn: zoomIn);

  /// One press of [panel]'s timeline ⇄ X-sheet.
  void toggleOrientation(WorkingPanel panel) =>
      _toggleOrientation?.call(panel);

  /// One press of the sill's camera view switch.
  void toggleCameraView() => _toggleCameraView?.call();
}
