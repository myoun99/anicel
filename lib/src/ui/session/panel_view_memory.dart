import 'package:flutter/foundation.dart';

import '../timeline/layer_rail_window.dart' show LayerRailId;

/// WHERE THIS PROJECT'S PANELS WERE LEFT — the conte's zoom, and how far each
/// frame panel's frame axis is scrolled (F-267, 유저 2026-10-01: 「콘티패널,
/// 타임라인패널 스크롤상태, 콘티패널, 그리고 각 컷들 줌 상태도 프로젝트 파일에
/// 기록해서 다시 열면 그대로 열리도록」).
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
  final Map<String, ValueNotifier<double>> frameAxisOffsets = {
    for (final railId in LayerRailId.values) railId: ValueNotifier<double>(0),
  };

  void dispose() {
    storyboardPixelsPerFrame.dispose();
    for (final offset in frameAxisOffsets.values) {
      offset.dispose();
    }
  }
}
