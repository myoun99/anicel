import 'package:flutter/foundation.dart';

import '../timeline/layer_rail_window.dart' show LayerRailId;

/// WHERE THIS PROJECT'S PANELS WERE LEFT — the conte's zoom, and how far each
/// frame panel is scrolled along both of its axes (F-267, 유저 2026-10-01:
/// 「콘티패널,타임라인패널 스크롤상태, 콘티패널, 그리고 각 컷들 줌 상태도
/// 프로젝트 파일에 기록해서 다시 열면 그대로 열리도록」).
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

  static const double defaultStoryboardPixelsPerFrame = 8;

  /// Where each frame grid's FRAME axis is scrolled to, in pixels at that
  /// grid's own zoom, one per rail ([LayerRailId]): the grid and its folded
  /// row read the one fact (F-143), and a save writes it.
  final Map<String, ValueNotifier<double>> frameAxisOffsets = _onePerRail();

  /// Where each frame grid's LAYER axis is scrolled to — the timeline's
  /// rows, the sheet's columns — in pixels, one per rail: the grid is born
  /// there, and a save writes it.
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
    for (final offset in [
      ...frameAxisOffsets.values,
      ...layerAxisOffsets.values,
    ]) {
      offset.dispose();
    }
  }
}
