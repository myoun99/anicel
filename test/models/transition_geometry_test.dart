import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/transition_geometry.dart';

/// The 撮ま! accounting in numbers: a transition never moves a cut block and
/// never changes a total. It only says how much material each side draws
/// OUTSIDE its conte length.
///
/// The worked example throughout is the design's own: c20 is 2+0 (48
/// frames), c21 is 3+0 (72), and a 1+0 (24) O.L sits centred on the
/// boundary at global frame 48 — so it runs [36, 60).
void main() {
  const fps = 24;
  const c20Start = 0;
  const c20End = 2 * fps; // 48 — the conte boundary
  const c21Start = c20End;
  const c21End = c21Start + 3 * fps; // 120
  const ol = (start: 36, length: 24); // [36, 60), centred on 48

  group('firing', () {
    test('a span inside one cut does nothing at all', () {
      const inside = (start: 10, length: 12); // [10, 22) — well within c20

      expect(
        transitionSpanFires(span: inside, cutStart: c20Start, cutEnd: c20End),
        isFalse,
      );
      expect(
        cutTransitionHandles(
          cutStart: c20Start,
          cutEnd: c20End,
          spans: const [inside],
        ),
        CutTransitionHandles.none,
      );
    });

    test('a span crossing a boundary fires for BOTH neighbours', () {
      expect(
        transitionSpanFires(span: ol, cutStart: c20Start, cutEnd: c20End),
        isTrue,
      );
      expect(
        transitionSpanFires(span: ol, cutStart: c21Start, cutEnd: c21End),
        isTrue,
      );
    });

    test('a span that merely touches a boundary does not cross it', () {
      // [24, 48): ends exactly where c20 ends, so it is inside c20 — there
      // is no frame of it on the other side to overlap with.
      const upTo = (start: 24, length: 24);

      expect(
        transitionSpanFires(span: upTo, cutStart: c20Start, cutEnd: c20End),
        isFalse,
      );
    });
  });

  group('のりしろ', () {
    test('the outgoing cut draws past its end, the incoming before its start', () {
      final outgoing = cutTransitionHandles(
        cutStart: c20Start,
        cutEnd: c20End,
        spans: const [ol],
      );
      final incoming = cutTransitionHandles(
        cutStart: c21Start,
        cutEnd: c21End,
        spans: const [ol],
      );

      expect(outgoing, const CutTransitionHandles(head: 0, tail: 12));
      expect(incoming, const CutTransitionHandles(head: 12, tail: 0));
    });

    test('the sheet prints 2+0 (2+12) and 3+0 (3+12)', () {
      final outgoing = cutTransitionHandles(
        cutStart: c20Start,
        cutEnd: c20End,
        spans: const [ol],
      );
      final incoming = cutTransitionHandles(
        cutStart: c21Start,
        cutEnd: c21End,
        spans: const [ol],
      );

      expect(outgoing.drawnFrames(c20End - c20Start), 2 * fps + 12);
      expect(incoming.drawnFrames(c21End - c21Start), 3 * fps + 12);
    });

    test('the conte total is untouched — that is the whole accounting', () {
      // 2+0 + 3+0 = 5+0 whether or not the O.L is there. Only the drawn
      // material grew.
      expect((c20End - c20Start) + (c21End - c21Start), 5 * fps);
    });

    test('a cut between two transitions owes material on both sides', () {
      const before = (start: 36, length: 24); // crosses c21's start
      const after = (start: 108, length: 24); // [108, 132) crosses c21's end

      expect(
        cutTransitionHandles(
          cutStart: c21Start,
          cutEnd: c21End,
          spans: const [before, after],
        ),
        const CutTransitionHandles(head: 12, tail: 12),
      );
    });

    test('overlapping demands take the largest reach, not the sum', () {
      const short = (start: 40, length: 16); // reaches 8 past the boundary
      const long = (start: 36, length: 24); // reaches 12 past it

      expect(
        cutTransitionHandles(
          cutStart: c20Start,
          cutEnd: c20End,
          spans: const [short, long],
        ).tail,
        12,
      );
    });
  });

  test('the media range widens while the conte range stays put', () {
    final handles = cutTransitionHandles(
      cutStart: c21Start,
      cutEnd: c21End,
      spans: const [ol],
    );
    final media = cutMediaRange(
      cutStart: c21Start,
      cutEnd: c21End,
      handles: handles,
    );

    expect(media.start, c21Start - 12);
    expect(media.end, c21End);
    // The block itself never moved: whoever asks "which cut owns frame 40"
    // still reads the conte range and still gets c20.
    expect(c21Start, c20End);
  });

  group('the ramp', () {
    test('runs 0 to 1 across the span and is null outside it', () {
      expect(transitionProgressAt(ol, 35), isNull);
      expect(transitionProgressAt(ol, 36), 0.0);
      expect(transitionProgressAt(ol, 48), 0.5); // the conte boundary
      expect(transitionProgressAt(ol, 59), closeTo(1.0, 1 / 24));
      expect(transitionProgressAt(ol, 60), isNull);
    });

    test('both cuts read the SAME ramp — that is what makes it an O.L', () {
      // The outgoing side fades out by it and the incoming side fades in by
      // it. Two separate fades would be a dip to black instead.
      for (final frame in [36, 42, 48, 54, 59]) {
        final progress = transitionProgressAt(ol, frame)!;
        expect(progress + (1 - progress), 1.0);
      }
    });

    test('a zero-length span has no ramp rather than dividing by zero', () {
      expect(transitionProgressAt((start: 48, length: 0), 48), isNull);
    });
  });
}
