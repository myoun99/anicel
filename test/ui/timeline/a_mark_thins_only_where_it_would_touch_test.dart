import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show buildAppTheme;
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineFittedGlyphFontSize;
import 'package:anicel/src/ui/timeline/timeline_frame_header_row.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_ruler_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_glyph_cache.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';

/// 🗣️I-22 (유저 2026-09-12): 「추가로 지금 룰러 텍스트나 그리드가 너무 빨리?
/// 사라지는느낌. 뭐냐면 33.3%배율에서 3f마다의 그리드 세로선이랑 글자, 아직
/// 존재해도 안겹칠거같은데 뭔가 벌써 사라져? 이런느낌. 1f마다 그리드선이랑
/// 글자도 똑같음. 최대한 버텨보자. 룰러 텍스트 글자가 겹칠때 생략한다는
/// 느낌으로. 지금 겹칠 기미도 안보이는데 벌써 생략시작하는느낌」.
///
/// A mark on the frame axis thins out where it would touch the next one, and
/// not before: a number by its width, a grid line by its stroke. The ruler
/// here is the real header row — the timeline's and the storyboard's —
/// read back through its painter.
void main() {
  final scheme = buildAppTheme().colorScheme;

  Future<TimelineRulerScale> rulerOf(
    WidgetTester tester, {
    required double cell,
    required int frames,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: TimelineFrameHeaderRow(
              frameStartIndex: 0,
              frameEndIndexExclusive: frames,
              currentFrameIndex: -1,
              playbackFrameCount: frames,
              leadingFrameSpacerWidth: 0,
              trailingFrameSpacerWidth: 0,
              metrics: TimelineGridMetrics.defaults.copyWith(
                frameCellWidth: cell,
              ),
              onSelectFrame: (_) {},
            ),
          ),
        ),
      ),
    );
    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey<String>('timeline-frame-ruler-paint')),
    );
    return (paint.painter! as TimelineFrameRulerPainter).scale;
  }

  /// The box of the NUMBER the ruler writes at [frame], or null where it
  /// writes none.
  Rect? numberAt(TimelineRulerScale scale, int frame) {
    for (final glyph in TimelineFrameRulerPainter.glyphsAt(
      scale,
      frame,
      current: false,
    )) {
      if (glyph.painter.plainText == '${frame + 1}') {
        return glyph.rect;
      }
    }
    return null;
  }

  group('the ruler\'s numbers', () {
    testWidgets('at 33% two digits keep every third frame — three cells hold '
        'one with room to spare', (tester) async {
      expect(
        timelineGlyphPainter('00', const TextStyle(fontSize: 10)).width + 2,
        lessThanOrEqualTo(3 * 8),
        reason: 'fixture: the every-Nth number fits three 8px cells',
      );
      final scale = await rulerOf(tester, cell: 8, frames: 30);
      expect(scale.modelAt(3).label, '4');
      expect(scale.modelAt(6).label, '7');
      expect(scale.modelAt(4).label, '');
    });

    testWidgets('four digits that would run into each other thin out, even '
        'at 100%', (tester) async {
      expect(
        timelineGlyphPainter(
              '1000',
              TextStyle(
                fontSize: timelineFittedGlyphFontSize(
                  11,
                  24,
                  crossExtent: TimelineGridMetrics.defaults.layerRowHeight,
                ),
              ),
            ).width +
            2,
        greaterThan(24),
        reason: 'fixture: a four-digit number does not fit its own 24px cell',
      );
      final scale = await rulerOf(tester, cell: 24, frames: 1200);
      expect(scale.modelAt(1).label, '');
      expect(scale.modelAt(3).label, '4');
    });

    testWidgets('whatever the zoom and the length, neighbouring numbers never '
        'touch', (tester) async {
      for (final frames in [9, 30, 120, 1200]) {
        for (final cell in [4.0, 8.0, 12.0, 16.0, 20.0, 24.0, 36.0]) {
          final scale = await rulerOf(tester, cell: cell, frames: frames);
          Rect? previous;
          for (var frame = 0; frame < frames && frame < 240; frame += 1) {
            final number = numberAt(scale, frame);
            if (number == null) {
              continue;
            }
            if (previous != null) {
              expect(
                number.left - previous.right,
                greaterThanOrEqualTo(2 - 1e-9),
                reason: '$frames frames at ${cell}px: number ${frame + 1}',
              );
            }
            previous = number;
          }
        }
      }
    });
  });

  group('the grid\'s lines', () {
    ({Color color, double strokeWidth})? lineAt(int frame, double cell) =>
        timelineFrameBoundaryLineInk(
          frameIndex: frame,
          frameCellExtent: cell,
          framesPerSecond: 24,
          colorScheme: scheme,
        );

    test('at 33% every frame keeps its line — 8px leaves a line its ground',
        () {
      for (var frame = 1; frame < 6; frame += 1) {
        expect(lineAt(frame, 8), isNotNull, reason: 'frame $frame');
      }
    });

    test('at 10% a line stands every third frame, where a line and its '
        'ground fit', () {
      expect(lineAt(3, 2.4), isNotNull);
      expect(lineAt(9, 2.4), isNotNull);
      expect(
        lineAt(1, 2.4),
        isNull,
        reason: 'one 2.4px frame is narrower than a line and its ground',
      );
      expect(lineAt(4, 2.4), isNull);
    });
  });
}
