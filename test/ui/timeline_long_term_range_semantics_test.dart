import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

import 'timeline/timeline_cell_probe.dart';
import 'timeline/timeline_ruler_probe.dart';

void main() {
  group('Timeline long-term range semantics regression', () {
    testWidgets(
      'TimelinePanel renders visible cells beyond Cut.duration playback range',
      (tester) async {
        final fixture = _fixture(cutDuration: 3);

        await tester.pumpWidget(_panel(fixture));

        expect(fixture.cut.duration, 3);
        expect(timelineCellInWindow(tester, 'layer-a', 10), isTrue);
        expect(timelineHeaderInWindow(tester, 10), isTrue);
      },
    );

    testWidgets(
      'out-of-playback authored exposure is represented when its cell is visible',
      (tester) async {
        final fixture = _fixture(cutDuration: 3);

        await tester.pumpWidget(_panel(fixture));

        expect(timelineCellInWindow(tester, 'layer-a', 10), isTrue);
        expect(timelineCellModel(tester, 'layer-a', 10).glyph, 'Late 10');
      },
    );

    testWidgets(
      'cut-end boundary is playback-only and does not remove authored later cells',
      (tester) async {
        final fixture = _fixture(cutDuration: 3);

        await tester.pumpWidget(_panel(fixture));

        expect(
          find.byKey(const ValueKey<String>('timeline-cut-end-boundary')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('timeline-cut-end-boundary-ruler')),
          findsOneWidget,
        );
        expect(timelineCellInWindow(tester, 'layer-a', 10), isTrue);
        expect(timelineCellModel(tester, 'layer-a', 10).glyph, 'Late 10');
      },
    );

    testWidgets(
      'playhead can render beyond authored extent when current frame is visible',
      (tester) async {
        final fixture = _fixture(
          cutDuration: 3,
          layer: _layer(
            timeline: {
              0: TimelineExposure.drawing(const FrameId('head'), length: 1),
            },
          ),
        );

        await tester.pumpWidget(_panel(fixture, currentFrameIndex: 10));

        expect(fixture.authoredExtentFrameCount, 1);
        expect(timelineCellInWindow(tester, 'layer-a', 10), isTrue);
        expect(
          find.byKey(const ValueKey<String>('timeline-playhead')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('timeline-playhead-column')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'selected exposure outline is a display-range visual beyond playback duration',
      (tester) async {
        // The 312px layer rail (fx switch) narrows the default test
        // viewport's frame window below cell 12 — widen the surface so the
        // asserted cells stay rendered.
        await tester.binding.setSurfaceSize(const Size(1000, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final fixture = _fixture(cutDuration: 3);

        await tester.pumpWidget(_panel(fixture, currentFrameIndex: 10));

        final outline = find.byKey(
          const ValueKey<String>(
            'timeline-selected-exposure-range-outline-layer-a',
          ),
        );
        expect(outline, findsOneWidget);
        expect(timelineCellInWindow(tester, 'layer-a', 10), isTrue);
        expect(timelineCellInWindow(tester, 'layer-a', 12), isTrue);

        final positioned = tester.widget<Positioned>(outline);
        expect(
          positioned.width,
          3 * TimelineGridMetrics.defaults.frameCellWidth,
        );
      },
    );
  });
}

_TimelineRangeFixture _fixture({required int cutDuration, Layer? layer}) {
  final resolvedLayer = layer ?? _layer();
  final cut = Cut(
    id: const CutId('cut-a'),
    name: 'Cut A',
    duration: cutDuration,
    canvasSize: const CanvasSize(width: 1920, height: 1080),
    layers: [resolvedLayer],
  );
  final project = Project(
    id: const ProjectId('project-a'),
    name: 'Project A',
    tracks: [
      Track(id: const TrackId('track-a'), name: 'V1', cuts: [cut]),
    ],
    createdAt: DateTime.utc(2026),
  );

  return _TimelineRangeFixture(project: project);
}

Layer _layer({Map<int, TimelineExposure>? timeline}) {
  return Layer(
    id: const LayerId('layer-a'),
    name: 'Layer A',
    frames: [
      Frame(id: const FrameId('head'), duration: 1, strokes: const []),
      Frame(id: const FrameId('late'), duration: 3, strokes: const []),
    ],
    timeline:
        timeline ??
        {
          0: TimelineExposure.drawing(const FrameId('head'), length: 1),
          10: TimelineExposure.drawing(const FrameId('late'), length: 1),
        },
  );
}

Widget _panel(_TimelineRangeFixture fixture, {int currentFrameIndex = 0}) {
  final cut = fixture.cut;

  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 900,
        height: 320,
        child: TimelinePanel(
          layers: cut.layers,
          activeLayerId: cut.layers.single.id,
          frameCursor: ValueNotifier<int>(currentFrameIndex),
          playbackFrameCount: cut.duration,
          exposureStateForLayer: fixture.exposureStateForLayer,
          frameNameForLayer: fixture.frameNameForLayer,
          onSelectLayer: (_) {},
          onSelectFrame: (_) {},
          onAddLayer: () {},
          onToggleLayerVisibility: (_) {},
          onLayerOpacityChanged: (_, _) {},
          onToggleLayerTimesheet: (_) {},
          onLayerMarkSelected: (_, _) {},
          orientation: TimelineOrientation.horizontal,
          onOrientationChanged: (_) {},
        ),
      ),
    ),
  );
}

class _TimelineRangeFixture {
  const _TimelineRangeFixture({required this.project});

  final Project project;

  Cut get cut => project.tracks.single.cuts.single;

  int get authoredExtentFrameCount {
    var extent = 0;
    for (final layer in cut.layers) {
      for (final entry in layer.timeline.entries) {
        final frame = layer.frames.singleWhere(
          (candidate) => candidate.id == entry.value.frameId,
        );
        extent = extent > entry.key + frame.duration
            ? extent
            : entry.key + frame.duration;
      }
    }
    return extent;
  }

  TimelineCellExposureState exposureStateForLayer(Layer layer, int frameIndex) {
    final exposure = layer.timeline[frameIndex];
    if (exposure != null) {
      return TimelineCellExposureState.drawingStart;
    }

    final activeExposureStart = layer.timeline.keys
        .where((startFrameIndex) => startFrameIndex < frameIndex)
        .fold<int?>(null, (latest, startFrameIndex) {
          if (latest == null || startFrameIndex > latest) {
            return startFrameIndex;
          }
          return latest;
        });
    if (activeExposureStart == null) {
      return TimelineCellExposureState.uncovered;
    }

    final activeExposure = layer.timeline[activeExposureStart]!;
    final frame = layer.frames.singleWhere(
      (candidate) => candidate.id == activeExposure.frameId,
    );
    final exposureEndExclusive = activeExposureStart + frame.duration;
    if (frameIndex < exposureEndExclusive) {
      return TimelineCellExposureState.held;
    }
    return TimelineCellExposureState.uncovered;
  }

  String? frameNameForLayer(Layer layer, int frameIndex) {
    final exposure = layer.timeline[frameIndex];
    if (exposure?.frameId == const FrameId('late')) {
      return 'Late 10';
    }
    return null;
  }
}
