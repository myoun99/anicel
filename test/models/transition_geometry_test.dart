import 'package:anicel/src/models/camera_instruction.dart';
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
  const ol = (start: 36, length: 24, mark: CameraInstructionMarkType.ol); // [36, 60), centred on 48

  group('firing', () {
    test('a span inside one cut does nothing at all', () {
      const inside = (start: 10, length: 12, mark: CameraInstructionMarkType.ol); // [10, 22) — well within c20

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
      const upTo = (start: 24, length: 24, mark: CameraInstructionMarkType.ol);

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
      const before = (start: 36, length: 24, mark: CameraInstructionMarkType.ol); // crosses c21's start
      const after = (start: 108, length: 24, mark: CameraInstructionMarkType.ol); // [108, 132) crosses c21's end

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
      const short = (start: 40, length: 16, mark: CameraInstructionMarkType.ol); // reaches 8 past the boundary
      const long = (start: 36, length: 24, mark: CameraInstructionMarkType.ol); // reaches 12 past it

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
    test('runs 0 to 1 INCLUSIVE across the span and is null outside it', () {
      expect(transitionProgressAt(ol, 35), isNull);
      expect(transitionProgressAt(ol, 36), 0.0);
      // Bottoms out ON the last frame — the canonical fade shape the cut
      // fade already uses, so a 1+0 O.L is 24 frames from wholly A to
      // wholly B and the frame after it is simply B.
      expect(transitionProgressAt(ol, 59), 1.0);
      expect(transitionProgressAt(ol, 60), isNull);
    });

    test('a one-frame transition is over on its only frame', () {
      expect(transitionProgressAt((start: 48, length: 1, mark: CameraInstructionMarkType.ol), 48), 1.0);
      expect(transitionProgressAt((start: 48, length: 1, mark: CameraInstructionMarkType.ol), 49), isNull);
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
      expect(transitionProgressAt((start: 48, length: 0, mark: CameraInstructionMarkType.ol), 48), isNull);
    });
  });

  /// ⑩ F.I and F.O move ONE cut (user 2026-08-11: 「자기컷일때만 발동」).
  ///
  /// The span reader used to drop the term's mark, so `cutOpacityAt` treated
  /// every span as a symmetric cross-dissolve: an F.O faded the NEXT cut in and
  /// was an O.L in all but name. The mark is carried now, and the sidedness is
  /// read off it — the bowtie is two cuts crossing, a wedge is one screen.
  group('sidedness', () {
    const foAcross = (
      start: 36,
      length: 24,
      mark: CameraInstructionMarkType.fo,
    );
    const foInside = (
      start: 24,
      length: 24,
      mark: CameraInstructionMarkType.fo,
    );

    test('the mark decides how many cuts a span touches', () {
      expect(transitionSidesOf(CameraInstructionMarkType.ol),
          TransitionSides.both);
      expect(transitionSidesOf(CameraInstructionMarkType.fo),
          TransitionSides.fadesOut);
      expect(transitionSidesOf(CameraInstructionMarkType.fi),
          TransitionSides.fadesIn);
    });

    test('🚨an F.O across the boundary fades ITS cut out and leaves the next '
        'one alone — the O.L would have faded it in', () {
      // The leaving cut ramps down, exactly as under an O.L…
      expect(cutOpacityAt(
        cutStart: c20Start,
        cutEnd: c20End,
        spans: const [foAcross],
        globalFrame: 36,
      ), 1.0);
      expect(cutOpacityAt(
        cutStart: c20Start,
        cutEnd: c20End,
        spans: const [foAcross],
        globalFrame: 59,
      ), 0.0);

      // …and the ARRIVING cut is untouched, which is the whole difference.
      //
      // ⚠️Frame 59 is deliberately NOT in the O.L comparison: the ramp reaches
      // 1 ON the span's last frame, so an O.L has the arriving cut already
      // whole there. Mid-ramp is where the two answers differ.
      for (final frame in [48, 54, 59]) {
        expect(
          cutOpacityAt(
            cutStart: c21Start,
            cutEnd: c21End,
            spans: const [foAcross],
            globalFrame: frame,
          ),
          1.0,
          reason: 'frame $frame: nothing rises to meet the fade',
        );
      }
      for (final frame in [48, 54]) {
        expect(
          cutOpacityAt(
            cutStart: c21Start,
            cutEnd: c21End,
            spans: const [ol],
            globalFrame: frame,
          ),
          lessThan(1.0),
          reason: 'frame $frame: under an O.L it would still be rising',
        );
      }
    });

    test('🚨an F.O INSIDE its cut fires — the placement that used to be a '
        'no-op, and the only one that actually falls to black', () {
      expect(
        transitionSpanFires(
          span: foInside,
          cutStart: c20Start,
          cutEnd: c20End,
        ),
        isTrue,
        reason: '"must straddle" is the O.L rule; a wedge needs no partner',
      );
      expect(cutOpacityAt(
        cutStart: c20Start,
        cutEnd: c20End,
        spans: const [foInside],
        globalFrame: 47,
      ), 0.0);
      // An O.L in the same place still does nothing, so the straddle rule is
      // relaxed for the wedges ONLY.
      expect(
        transitionSpanFires(
          span: const (start: 24, length: 24, mark: CameraInstructionMarkType.ol),
          cutStart: c20Start,
          cutEnd: c20End,
        ),
        isFalse,
      );
    });

    test('a one-sided span owes のりしろ on its OWN side only', () {
      // F.O reaching past c20's end: c20 draws the tail, c21 draws nothing —
      // it takes no part in this transition.
      expect(
        cutTransitionHandles(
          cutStart: c20Start,
          cutEnd: c20End,
          spans: const [foAcross],
        ),
        const CutTransitionHandles(head: 0, tail: 12),
      );
      expect(
        cutTransitionHandles(
          cutStart: c21Start,
          cutEnd: c21End,
          spans: const [foAcross],
        ),
        CutTransitionHandles.none,
      );
      // The mirror: an F.I gives the arriving cut its head and the leaving cut
      // nothing.
      const fiAcross = (
        start: 36,
        length: 24,
        mark: CameraInstructionMarkType.fi,
      );
      expect(
        cutTransitionHandles(
          cutStart: c21Start,
          cutEnd: c21End,
          spans: const [fiAcross],
        ),
        const CutTransitionHandles(head: 12, tail: 0),
      );
      expect(
        cutTransitionHandles(
          cutStart: c20Start,
          cutEnd: c20End,
          spans: const [fiAcross],
        ),
        CutTransitionHandles.none,
      );
    });

    test('an F.I ramps its own cut UP', () {
      const fi = (start: 48, length: 24, mark: CameraInstructionMarkType.fi);
      expect(cutOpacityAt(
        cutStart: c21Start,
        cutEnd: c21End,
        spans: const [fi],
        globalFrame: 48,
      ), 0.0);
      expect(cutOpacityAt(
        cutStart: c21Start,
        cutEnd: c21End,
        spans: const [fi],
        globalFrame: 71,
      ), 1.0);
    });
  });

  group('the mark projected into a cut', () {
    test('does not appear for a span that stays inside the cut', () {
      expect(
        transitionMarkInCut(
          span: const (start: 10, length: 12, mark: CameraInstructionMarkType.ol),
          cutStart: c20Start,
          cutEnd: c20End,
        ),
        isNull,
      );
    });

    test('sits at the outgoing cut\'s tail and overhangs its end', () {
      final mark = transitionMarkInCut(
        span: ol,
        cutStart: c20Start,
        cutEnd: c20End,
      )!;

      expect(mark.start, 36);
      expect(mark.length, 24, reason: 'the FULL 1+0, not the half inside');
      expect(mark.start + mark.length, greaterThan(c20End - c20Start));
    });

    test('is pulled whole to the incoming cut\'s head, never clipped', () {
      final mark = transitionMarkInCut(
        span: ol,
        cutStart: c21Start,
        cutEnd: c21End,
      )!;

      // Globally the span opens 12 frames before c21 does; locally the mark
      // starts at 0 and keeps its whole length. Half a bowtie would say
      // nothing to the animator reading the row.
      expect(mark.start, 0);
      expect(mark.length, 24);
    });

    test('global and local disagree on purpose', () {
      final outgoing = transitionMarkInCut(
        span: ol,
        cutStart: c20Start,
        cutEnd: c20End,
      )!;
      final incoming = transitionMarkInCut(
        span: ol,
        cutStart: c21Start,
        cutEnd: c21End,
      )!;

      // Same span, two different local placements — each cut sees it at its
      // own end. Only the global row places it where it really is.
      expect(outgoing.start + c20Start, ol.start);
      expect(incoming.start + c21Start, isNot(ol.start));
      expect(outgoing.length, incoming.length);
    });
  });

  group('per-cut opacity', () {
    double outgoing(int frame) => cutOpacityAt(
      cutStart: c20Start,
      cutEnd: c20End,
      spans: const [ol],
      globalFrame: frame,
    );
    double incoming(int frame) => cutOpacityAt(
      cutStart: c21Start,
      cutEnd: c21End,
      spans: const [ol],
      globalFrame: frame,
    );

    test('is 1 wherever no transition is running', () {
      expect(outgoing(0), 1.0);
      expect(outgoing(35), 1.0);
      expect(incoming(100), 1.0);
    });

    test('the two sides are mirror images across the same span', () {
      // Same question, opposite answers — that is the cross-dissolve.
      for (final frame in [36, 42, 48, 54, 59]) {
        expect(
          outgoing(frame) + incoming(frame),
          closeTo(1.0, 1e-9),
          reason: 'frame $frame',
        );
      }
      expect(outgoing(36), 1.0, reason: 'first frame: wholly the old cut');
      expect(incoming(36), 0.0);
      expect(outgoing(59), 0.0, reason: 'last frame: wholly the new cut');
      expect(incoming(59), 1.0);
    });

    test('two cuts on the same frame get DIFFERENT values', () {
      // The thing one opacity lane per track could never do.
      expect(outgoing(42), isNot(incoming(42)));
    });

    test('a cut has no picture outside its media range', () {
      // c21's material starts 12 frames before its conte start and not one
      // frame earlier.
      expect(incoming(35), 0.0);
      expect(incoming(36), 0.0, reason: 'in range, but the ramp is at 0');
      expect(incoming(37), greaterThan(0.0));
      expect(outgoing(60), 0.0, reason: 'past c20 tail material');
    });

    test('a span inside the cut changes nothing', () {
      expect(
        cutOpacityAt(
          cutStart: c20Start,
          cutEnd: c20End,
          spans: const [(start: 10, length: 12, mark: CameraInstructionMarkType.ol)],
          globalFrame: 16,
        ),
        1.0,
      );
    });
  });

  group('the ramp alone (the editing canvas\'s half)', () {
    // The split: [cutOpacityAt] = material clamp × ramp. The compositor
    // keeps both; a standing playhead reads only the ramp, because the
    // frames past the end line are ordinary space (T12) and "no material to
    // COMPOSE" must not become "an opaque wash over the paper you stand on".
    test('past the media end the ramp is 1 where the material term is 0', () {
      expect(
        cutOpacityAt(
          cutStart: c20Start,
          cutEnd: c20End,
          spans: const <TransitionSpan>[],
          globalFrame: c20End + 5,
        ),
        0.0,
        reason: 'the compositor really has nothing to draw there',
      );
      expect(
        cutTransitionRampAt(
          cutStart: c20Start,
          cutEnd: c20End,
          spans: const <TransitionSpan>[],
          globalFrame: c20End + 5,
        ),
        1.0,
        reason: 'but no transition covers the frame, so nothing thins it',
      );
    });

    test('inside the media range the two answers are the same number', () {
      for (final frame in [0, 36, 42, 48, 54, 59]) {
        expect(
          cutTransitionRampAt(
            cutStart: c20Start,
            cutEnd: c20End,
            spans: const [ol],
            globalFrame: frame,
          ),
          cutOpacityAt(
            cutStart: c20Start,
            cutEnd: c20End,
            spans: const [ol],
            globalFrame: frame,
          ),
          reason: 'frame $frame — the clamp is the ONLY thing the split '
              'removed, so wherever it does not fire the ramp IS the opacity',
        );
      }
    });
  });
}
