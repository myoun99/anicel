import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_section_policy.dart';

import '../flyout_test_helpers.dart';
import 'timeline_cell_probe.dart';

Layer _layer(String id, LayerKind kind) {
  return Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    frames: const [],
    timeline: const {},
  );
}

Project _project() {
  return Project(
    id: const ProjectId('vis-project'),
    name: 'Visibility Project',
    createdAt: DateTime.utc(2026, 7, 9),
    tracks: [
      Track(
        id: const TrackId('vis-track'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('vis-cut'),
            name: 'Visibility Cut',
            duration: 12,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              _layer('cel-a', LayerKind.animation),
              _layer('se-1', LayerKind.se),
              _layer('se-2', LayerKind.se),
              _layer('cam-inst', LayerKind.instruction),
              _layer('cam', LayerKind.camera),
            ],
          ),
        ],
      ),
    ],
  );
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project())),
  );
  await tester.pumpAndSettle();
}

Finder _row(String layerId) =>
    find.byKey(ValueKey<String>('timeline-layer-row-$layerId'));

// Menu-aware (R-toolbar round): the section show/hide items live in the
// Layer ▾ flyout (both orientations); the horizontal rail additionally
// folds via the gutter chevrons — pinned separately below.
Future<void> _toggleSection(WidgetTester tester, String buttonKey) =>
    tapCommandButton(tester, ValueKey<String>(buttonKey));

void main() {
  group('buildTimelineDisplayRows hiddenSections', () {
    test('hidden sections contribute no rows; the layers stay put', () {
      final layers = [
        _layer('cel-a', LayerKind.animation),
        _layer('se-1', LayerKind.se),
        _layer('se-2', LayerKind.se),
        _layer('cam', LayerKind.camera),
      ];

      final rows = buildTimelineDisplayRows(
        layers: layers,
        expandedLayerIds: const {},
        lanesForLayer: (_) => const [],
        hiddenSections: const {TimelineSection.se, TimelineSection.camera},
      );

      expect(rows, hasLength(1));
      expect(rows.single.layer.id, const LayerId('cel-a'));
      // Purely a view filter — the layer list is untouched.
      expect(layers, hasLength(4));
    });
  });

  testWidgets('toolbar SE toggle hides all SE rows and shows them again', (
    tester,
  ) async {
    await _pump(tester);

    expect(_row('se-1'), findsOneWidget);
    expect(_row('se-2'), findsOneWidget);

    await _toggleSection(tester, 'toggle-se-section-button');
    expect(_row('se-1'), findsNothing);
    expect(_row('se-2'), findsNothing);
    // Other sections stay.
    expect(_row('cel-a'), findsOneWidget);
    expect(_row('cam'), findsOneWidget);

    await _toggleSection(tester, 'toggle-se-section-button');
    expect(_row('se-1'), findsOneWidget);
  });

  testWidgets('camera toggle hides instruction AND camera rows; the active '
      'layer may be hidden without crashing', (tester) async {
    await _pump(tester);

    // Make a camera-section layer active first.
    await tapTimelineCell(tester, 'cam', 0);
    await tester.pumpAndSettle();

    await _toggleSection(tester, 'toggle-camera-section-button');
    expect(_row('cam'), findsNothing);
    expect(_row('cam-inst'), findsNothing);
    expect(_row('cel-a'), findsOneWidget);

    await _toggleSection(tester, 'toggle-camera-section-button');
    expect(_row('cam'), findsOneWidget);
  });

  testWidgets('hidden sections drop their X-sheet columns too (shared '
      'policy)', (tester) async {
    await _pump(tester);

    await _toggleSection(tester, 'toggle-se-section-button');
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('xsheet-frame-column-area-se-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('xsheet-frame-column-area-cel-a')),
      findsOneWidget,
    );

    // The toolbar toggle works from the X-sheet as well.
    await _toggleSection(tester, 'toggle-se-section-button');
    expect(
      find.byKey(const ValueKey<String>('xsheet-frame-column-area-se-1')),
      findsOneWidget,
    );
  });

  testWidgets('the retired fold controls are gone', (tester) async {
    await _pump(tester);

    expect(
      find.byKey(const ValueKey<String>('timeline-section-collapse-se')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-section-collapse-camera')),
      findsNothing,
    );
    // Upright section headings (one semantics node per bracket).
    expect(find.bySemanticsLabel('ACTION'), findsWidgets);
    expect(find.bySemanticsLabel('CAM'), findsWidgets);
  });
}
