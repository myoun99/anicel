import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
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
/// keep what lies before it. What draws the row over them told the layer
/// apart otherwise, and the row's image was taken once more (🔬the whole
/// workspace, the timeline view: every press of a ▸ — the camera row's,
/// the direction row's, an S row's — the row's own 2802×28 image let go and
/// taken again):
///
/// - the painter that lays the tiles down, by identity;
/// - the numbers over a direction row's spans, by identity;
/// - the grips on a row's paper — an S row's, a cel row's: the reader that
///   stands them by its layers' identity, the row they stand on by the
///   layer whole, folds and all.
///
/// The tab as the workspace hosts it, the rail's own toggle pressed.
const _toggle = 'timeline-lane-toggle-';
const _cells = 'timeline-row-cells-';

Finder _everyCells() => find.namedWhere((name) => name.startsWith(_cells));

/// The rows wearing a lane toggle, by their ids.
List<String> _twirlable() => [
  for (final toggle
      in find.namedWhere((name) => name.startsWith(_toggle)).evaluate())
    nameOf(toggle)!.substring(_toggle.length),
];

/// Every row the timeline shows: the cut's, and the track's.
Layer _row(EditorSessionManager session, String id) {
  final track = session.repository.requireProject().tracks.single;
  return [
    ...session.layers,
    ...track.seLayers,
    track.transitionLayer,
  ].firstWhere((layer) => layer.id.value == id);
}

/// The cells waiting to be painted again, the tab built and laid out and
/// not yet painted — a row's own paint, or a boundary under it.
List<String?> _cellsWaiting(WidgetTester tester) => [
  for (final cells in _everyCells().evaluate())
    if (cells.renderObject!.debugNeedsPaint ||
        repaintStrays(cells.renderObject!, allowed: const {}).isNotEmpty)
      nameOf(cells),
];

/// The default project in the timeline tab, a cel row added to it — born
/// with its first cel, a block with a grip at each end.
Future<EditorSessionManager> _timeline(WidgetTester tester) async {
  final session = await pumpTimelineHost(
    tester,
    createDefaultProject(),
    surface: const Size(1400, 1000),
  );
  session.layerStack.addLayerOfKind(LayerKind.animation);
  await tester.pumpAndSettle();
  return session;
}

void main() {
  testWidgets('🚨a lane twirled on a row of the timeline, the rail\'s own '
      'toggle pressed: the row is another layer, and no row\'s cells are '
      'painted again — the camera row, a direction row, an S row, a cel '
      'row with its grips', (tester) async {
    final session = await _timeline(tester);
    final rows = _twirlable();
    final kinds = {for (final id in rows) _row(session, id).kind};
    expect(
      kinds,
      containsAll([
        LayerKind.camera,
        LayerKind.instruction,
        LayerKind.se,
        LayerKind.animation,
      ]),
      reason: '⛔premise: a row of each kind wears a toggle — $rows',
    );

    for (final id in rows) {
      expect(
        find.named('$_cells$id'),
        findsOneWidget,
        reason: '⛔premise: $id has cells',
      );
      final before = _row(session, id);

      await tester.tap(find.named('$_toggle$id'));
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
      expect(_cellsWaiting(tester), isEmpty, reason: 'twirled $id');
      await tester.pumpAndSettle();
    }
  });

  testWidgets('⛔premise: a row whose cells change IS painted again, and no '
      'other — the cel row\'s block pushed a frame on', (tester) async {
    final session = await _timeline(tester);
    final row = session.activeLayer!;
    expect(row.kind, LayerKind.animation, reason: '⛔premise: stood on it');
    session.selectFrameIndex(0);
    await tester.pumpAndSettle();

    session.blockShift.pushFrames(1);
    await tester.pump(null, EnginePhase.layout);
    expect(
      identical(session.activeLayer, row),
      isFalse,
      reason: '⛔premise: the push made the row anew',
    );
    expect(_cellsWaiting(tester), ['$_cells${row.id.value}']);
    await tester.pumpAndSettle();
  });

  testWidgets('⛔premise: a cel renamed — a word its cells print, and '
      'nothing its grips or its numbers read — paints its row\'s cells '
      'again', (tester) async {
    final session = await _timeline(tester);
    final row = session.activeLayer!;
    session.selectFrameIndex(0);
    await tester.pumpAndSettle();

    expect(session.frameVerbs.renameSelectedFrame('Z9'), isNull);
    await tester.pump(null, EnginePhase.layout);
    expect(
      session.activeLayer!.frames.single.name,
      'Z9',
      reason: '⛔premise: the cel took the name',
    );
    expect(
      session.activeLayer!.timeline,
      row.timeline,
      reason: '⛔premise: no block moved',
    );
    expect(_cellsWaiting(tester), ['$_cells${row.id.value}']);
    await tester.pumpAndSettle();
  });

  testWidgets('🚨a row twirled and THEN changed is painted again — what was '
      'laid down before the twirl is asked about the row as it is now, not '
      'answered as the twirl was', (tester) async {
    final session = await _timeline(tester);
    final row = session.activeLayer!;
    session.selectFrameIndex(0);
    await tester.pumpAndSettle();
    await tester.tap(find.named('$_toggle${row.id.value}'));
    await tester.pumpAndSettle();
    expect(
      session.activeLayer!.lanesExpanded,
      isNot(row.lanesExpanded),
      reason: '⛔premise: the twirl turned',
    );

    session.blockShift.pushFrames(1);
    await tester.pump(null, EnginePhase.layout);
    expect(_cellsWaiting(tester), ['$_cells${row.id.value}']);
    await tester.pumpAndSettle();
  });
}
