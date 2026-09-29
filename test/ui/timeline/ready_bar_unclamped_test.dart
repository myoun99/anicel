import 'dart:ui' show Rect, Size;

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
      readyRunsIn: (start, end) => [
        (startIndex: start, endIndexExclusive: end),
      ],
    );

    expect(
      painter.readyRuns(),
      [(startIndex: 0, endIndexExclusive: 10)],
      reason: 'a 4-frame cut whose ruler renders 10 frames paints green '
          'across all 10 when every frame answers ready',
    );
  });

  // 🗣️F-246 (유저 2026-09-30): 「재생준비완료인 초록띠가 너무 세로가 두꺼움.
  // 지금의 절반정도로 얇게」 — half the 3px it was.
  test('the strip lies half as thick along the ruler\'s edge', () {
    final painter = TimelineRulerCursorOverlayPainter(
      playhead: null,
      repaintSignal: null,
      windowBucket: ValueNotifier<int>(0),
      viewportMainExtent: 0,
      renderedFrames: 10,
      cellWidth: 8,
      readyRunsIn: (start, end) => [
        (startIndex: start, endIndexExclusive: end),
      ],
    );
    final canvas = TestRecordingCanvas();
    painter.paint(canvas, const Size(80, 24));
    final bars = [
      for (final call in canvas.invocations)
        if (call.invocation.memberName == #drawRect)
          call.invocation.positionalArguments.first as Rect,
    ];
    expect(bars, isNotEmpty, reason: 'fixture: a ready run');
    expect([for (final bar in bars) (bar.top, bar.bottom)], [(22.5, 24.0)]);
  });
}
