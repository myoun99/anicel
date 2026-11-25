import 'package:flutter/foundation.dart';

import '../../models/cut_id.dart';
import '../../models/timeline_id.dart';
import '../timeline/frame_ruler_view.dart';
import '../timeline/layer_rail_window.dart' show LayerRailId;
import '../timeline/timeline_zoom_limits.dart' show TimelineZoomLimits;

/// WHERE THIS PROJECT'S PANELS WERE LEFT — the conte's zoom, and how far each
/// frame panel is scrolled along both of its axes (F-267, 유저 2026-10-01:
/// 「콘티패널,타임라인패널 스크롤상태, 콘티패널, 그리고 각 컷들 줌 상태도
/// 프로젝트 파일에 기록해서 다시 열면 그대로 열리도록」) — and how they write
/// a frame (F-354).
///
/// 🗣️H78 (유저 2026-11-24): 「타임라인별로 스크롤상태, 줌상태 별도기억,
/// 내부컷도 마찬가지」 — each timeline keeps the conte's scroll and zoom of
/// its own, and each cut the timeline panel's and the sheet's scroll
/// ([PanelAxes]), as each cut kept its zoom already (`TimelineZoomMemory`,
/// F-253). ↩️One scroll a panel, for every cut and every timeline: a cut or
/// a timeline opened showed the panels where the last one was left.
///
/// The PROJECT's, as `TimelineZoomMemory` and the canvas framing are (I-7, a
/// project per tab). ↩️The window held these, one set for every tab: a
/// project came on screen at the zoom and the scroll the last one was left
/// at, and a save of a tab behind wrote down the one in front. Saved beside
/// the project, not in it (`ProjectResume`) — zooming and scrolling are not
/// edits.
class PanelViewMemory {
  /// Memory for the panels of a project whose cut open [cut] and whose
  /// timeline open [timeline] say — what each rail's scroll is kept by.
  PanelViewMemory({
    required CutId? Function() cut,
    required TimelineId? Function() timeline,
  }) : _timeline = timeline {
    String scopeOf(String rail) => switch (rail) {
      LayerRailId.storyboard => timeline()?.value ?? '',
      _ => cut()?.value ?? '',
    };
    frameAxisOffsets = PanelAxes._(scopeOf);
    layerAxisOffsets = PanelAxes._(scopeOf);
  }

  final TimelineId? Function() _timeline;

  /// The conte's zoom, in pixels a frame — the open timeline's, which the
  /// conte shows end to end: each timeline's kept apart
  /// ([followTimeline], H78), and one notifier for whatever listens.
  final ValueNotifier<double> storyboardPixelsPerFrame = ValueNotifier(
    defaultStoryboardPixelsPerFrame,
  );

  /// The conte's zoom each timeline other than the open one was left at,
  /// by its id — one nobody zoomed is not here.
  final Map<String, double> _conteZoomsLeft = {};

  /// The timeline [storyboardPixelsPerFrame] is the zoom of.
  String? _conteZoomOf;

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
  /// grid's own zoom, by rail ([LayerRailId]) — the open cut's or the open
  /// timeline's ([PanelAxes]): the grid and its folded row read the one
  /// fact (F-143), and a save writes every one.
  late final PanelAxes frameAxisOffsets;

  /// Where each frame panel's LAYER axis is scrolled to — the timeline's
  /// rows, the sheet's columns, the conte's rows — in pixels, by rail as
  /// [frameAxisOffsets] is: the panel is born there, and a save writes it.
  late final PanelAxes layerAxisOffsets;

  /// The conte's zoom follows the open timeline: the one it leaves keeps
  /// the zoom it was left at, and the one it opens shows its own — or the
  /// default, where nobody zoomed it (H78, as `TimelineZoomMemory` has
  /// each cut's). Asked at every change of the session's; a change that
  /// leaves the timeline where it was leaves the zoom alone.
  void followTimeline() {
    final now = _timeline()?.value;
    final was = _conteZoomOf;
    if (now == was) {
      return;
    }
    if (was != null) {
      _conteZoomsLeft[was] = storyboardPixelsPerFrame.value;
    }
    _conteZoomOf = now;
    storyboardPixelsPerFrame.value =
        _conteZoomsLeft.remove(now) ?? defaultStoryboardPixelsPerFrame;
  }

  /// The conte zoom of every timeline the conte has shown, by its id — the
  /// open one's as it stands — as a save writes them.
  Map<String, double> get conteZooms => {
    ..._conteZoomsLeft,
    ?_timeline()?.value: storyboardPixelsPerFrame.value,
  };

  /// Each timeline's conte zoom [saved] names, put back — the open one's
  /// shown, by [followTimeline] from here on.
  void standAtConteZooms(Map<String, double> saved) {
    _conteZoomsLeft
      ..clear()
      ..addAll(saved);
    _conteZoomOf = null;
    followTimeline();
  }

  void dispose() {
    storyboardPixelsPerFrame.dispose();
    rulerView.dispose();
    frameAxisOffsets._dispose();
    layerAxisOffsets._dispose();
  }
}

/// ONE AXIS OF EVERY FRAME PANEL, kept apart for each place a panel shows
/// (H78): the timeline panel's and the sheet's for each cut, the conte's
/// for each timeline. `[rail]` is the axis of the place open now — its own
/// notifier, so a panel born on it (keyed by its cut, its timeline) stands
/// where that place was left and moves no other place's.
final class PanelAxes {
  PanelAxes._(this._scopeOf);

  /// The place [rail]'s axis is kept for now — a cut's id or a timeline's.
  final String Function(String rail) _scopeOf;

  /// Every axis kept, by [_keyOf].
  final Map<String, ValueNotifier<double>> _axes = {};

  /// How an axis is named in the map and in a save: its rail, then its
  /// place — `timeline@cut-3`, `storyboard@timeline-1`.
  static String _keyOf(String rail, String scope) => '$rail@$scope';

  /// [rail]'s axis for the place open now — at its start, where it was
  /// never scrolled — or null for a rail there is none of.
  ValueNotifier<double>? operator [](String rail) =>
      LayerRailId.values.contains(rail)
      ? _axes.putIfAbsent(
          _keyOf(rail, _scopeOf(rail)),
          () => ValueNotifier<double>(0),
        )
      : null;

  /// Each rail's axis for the places open now.
  Iterable<ValueNotifier<double>> get values => [
    for (final rail in LayerRailId.values) this[rail]!,
  ];

  /// What a save writes: every axis kept away from its start, by rail and
  /// place — one at its start has nothing to say.
  Map<String, double> get awayFromTheStart => {
    for (final MapEntry(:key, value: offset) in _axes.entries)
      if (offset.value > 0) key: offset.value,
  };

  /// Each axis [saved] names, put back where it was — a place opened
  /// later is born there.
  void standAt(Map<String, double> saved) {
    for (final MapEntry(:key, value: offset) in saved.entries) {
      final at = key.indexOf('@');
      if (at > 0 && LayerRailId.values.contains(key.substring(0, at))) {
        _axes.putIfAbsent(key, () => ValueNotifier<double>(0)).value = offset;
      }
    }
  }

  void _dispose() {
    for (final offset in _axes.values) {
      offset.dispose();
    }
  }
}
