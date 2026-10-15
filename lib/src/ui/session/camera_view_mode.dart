import 'package:flutter/foundation.dart';

import '../../models/layer.dart';
import '../../models/track_camera_head.dart' show cameraHeadOf;
import 'layer_switch_verbs.dart';
import 'opacity_verbs.dart';
import 'session_roles.dart';

/// THE CAMERA VIEW — whether the canvas frames the shot, and how dark it
/// lays what falls outside the frame — read off the camera row the session
/// stands on: its EYE and its static OPACITY.
///
/// 🗣️유저 2026-10-15 (F-363): 「카메라 불투명도는 레이어랑 통일. 레이어가
/// 눈이랑 불투명도 바꾸면 언두 저장되니까. 기본적으로 레이어 버튼은 그게
/// 기준」. The camera row's eye and slider are its layer's, written by the
/// commands every row's are — one undo, kept by the file — and worn as one
/// by the cameras of its track (`cameraHeadTargets`). This object READS
/// them for the canvas and the buttons that show the view; the one write it
/// makes ([toggle]) is a press of the row's eye.
///
/// ↩️They were the WINDOW's: two notifiers the workspace held beside the
/// tool options, which the camera row's eye and slider wrote instead of the
/// layer — so no file kept them, and a project opened in the window came up
/// in the view the last one was left in (「파일 열때, 카메라 불투명도가 열기
/// 전 열려있던 프로젝트의 카메라 불투명도랑 같은상태로 열림」).
class CameraViewMode {
  CameraViewMode({
    required ProjectAccess project,
    required SelectionAccess selection,
    required OpacityVerbs opacity,
    required LayerSwitchVerbs switches,
  }) : _project = project,
       _selection = selection,
       _opacity = opacity,
       _switches = switches;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final OpacityVerbs _opacity;
  final LayerSwitchVerbs _switches;

  final ValueNotifier<bool> _enabled = ValueNotifier(false);
  final ValueNotifier<double> _dim = ValueNotifier(1);

  /// Whether the view is on: the camera row's eye.
  ValueListenable<bool> get enabled => _enabled;

  /// How dark the view lays the outside of the frame: the camera row's
  /// opacity — while its slider moves, the value it is dragged through
  /// ([OpacityVerbs.dragPreview]), as a picture follows its row's slider.
  ValueListenable<double> get dim => _dim;

  /// The camera row the view is read off: the camera of the cut the session
  /// stands in — or, in a gap, the head the cameras of its track wear
  /// ([cameraHeadOf]), which is each of theirs.
  Layer? get _camera =>
      _project.activeCutOrNull?.layers.cameraLayer ??
      switch (_project.trackById(_selection.selectedTrackId)) {
        final track? => cameraHeadOf(track.cuts),
        null => null,
      };

  /// Reads the view again — after a session change, or a move of a slider,
  /// which no change carries. The listeners hear only a value that moved.
  void read() {
    final camera = _camera;
    if (camera == null) {
      _enabled.value = false;
      return;
    }
    _enabled.value = camera.isVisible;
    final dragging = _opacity.dragPreview.value;
    _dim.value = dragging != null && dragging.layerIds.contains(camera.id)
        ? dragging.opacity
        : camera.opacity;
  }

  /// The view's own switch — the bars' button and its key (I-40): the
  /// camera row's eye, pressed.
  void toggle() {
    if (_camera case final camera?) {
      _switches.toggleLayerVisibility(camera.id);
    }
  }

  void dispose() {
    _enabled.dispose();
    _dim.dispose();
  }
}
