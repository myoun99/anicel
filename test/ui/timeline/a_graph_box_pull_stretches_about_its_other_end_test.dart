import 'package:flutter/widgets.dart' show Axis, Offset, Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/key_range_shift.dart';
import 'package:anicel/src/ui/timeline/lane_graph_box_stretch.dart';

/// **I-3 ⑥ — a header graph's box handle stretches the keys it holds about
/// the box's other end** (AE's transform box: 「Ctrl-drag to scale around
/// the anchor point」, 「Shift-drag to constrain the ratio」, 「Scale by
/// negative amounts to reverse the keyframes in time」).
void main() {
  const plain = (centred: false, square: false);

  /// Keys from frame 0 to 8, their marks 100 to 200 across the graph.
  LaneGraphBoxHeld held(int along, int across) => (
    handle: (along: along, across: across),
    times: (low: 0, high: 8),
    across: (low: 100, high: 200),
  );

  test('the end of the frames pulled stretches them about the other end: '
      'twice as far, twice as long — and nothing across', () {
    final pull = laneGraphBoxPulled(
      held(1, 0),
      (time: 16, across: 999),
      plain,
    );
    expect(pull.time, (anchor: 0, factor: 2));
    expect(pull.across.factor, 1);

    final back = laneGraphBoxPulled(held(-1, 0), (time: -8, across: 0), plain);
    expect(back.time, (anchor: 8, factor: 2));
  });

  test('a side across stretches across alone, about the other side', () {
    final pull = laneGraphBoxPulled(
      held(0, -1),
      (time: 99, across: 50),
      plain,
    );
    expect(pull.time.factor, 1);
    expect(pull.across, (anchor: 200, factor: 1.5));
  });

  test('a corner stretches both ways, each about its own other end', () {
    final pull = laneGraphBoxPulled(
      held(1, 1),
      (time: 4, across: 300),
      plain,
    );
    expect(pull.time, (anchor: 0, factor: 0.5));
    expect(pull.across, (anchor: 100, factor: 2));
  });

  test('with Ctrl held, about the box\'s middle', () {
    final pull = laneGraphBoxPulled(
      held(1, 1),
      (time: 12, across: 250),
      (centred: true, square: false),
    );
    expect(pull.time, (anchor: 4, factor: 2));
    expect(pull.across, (anchor: 150, factor: 2));
  });

  test('with Shift held, a corner keeps the box\'s shape: both ways by the '
      'one that has gone further — and a side is not held to it', () {
    const square = (centred: false, square: true);
    final further = laneGraphBoxPulled(
      held(1, 1),
      (time: 24, across: 150),
      square,
    );
    expect((further.time.factor, further.across.factor), (3, 3));
    final across = laneGraphBoxPulled(
      held(1, 1),
      (time: 4, across: 400),
      square,
    );
    expect((across.time.factor, across.across.factor), (3, 3));

    final side = laneGraphBoxPulled(
      held(1, 0),
      (time: 24, across: 999),
      square,
    );
    expect((side.time.factor, side.across.factor), (3, 1));
  });

  test('pulled past the other end, the factor goes under 0 — the keys turn '
      'about it', () {
    final pull = laneGraphBoxPulled(held(1, 0), (time: -8, across: 0), plain);
    expect(pull.time, (anchor: 0, factor: -1));
    expect(frameStretched(pull.time, 8), -8);
  });

  test('keys all on one frame are not stretched along the frames', () {
    final pull = laneGraphBoxPulled(
      (
        handle: (along: 1, across: 1),
        times: (low: 4, high: 4),
        across: (low: 100, high: 200),
      ),
      (time: 9, across: 300),
      plain,
    );
    expect(pull.time.factor, 1);
    expect(pull.across.factor, 2);
  });

  test('a frame stretched lands on the nearest whole frame', () {
    expect(frameStretched((anchor: 0, factor: 1.5), 3), 5);
    expect(frameStretched((anchor: 2, factor: 0.5), 9), 6);
    expect(frameStretched((anchor: 4, factor: -1), 1), 7);
  });

  test('the handles stand at the box\'s corners and its sides\' middles, '
      'turned with the axis the frames run along', () {
    const box = Rect.fromLTRB(10, 20, 50, 100);
    expect(
      [
        for (final handle in laneGraphBoxHandles)
          laneGraphBoxHandleAt(handle, box, Axis.horizontal),
      ],
      const [
        Offset(10, 20),
        Offset(30, 20),
        Offset(50, 20),
        Offset(50, 60),
        Offset(50, 100),
        Offset(30, 100),
        Offset(10, 100),
        Offset(10, 60),
      ],
    );
    expect(
      laneGraphBoxHandleAt((along: 1, across: -1), box, Axis.vertical),
      const Offset(10, 100),
      reason: 'the X-sheet\'s frames run down: the end of them is the bottom',
    );
  });
}
