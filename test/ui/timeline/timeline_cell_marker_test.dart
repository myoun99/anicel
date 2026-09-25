// ONE MARKER TABLE FOR THE ROW PAINTER AND THE DIALOG MINIATURE.
//
// The miniature kept its own copy of this table until 2026-09-03, and the
// copy still stopped the timesheet X at the playback range — a rule the
// user retired on 2026-08-02. These pins say what the one table answers,
// so the next copy has nothing to drift from.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/frame.dart'
    show InbetweenMark, breakdownMark, unnamedDrawingMark;
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_marker.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_block_visual.dart';

Layer _layer(LayerKind kind) =>
    Layer(id: const LayerId('l'), name: 'L', frames: const [], kind: kind);

TimelineCellWriting _marker(
  LayerKind kind,
  TimelineCellExposureState state, {
  bool emptyRunStart = false,
  String? frameName,
}) => timelineCellMarker(
  layer: _layer(kind),
  exposureState: state,
  emptyRunStart: emptyRunStart,
  frameName: frameName,
);

TimelineCellWriting _word(String word) => (word: word, mark: null);

TimelineCellWriting _mark(InbetweenMark mark) => (word: '', mark: mark);

void main() {
  group('the timesheet X', () {
    test('marks the first cell of an empty run on a drawing row', () {
      expect(
        _marker(
          LayerKind.animation,
          TimelineCellExposureState.uncovered,
          emptyRunStart: true,
        ),
        _word('X'),
      );
    });

    test('only the FIRST cell — the rest of the run stays blank', () {
      expect(
        _marker(LayerKind.animation, TimelineCellExposureState.uncovered),
        timelineCellWritesNothing,
      );
    });

    test('never on an SE sheet column or an instruction row', () {
      for (final kind in [LayerKind.se, LayerKind.instruction]) {
        expect(
          _marker(
            kind,
            TimelineCellExposureState.uncovered,
            emptyRunStart: true,
          ),
          timelineCellWritesNothing,
          reason: '$kind',
        );
      }
    });
  });

  group('a drawing start', () {
    test('writes the frame name, or wears the in-between mark when it has '
        'none', () {
      expect(
        _marker(
          LayerKind.animation,
          TimelineCellExposureState.drawingStart,
          frameName: 'A',
        ),
        _word('A'),
      );
      expect(
        _marker(LayerKind.animation, TimelineCellExposureState.drawingStart),
        _mark(unnamedDrawingMark),
      );
      expect(
        _marker(
          LayerKind.animation,
          TimelineCellExposureState.drawingStart,
          frameName: '',
        ),
        _mark(unnamedDrawingMark),
      );
      expect(
        _marker(
          LayerKind.animation,
          TimelineCellExposureState.drawingStart,
          frameName: '  ',
        ),
        _mark(unnamedDrawingMark),
        reason: 'a blank name is no name — the sheet wears the mark for it too',
      );
    });

    test('says the name it prints — and no name for a blank one', () {
      String? said(String? frameName) => timelineCellSemanticsLabel(
        layerKind: LayerKind.animation,
        exposureState: TimelineCellExposureState.drawingStart,
        frameName: frameName,
      );
      expect(said(' A1 '), 'drawing start A1');
      expect(said(null), 'drawing start');
      expect(said('  '), 'drawing start');
    });

    test('says nothing on a camera row — its keys ride the lane markers', () {
      expect(
        _marker(
          LayerKind.camera,
          TimelineCellExposureState.drawingStart,
          frameName: 'K',
        ),
        timelineCellWritesNothing,
      );
    });
  });

  test('a held cell is blank and a dotted one wears the block\'s mark', () {
    expect(
      _marker(LayerKind.animation, TimelineCellExposureState.held),
      timelineCellWritesNothing,
    );
    expect(
      _marker(LayerKind.animation, TimelineCellExposureState.markHeld),
      _mark(breakdownMark),
    );
    expect(
      _marker(LayerKind.animation, TimelineCellExposureState.markUncovered),
      _mark(breakdownMark),
    );
  });

  test('🗣️an unnamed head and the dot inside a block are ONE mark, as data '
      '(유저 2026-09-24: 「중간나누기 마크1로서 작동했으면」)', () {
    final head = _marker(
      LayerKind.animation,
      TimelineCellExposureState.drawingStart,
    ).mark;
    final dot = _marker(
      LayerKind.animation,
      TimelineCellExposureState.markHeld,
    ).mark;
    expect(head, InbetweenMark.one);
    expect(dot, InbetweenMark.one);
  });
}
