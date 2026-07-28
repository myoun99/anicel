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
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/storyboard_timeline_layout.dart';
import 'storyboard_cut_block_probe.dart';

void main() {
  testWidgets('the panel body hosts NO cut toolbar (cut commands moved to the '
      'shared CutCommandGroup on the tab toolbars, R-toolbar round)', (
    tester,
  ) async {
    await _pumpPanel(tester, _project(storyboardLayer: null));

    expect(
      find.byKey(const ValueKey<String>('storyboard-cut-actions')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey<String>('new-cut-button')), findsNothing);
  });

  testWidgets('the cut row PAINTS its blocks — one painter, no widget per '
      'cut', (tester) async {
    await _pumpPanel(tester, _project(storyboardLayer: null));

    expect(cutBlocksFinder(trackId: 'track-a'), findsOneWidget);
    expect(requireCutBlock(tester, 'cut-a').title, 'Cut A');
  });

  testWidgets('track rows expose timeline areas for cut positioning', (
    tester,
  ) async {
    await _pumpPanel(tester, _project(storyboardLayer: null));

    expect(
      find.byKey(const ValueKey<String>('storyboard-track-label-rail')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('storyboard-timeline-horizontal-viewport'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-timeline-scroll-content')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-track-row-track-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-track-row-track-b')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('storyboard-track-timeline-area-track-a'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('storyboard-track-timeline-area-track-b'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('track labels stay outside horizontal scroll content', (
    tester,
  ) async {
    await _pumpPanel(tester, _project(storyboardLayer: null));

    final trackLabel = find.byKey(
      const ValueKey<String>('storyboard-track-label-track-a'),
    );
    final labelRail = find.byKey(
      const ValueKey<String>('storyboard-track-label-rail'),
    );
    final scrollContent = find.byKey(
      const ValueKey<String>('storyboard-timeline-scroll-content'),
    );

    expect(
      find.descendant(of: labelRail, matching: trackLabel),
      findsOneWidget,
    );
    expect(
      find.descendant(of: scrollContent, matching: trackLabel),
      findsNothing,
    );
  });

  testWidgets('track labels and timeline lanes stay vertically aligned', (
    tester,
  ) async {
    await _pumpPanel(tester, _project(storyboardLayer: null));

    final trackALabelRowFinder = find.byKey(
      const ValueKey<String>('storyboard-track-label-row-track-a'),
    );
    final trackAAreaFinder = find.byKey(
      const ValueKey<String>('storyboard-track-timeline-area-track-a'),
    );
    final trackBLabelRowFinder = find.byKey(
      const ValueKey<String>('storyboard-track-label-row-track-b'),
    );
    final trackBAreaFinder = find.byKey(
      const ValueKey<String>('storyboard-track-timeline-area-track-b'),
    );

    final trackALabelRowTop = tester.getTopLeft(trackALabelRowFinder).dy;
    final trackAAreaTop = tester.getTopLeft(trackAAreaFinder).dy;
    final trackBLabelRowTop = tester.getTopLeft(trackBLabelRowFinder).dy;
    final trackBAreaTop = tester.getTopLeft(trackBAreaFinder).dy;

    expect(trackALabelRowTop, trackAAreaTop);
    expect(trackBLabelRowTop, trackBAreaTop);
    expect(
      tester.getSize(trackALabelRowFinder).height,
      tester.getSize(trackAAreaFinder).height,
    );
    expect(
      tester.getSize(trackBLabelRowFinder).height,
      tester.getSize(trackBAreaFinder).height,
    );
  });

  testWidgets('every cut of the track gets a block', (tester) async {
    await _pumpPanel(tester, _twoCutProject());

    expect(
      [for (final block in cutBlocks(tester)) block.cutId.value],
      ['cut-short', 'cut-long'],
    );
  });

  testWidgets('long sequential cut timeline pumps inside horizontal viewport', (
    tester,
  ) async {
    await _pumpPanel(tester, _longSequentialCutProject());

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(
        const ValueKey<String>('storyboard-timeline-horizontal-viewport'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('storyboard-track-timeline-area-track-long'),
      ),
      findsOneWidget,
    );
    // The row draws what the WINDOW covers (UI-R16's shared policy): the
    // near cuts, not the ones the viewport cannot reach — which is also
    // what keeps the thumbnail store from being asked for them.
    expect(cutBlock(tester, 'cut-01', trackId: 'track-long'), isNotNull);
    expect(cutBlock(tester, 'cut-08', trackId: 'track-long'), isNull);
  });

  testWidgets('second cut is positioned to the right of the first cut', (
    tester,
  ) async {
    await _pumpPanel(tester, _twoCutProject());

    expect(
      requireCutBlock(tester, 'cut-long').rect.left,
      greaterThan(requireCutBlock(tester, 'cut-short').rect.left),
    );
  });

  testWidgets('shows storyboard shell, V tracks, cut blocks, and empty state', (
    tester,
  ) async {
    final project = _project(storyboardLayer: null);

    await _pumpPanel(tester, project);

    expect(
      find.byKey(const ValueKey<String>('storyboard-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-track-label-track-a')),
      findsOneWidget,
    );
    expect(find.text('V1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('storyboard-track-label-track-b')),
      findsOneWidget,
    );
    expect(find.text('V2'), findsOneWidget);

    final block = requireCutBlock(tester, 'cut-a');
    expect(block.title, 'Cut A');
    // The conte-sheet TIME column: cumulative time at the cut's end sits
    // bottom-right (the old duration/frame-range row is gone).
    expect(block.total, '24');
    expect(block.hasStoryboardLayer, isFalse);
    expect(block.layerLabel, 'No Storyboard Layer');
  });

  testWidgets(
    'shows storyboard strip and name when a storyboard layer exists',
    (tester) async {
      await _pumpPanel(
        tester,
        _project(
          storyboardLayer: _layer(kind: LayerKind.storyboard, name: 'SB'),
        ),
      );

      final block = requireCutBlock(tester, 'cut-a');
      expect(block.hasStoryboardLayer, isTrue);
      expect(block.layerLabel, 'SB');
    },
  );

  testWidgets('shows cumulative end times for sequential cuts', (tester) async {
    await _pumpPanel(tester, _twoCutProject());

    expect(requireCutBlock(tester, 'cut-short').total, '12');
    expect(requireCutBlock(tester, 'cut-long').total, '48');
  });

  testWidgets('tapping inactive cut block calls onCutSelected with cut id', (
    tester,
  ) async {
    CutId? selectedCutId;

    await _pumpPanel(
      tester,
      _twoCutProject(),
      activeCutId: const CutId('cut-short'),
      onCutSelected: (cutId) => selectedCutId = cutId,
    );

    await tester.tapAt(cutBlockCenter(tester, 'cut-long'));
    await tester.pumpAndSettle();

    expect(selectedCutId, const CutId('cut-long'));
  });

  testWidgets('tapping the active cut announces it again — the row press '
      'reports WHICH cut, and the session drops the repeat', (tester) async {
    final selected = <CutId>[];

    await _pumpPanel(
      tester,
      _twoCutProject(),
      activeCutId: const CutId('cut-short'),
      onCutSelected: selected.add,
    );

    await tester.tapAt(cutBlockCenter(tester, 'cut-short'));
    await tester.pumpAndSettle();

    expect(selected, [const CutId('cut-short')]);
  });

  testWidgets('cut block width roughly represents cut duration', (
    tester,
  ) async {
    await _pumpPanel(tester, _twoCutProject());

    expect(
      requireCutBlock(tester, 'cut-long').rect.width,
      greaterThan(requireCutBlock(tester, 'cut-short').rect.width),
    );
  });

  testWidgets('a long layer name still fits the block — the label stops at '
      'its box instead of overflowing it', (tester) async {
    await _pumpPanel(
      tester,
      _project(
        storyboardLayer: _layer(
          kind: LayerKind.storyboard,
          name: 'Storyboard Layer With A Long Name',
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final block = requireCutBlock(tester, 'cut-a');
    expect(block.title, 'Cut A');
    expect(block.total, isNotNull);
    expect(block.layerLabel, 'Storyboard Layer With A Long Name');
  });

  testWidgets('building the panel does not mutate the project', (tester) async {
    final project = _project(
      storyboardLayer: _layer(kind: LayerKind.storyboard, name: 'Storyboard'),
    );
    final beforeJson = project.toJson().toString();

    await _pumpPanel(tester, project);

    expect(project.toJson().toString(), beforeJson);
    expect(
      project,
      _project(
        storyboardLayer: _layer(kind: LayerKind.storyboard, name: 'Storyboard'),
      ),
    );
  });
}

Future<void> _pumpPanel(
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

Project _project({required Layer? storyboardLayer}) {
  return Project(
    id: const ProjectId('project-a'),
    name: 'Project A',
    createdAt: DateTime.utc(2026, 6, 14),
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
              _layer(kind: LayerKind.animation, name: 'A'),
              ?storyboardLayer,
            ],
          ),
        ],
      ),
      Track(id: const TrackId('track-b'), name: 'Track B', cuts: const []),
    ],
  );
}

Project _twoCutProject() {
  return Project(
    id: const ProjectId('project-b'),
    name: 'Project B',
    createdAt: DateTime.utc(2026, 6, 14),
    tracks: [
      Track(
        id: const TrackId('track-a'),
        name: 'Track A',
        cuts: [
          Cut(
            id: const CutId('cut-short'),
            name: 'Short',
            duration: 12,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            layers: [_layer(kind: LayerKind.animation, name: 'A')],
          ),
          Cut(
            id: const CutId('cut-long'),
            name: 'Long',
            duration: 36,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            layers: [_layer(kind: LayerKind.animation, name: 'A')],
          ),
        ],
      ),
    ],
  );
}

Project _longSequentialCutProject() {
  return Project(
    id: const ProjectId('project-long'),
    name: 'Project Long',
    createdAt: DateTime.utc(2026, 6, 14),
    tracks: [
      Track(
        id: const TrackId('track-long'),
        name: 'Track Long',
        cuts: [
          for (var index = 1; index <= 8; index++)
            Cut(
              id: CutId('cut-${index.toString().padLeft(2, '0')}'),
              name: 'Cut ${index.toString().padLeft(2, '0')}',
              duration: 48,
              canvasSize: const CanvasSize(width: 1280, height: 720),
              layers: [_layer(kind: LayerKind.animation, name: 'A$index')],
            ),
        ],
      ),
    ],
  );
}

Layer _layer({required LayerKind kind, required String name}) {
  return Layer(
    id: LayerId('layer-$name-${kind.name}'),
    name: name,
    kind: kind,
    frames: [Frame(id: FrameId('frame-$name'), duration: 1, strokes: const [])],
  );
}
