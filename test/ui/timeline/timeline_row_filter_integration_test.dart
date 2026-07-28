import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/home_page.dart';

Layer _layer(String id, {LayerMark mark = LayerMark.none}) => Layer(
  id: LayerId(id),
  name: id,
  kind: LayerKind.animation,
  mark: mark,
  frames: const [],
  timeline: const {},
);

Project _project() => Project(
  id: const ProjectId('rf-project'),
  name: 'Row Filter',
  createdAt: DateTime.utc(2026, 7, 15),
  tracks: [
    Track(
      id: const TrackId('rf-track'),
      name: 'Video',
      cuts: [
        Cut(
          id: const CutId('rf-cut'),
          name: 'Cut',
          duration: 12,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: [
            _layer('red-a', mark: LayerMark.red),
            _layer('blue-b', mark: LayerMark.blue),
            _layer('plain-c'),
          ],
        ),
      ],
    ),
  ],
);

Finder _row(String id) =>
    find.byKey(ValueKey<String>('timeline-layer-row-$id'));

void main() {
  testWidgets('the legend mark solo drops non-matching rows and toggles '
      'back off from the same menu item — no chip bar (R3 #1/#2)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: _project())),
    );
    await tester.pumpAndSettle();

    expect(_row('red-a'), findsOneWidget);
    expect(_row('blue-b'), findsOneWidget);
    expect(_row('plain-c'), findsOneWidget);

    // Open the mark legend flyout and pick "solo red".
    await tester.tap(find.byKey(const ValueKey<String>('legend-mark')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('legend-filter-mark-red')),
    );
    await tester.pumpAndSettle();

    // Only the red layer's row survives (plus the active layer exemption:
    // the default active layer is red-a, which also matches).
    expect(_row('red-a'), findsOneWidget);
    expect(_row('blue-b'), findsNothing);
    expect(_row('plain-c'), findsNothing);

    // The retired chip bar never appears (the legend icon carries the
    // engaged state instead).
    expect(
      find.byKey(const ValueKey<String>('row-filter-chip-mark-red')),
      findsNothing,
    );

    // Toggling the same menu item off restores all rows.
    await tester.tap(find.byKey(const ValueKey<String>('legend-mark')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('legend-filter-mark-red')),
    );
    await tester.pumpAndSettle();
    expect(_row('blue-b'), findsOneWidget);
    expect(_row('plain-c'), findsOneWidget);
  });
}
