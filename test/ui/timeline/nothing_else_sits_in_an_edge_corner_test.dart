import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/timeline/axis_turn.dart'
    show rectAlong, sizedAlong;
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_span_layout.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart';

import '../../helpers/an_se_row.dart';

/// I-43 (유저 2026-09-23): the edges took the two corners — so what used to
/// stand in them moved out.
///
/// ① The SE block's red closing line: 「se는 왜 제안에서 엣지가 빨간색
/// 남아있지? 그부분만 혹시모르니 잘 통일해주고」 — it stood exactly where
/// every block's edge used to, so it read as a red edge. The block views
/// close an SE block the way they close every block.
///
/// ② The block warning (SE clipped take, D26 crossing fade): 「(나) 윗변
/// 줄」 — a red line along the block's near long edge, end to end, instead
/// of an 11px triangle in the top-right corner the end edge now owns.
void main() {
  testWidgets('the SE writing draws no red of its own — no closing line '
      'where the edge used to be', (tester) async {
    for (final axis in Axis.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: sizedAlong(
              axis,
              along: 200,
              across: 28,
              child: SeSpanVisual(
                layer: anSeRow(),
                axis: axis,
                frames: 10,
                dialogue: 'ガチャ',
                seName: 'ドア',
              ),
            ),
          ),
        ),
      );
      final red = find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == AppColors.danger,
      );
      expect(red, findsNothing, reason: '$axis');
    }
  });

  group('the block warning runs along the block\'s near long edge', () {
    Layer clipped() => Layer(
      id: const LayerId('se-warn'),
      name: 'S1',
      kind: LayerKind.se,
      frames: [Frame(id: const FrameId('f1'), duration: 1, strokes: const [])],
      timeline: const {2: TimelineExposure.drawing(FrameId('f1'), length: 4)},
      audioClips: [
        AudioClip(filePath: 'a.wav', frameId: const FrameId('f1'), clipped: true),
      ],
    );

    const marker = ValueKey<String>('timeline-block-warning-se-warn-b2');

    /// Pumps the row's warning; what it paints, the line, is measured.
    Future<Rect> warning(WidgetTester tester, Axis axis) async {
      const cell = 20.0;
      const cross = 28.0;
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: sizedAlong(
              axis,
              along: 400,
              across: cross,
              child: TimelineFixedFrameSpanLayer(
                geometry: const TimelineFrameGeometry(
                  frameCellExtent: cell,
                  frameStartIndex: 0,
                  frameEndIndexExclusive: 20,
                ),
                crossAxisExtent: cross,
                axis: axis,
                children: timelineRowSoundWarningOverlays(
                  layer: clipped(),
                  frameStartIndex: 0,
                  frameEndIndexExclusive: 20,
                  crossAxisExtent: cross,
                  axis: axis,
                  warnings: (clipped: 'clipped take', cannotPlay: null),
                  color: AppColors.danger,
                ),
              ),
            ),
          ),
        ),
      );
      return tester.getRect(
        find.descendant(
          of: find.byKey(marker),
          matching: find.byWidgetPredicate(
            (widget) => widget is CustomPaint && widget.painter != null,
          ),
        ),
      );
    }

    testWidgets('the timeline: the top edge, end to end', (tester) async {
      final line = await warning(tester, Axis.horizontal);
      expect(
        line,
        const Rect.fromLTWH(
          2 * 20,
          0,
          4 * 20,
          timelineBlockWarningBarThickness,
        ),
      );
    });

    testWidgets('the X-sheet: turned on its side — the left edge, end to '
        'end', (tester) async {
      final line = await warning(tester, Axis.vertical);
      expect(
        line,
        const Rect.fromLTWH(
          0,
          2 * 20,
          timelineBlockWarningBarThickness,
          4 * 20,
        ),
      );
    });

    // 🗣️F-495 (유저 2026-10-28): 「블록에 호버하면 툴팁 띄우도록」.
    for (final axis in Axis.values) {
      testWidgets('its hover is the whole block\'s ($axis)', (tester) async {
        await warning(tester, axis);
        expect(
          tester.getRect(find.byKey(marker)),
          rectAlong(
            axis,
            along: (from: 2 * 20, to: 6 * 20),
            across: (from: 0, to: 28),
          ),
        );
      });
    }
  });
}
