import 'package:flutter/widgets.dart' show Axis, Offset, Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/key_range_shift.dart';
import 'package:anicel/src/ui/timeline/lane_graph_box_stretch.dart';

/// **I-3 ⑥ — a header graph's box handle stretches the keys it holds about
/// the box's other end** (AE's transform box: 「Ctrl-drag to scale around
/// the anchor point」, 「Shift-drag to constrain the ratio」, 「Scale by
/// negative amounts to reverse the keyframes in time」).
void main() {
  const plain = (control: false, alt: false, shift: false);
  const ctrl = (control: true, alt: false, shift: false);

  /// The box's keys spread from [low] to [high] across the graph at both its
  /// ends — a box still.
  ({LaneGraphSpan first, LaneGraphSpan last}) even(double low, double high) =>
      (first: (low: low, high: high), last: (low: low, high: high));

  /// Keys from frame 0 to 8, their marks 100 to 200 across the graph, the
  /// box's anchor point at [pivot] between them.
  LaneGraphBoxHeld held(
    int along,
    int across, {
    LaneGraphBoxPoint pivot = laneGraphBoxMiddle,
  }) => (
    handle: (along: along, across: across),
    times: (low: 0, high: 8),
    across: (low: 100, high: 200),
    pivot: pivot,
  );

  test('the end of the frames pulled stretches them about the other end: '
      'twice as far, twice as long — and nothing across', () {
    final pull = laneGraphBoxPulled(
      held(1, 0),
      (time: 16, across: 999),
      plain,
    );
    expect(pull.time, (anchor: 0, factor: 2));
    expect(pull.across, even(100, 200));

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
    expect(pull.across, even(50, 200));
  });

  test('a corner stretches both ways, each about its own other end', () {
    final pull = laneGraphBoxPulled(
      held(1, 1),
      (time: 4, across: 300),
      plain,
    );
    expect(pull.time, (anchor: 0, factor: 0.5));
    expect(pull.across, even(100, 300));
  });

  test('with Ctrl held, about the box\'s middle', () {
    final pull = laneGraphBoxPulled(
      held(1, 1),
      (time: 12, across: 250),
      ctrl,
    );
    expect(pull.time, (anchor: 4, factor: 2));
    expect(pull.across, even(50, 250));
  });

  // graph-box-handles-more ⓓ — AE's 「Ctrl-drag to scale around the anchor
  // point」, its anchor point moved.
  test('with Ctrl held, about the anchor point where the hand has put it',
      () {
    final pull = laneGraphBoxPulled(
      held(1, 1, pivot: (along: 0.25, across: 0)),
      (time: 14, across: 300),
      ctrl,
    );
    expect(pull.time, (anchor: 2, factor: 2));
    expect(pull.across, even(100, 300));
  });

  test('a point of the way across a span, and back — none where it has no '
      'width', () {
    const span = (low: 100.0, high: 200.0);
    expect(
      [for (final of in [0.0, 0.25, 0.5, 1.0]) laneGraphSpanAt(span, of)],
      [100, 125, 150, 200],
    );
    expect(laneGraphSpanOf(span, 125), 0.25);
    expect(laneGraphSpanOf((low: 4, high: 4), 4), isNull);
  });

  test('with Shift held, a corner keeps the box\'s shape: both ways by the '
      'one that has gone further — and a side is not held to it', () {
    const square = (control: false, alt: false, shift: true);
    final further = laneGraphBoxPulled(
      held(1, 1),
      (time: 24, across: 150),
      square,
    );
    expect((further.time.factor, further.across), (3, even(100, 400)));
    final across = laneGraphBoxPulled(
      held(1, 1),
      (time: 4, across: 400),
      square,
    );
    expect((across.time.factor, across.across), (3, even(100, 400)));

    final side = laneGraphBoxPulled(
      held(1, 0),
      (time: 24, across: 999),
      square,
    );
    expect((side.time.factor, side.across), (3, even(100, 200)));
    final top = laneGraphBoxPulled(
      held(0, 1),
      (time: 99, across: 300),
      square,
    );
    expect((top.time.factor, top.across), (1, even(100, 300)));
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
        pivot: laneGraphBoxMiddle,
      ),
      (time: 9, across: 300),
      plain,
    );
    expect(pull.time.factor, 1);
    expect(pull.across, even(100, 300));
  });

  test('a frame stretched lands on the nearest whole frame', () {
    expect(frameStretched((anchor: 0, factor: 1.5), 3), 5);
    expect(frameStretched((anchor: 2, factor: 0.5), 9), 6);
    expect(frameStretched((anchor: 4, factor: -1), 1), 7);
  });

  // graph-box-handles-more ⓑ ⓒ — AE's 「To taper keyframe values
  // vertically, Ctrl+Alt-drag」 · 「To move one side of the bounding box up
  // or down, Ctrl+Alt+Shift-drag」.
  group('a corner with Ctrl and Alt held pulls its side alone', () {
    const taper = (control: true, alt: true, shift: false);
    const side = (control: true, alt: true, shift: true);

    /// Where a mark that stood [across] at [time] goes once [held] is
    /// pulled to [now] with [keys] held.
    double placed(
      LaneGraphBoxHeld held,
      LaneGraphBoxNow now,
      LaneGraphBoxKeys keys, {
      required double time,
      required double across,
    }) => laneGraphBoxAcrossOf(
      held,
      laneGraphBoxPulled(held, now, keys),
      time: time,
      across: across,
    );

    test('tapered: its two corners go apart about its middle as far as the '
        'hand, the other side stays, and nothing goes along the frames', () {
      final pull = laneGraphBoxPulled(
        held(1, -1),
        (time: 99, across: 80),
        taper,
      );
      expect(pull.time.factor, 1);
      expect(pull.across, (
        first: (low: 100, high: 200),
        last: (low: 80, high: 220),
      ));
      expect(
        [
          for (final (time, across) in [
            (8.0, 100.0),
            (8.0, 150.0),
            (0.0, 100.0),
            (4.0, 200.0),
          ])
            placed(
              held(1, -1),
              (time: 99, across: 80),
              taper,
              time: time,
              across: across,
            ),
        ],
        [80, 150, 100, 210],
        reason: 'the side pulled as far as the hand, its middle staying; the '
            'other side staying; between them, as far as they stood',
      );
    });

    test('and pulled in, they go together — past the middle, over it', () {
      final pull = laneGraphBoxPulled(
        held(-1, 1),
        (time: 99, across: 100),
        taper,
      );
      expect(pull.across, (
        first: (low: 200, high: 100),
        last: (low: 100, high: 200),
      ));
    });

    test('with Shift held too, the side goes with the hand', () {
      final pull = laneGraphBoxPulled(
        held(-1, 1),
        (time: 99, across: 230),
        side,
      );
      expect(pull.time.factor, 1);
      expect(pull.across, (
        first: (low: 130, high: 230),
        last: (low: 100, high: 200),
      ));
      expect(
        [
          for (final (time, across) in [
            (0.0, 100.0),
            (8.0, 100.0),
            (4.0, 150.0),
          ])
            placed(
              held(-1, 1),
              (time: 99, across: 230),
              side,
              time: time,
              across: across,
            ),
        ],
        [130, 100, 165],
      );
    });

    test('a side\'s middle has no side to pull alone: Alt goes unread, as '
        'Ctrl alone stretches it', () {
      expect(
        laneGraphBoxPulled(held(1, 0), (time: 12, across: 0), taper),
        laneGraphBoxPulled(held(1, 0), (time: 12, across: 0), ctrl),
      );
      expect(
        laneGraphBoxPulled(held(0, 1), (time: 0, across: 250), side),
        laneGraphBoxPulled(
          held(0, 1),
          (time: 0, across: 250),
          (control: true, alt: false, shift: true),
        ),
      );
    });

    test('keys all on one frame go with the end the hand has; keys all as '
        'high stand in the middle of the side', () {
      const oneFrame = (
        handle: (along: 1, across: -1),
        times: (low: 4.0, high: 4.0),
        across: (low: 100.0, high: 200.0),
        pivot: laneGraphBoxMiddle,
      );
      expect(
        placed(
          oneFrame,
          (time: 99, across: 80),
          side,
          time: 4,
          across: 100,
        ),
        80,
      );
      const level = (
        handle: (along: 1, across: -1),
        times: (low: 0.0, high: 8.0),
        across: (low: 150.0, high: 150.0),
        pivot: laneGraphBoxMiddle,
      );
      expect(
        placed(level, (time: 99, across: 130), taper, time: 8, across: 150),
        150,
        reason: 'a taper about the middle they stand on',
      );
      expect(
        placed(level, (time: 99, across: 130), side, time: 8, across: 150),
        130,
      );
    });
  });

  test('a box stretched still places each mark as far from the anchor '
      'times as far as it stood', () {
    final pull = laneGraphBoxPulled(
      held(0, 1),
      (time: 99, across: 300),
      plain,
    );
    expect(
      [
        for (final across in [100.0, 150.0, 200.0])
          laneGraphBoxAcrossOf(held(0, 1), pull, time: 3, across: across),
      ],
      [100, 200, 300],
    );
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
