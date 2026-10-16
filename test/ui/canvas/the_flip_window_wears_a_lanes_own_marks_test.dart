import 'dart:ui' show ClipOp;

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
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart'
    show timelineLaneKeyMarkerSize, timelineLaneUnionKeyMarkerSize;

/// I-89 ②: the flip window's key rows wear their lanes' own marks — the
/// half for each side, the one drawing every key on the frame axis wears
/// ([paintKeyMark]) — at their lanes' own sizes, a frame's slot their cell
/// (F-367).
void main() {
  // A frame's slot on the window's frame axis: its cell.
  const slot = (
    cross: FlipHudMetrics.rowExtent,
    along: FlipHudMetrics.frameCellWidth,
  );
  final member = timelineLaneKeyMarkerSize(
    slot.cross,
    frameCellExtent: slot.along,
  );
  final union = timelineLaneUnionKeyMarkerSize(
    slot.cross,
    frameCellExtent: slot.along,
  );

  test('a lane\'s row carries the mark of each key it draws, and whether '
      'it heads a group', () {
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
    expect(row.isGroupHeader, isFalse);
    expect(
      flipHudLaneRow(
        const PropertyLaneRow(
          laneId: 'transform-group',
          label: 'Transform',
          keyMarks: {},
          isGroupHeader: true,
        ),
        kind: LayerKind.camera,
        withRuns: true,
      ).isGroupHeader,
      isTrue,
    );
  });

  /// What the window paints of a lane row keyed at 2, 5 and 8, the key at
  /// 5 wearing [middle].
  List<Invocation> paintedWith(KeyMark middle) {
    final canvas = TestRecordingCanvas();
    FlipHudPainter(
      snapshot: FlipHudSnapshot(
        rows: [
          FlipHudRow(
            name: 'Transform',
            kind: LayerKind.camera,
            isLane: true,
            isGroupHeader: true,
            holdsDrawings: false,
            runs: [
              const FlipHudRun(
                startIndex: 2,
                length: 1,
                keyMark: KeyMark.linear,
              ),
              FlipHudRun(startIndex: 5, length: 1, keyMark: middle),
              const FlipHudRun(
                startIndex: 8,
                length: 1,
                keyMark: KeyMark.linear,
              ),
            ],
          ),
        ],
        rowIndex: 0,
        frameIndex: 5,
        frameCount: 12,
      ),
      axis: FlipHudAxis.frame,
      frameStep: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      baseTextStyle: const TextStyle(fontSize: 11),
    ).paint(canvas, FlipHudMetrics.sizeFor(FlipHudAxis.frame));
    return [for (final call in canvas.invocations) call.invocation];
  }

  bool clearing(Invocation call) =>
      call.memberName == #clipRect &&
      call.namedArguments[#clipOp] == ClipOp.difference;

  test('the line stops at a hollow mark\'s box and goes on past it, as the '
      'panels\' does (I-89 ②)', () {
    final calls = paintedWith(KeyMark.mixed);
    // The ring is the one key's path, a header's, with a gap round its
    // middle (F-367-Q2).
    final ring = [
      for (final call in calls)
        if (call.memberName == #drawPath)
          call.positionalArguments[0] as Path,
    ].singleWhere((path) {
      final box = path.getBounds();
      return (box.width - union).abs() < 1e-6 &&
          !path.contains(box.center + Offset(box.width * 0.36, 0));
    });
    final clip = calls.indexWhere(clearing);
    expect(clip, isNot(-1), reason: 'the line is kept out of the ring');
    expect(
      calls[clip].positionalArguments[0],
      rectMoreOrLessEquals(ring.getBounds()),
    );
    expect(calls.where(clearing), hasLength(1), reason: 'only the ring');
    final line = calls.indexWhere((call) => call.memberName == #drawLine, clip);
    final restore = calls.indexWhere(
      (call) => call.memberName == #restore,
      clip,
    );
    expect(line, isNot(-1));
    expect(line, lessThan(restore), reason: 'stroked while it is kept out');
  });

  test('⛔every other mark has the line run under it', () {
    expect(paintedWith(_heldOut).where(clearing), isEmpty);
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

    // The key's mark is the one path drawn in a member key's box.
    final mark = [
      for (final call in canvas.invocations)
        if (call.invocation.memberName == #drawPath)
          call.invocation.positionalArguments[0] as Path,
    ].singleWhere((path) {
      final box = path.getBounds();
      return (box.width - member).abs() < 1e-6 &&
          (box.height - member).abs() < 1e-6;
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
