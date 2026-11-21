import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/ui/storyboard_cut_blocks_painter.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/conte_track_fixture.dart';
import '../../helpers/fixed_thumbnails.dart';
import '../../helpers/repaint_strays.dart';

/// 🚨A CUT CHANGED WHERE NO FILM ROW READS IT REPAINTS NO BAND (card
/// a-twirl-repaints-the-film-views-cut-band, 11-22).
///
/// Every edit inside a cut makes a new cut. The film view's V row and conte
/// row knew their cuts by identity, so a lane twirled on the camera row —
/// one flag of one layer neither row draws — painted both bands of the
/// whole film again, and each took its image again (🔬the test VM, the
/// whole workspace, three cuts: four twirls, both bands four times).
///
/// A row repaints for what it draws: the V row a cut's place, name, colour
/// label, conte panels and the pictures' material; the conte row the rows
/// of the cut's conte group.
const _cut1 = CutId('cut-1');
const _conte = LayerId('cut-1-conte');

/// [project] with [change] made to `cut-1` — a new cut, as every edit makes.
Project _withCut1(Project project, Cut Function(Cut cut) change) {
  final track = project.tracks.single;
  return project.copyWith(
    tracks: [
      track.copyWith(
        cuts: [
          for (final cut in track.cuts)
            if (cut.id == _cut1) change(cut) else cut,
        ],
      ),
    ],
  );
}

Cut _withLayer(Cut cut, LayerId id, Layer Function(Layer layer) change) =>
    cut.copyWith(
      layers: [
        for (final layer in cut.layers)
          if (layer.id == id) change(layer) else layer,
      ],
    );

/// The film in the storyboard panel, its panels' pictures asked of a
/// store that says a cut's pictures are made of its rows' eyes — as the
/// app's says they are made of what a render reads, and of no lane's
/// twirl.
Future<ValueNotifier<Project>> _film(WidgetTester tester) async {
  final film = ValueNotifier(conteTrackProject());
  addTearDown(film.dispose);
  final fixed = fixedThumbnails(
    (cut, frame, {required shownHeight, region}) => null,
  );
  final pictures = (
    resolve: fixed.resolve,
    madeOf: (Cut cut) =>
        [for (final layer in cut.layers) layer.isVisible].join(),
    noticesFor: fixed.noticesFor,
    landed: fixed.landed,
    pending: fixed.pending,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<Project>(
          valueListenable: film,
          builder: (_, project, _) => StoryboardPanel(
            project: project,
            activeCutId: _cut1,
            thumbnails: pictures,
          ),
        ),
      ),
    ),
  );
  return film;
}

StoryboardCutBlocksPainter _blocks(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byKey(const ValueKey<String>('storyboard-cut-blocks-t')),
            )
            .painter!
        as StoryboardCutBlocksPainter;

TimelineRowCellsPainter _conteCells(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is CustomPaint &&
                    widget.painter is TimelineRowCellsPainter,
              ),
            )
            .painter!
        as TimelineRowCellsPainter;

/// The boundaries under the V row and the conte row waiting to repaint,
/// the film built and laid out again and not yet painted.
///
/// The two rows, not the panel: the rail beside them shows the twirl, and
/// is painted again for it.
Future<List<String>> _rowsWaitingToRepaint(WidgetTester tester) async {
  await tester.pump(null, EnginePhase.layout);
  final named = [
    for (final row in const [
      'storyboard-track-timeline-area-t',
      'storyboard-conte-row-t',
    ])
      for (final stray in repaintStrays(
        tester.renderObject(find.byKey(ValueKey<String>(row))),
        allowed: const {},
      ))
        '$row: ${stray.runtimeType} ${stray.paintBounds.size}',
  ];
  await tester.pump();
  return named;
}

void main() {
  testWidgets('🚨a lane twirled on a row of the cut neither band draws: the '
      'rows are built again with the cut as it is, and nothing is painted '
      'again', (tester) async {
    final film = await _film(tester);
    final blocksBefore = _blocks(tester);
    final cellsBefore = _conteCells(tester);

    film.value = _withCut1(
      film.value,
      (cut) => _withLayer(
        cut,
        conteCelId,
        (layer) => layer.copyWith(lanesExpanded: !layer.lanesExpanded),
      ),
    );
    final waiting = await _rowsWaitingToRepaint(tester);

    final blocks = _blocks(tester);
    expect(blocks, isNot(same(blocksBefore)), reason: '⛔premise: built again');
    expect(
      blocks.entries.first.cut,
      same(film.value.tracks.single.cuts.first),
      reason: 'the row holds the cut as it is — what its presses and its '
          'pictures are asked with',
    );
    expect(blocks.shouldRepaint(blocksBefore), isFalse, reason: 'the V row');
    expect(
      _conteCells(tester).layer,
      same(cellsBefore.layer),
      reason: 'the conte row as it was laid',
    );
    expect(waiting, isEmpty);
  });

  testWidgets('a cut named again repaints the V row, which prints its name — '
      'and not the conte row', (tester) async {
    final film = await _film(tester);
    final blocksBefore = _blocks(tester);
    final cellsBefore = _conteCells(tester);

    film.value = _withCut1(film.value, (cut) => cut.copyWith(name: '1A'));
    await tester.pump();

    expect(_blocks(tester).shouldRepaint(blocksBefore), isTrue);
    expect(_conteCells(tester).layer, same(cellsBefore.layer));
  });

  testWidgets('🚨an eye turned off on a row of the cut repaints the V row — '
      'its pictures are made of something else, and are asked again — and '
      'not the conte row', (tester) async {
    final film = await _film(tester);
    final blocksBefore = _blocks(tester);
    final cellsBefore = _conteCells(tester);

    film.value = _withCut1(
      film.value,
      (cut) => _withLayer(
        cut,
        conteCelId,
        (layer) => layer.copyWith(isVisible: false),
      ),
    );
    final waiting = await _rowsWaitingToRepaint(tester);

    expect(_blocks(tester).shouldRepaint(blocksBefore), isTrue);
    expect(_conteCells(tester).layer, same(cellsBefore.layer));
    expect(
      waiting,
      contains(startsWith('storyboard-track-timeline-area-t')),
      reason: 'the V row waits to be painted again',
    );
    expect(
      waiting,
      isNot(contains(startsWith('storyboard-conte-row-t'))),
      reason: 'and the conte row does not',
    );
  });

  testWidgets('a panel made longer repaints both rows — the conte row\'s '
      'blocks, and the V row\'s panels', (tester) async {
    final film = await _film(tester);
    final blocksBefore = _blocks(tester);
    final cellsBefore = _conteCells(tester);

    film.value = _withCut1(
      film.value,
      (cut) => _withLayer(
        cut,
        _conte,
        (layer) => layer.copyWith(
          timeline: {
            0: const TimelineExposure.drawing(FrameId('p1'), length: 6),
            6: const TimelineExposure.drawing(FrameId('p2'), length: 2),
            8: const TimelineExposure.drawing(FrameId('p3'), length: 4),
          },
        ),
      ),
    );
    await tester.pump();

    expect(_blocks(tester).shouldRepaint(blocksBefore), isTrue);
    expect(_conteCells(tester).layer, isNot(same(cellsBefore.layer)));
  });
}
