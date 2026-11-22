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

/// 🚨THE V ROW'S GRIPS ARE PAINTED AGAIN WHERE ITS BLOCKS ARE, AND NOWHERE
/// ELSE (card a-twirl-repaints-the-film-views-cut-band, 11-22 — its second
/// half).
///
/// The triangles at a cut's two ends read what they stand on off the blocks
/// under them — a band in the cut's label, a picture. They told two readers
/// apart by identity, and the row hands them a new one every time it is
/// built: the blocks had stopped repainting for a lane twirled on the
/// camera row, and the grips over them went on — one layer of the row
/// painted again, and the row's image taken again (🔬the whole workspace,
/// three cuts: four twirls, the V row four times).
///
/// 🪦The first half's pins stood on a panel handed no edge callbacks — a row
/// with no grips on it — and read nothing waiting there. These stand on the
/// tab as the workspace hosts it, and the twirl is the rail's own toggle,
/// pressed.
const _track = 'default-track';

final _vRow = find.byKey(
  const ValueKey<String>('storyboard-track-timeline-area-$_track'),
);
final _conteRow = find.byKey(
  const ValueKey<String>('storyboard-conte-row-$_track'),
);
final _blocks = find.byKey(
  const ValueKey<String>('storyboard-cut-blocks-$_track'),
);
final _grips = timelineRowChromeFinder(_track, prefix: 'storyboard-plate');

/// The lane toggle of the camera row in the rail — the row of the cut the
/// conte stands in.
final _cameraToggle = find.namedWhere(
  (name) => name.contains('-lane-toggle-') && name.endsWith('-camera'),
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
  return session;
}

List<Cut> _cuts(EditorSessionManager session) =>
    session.repository.requireProject().tracks.single.cuts;

/// The row [toggle] twirls, as the film holds it.
Layer _rowOf(EditorSessionManager session, Finder toggle) {
  final name = nameOf(toggle.evaluate().single)!;
  final id = name.substring(name.indexOf('-lane-toggle-') + 13);
  return [
    for (final cut in _cuts(session)) ...cut.layers,
  ].singleWhere((layer) => layer.id.value == id);
}

StoryboardCutBlocksPainter _blocksPainter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_blocks).painter! as StoryboardCutBlocksPainter;

/// Whether [painted]'s own paint waits to be made again, the film built
/// and laid out again and not yet painted.
bool _waits(WidgetTester tester, Finder painted) =>
    tester.renderObject(painted).debugNeedsPaint;

/// The boundaries under [rows] waiting to repaint, by the row.
List<String> _waitingUnder(WidgetTester tester, List<Finder> rows) => [
  for (final row in rows)
    for (final stray in repaintStrays(
      tester.renderObject(row),
      allowed: const {},
    ))
      '${row.evaluate().single.widget.key}: ${nameOfBoundary(stray, depth: 6)}',
];

void main() {
  testWidgets('🚨a lane twirled on the camera row, the rail\'s own toggle '
      'pressed: the film\'s rows are built again with the cut as it is, and '
      'neither the V row — its blocks, the grips over them — nor the conte '
      'row is painted again', (tester) async {
    final session = await _film(tester);
    expect(_cameraToggle, findsOneWidget, reason: '⛔premise');
    final twirledBefore = _rowOf(session, _cameraToggle).lanesExpanded;
    final gripsBefore = timelineRowChromePainter(
      tester,
      _track,
      prefix: 'storyboard-plate',
    );

    await tester.tap(_cameraToggle);
    await tester.pump(null, EnginePhase.layout);
    final waiting = _waitingUnder(tester, [_vRow, _conteRow]);
    final gripsWait = _waits(tester, _grips);
    await tester.pump();

    expect(
      _rowOf(session, _cameraToggle).lanesExpanded,
      !twirledBefore,
      reason: '⛔premise: the press twirled the row — its cut is another cut',
    );
    expect(
      timelineRowChromePainter(tester, _track, prefix: 'storyboard-plate'),
      isNot(same(gripsBefore)),
      reason: '⛔premise: the V row was built again',
    );
    expect(gripsWait, isFalse, reason: 'the grips');
    expect(waiting, isEmpty);
  });

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
