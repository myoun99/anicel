import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';
import 'package:anicel/src/ui/timeline/timeline_row_edit_chrome.dart';

import '../../helpers/exposure_of.dart';
import 'timeline_frame_geometry_probe.dart';
import 'timeline_row_chrome_probe.dart';

/// 🚨I-22 ③: THE EDIT CHROME PAINTS WHAT ITS WINDOW SHOWS.
///
/// The storyboard's cut row spans the whole film, and its chrome drew every
/// grip of it whenever it painted — ~900 at ten minutes, when the view at
/// 24px a frame shows about twenty. Measured on the ten-minute film: the
/// chrome's paint was the heaviest item of a playback tick at every zoom
/// (327ms of samples at 24px, 522ms at 0.16px, debug). It takes the row's
/// scroll window now, as the cells under it do (UI-R15), and draws what the
/// window can reach; hit testing still reads every target.
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

  test('a paint draws the grips its window reaches and none past it — and '
      'a scroll across a span repaints it where the window went', () {
    final layer = longLayer(300);
    final window = ValueNotifier<int>(0);
    final painter = TimelineRowEditChromePainter(
      resolver: TimelineRowChromeResolver(
        gripBlocks: timelineLayerGripBlocks(layer),
        gripIdScope: 'long',
        layer: layer,
        baseLayer: layer,
        crossAxisExtent: 28,
        axis: Axis.horizontal,
        includeRunEdges: false,
      ),
      geometry: testFrameGeometry(
        frameCellExtent: 24,
        frameEndIndexExclusive: 1200,
      ),
      colorScheme: const ColorScheme.dark(),
      face: const TextStyle(fontSize: 11),
      hoveredId: null,
      operatingId: null,
      draggingGripId: null,
      devicePixelRatio: 1,
      windowBucket: window,
      viewportMainExtent: 480,
    );
    Iterable<Rect> drawnGrips() {
      final canvas = TestRecordingCanvas();
      painter.paint(canvas, const Size(1200 * 24, 28));
      return [
        for (final call in canvas.invocations)
          if (call.invocation.memberName == #drawPath)
            (call.invocation.positionalArguments.first as Path).getBounds(),
      ];
    }

    expect(painter.targets, hasLength(600), reason: 'premise: every edge');
    final atStart = drawnGrips();
    expect(atStart, isNotEmpty, reason: 'premise: the window has grips');
    // Bucket 0 of a 20-cell viewport reaches frame 26
    // ([timelineFrameWindowFor]).
    expect(atStart.where((grip) => grip.left > 26 * 24.0), isEmpty);

    var repaints = 0;
    painter.addListener(() => repaints += 1);
    window.value = 200;
    expect(repaints, 1, reason: 'the window moved, so the chrome repaints');
    final later = drawnGrips();
    expect(later, isNotEmpty);
    expect(
      later.where((grip) => grip.right < 200 * 4 * 24.0 - 2 * 24),
      isEmpty,
      reason: 'the grips behind the window are not drawn',
    );
  });

  testWidgets('a timeline row hands its chrome the window its cells take', (
    tester,
  ) async {
    final layer = longLayer(300);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200 * 24,
            height: 52,
            child: TimelineFrameCellsRow(
              layer: layer,
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

    final painter = timelineRowChromePainter(tester, 'long')!;
    expect(painter.targets, hasLength(600), reason: 'premise: every edge');
    expect(
      painter.targetsInWindow.length,
      lessThan(20),
      reason: 'a 480px view of a 28,800px row reaches a handful of blocks',
    );
  });

  testWidgets('the storyboard cut row hands its chrome the window its blocks '
      'take', (tester) async {
    // Sixty cuts of three panels: 180 panels, 360 edges — at 24px a frame
    // the view reaches the first few cuts.
    final project = Project(
      id: const ProjectId('chrome-window'),
      name: 'Chrome window',
      createdAt: DateTime.utc(2026, 9, 27),
      tracks: [
        Track(
          id: const TrackId('t'),
          name: 'Video',
          cuts: [
            for (var cut = 0; cut < 60; cut += 1)
              Cut(
                id: CutId('c$cut'),
                name: 'C$cut',
                duration: 96,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  Layer(
                    id: LayerId('c$cut-sb'),
                    name: 'SB',
                    kind: LayerKind.storyboard,
                    frames: [
                      for (var panel = 0; panel < 3; panel += 1)
                        Frame(
                          id: FrameId('c$cut-p$panel'),
                          duration: 1,
                          strokes: const [],
                        ),
                    ],
                    timeline: {
                      for (var panel = 0; panel < 3; panel += 1)
                        panel * 32: TimelineExposure.drawing(
                          FrameId('c$cut-p$panel'),
                          length: 32,
                        ),
                    },
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(1900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project)),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();

    final painter = timelineRowChromePainter(
      tester,
      't',
      prefix: 'storyboard',
    )!;
    expect(
      painter.targets.length,
      greaterThan(300),
      reason: 'premise: the row carries the whole film',
    );
    expect(
      painter.targetsInWindow.length,
      lessThan(painter.targets.length ~/ 4),
      reason: 'it draws what the view can reach',
    );
  });
}
