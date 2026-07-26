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
import 'package:quick_animaker_v2/src/ui/timeline/timeline_block.dart';

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

  testWidgets('cut blocks use the shared timeline block primitive', (
    tester,
  ) async {
    await _pumpPanel(tester, _project(storyboardLayer: null));

    expect(
      find.byKey(const ValueKey<String>('storyboard-cut-block-cut-a')),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TimelineBlock &&
            widget.key == const ValueKey<String>('storyboard-cut-block-cut-a'),
      ),
      findsOneWidget,
    );
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

  testWidgets('cuts are wrapped in positioned timeline entries', (
    tester,
  ) async {
    await _pumpPanel(tester, _twoCutProject());

    expect(
      find.byKey(const ValueKey<String>('storyboard-cut-positioned-cut-short')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-cut-positioned-cut-long')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-cut-block-cut-short')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-cut-block-cut-long')),
      findsOneWidget,
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
    expect(
      find.byKey(const ValueKey<String>('storyboard-cut-positioned-cut-01')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-cut-block-cut-01')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-cut-positioned-cut-08')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-cut-block-cut-08')),
      findsOneWidget,
    );
  });

  testWidgets('second cut is positioned to the right of the first cut', (
    tester,
  ) async {
    await _pumpPanel(tester, _twoCutProject());

    final firstLeft = tester
        .getTopLeft(
          find.byKey(
            const ValueKey<String>('storyboard-cut-positioned-cut-short'),
          ),
        )
        .dx;
    final secondLeft = tester
        .getTopLeft(
          find.byKey(
            const ValueKey<String>('storyboard-cut-positioned-cut-long'),
          ),
        )
        .dx;

    expect(secondLeft, greaterThan(firstLeft));
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
    expect(
      find.byKey(const ValueKey<String>('storyboard-cut-block-cut-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-cut-title-cut-a')),
      findsOneWidget,
    );
    expect(find.text('Cut A'), findsOneWidget);
    // The conte-sheet TIME column: cumulative time at the cut's end sits
    // bottom-right (the old duration/frame-range row is gone).
    expect(
      find.byKey(const ValueKey<String>('storyboard-cut-total-cut-a')),
      findsOneWidget,
    );
    expect(find.text('24'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('storyboard-layer-empty-cut-a')),
      findsOneWidget,
    );
    expect(find.text('No Storyboard Layer'), findsOneWidget);
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

      expect(
        find.byKey(const ValueKey<String>('storyboard-layer-strip-cut-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('storyboard-layer-name-cut-a')),
        findsOneWidget,
      );
      expect(find.text('SB'), findsOneWidget);
      expect(find.text('No Storyboard Layer'), findsNothing);
    },
  );

  testWidgets('shows cumulative end times for sequential cuts', (tester) async {
    await _pumpPanel(tester, _twoCutProject());

    expect(
      find.byKey(const ValueKey<String>('storyboard-cut-total-cut-short')),
      findsOneWidget,
    );
    expect(find.text('12'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('storyboard-cut-total-cut-long')),
      findsOneWidget,
    );
    expect(find.text('48'), findsOneWidget);
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

    await tester.tap(
      find.byKey(const ValueKey<String>('storyboard-cut-block-cut-long')),
    );
    await tester.pumpAndSettle();

    expect(selectedCutId, const CutId('cut-long'));
  });

  testWidgets('tapping active cut block is a no-op', (tester) async {
    var selectionCount = 0;

    await _pumpPanel(
      tester,
      _twoCutProject(),
      activeCutId: const CutId('cut-short'),
      onCutSelected: (_) => selectionCount += 1,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('storyboard-cut-block-cut-short')),
    );
    await tester.pumpAndSettle();

    expect(selectionCount, 0);
  });

  testWidgets('cut block width roughly represents cut duration', (
    tester,
  ) async {
    await _pumpPanel(tester, _twoCutProject());

    final shortSize = tester.getSize(
      find.byKey(const ValueKey<String>('storyboard-cut-block-cut-short')),
    );
    final longSize = tester.getSize(
      find.byKey(const ValueKey<String>('storyboard-cut-block-cut-long')),
    );

    expect(longSize.width, greaterThan(shortSize.width));
  });

  testWidgets('compact cut blocks keep content vertically overflow-safe', (
    tester,
  ) async {
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
    expect(
      find.byKey(const ValueKey<String>('storyboard-cut-title-cut-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-cut-total-cut-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-layer-strip-cut-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-layer-name-cut-a')),
      findsOneWidget,
    );
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
          onCutSelected: onCutSelected ?? (_) {},
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
    frames: [
      Frame(
        id: FrameId('frame-$name'),
        duration: 1,
        strokes: const [],
      ),
    ],
  );
}
