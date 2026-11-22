import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/repaint_strays.dart';
import '../../helpers/timeline_host.dart';

/// 🚨A LANE TWIRLED ON THE TIMELINE PAINTS NO ROW'S CELLS AGAIN (card
/// a-rows-own-twirl-retakes-its-band-on-the-timeline, 11-22).
///
/// A twirl is an edit of the row it is pressed on (`Layer.lanesExpanded`,
/// F-360: the folds are the file's) — a new layer for a row whose cells
/// read none of it. The row's tiles knew: they ask where two instances of
/// their row may first show different cells (`firstCellThatMayDiffer`) and
/// keep what lies before it. The painter that lays them down told its
/// layer apart by identity, so it was painted again over the same tiles
/// and the row's image was taken once more (🔬the whole workspace, the
/// timeline view: every press of a ▸ — the camera row's, the direction
/// row's, an S row's — the row's own 2802×28 image let go and taken
/// again).
///
/// The tab as the workspace hosts it, the rail's own toggle pressed.
Finder _toggles() =>
    find.namedWhere((name) => name.startsWith('timeline-lane-toggle-'));

Finder _cellsOf(String rowId) => find.named('timeline-row-cells-$rowId');

String _rowIdOf(Element toggle) =>
    nameOf(toggle)!.substring('timeline-lane-toggle-'.length);

/// Every row the timeline shows, the session's own and the track's.
Layer _row(EditorSessionManager session, String id) => [
  ...session.layers,
  ...session.repository.requireProject().tracks.single.seLayers,
  session.repository.requireProject().tracks.single.transitionLayer,
].firstWhere((layer) => layer.id.value == id);

void main() {
  testWidgets('🚨a lane twirled on a row of the timeline, the rail\'s own '
      'toggle pressed: the row is another layer, and its cells are not '
      'painted again — nor any other row\'s', (tester) async {
    final session = await pumpTimelineHost(
      tester,
      createDefaultProject(),
      surface: const Size(1400, 1000),
    );
    final rows = [for (final toggle in _toggles().evaluate()) _rowIdOf(toggle)];
    expect(
      rows.length,
      greaterThanOrEqualTo(3),
      reason: '⛔premise: rows with lanes to twirl — $rows',
    );

    for (final id in rows) {
      final toggle = find.named('timeline-lane-toggle-$id');
      expect(_cellsOf(id), findsOneWidget, reason: '⛔premise: $id has cells');
      final before = _row(session, id);

      await tester.tap(toggle);
      // The twirl, run to its layout and stopped before the paint, so what
      // waits to repaint can be read.
      await tester.pump(null, EnginePhase.layout);
      expect(
        identical(_row(session, id), before),
        isFalse,
        reason: '⛔premise: the twirl made $id anew',
      );
      expect(
        _row(session, id).lanesExpanded,
        isNot(before.lanesExpanded),
        reason: '⛔premise: the twirl turned',
      );
      final waiting = [
        for (final cells in find
            .namedWhere((name) => name.startsWith('timeline-row-cells-'))
            .evaluate())
          if (cells.renderObject!.debugNeedsPaint ||
              repaintStrays(cells.renderObject!, allowed: const {}).isNotEmpty)
            nameOf(cells),
      ];
      expect(waiting, isEmpty, reason: 'twirled $id');
      await tester.pumpAndSettle();
    }
  });
}
