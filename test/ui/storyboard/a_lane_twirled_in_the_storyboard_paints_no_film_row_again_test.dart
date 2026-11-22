import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_cut_blocks_painter.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/repaint_strays.dart';
import '../../helpers/storyboard_host.dart';
import '../timeline/timeline_row_chrome_probe.dart';

/// 🚨A LANE TWIRLED IN THE STORYBOARD PAINTS NO ROW OF THE FILM AGAIN (card
/// a-twirl-repaints-the-film-views-cut-band, 11-22 — its second half).
///
/// A twirl is an edit of the row it is pressed on — a new layer, a new cut
/// — and the film's rows are built again with it. Two of what they draw
/// still told the old from the new by identity:
///
/// - the V row's GRIPS, the triangles at a cut's two ends. They read what
///   they stand on off the blocks under them, through a reader the row
///   hands them new at every build: the blocks had stopped repainting for a
///   lane twirled on the camera row, and the grips over them went on (🔬the
///   whole workspace, three cuts: four twirls, the V row's image taken
///   four times);
/// - an S row's NUMBERS, each block's length, compared by their layer: the
///   S row's own lanes twirled printed every number of the track again
///   (🔬four twirls, the row's image four times).
///
/// 🪦The first half's pins stood on a panel handed no edge callbacks — a row
/// with no grips on it — and read nothing waiting there. These stand on the
/// tab as the workspace hosts it, and the twirl is the rail's own toggle,
/// pressed.
const _track = 'default-track';

/// Every row of the film — the transition row, the S rows, the V row and
/// the conte row.
final _filmRows = find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      (key.value.startsWith('storyboard-transition-row-') ||
          key.value.startsWith('storyboard-se-row-') ||
          key.value.startsWith('storyboard-track-timeline-area-') ||
          key.value.startsWith('storyboard-conte-row-'));
});
final _blocks = find.byKey(
  const ValueKey<String>('storyboard-cut-blocks-$_track'),
);
final _grips = timelineRowChromeFinder(_track, prefix: 'storyboard-plate');

/// The lane toggle of the row whose id ends [row] — the camera row of the
/// cut the conte stands in, an S row.
Finder _toggleOf(String row) => find.namedWhere(
  (name) => name.contains('-lane-toggle-') && name.endsWith(row),
);

/// A film of three cuts in the storyboard tab.
Future<EditorSessionManager> _film(WidgetTester tester) async {
  final session = await pumpStoryboardHost(tester, createDefaultProject());
  session.cutVerbs.createCut();
  session.cutVerbs.createCut();
  await tester.pumpAndSettle();
  expect(
    timelineRowChromeTargets(tester, _track, prefix: 'storyboard-plate'),
    hasLength(6),
    reason: '⛔premise: the V row wears its grips — two a cut',
  );
  expect(
    _filmRows,
    findsNWidgets(5),
    reason: '⛔premise: the transition row, two S rows, the V row and the '
        'conte row',
  );
  return session;
}

List<Cut> _cuts(EditorSessionManager session) =>
    session.repository.requireProject().tracks.single.cuts;

/// The row [toggle] twirls, as the film holds it — a cut's row or the
/// track's.
Layer _rowOf(EditorSessionManager session, Finder toggle) {
  final name = nameOf(toggle.evaluate().single)!;
  final id = name.substring(name.indexOf('-lane-toggle-') + 13);
  return [
    ...session.repository.requireProject().tracks.single.seLayers,
    for (final cut in _cuts(session)) ...cut.layers,
  ].singleWhere((layer) => layer.id.value == id);
}

CustomPainter _gripsPainter(WidgetTester tester) =>
    timelineRowChromePainter(tester, _track, prefix: 'storyboard-plate')!;

/// The painter of the first S row's numbers — its blocks' lengths.
CustomPainter _numbersPainterOfS1(WidgetTester tester) => tester
    .widget<CustomPaint>(
      find.byKey(const ValueKey<String>('storyboard-run-labels-$_track-se-1')),
    )
    .foregroundPainter!;

StoryboardCutBlocksPainter _blocksPainter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_blocks).painter! as StoryboardCutBlocksPainter;

/// Whether [painted]'s own paint waits to be made again, the film built
/// and laid out again and not yet painted.
bool _waits(WidgetTester tester, Finder painted) =>
    tester.renderObject(painted).debugNeedsPaint;

/// The boundaries under the film's rows waiting to repaint, by the row.
List<String> _rowsWaiting(WidgetTester tester) => [
  for (final row in _filmRows.evaluate())
    for (final stray in repaintStrays(row.renderObject!, allowed: const {}))
      '${row.widget.key}: ${nameOfBoundary(stray, depth: 6)}',
];

void main() {
  // Each with what is built again for it: the camera row is a cut's, and
  // the V row is built with the cut; an S row is the track's, and only its
  // own row is built with it.
  for (final (row, id, builtWithIt) in [
    ('the camera row', '-camera', _gripsPainter),
    ('an S row', '-se-1', _numbersPainterOfS1),
  ]) {
    testWidgets('🚨a lane twirled on $row, the rail\'s own toggle pressed: '
        'the film\'s rows are built again with the row as it is, and none '
        'of them is painted again — the V row\'s blocks and the grips over '
        'them, an S row\'s numbers', (tester) async {
      final session = await _film(tester);
      final toggle = _toggleOf(id);
      expect(toggle, findsOneWidget, reason: '⛔premise');
      final rowBefore = _rowOf(session, toggle);
      final builtBefore = builtWithIt(tester);

      await tester.tap(toggle);
      await tester.pump(null, EnginePhase.layout);
      final waiting = _rowsWaiting(tester);
      final gripsWait = _waits(tester, _grips);
      await tester.pump();

      expect(
        _rowOf(session, toggle).lanesExpanded,
        !rowBefore.lanesExpanded,
        reason: '⛔premise: the press twirled the row — it is another row',
      );
      expect(
        builtWithIt(tester),
        isNot(same(builtBefore)),
        reason: '⛔premise: the row that reads it was built again',
      );
      expect(gripsWait, isFalse, reason: 'the grips');
      expect(waiting, isEmpty);
    });
  }

  testWidgets('a cut given a colour label paints its grips again with its '
      'blocks — the bands they stand on wear it', (tester) async {
    final session = await _film(tester);
    final blocksBefore = _blocksPainter(tester);
    final gripsBefore = timelineRowChromePainter(
      tester,
      _track,
      prefix: 'storyboard-plate',
    )!;

    session.cutVerbs.setAddressedCutMark(
      const LayerMark(process: LayerProcess.layout),
    );
    await tester.pump(null, EnginePhase.layout);
    final gripsWait = _waits(tester, _grips);
    await tester.pump();

    expect(
      _blocksPainter(tester).shouldRepaint(blocksBefore),
      isTrue,
      reason: '⛔premise: the blocks are painted again',
    );
    expect(
      timelineRowChromePainter(
        tester,
        _track,
        prefix: 'storyboard-plate',
      )!.shouldRepaint(gripsBefore),
      isTrue,
    );
    expect(gripsWait, isTrue);
  });

  testWidgets('🚨what the blocks are told to draw again with no cut changed '
      '— another cut stood on, its bands in the standing wash — the grips '
      'are told too', (tester) async {
    final session = await _film(tester);
    final cutsBefore = _cuts(session);
    final blocksBefore = _blocksPainter(tester);
    final other = blocksBefore.blocks().firstWhere(
      (block) => block.cutId != session.activeCutId,
    );

    await tester.tapAt(tester.getTopLeft(_blocks) + other.rect.center);
    await tester.pump(null, EnginePhase.layout);
    final blocksWait = _waits(tester, _blocks);
    final gripsWait = _waits(tester, _grips);
    // The plate's second tap, waited out.
    await tester.pump(kDoubleTapTimeout);

    expect(
      session.activeCutId,
      other.cutId,
      reason: '⛔premise: the press stood on the cut',
    );
    expect(
      [
        for (final (index, cut) in _cuts(session).indexed)
          identical(cut, cutsBefore[index]),
      ],
      everyElement(isTrue),
      reason: '⛔premise: no cut changed',
    );
    expect(
      _blocksPainter(tester).shouldRepaint(blocksBefore),
      isFalse,
      reason: '⛔premise: nothing the blocks are built with changed',
    );
    expect(blocksWait, isTrue, reason: '⛔premise: the blocks were told');
    expect(gripsWait, isTrue);
  });
}
