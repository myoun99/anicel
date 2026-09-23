import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';
import 'package:anicel/src/ui/timeline/se_audio_lane.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cut_end_handle.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_handle.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_run_end_handles.dart';

import 'timeline_frame_geometry_probe.dart';
import 'timeline_row_chrome_probe.dart';

/// 🚨★★★F-163, REOPENED (유저 2026-09-23): 「모서리 클릭해서 위아래
/// 드래그하면 스크롤 작동해버리는거, 아마 카드로도 기록했을텐데, **버튼은
/// 무조건 강한클레임**이라는거 감안해서 같은법 적용해줘」.
///
/// The first landing (09-23 01:19) fixed the WIDGET grip and nothing else:
/// the timeline's drawing rows paint their triangles in one row-wide chrome
/// and route presses to them by rect, and that router still mounted a plain
/// one-axis drag — a vertical pull moved 0 along it, never reached a
/// threshold, and the scroller walked over. And every grip, the widget one
/// included, took no finger while touch scrolls the timeline (UI-R22F) —
/// the 「finger resting to scroll」 case the user has called an assumption.
///
/// ⚠️Driven by MOUSE as well as touch: the app's own scroll behaviour drags
/// with a mouse (a plain ListView would ignore it, and a mouse pin measured
/// without it would pass on a build where the grip does nothing).
void main() {
  // ⚠️THE PRODUCT DEFAULT, on purpose: the test corpus runs touch-as-pen
  // (`AppInputSettings.testCorpusBaseline` — one finger draws, so timeline
  // edits take touch), and under it the grips took a finger before this fix
  // as well. Only with one finger scrolling the timeline — what ships — is
  // there a device the grips used to hand to the scroller.
  setUp(() => AppInput.settings.value = const AppInputSettings());
  tearDown(
    () => AppInput.settings.value = AppInputSettings.testCorpusBaseline,
  );

  Layer oneRun() => Layer(
    id: const LayerId('layer-a'),
    name: 'A',
    frames: [Frame(id: const FrameId('f1'), duration: 1, strokes: const [])],
    timeline: {0: const TimelineExposure.drawing(FrameId('f1'), length: 2)},
  );

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) {
    if (layer.timeline[frameIndex]?.isDrawing ?? false) {
      return TimelineCellExposureState.drawingStart;
    }
    if (coveringDrawingBlockAt(layer.timeline, frameIndex) != null) {
      return TimelineCellExposureState.held;
    }
    return TimelineCellExposureState.uncovered;
  }

  Future<ScrollController> pumpInAScroller(
    WidgetTester tester,
    Widget child,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: ListView(
              controller: controller,
              children: [
                const SizedBox(height: 60),
                child,
                const SizedBox(height: 900),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> pullDown(
    WidgetTester tester,
    Offset from,
    PointerDeviceKind kind,
  ) async {
    final gesture = await tester.startGesture(from, kind: kind);
    await tester.pump();
    for (var i = 0; i < 6; i += 1) {
      await gesture.moveBy(const Offset(0, -14));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Widget denseRow({
    required List<TimelineBlockEdge> gripBegins,
    required List<bool> addBegins,
  }) => SizedBox(
    height: 52,
    child: TimelineFrameCellsRow(
      layer: oneRun(),
      active: true,
      playbackFrameCount: 24,
      geometry: testFrameGeometry(
        frameCellExtent: 48,
        frameEndIndexExclusive: 8,
      ),
      crossAxisExtent: 52,
      exposureStateForLayer: stateFor,
      onSelectLayer: (_) {},
      onSelectFrame: (_) {},
      commaDrag: TimelineCommaDragCallbacks(
        onBegin: (_, _, edge) {
          gripBegins.add(edge);
          return true;
        },
        onUpdate: (_) {},
        onEnd: () {},
        onCancel: () {},
      ),
      runEdit: TimelineRunEditCallbacks(
        onAddBegin: (_, _, {required atEnd}) {
          addBegins.add(atEnd);
          return true;
        },
        onAddUpdate: (_) {},
        onAddEnd: () {},
        onAddCancel: () {},
        onEdgeModeSelected: (_, _, _, _, {scopeToSelection = false}) {},
      ),
    ),
  );

  for (final kind in const [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('🚨a pull ACROSS the dense row\'s edge triangle never scrolls, '
        'and the edge holds it (${kind.name})', (tester) async {
      final gripBegins = <TimelineBlockEdge>[];
      final controller = await pumpInAScroller(
        tester,
        denseRow(gripBegins: gripBegins, addBegins: []),
      );
      await pullDown(
        tester,
        timelineRowChromeCenter(
          tester,
          'layer-a',
          'block-edge-grip-end-layer-a-0',
        ),
        kind,
      );
      expect(controller.offset, 0, reason: '「버튼은 무조건 강한클레임」');
      expect(gripBegins, [TimelineBlockEdge.end]);
    });

    testWidgets('🚨…and so does the [+] beside it (${kind.name})', (
      tester,
    ) async {
      final addBegins = <bool>[];
      final controller = await pumpInAScroller(
        tester,
        denseRow(gripBegins: [], addBegins: addBegins),
      );
      await pullDown(
        tester,
        timelineRowChromeCenter(tester, 'layer-a', 'run-add-end-layer-a-0'),
        kind,
      );
      expect(controller.offset, 0);
      expect(addBegins, [true]);
    });
  }

  testWidgets('⛔a pull that starts OFF every control still scrolls — 그 외는 '
      '스크롤이다', (tester) async {
    final gripBegins = <TimelineBlockEdge>[];
    final controller = await pumpInAScroller(
      tester,
      denseRow(gripBegins: gripBegins, addBegins: []),
    );
    // The spacer above the row: nothing there is anybody's control.
    await pullDown(
      tester,
      tester.getTopLeft(find.byType(ListView)) + const Offset(40, 30),
      PointerDeviceKind.touch,
    );
    expect(controller.offset, greaterThan(0));
    expect(gripBegins, isEmpty);
  });

  testWidgets('🚨the WIDGET grip takes a finger too — no device is sent to the '
      'scroller from a control', (tester) async {
    final begins = <TimelineBlockEdge>[];
    final controller = await pumpInAScroller(
      tester,
      Center(
        child: SizedBox(
          width: 40,
          height: 40,
          child: TimelineBlockEdgeGrip(
            layerId: const LayerId('layer-a'),
            blockStartIndex: 0,
            blockOrdinal: 0,
            edge: TimelineBlockEdge.end,
            resolveFrameCellExtent: () => 48,
            callbacks: TimelineCommaDragCallbacks(
              onBegin: (_, _, edge) {
                begins.add(edge);
                return true;
              },
              onUpdate: (_) {},
              onEnd: () {},
              onCancel: () {},
            ),
          ),
        ),
      ),
    );
    await pullDown(
      tester,
      tester.getCenter(find.byType(TimelineBlockEdgeGrip)),
      PointerDeviceKind.touch,
    );
    expect(controller.offset, 0);
    expect(begins, [TimelineBlockEdge.end]);
  });

  for (final kind in const [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('🚨the cut\'s END handle holds a cross pull as well — the '
        'third grip of the same law (${kind.name})', (tester) async {
      var begun = 0;
      final controller = await pumpInAScroller(
        tester,
        SizedBox(
          height: 52,
          child: Stack(
            children: [
              TimelineCutEndDragHandle(
                cellExtent: 48,
                playbackFrameCount: 4,
                callbacks: TimelineCutEndDragCallbacks(
                  cutId: const CutId('cut'),
                  onBegin: () {
                    begun += 1;
                    return true;
                  },
                  onUpdate: (_) {},
                  onEnd: () {},
                  onCancel: () {},
                ),
              ),
            ],
          ),
        ),
      );
      await pullDown(
        tester,
        tester.getCenter(find.byType(TimelineCutEndDragHandle)),
        kind,
      );
      expect(controller.offset, 0);
      expect(begun, 1);
    });
  }

  for (final kind in const [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('🚨a sound\'s lane span holds a cross pull too — sliding the '
        'sound is its verb (${kind.name})', (tester) async {
      final controller = await pumpInAScroller(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: TimelineGridMetrics.defaults.layerRowHeight,
            child: SeAudioLaneFrameRow(
              layer: Layer(
                id: const LayerId('se'),
                name: 'S1',
                kind: LayerKind.se,
                frames: [
                  Frame(id: const FrameId('se-f'), duration: 1, strokes: const []),
                ],
                timeline: const {
                  2: TimelineExposure.drawing(FrameId('se-f'), length: 8),
                },
                audioClips: const [
                  AudioClip(filePath: 'steps.wav', frameId: FrameId('se-f')),
                ],
              ),
              frameStartIndex: 0,
              frameEndIndexExclusive: 16,
              leadingFrameSpacerWidth: 0,
              trailingFrameSpacerWidth: 0,
              metrics: TimelineGridMetrics.defaults,
              frameRate: ProjectFrameRate.fps24,
              audioPeaksFor: (_) =>
                  AudioPeaks(bucketsPerSecond: 80, peaks: Float32List(160)),
              onSetClipOffset: (_, _) {},
            ),
          ),
        ),
      );
      await pullDown(
        tester,
        tester.getCenter(
          find.byKey(const ValueKey<String>('timeline-audio-lane-span-se-0-b2')),
        ),
        kind,
      );
      expect(controller.offset, 0);
    });
  }
}
