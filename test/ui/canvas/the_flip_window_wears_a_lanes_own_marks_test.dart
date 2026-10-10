import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/key_mark.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart' show KeySideKind;
import 'package:anicel/src/ui/canvas/flip_hud_controller.dart';
import 'package:anicel/src/ui/canvas/flip_hud_model.dart';
import 'package:anicel/src/ui/canvas/flip_hud_overlay.dart';
import 'package:anicel/src/ui/canvas/flip_hud_rows.dart' show flipHudLaneRow;
import 'package:anicel/src/ui/timeline/property_lane_model.dart';

/// I-89 ②: the flip window's key rows wear their lanes' own marks — the
/// half for each side, the one drawing every key on the frame axis wears
/// ([paintKeyMark]).
void main() {
  test('a lane\'s row carries the mark of each key it draws', () {
    final row = flipHudLaneRow(
      const PropertyLaneRow(
        laneId: 'position',
        label: 'Position',
        keyMarks: {5: KeyMark.linear, 2: _heldOut},
      ),
      kind: LayerKind.camera,
      withRuns: true,
    );
    expect(
      [for (final run in row.runs) (run.startIndex, run.keyMark)],
      [(2, _heldOut), (5, KeyMark.linear)],
    );
  });

  test('the window paints a key\'s mark, not a diamond of its own', () {
    final canvas = TestRecordingCanvas();
    FlipHudPainter(
      snapshot: const FlipHudSnapshot(
        rows: [
          FlipHudRow(
            name: 'Position',
            kind: LayerKind.camera,
            isLane: true,
            holdsDrawings: false,
            runs: [FlipHudRun(startIndex: 3, length: 1, keyMark: _heldOut)],
          ),
        ],
        rowIndex: 0,
        frameIndex: 3,
        frameCount: 12,
      ),
      axis: FlipHudAxis.frame,
      frameStep: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      baseTextStyle: const TextStyle(fontSize: 11),
    ).paint(canvas, FlipHudMetrics.sizeFor(FlipHudAxis.frame));

    // The key's mark is the one path drawn in a key's 9px box.
    final mark = [
      for (final call in canvas.invocations)
        if (call.invocation.memberName == #drawPath)
          call.invocation.positionalArguments[0] as Path,
    ].singleWhere((path) {
      final box = path.getBounds();
      return (box.width - 9).abs() < 1e-6 && (box.height - 9).abs() < 1e-6;
    });
    final middle = mark.getBounds().center;
    expect(
      mark.contains(middle + const Offset(3.5, -3.5)),
      isTrue,
      reason: 'the side leaving holds: its half is a square',
    );
    expect(
      mark.contains(middle + const Offset(-3.5, -3.5)),
      isFalse,
      reason: 'the side arriving is straight: its half is a diamond\'s',
    );
  });
}

/// A straight key that holds from there on — AE's Toggle Hold Keyframe.
const _heldOut = SidesKeyMark(
  incoming: KeySideKind.linear,
  outgoing: KeySideKind.hold,
);
