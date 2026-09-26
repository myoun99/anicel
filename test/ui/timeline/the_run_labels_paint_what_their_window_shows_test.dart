import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';
import 'package:anicel/src/ui/timeline/timeline_row_run_labels_painter.dart';

import '../../helpers/exposure_of.dart';
import 'timeline_frame_geometry_probe.dart';

/// 🚨I-22 ③: THE RUN LABELS PAINT WHAT THEIR WINDOW SHOWS.
///
/// Each block's length rides the cells painter as its foreground, so the
/// two paint together — and while the cells drew the frames their scroll
/// window reaches, the labels printed EVERY block's number on the row. A
/// scroll repaints the row at every span crossing: measured at 24px on the
/// ten-minute film, profile build, the labels were 95ms of a 769ms scroll
/// sample. They take the cells' window now and print what it can reach;
/// [TimelineRowRunLabelsPainter.runLabels] still answers for every block.
void main() {
  /// [blocks] blocks of four frames, back to back.
  Layer longLayer(int blocks) => Layer(
    id: const LayerId('long'),
    name: 'long',
    frames: [Frame(id: const FrameId('f'), duration: 1, strokes: const [])],
    timeline: {
      for (var block = 0; block < blocks; block += 1)
        block * 4: const TimelineExposure.drawing(FrameId('f'), length: 4),
    },
  );

  test('a paint prints the labels its window reaches and none past it — and '
      'a scroll across a span repaints them where the window went', () {
    final window = ValueNotifier<int>(0);
    final painter = TimelineRowRunLabelsPainter(
      layer: longLayer(300),
      geometry: testFrameGeometry(
        frameCellExtent: 24,
        frameEndIndexExclusive: 1200,
      ),
      crossAxisExtent: 52,
      showSeconds: false,
      countingBase: 24,
      baseTextStyle: const TextStyle(fontSize: 11),
      windowBucket: window,
      viewportMainExtent: 480,
    );
    // Each label clips to its own block before it prints.
    List<Rect> printedBlocks() {
      final canvas = TestRecordingCanvas();
      painter.paint(canvas, const Size(1200 * 24, 52));
      return [
        for (final call in canvas.invocations)
          if (call.invocation.memberName == #clipRect)
            call.invocation.positionalArguments.first as Rect,
      ];
    }

    expect(painter.runLabels(), hasLength(300), reason: 'premise: every block');
    final atStart = printedBlocks();
    expect(atStart, isNotEmpty, reason: 'premise: the window has labels');
    // Bucket 0 of a 20-cell viewport reaches frame 26
    // ([timelineFrameWindowFor]).
    expect(atStart.where((block) => block.left >= 26 * 24.0), isEmpty);

    var repaints = 0;
    painter.addListener(() => repaints += 1);
    window.value = 200;
    expect(repaints, 1, reason: 'the window moved, so the labels repaint');
    final later = printedBlocks();
    expect(later, isNotEmpty);
    expect(
      later.where((block) => block.right <= (200 * 4 - 2) * 24.0),
      isEmpty,
      reason: 'the labels behind the window are not printed',
    );
  });

  testWidgets('a timeline row hands its labels the window its cells take', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200 * 24,
            height: 52,
            child: TimelineFrameCellsRow(
              layer: longLayer(300),
              playbackFrameCount: 1200,
              geometry: testFrameGeometry(
                frameCellExtent: 24,
                frameEndIndexExclusive: 1200,
              ),
              crossAxisExtent: 52,
              exposureStateForLayer: exposureOf,
              onSelectLayer: (_) {},
              onSelectFrame: (_) {},
              commaDrag: TimelineCommaDragCallbacks(
                onBegin: (_, _, _) => true,
                onUpdate: (_) {},
                onEnd: () {},
                onCancel: () {},
              ),
              windowBucket: ValueNotifier<int>(0),
              viewportMainExtent: 480,
            ),
          ),
        ),
      ),
    );

    final painter =
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey<String>('timeline-row-cells-long')),
                )
                .foregroundPainter!
            as TimelineRowRunLabelsPainter;
    expect(painter.runLabels(), hasLength(300), reason: 'premise: every block');
    expect(
      painter.runLabelsInWindow().length,
      lessThan(20),
      reason: 'a 480px view of a 28,800px row reaches a handful of blocks',
    );
  });
}
