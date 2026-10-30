import 'package:flutter/foundation.dart';

import '../timeline/frame_ruler_view.dart';
import '../timeline/layer_rail_window.dart' show LayerRailId;
import '../timeline/timeline_zoom_limits.dart' show TimelineZoomLimits;

/// WHERE THIS PROJECT'S PANELS WERE LEFT — the conte's zoom, and how far each
/// frame panel is scrolled along both of its axes (F-267, 유저 2026-10-01:
/// 「콘티패널,타임라인패널 스크롤상태, 콘티패널, 그리고 각 컷들 줌 상태도
/// 프로젝트 파일에 기록해서 다시 열면 그대로 열리도록」) — and how they write
/// a frame (F-354).
///
/// The PROJECT's, as `TimelineZoomMemory` and the canvas framing are (I-7, a
/// project per tab). ↩️The window held these, one set for every tab: a
/// project came on screen at the zoom and the scroll the last one was left
/// at, and a save of a tab behind wrote down the one in front. Saved beside
/// the project, not in it (`ProjectResume`) — zooming and scrolling are not
/// edits.
class PanelViewMemory {
  /// The conte's zoom, in pixels a frame — one for the whole track, which
  /// the conte shows end to end.
  final ValueNotifier<double> storyboardPixelsPerFrame = ValueNotifier(
    defaultStoryboardPixelsPerFrame,
  );

  /// 80% on the bar — a zoom on one of its steps, so the first nudge moves
  /// the number with the zoom (F-403, [TimelineZoomLimits.clamped]).
  /// ↩️The same zoom read 40% from F-403 to F-491; 8 pixels a frame before
  /// it: 33.3% then, between two steps now.
  static const double defaultStoryboardPixelsPerFrame =
      400 * TimelineZoomLimits.referencePixelsPerFrame / 1000;

  /// How the frame rulers count ([FrameRulerView]: frames, seconds+frames
  /// or pages, I-81) — the DISPLAY (초+코마 표시) that writes a frame's
  /// place and a length: the rulers, the block words, and every list that
  /// names a frame (`ProjectAccess.framePlaceLabel`).
  ///
  /// 🗣️F-354 (유저 2026-10-13): 「초+코마 표시 설정한게 저장되도록. 파일안에.
  /// 열렸을때 같은상태 유지하고싶어서」 — so it is the project's, saved beside
  /// it as the zoom is. ↩️It was the window's (`EditorAppSettings`), one
  /// for every tab and forgotten at every restart; before that, until F-284
  /// (유저 2026-10-04: 「이런 표기는 초+코마 표기로 바꾼거에 대응하도록 법
  /// 통일」), the workspace's — where the lists the session's verbs write
  /// could not read it. The session holds this, so they still can.
  final ValueNotifier<FrameRulerView> rulerView = ValueNotifier(
    FrameRulerView.frames,
  );

  /// Where each frame grid's FRAME axis is scrolled to, in pixels at that
  /// grid's own zoom, one per rail ([LayerRailId]): the grid and its folded
  /// row read the one fact (F-143), and a save writes it.
  final Map<String, ValueNotifier<double>> frameAxisOffsets = _onePerRail();

  /// Where each frame panel's LAYER axis is scrolled to — the timeline's
  /// rows, the sheet's columns, the conte's rows — in pixels, one per rail:
  /// the panel is born there, and a save writes it.
  final Map<String, ValueNotifier<double>> layerAxisOffsets = _onePerRail();

  static Map<String, ValueNotifier<double>> _onePerRail() => {
    for (final railId in LayerRailId.values) railId: ValueNotifier<double>(0),
  };

  /// What a save writes of [offsets]: the rails scrolled away from their
  /// start — a rail at its start has nothing to say.
  static Map<String, double> awayFromTheStart(
    Map<String, ValueNotifier<double>> offsets,
  ) => {
    for (final MapEntry(key: rail, value: offset) in offsets.entries)
      if (offset.value > 0) rail: offset.value,
  };

  /// Each rail [saved] names, put back in [offsets] where it was.
  static void standAt(
    Map<String, ValueNotifier<double>> offsets,
    Map<String, double> saved,
  ) {
    for (final MapEntry(key: rail, value: offset) in saved.entries) {
      offsets[rail]?.value = offset;
    }
  }

  void dispose() {
    storyboardPixelsPerFrame.dispose();
    rulerView.dispose();
    for (final offset in [
      ...frameAxisOffsets.values,
      ...layerAxisOffsets.values,
    ]) {
      offset.dispose();
    }
  }
}
