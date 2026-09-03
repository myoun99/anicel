// ONE MARKER TABLE FOR THE ROW PAINTER AND THE DIALOG MINIATURE.
//
// The miniature kept its own copy of this table until 2026-09-03, and the
// copy still stopped the timesheet X at the playback range — a rule the
// user retired on 2026-08-02. These pins say what the one table answers,
// so the next copy has nothing to drift from.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_marker.dart';

Layer _layer(LayerKind kind) =>
    Layer(id: const LayerId('l'), name: 'L', frames: const [], kind: kind);

String _marker(
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

void main() {
  group('the timesheet X', () {
    test('marks the first cell of an empty run on a drawing row', () {
      expect(
        _marker(
          LayerKind.animation,
          TimelineCellExposureState.uncovered,
          emptyRunStart: true,
        ),
        'X',
      );
    });

    test('only the FIRST cell — the rest of the run stays blank', () {
      expect(
        _marker(LayerKind.animation, TimelineCellExposureState.uncovered),
        '',
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
          '',
          reason: '$kind',
        );
      }
    });
  });

  group('a drawing start', () {
    test('shows the frame name, or the paper ○ when it has none', () {
      expect(
        _marker(
          LayerKind.animation,
          TimelineCellExposureState.drawingStart,
          frameName: 'A',
        ),
        'A',
      );
      expect(
        _marker(LayerKind.animation, TimelineCellExposureState.drawingStart),
        '○',
      );
      expect(
        _marker(
          LayerKind.animation,
          TimelineCellExposureState.drawingStart,
          frameName: '',
        ),
        '○',
      );
    });

    test('says nothing on a camera row — its keys ride the lane markers', () {
      expect(
        _marker(
          LayerKind.camera,
          TimelineCellExposureState.drawingStart,
          frameName: 'K',
        ),
        '',
      );
    });
  });

  test('a held cell is blank and a mark is ●', () {
    expect(_marker(LayerKind.animation, TimelineCellExposureState.held), '');
    expect(
      _marker(LayerKind.animation, TimelineCellExposureState.markHeld),
      '●',
    );
    expect(
      _marker(LayerKind.animation, TimelineCellExposureState.markUncovered),
      '●',
    );
  });
}
