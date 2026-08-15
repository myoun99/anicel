import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_ruler_cursor_overlay.dart';

/// B1 — the ready bar has NO content-end clamp (유저 2026-08-16: 「왜
/// 콘텐츠끝너머가 초록이되면 안되는거지? 재생가능한거잖아」). The old strip
/// stopped at the cut's playback length, which repainted "ready by
/// definition" answers past the drawings as "not ready" — the runs must
/// cover whatever the predicate says across the whole rendered window.
void main() {
  test('ready runs reach the rendered edge, not the content edge', () {
    final painter = TimelineRulerCursorOverlayPainter(
      playhead: null,
      repaintSignal: null,
      windowBucket: ValueNotifier<int>(0),
      viewportMainExtent: 0, // window falls back to the full rendered span
      renderedFrames: 10,
      cellWidth: 8,
      isFrameReady: (_) => true,
    );

    expect(
      painter.readyRuns(),
      [(startIndex: 0, endIndexExclusive: 10)],
      reason: 'a 4-frame cut whose ruler renders 10 frames paints green '
          'across all 10 when every frame answers ready',
    );
  });
}
