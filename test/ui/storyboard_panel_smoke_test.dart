import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/canvas_size.dart';
import 'package:quick_animaker_v2/src/models/cut.dart';
import 'package:quick_animaker_v2/src/models/cut_id.dart';
import 'package:quick_animaker_v2/src/models/frame.dart';
import 'package:quick_animaker_v2/src/models/frame_id.dart';
import 'package:quick_animaker_v2/src/models/layer.dart';
import 'package:quick_animaker_v2/src/models/layer_id.dart';
import 'package:quick_animaker_v2/src/models/layer_kind.dart';
import 'package:quick_animaker_v2/src/models/project.dart';
import 'package:quick_animaker_v2/src/models/project_id.dart';
import 'package:quick_animaker_v2/src/models/track.dart';
import 'package:quick_animaker_v2/src/models/track_id.dart';
import 'package:quick_animaker_v2/src/ui/storyboard_panel.dart';
import 'package:quick_animaker_v2/src/ui/storyboard_timeline_layout.dart';
import 'storyboard_cut_block_probe.dart';

void main() {
  group('StoryboardPanel baseline smoke tests', () {
    testWidgets('renders current root key without a title header', (
      tester,
    ) async {
      await _pumpStoryboardPanel(tester, _projectWithStoryboardLayer());

      expect(
        find.byKey(const ValueKey<String>('storyboard-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('storyboard-panel-title')),
        findsNothing,
      );
      expect(find.text('STORYBOARD'), findsNothing);
    });

    testWidgets('renders current track row and track label keys', (
      tester,
    ) async {
      await _pumpStoryboardPanel(tester, _projectWithStoryboardLayer());

      expect(
        find.byKey(const ValueKey<String>('storyboard-track-row-track-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('storyboard-track-label-row-track-a'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('storyboard-track-label-track-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('storyboard-track-timeline-area-track-a'),
        ),
        findsOneWidget,
      );
      expect(find.text('V1'), findsOneWidget);
    });

    testWidgets('renders the current cut as a painted block', (tester) async {
      await _pumpStoryboardPanel(tester, _projectWithStoryboardLayer());

      expect(cutBlock(tester, 'cut-a'), isNotNull);
    });

    testWidgets('renders current cut title and cumulative end time', (
      tester,
    ) async {
      await _pumpStoryboardPanel(tester, _projectWithStoryboardLayer());

      final block = requireCutBlock(tester, 'cut-a');
      expect(block.title, 'Cut A');
      // Conte-sheet TIME column bottom-right; the old duration/frame-range
      // row is gone.
      expect(block.total, '24');
    });

    testWidgets('renders current storyboard layer strip when present', (
      tester,
    ) async {
      await _pumpStoryboardPanel(tester, _projectWithStoryboardLayer());

      final block = requireCutBlock(tester, 'cut-a');
      expect(block.hasStoryboardLayer, isTrue);
      expect(block.layerLabel, 'Storyboard');
    });

    testWidgets('marks the active cut without an ACTIVE label', (tester) async {
      await _pumpStoryboardPanel(
        tester,
        _projectWithStoryboardLayer(),
        activeCutId: const CutId('cut-a'),
      );

      // The block's active highlight carries the state; the old text badge
      // is gone.
      expect(find.text('ACTIVE'), findsNothing);
      expect(
        tester
            .widget<StoryboardPanel>(find.byType(StoryboardPanel))
            .activeCutId,
        const CutId('cut-a'),
      );
    });

    testWidgets('preserves current inactive cut selection callback', (
      tester,
    ) async {
      CutId? selectedCutId;

      await _pumpStoryboardPanel(
        tester,
        _twoCutProject(),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (cutId) => selectedCutId = cutId,
      );

      await tester.tapAt(cutBlockCenter(tester, 'cut-b'));
      await tester.pumpAndSettle();

      expect(selectedCutId, const CutId('cut-b'));
    });

    testWidgets('renders current empty layer state when no storyboard layer', (
      tester,
    ) async {
      await _pumpStoryboardPanel(tester, _projectWithoutStoryboardLayer());

      final block = requireCutBlock(tester, 'cut-a');
      expect(block.hasStoryboardLayer, isFalse);
      expect(block.layerLabel, 'No Storyboard Layer');
    });

    testWidgets(
      'renders storyboard layer between animation layers in raw order',
      (tester) async {
        await _pumpStoryboardPanel(tester, _projectWithLayerStack());

        expect(
          requireCutBlock(tester, 'cut-a').layerLabel,
          'Middle Storyboard',
        );
      },
    );

    testWidgets('does not select storyboard layer by name', (tester) async {
      await _pumpStoryboardPanel(tester, _projectWithMisleadingLayerNames());

      final block = requireCutBlock(tester, 'cut-a');
      expect(block.hasStoryboardLayer, isTrue);
      expect(block.layerLabel, 'Animation Named Layer');
    });

    testWidgets('a cut holding two storyboard layers still DRAWS: the row '
        'takes the first as its own rather than red-screening', (tester) async {
      await _pumpStoryboardPanel(
        tester,
        _projectWithMultipleStoryboardLayers(),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('storyboard-track-row-track-a')),
        findsOneWidget,
      );
    });

    testWidgets('renders multi-track rows as storyboard overview', (
      tester,
    ) async {
      await _pumpStoryboardPanel(tester, _multiTrackProject());

      expect(
        find.byKey(const ValueKey<String>('storyboard-track-row-track-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('storyboard-track-row-track-b')),
        findsOneWidget,
      );
      expect(find.text('V1'), findsOneWidget);
      expect(find.text('V2'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>('storyboard-timeline-horizontal-viewport'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('carries the timeline 3-row scrollbar structure '
        '(UI-R10 #15/#21)', (tester) async {
      await _pumpStoryboardPanel(tester, _projectWithStoryboardLayer());

      // TOP: blank slot over the scrollbar lane, beside the ruler.
      expect(
        find.byKey(const ValueKey<String>('timeline-vertical-scrollbar-slot')),
        findsOneWidget,
      );
      // MIDDLE: the timeline's pinned rail between labels and strips.
      final verticalRail = find.byKey(
        const ValueKey<String>('storyboard-vertical-scrollbar'),
      );
      expect(verticalRail, findsOneWidget);
      expect(
        tester.getTopLeft(verticalRail).dx,
        372,
        reason: 'the rail sits right after the 372px label rail',
      );
      // BOTTOM: the pinned horizontal scrollbar row (it must NOT live
      // inside the vertical scroll content anymore).
      final horizontalRail = find.byKey(
        const ValueKey<String>('storyboard-horizontal-scrollbar'),
      );
      expect(horizontalRail, findsOneWidget);
      expect(
        find.ancestor(
          of: horizontalRail,
          matching: find.byKey(
            const ValueKey<String>('storyboard-vertical-viewport'),
          ),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey<String>('storyboard-bottom-scrollbar-left-spacer'),
        ),
        findsOneWidget,
      );
    });
  });
}

Future<void> _pumpStoryboardPanel(
  WidgetTester tester,
  Project project, {
  CutId activeCutId = const CutId('cut-a'),
  ValueChanged<CutId>? onCutSelected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StoryboardPanel(
          project: project,
          activeCutId: activeCutId,
          onRowFramePress: onCutSelected == null
              ? null
              : (row, globalFrame) {
                  for (final entry in buildStoryboardTimelineLayout(project)) {
                    if (globalFrame >= entry.startFrame &&
                        globalFrame < entry.endFrame) {
                      onCutSelected(entry.cutId);
                      return;
                    }
                  }
                },
        ),
      ),
    ),
  );
}

Project _projectWithStoryboardLayer() {
  return _project(storyboardLayer: _layer(LayerKind.storyboard, 'Storyboard'));
}

Project _projectWithoutStoryboardLayer() {
  return _project(storyboardLayer: null);
}

Project _project({required Layer? storyboardLayer}) {
  return Project(
    id: const ProjectId('project-a'),
    name: 'Project A',
    createdAt: DateTime.utc(2026, 6, 20),
    tracks: [
      Track(
        id: const TrackId('track-a'),
        name: 'Track A',
        cuts: [
          Cut(
            id: const CutId('cut-a'),
            name: 'Cut A',
            duration: 24,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            layers: [
              _layer(LayerKind.animation, 'Animation'),
              ?storyboardLayer,
            ],
          ),
        ],
      ),
    ],
  );
}

Project _twoCutProject() {
  return Project(
    id: const ProjectId('project-two-cut'),
    name: 'Project Two Cut',
    createdAt: DateTime.utc(2026, 6, 20),
    tracks: [
      Track(
        id: const TrackId('track-a'),
        name: 'Track A',
        cuts: [
          Cut(
            id: const CutId('cut-a'),
            name: 'Cut A',
            duration: 24,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            layers: [_layer(LayerKind.animation, 'Animation A')],
          ),
          Cut(
            id: const CutId('cut-b'),
            name: 'Cut B',
            duration: 12,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            layers: [_layer(LayerKind.animation, 'Animation B')],
          ),
        ],
      ),
    ],
  );
}

Project _projectWithLayerStack() {
  return _projectWithLayers([
    _layer(LayerKind.animation, 'Below Animation'),
    _layer(LayerKind.storyboard, 'Middle Storyboard'),
    _layer(LayerKind.animation, 'Above Animation'),
  ]);
}

Project _projectWithMisleadingLayerNames() {
  return _projectWithLayers([
    _layer(LayerKind.animation, 'Storyboard'),
    _layer(LayerKind.storyboard, 'Animation Named Layer'),
  ]);
}

Project _projectWithMultipleStoryboardLayers() {
  return _projectWithLayers([
    _layer(LayerKind.storyboard, 'Storyboard A'),
    _layer(LayerKind.animation, 'Animation'),
    _layer(LayerKind.storyboard, 'Storyboard B'),
  ]);
}

Project _projectWithLayers(List<Layer> layers) {
  return Project(
    id: const ProjectId('project-layer-stack'),
    name: 'Project Layer Stack',
    createdAt: DateTime.utc(2026, 6, 20),
    tracks: [
      Track(
        id: const TrackId('track-a'),
        name: 'Track A',
        cuts: [
          Cut(
            id: const CutId('cut-a'),
            name: 'Cut A',
            duration: 24,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            layers: layers,
          ),
        ],
      ),
    ],
  );
}

Project _multiTrackProject() {
  return Project(
    id: const ProjectId('project-multi-track'),
    name: 'Project Multi Track',
    createdAt: DateTime.utc(2026, 6, 20),
    tracks: [
      Track(
        id: const TrackId('track-a'),
        name: 'Track A',
        cuts: [
          Cut(
            id: const CutId('cut-a'),
            name: 'Cut A',
            duration: 24,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            layers: [_layer(LayerKind.storyboard, 'Storyboard A')],
          ),
        ],
      ),
      Track(
        id: const TrackId('track-b'),
        name: 'Track B',
        cuts: [
          Cut(
            id: const CutId('cut-b'),
            name: 'Cut B',
            duration: 12,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            layers: [_layer(LayerKind.storyboard, 'Storyboard B')],
          ),
        ],
      ),
    ],
  );
}

Layer _layer(LayerKind kind, String name) {
  return Layer(
    id: LayerId('layer-${kind.name}-$name'),
    name: name,
    kind: kind,
    frames: [
      Frame(
        id: FrameId('frame-${kind.name}-$name'),
        duration: 1,
        strokes: const [],
      ),
    ],
  );
}
