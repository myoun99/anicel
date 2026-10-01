import '../../models/cut_id.dart';

/// THE TIMELINE ZOOM EACH CUT WAS LEFT AT (F-253, 유저 2026-10-01:
/// 「타임라인패널의 줌 상태는 컷마다 기억하도록. 지금 한번 바꾸면 컷마다
/// 다른컷에서 바꾼 값 따라가니」).
///
/// View state, like [RailView]: session-only, never saved. It lives with the
/// SESSION for RailView's reason (I-7, a project per tab): it names CUT IDS,
/// which are the project's — every new project's first cut has the same
/// one — so a map the window kept would hand one project's zoom to another.
///
/// A cut nobody zoomed has no entry: it opens at the default, not at the
/// zoom another cut was left at — that following was the report.
class TimelineZoomMemory {
  final Map<CutId, double> _byCut = {};

  /// The zoom [cut] was left at, or null when it never was zoomed.
  double? zoomOf(CutId? cut) => cut == null ? null : _byCut[cut];

  /// [cut] is now shown at [zoom]. Nothing to remember without a cut.
  void remember(CutId? cut, double zoom) {
    if (cut != null) {
      _byCut[cut] = zoom;
    }
  }
}
