import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/present_slot.dart';

/// WHICH VBLANK EACH LOOK OF A CLOCK FILLS (유저 2026-10-11: 「144hz든
/// 몇이든 확실하게 근본/구조적으로 해결하도록」): one look, one real vblank,
/// one after another — whatever the engine's own vsync grid does — and a
/// hand-off that lands the scenes' measured lengths inside the latch.
void main() {
  const vblank = 5000000;
  const period = 6948.6; // a 143.9Hz screen, as DWM says it
  const budget = 3000;
  const width = period - presentLatchEarlyMicros - presentLatchLateMicros;

  int vblankIndexOf(num micros) => ((micros - vblank) / period).round();

  /// The hand-off for scenes of these [lengths], as the spread learns them.
  double handOffOf(List<int> lengths, {int capacity = 32}) {
    final spread = RasterSpread(capacity: capacity);
    lengths.forEach(spread.add);
    return spread.handOffFor(period);
  }

  /// A claim for a look made at [now].
  PresentClaim claimAt(
    PresentClaims claims,
    num now, {
    double? handOff,
  }) => claims.claim(
    nowMicros: now.round(),
    vblankMicros: vblank,
    periodMicros: period,
    composedVblankMicros: vblank,
    composedEveryMicros: period,
    budgetMicros: budget,
    handOffMicros: handOff ?? RasterSpread().handOffFor(period),
  );

  /// The vblank a claim's picture is shown on.
  int shownOn(PresentClaim claim) => vblankIndexOf(claim.shownAtMicros);

  /// Where, past the vblank [claim] claimed, a scene of [length] handed over
  /// at [handOff] ends.
  double endOf(PresentClaim claim, int handOff, int length) =>
      handOff +
      length -
      (claim.shownAtMicros - presentShownAfterVblanks * period);

  /// Inside the latch's window — to the microsecond each of the hand-off
  /// and the vblank round to.
  final insideTheLatch = inInclusiveRange(
    presentLatchEarlyMicros - 1,
    period - presentLatchLateMicros + 1,
  );

  test('🚨every learned length handed over at the hand-off ends between the '
      'latch\'s edges of the vblank it claimed', () {
    final lengths = [for (var i = 0; i < 32; i += 1) 3600 + i * 100];
    final claim = claimAt(
      PresentClaims(),
      vblank + 300 * period + 1234,
      handOff: handOffOf(lengths),
    );
    for (final length in lengths) {
      expect(
        endOf(claim, claim.handOffMicros, length),
        insideTheLatch,
        reason: '$length long',
      );
    }
  });

  test('🚨THE LATCH ON THE GLASS (10-13): the shortest scene is handed over '
      'to end ON the vblank its look claimed, and the picture is shown three '
      'vblanks after the claimed one', () {
    final lengths = [for (var i = 0; i < 16; i += 1) 2000 + i * 120];
    final claim = claimAt(
      PresentClaims(),
      vblank + 400 * period + 777,
      handOff: handOffOf(lengths),
    );
    final claimed = claim.shownAtMicros - 3 * period;
    expect(
      claim.handOffMicros + lengths.first - claimed,
      closeTo(0, 1),
      reason: 'a microsecond of rounding each, the hand-off and the vblank',
    );
  });

  test('🚨THE LATCH ON THE GLASS (10-13): scenes a refresh less the '
      'compositor\'s 1.5ms lead apart land together; a microsecond further '
      'apart, the more of them take the hand-off', () {
    final apart = (period - 1500).floor();
    // Four older scenes, and twelve newer ones that outweigh them.
    List<int> scenes(int longer) => [
      for (var i = 0; i < 4; i += 1) 2000,
      for (var i = 0; i < 12; i += 1) 2000 + longer,
    ];
    expect(handOffOf(scenes(apart)), -2000);
    expect(handOffOf(scenes(apart + 1)), -2000 - (apart + 1));
  });

  test('🚨lengths wider than the latch leaves: the hand-off lands the most '
      'of them — a few slow scenes among them do not move it', () {
    // Every fourth scene a slow one, the newest of all among them.
    final lengths = [
      for (var i = 0; i < 32; i += 1)
        if (i % 4 == 3) 9000 + (i ~/ 4) * 900 else 4000 + (i % 8) * 125,
    ];
    final steady = [for (final length in lengths) if (length < 9000) length];
    final claim = claimAt(
      PresentClaims(),
      vblank + 500 * period + 4321,
      handOff: handOffOf(lengths),
    );
    for (final length in steady) {
      expect(endOf(claim, claim.handOffMicros, length), insideTheLatch);
    }
  });

  test('🚨a run still making its pictures does not drag the window after '
      'it: the steady scenes take it back as soon as they outnumber the '
      'slow ones within one window\'s width', () {
    final making = [for (var i = 0; i < 24; i += 1) 20000 + i * 1700];
    final steady = [for (var i = 0; i < 8; i += 1) 4000 + i * 150];
    final claim = claimAt(
      PresentClaims(),
      vblank + 600 * period + 100,
      handOff: handOffOf([...making, ...steady]),
    );
    for (final length in steady) {
      expect(endOf(claim, claim.handOffMicros, length), insideTheLatch);
    }
  });

  test('🚨a run that changes is followed within a few frames: once its '
      'pictures are all made, six steady scenes take the window back — not '
      'half the ring', () {
    final making = [for (var i = 0; i < 26; i += 1) 12000 + (i % 7) * 100];
    final steady = [for (var i = 0; i < 6; i += 1) 4000 + i * 100];
    final claim = claimAt(
      PresentClaims(),
      vblank + 650 * period + 300,
      handOff: handOffOf([...making, ...steady]),
    );
    for (final length in steady) {
      expect(endOf(claim, claim.handOffMicros, length), insideTheLatch);
    }
  });

  test('older scenes running on up from the steady ones without a gap do '
      'not pull the window after them', () {
    final steady = [for (var i = 0; i < 6; i += 1) 4000 + i * 60];
    final claim = claimAt(
      PresentClaims(),
      vblank + 670 * period + 300,
      handOff: handOffOf([
        for (var i = 0; i < 26; i += 1) 4400 + i * 400,
        ...steady,
      ]),
    );
    for (final length in steady) {
      expect(endOf(claim, claim.handOffMicros, length), insideTheLatch);
    }
  });

  test('a ring come round still weighs its newest most', () {
    final steady = [for (var i = 0; i < 6; i += 1) 4000 + i * 100];
    final claim = claimAt(
      PresentClaims(),
      vblank + 660 * period + 300,
      handOff: handOffOf([
        for (var i = 0; i < 16; i += 1) 12000 + (i % 7) * 100,
        ...steady,
      ], capacity: 16),
    );
    for (final length in steady) {
      expect(endOf(claim, claim.handOffMicros, length), insideTheLatch);
    }
  });

  test('🚨looks a period apart fill vblanks one after another — at every '
      'phase the engine\'s vsync can stand at', () {
    for (var phase = 0.0; phase < period; phase += 400) {
      final claims = PresentClaims();
      final first = vblank + 1000 * period + phase;
      final shown = [
        for (var look = 0; look < 12; look += 1)
          shownOn(claimAt(claims, first + look * period)),
      ];
      for (var look = 1; look < shown.length; look += 1) {
        expect(
          shown[look] - shown[look - 1],
          1,
          reason: 'phase $phase, look $look',
        );
      }
    }
  });

  test('🚨the engine\'s grid jumping by part of a refresh moves when a look '
      'happens, not which vblank it fills', () {
    final claims = PresentClaims();
    var at = vblank + 2000 * period + 500;
    final shown = <int>[];
    for (var look = 0; look < 24; look += 1) {
      shown.add(shownOn(claimAt(claims, at)));
      // Every fifth look the grid jumps 1.95ms on, then back.
      at += period + (look % 10 == 4 ? 1950 : (look % 10 == 9 ? -1950 : 0));
    }
    for (var look = 1; look < shown.length; look += 1) {
      expect(shown[look] - shown[look - 1], 1, reason: 'look $look');
    }
  });

  test('🚨a look a little late — a jittered tick — still fills the vblank '
      'after the last: the run\'s lead covers it', () {
    final claims = PresentClaims();
    const at = vblank + 3000 * period + 100;
    final first = shownOn(claimAt(claims, at));
    final late = shownOn(claimAt(claims, at + period + 0.9 * period));
    expect(late, first + 1);
  });

  test('🚨the look after a change takes the lead back — passing over one '
      'vblank, the one right after the change, and no more', () {
    final claims = PresentClaims();
    const at = vblank + 4000 * period + 2500;
    final shown = [shownOn(claimAt(claims, at))];
    // A look that waited for its hand-off: the look after it comes two
    // vsyncs on and has spent the lead.
    claims.changed();
    shown.add(shownOn(claimAt(claims, at + 2 * period)));
    expect(shown[1] - shown[0], 2, reason: 'one vblank passed over');
    // From there the lead holds: a late look fills the next vblank.
    shown.add(shownOn(claimAt(claims, at + 3 * period + 0.9 * period)));
    expect(shown[2] - shown[1], 1);
  });

  test('a look after a change that comes late passes over one vblank still, '
      'and no more — a change could be due at the next', () {
    final claims = PresentClaims();
    const at = vblank + 8000 * period + 2500;
    final first = shownOn(claimAt(claims, at));
    claims.changed();
    final next = shownOn(claimAt(claims, at + 3 * period));
    expect(next - first, 2);
  });

  test('a look that comes long after the last — a run started again — '
      'starts the chain afresh, with its lead', () {
    final claims = PresentClaims();
    claimAt(claims, vblank + 5000 * period);
    final fresh = PresentClaims();
    const later = vblank + 6000 * period + 1000;
    expect(
      shownOn(claimAt(claims, later)),
      shownOn(claimAt(fresh, later)),
    );
  });

  test('a look that comes early claims the last vblank again, never one '
      'more than the reserve past what it can make', () {
    final claims = PresentClaims();
    const at = vblank + 7000 * period + 3000;
    final first = shownOn(claimAt(claims, at));
    // Two looks within the same refresh: the second claims the same.
    final again = shownOn(claimAt(claims, at + 10));
    expect(again - first, lessThanOrEqualTo(1));
    final more = shownOn(claimAt(claims, at + 20));
    expect(more, again, reason: 'the reserve stops the chain running ahead');
  });

  test('🚨a look that falls behind claims the first vblank whose hand-off '
      'its frame can still wait for — the budget to reach the seam left '
      'before it', () {
    final handOff = handOffOf([for (var i = 0; i < 8; i += 1) 4000]);
    final claims = PresentClaims();
    const at = vblank + 9000 * period;
    claimAt(claims, at, handOff: handOff);
    // Three refreshes and a half on: past what the run's lead covers.
    const behind = at + 3.5 * period;
    final claim = claimAt(claims, behind, handOff: handOff);
    expect(behind + budget, lessThanOrEqualTo(claim.handOffMicros));
    expect(
      behind + budget,
      greaterThan(claim.handOffMicros - period),
      reason: 'the vblank before it is out of reach',
    );
  });

  group('the scenes\' lengths', () {
    test('until eight frames have said, the hand-off ends a 2ms scene — the '
        'shortest the latch\'s machine took — on the vblank', () {
      final spread = RasterSpread();
      for (var i = 0; i < 7; i += 1) {
        spread.add(9000);
      }
      expect(spread.handOffFor(period), -2000);
      spread.add(9000);
      expect(spread.handOffFor(period), -9000);
    });

    test('🚨one scene an upload landed in does not move the window', () {
      final steady = [for (var i = 0; i < 31; i += 1) 3500 + (i % 10) * 200];
      expect(
        handOffOf([...steady, 13000]),
        handOffOf([...steady, 3500]),
      );
    });

    test('🚨how late the raster thread is seen past a scene is a batch\'s '
        'median — one fence held up behind a busy thread says nothing of '
        'the rest', () {
      expect(seenLateOf([12000, 540, 520, 560, 530]), 540);
      expect(seenLateOf([530, 540, 520, 560, 12000]), 540);
    });

    test('follow the last frames only — an old spread is forgotten', () {
      expect(
        handOffOf([
          for (var i = 0; i < 16; i += 1) 9000,
          for (var i = 0; i < 16; i += 1) 4000,
        ], capacity: 16),
        handOffOf([for (var i = 0; i < 16; i += 1) 4000], capacity: 16),
      );
    });
  });

  test('⛔premise: at 144Hz the latch leaves a window wider than the '
      'lengths these pins spread', () {
    expect(width, greaterThan(4000));
  });

  group('the quiet between two held frames', () {
    const held = 5000000.0; // the vblank the last held frame claimed
    const handOff = -3200.0;
    const margin = 4000;

    ({int fromMicros, int untilMicros}) quietAfter({
      int gap = 6,
      double periodMicros = period,
      double handOffMicros = handOff,
    }) => quietBetweenHeldFrames(
      held: (
        vblankMicros: held,
        periodMicros: periodMicros,
        gap: gap,
        handOffMicros: handOffMicros,
      ),
      marginMicros: margin,
    );

    test('🚨runs from where the held frame\'s latch window closes to the '
        'next held frame\'s hand-off, less the margin — on the vblank '
        'grid', () {
      expect(quietAfter(), (
        fromMicros: (held + period - presentLatchLateMicros).round(),
        untilMicros: (held + 6 * period + handOff).round() - margin,
      ));
    });

    test('🚨at 60Hz a film held two refreshes and three by turns leaves '
        'room after each — reckoned for the two', () {
      final quiet = quietAfter(gap: 2, periodMicros: 1e6 / 60);
      expect(quiet.untilMicros, greaterThan(quiet.fromMicros + 8000));
    });

    test('🚨scenes as long as the frames come leave an EMPTY quiet — the '
        'work waits; it is not let run beside the frames', () {
      final quiet = quietAfter(gap: 1, handOffMicros: -6000);
      expect(quiet.untilMicros, lessThanOrEqualTo(quiet.fromMicros));
    });
  });

  test('🚨on the compositor\'s own screen a picture is shown three vblanks '
      'past the one its raster ends past — at 60Hz too, where the law of a '
      'slower screen would have it two (at 143.9Hz the two meet)', () {
    const sixty = 16666.0;
    final claim = PresentClaims().claim(
      nowMicros: vblank + 1000,
      vblankMicros: vblank,
      periodMicros: sixty,
      composedVblankMicros: vblank,
      composedEveryMicros: sixty,
      budgetMicros: budget,
      handOffMicros: -2000,
    );
    expect(
      claim.shownAtMicros,
      (claim.vblankMicros + presentShownAfterVblanks * sixty).round(),
    );
  });

  /// 🚨THE COMPOSITOR HAS ONE CLOCK AND EVERY SCREEN ITS OWN VBLANKS (card
  /// playback-pacing-knows-one-display-only, 2026-11-02): a window on a
  /// 59.95Hz screen under a 143.9Hz compositor.
  group('on a screen slower than the compositor\'s clock', () {
    const refresh = 16680.0;
    const composedAt = vblank + 1000;
    const handOff = -2000.0;

    PresentClaim claimOnIt(
      PresentClaims claims,
      num now, {
      double screen = refresh,
      double composedEvery = period,
    }) => claims.claim(
      nowMicros: now.round(),
      vblankMicros: vblank,
      periodMicros: screen,
      composedVblankMicros: composedAt,
      composedEveryMicros: composedEvery,
      budgetMicros: budget,
      handOffMicros: handOff,
    );

    double latchOf(double vblankShownOn) => latchOnTheCompositor(
      vblank: vblankShownOn,
      composedVblankMicros: composedAt,
      composedEveryMicros: period,
    );

    int indexOf(num shownAt) => ((shownAt - vblank) / refresh).round();

    /// The earliest of the screen's vblanks a look at [now] can make.
    int earliestAt(num now) {
      var index = -1000;
      while (latchOf(vblank + index * refresh) + handOff < now + budget) {
        index += 1;
      }
      return index;
    }

    test('🚨the latch on the compositor\'s grid is the last whose frame and '
        'present still come before the vblank shown on', () {
      const shownOn = vblank + 100 * refresh;
      final latch = latchOf(shownOn);
      expect(
        ((latch - composedAt) / period) % 1,
        closeTo(0, 1e-6),
        reason: 'one of the compositor\'s own vblanks',
      );
      final frame = latch + period;
      expect(
        frame + composedFramePresentsWithinMicros,
        lessThanOrEqualTo(shownOn),
      );
      expect(
        frame + period + composedFramePresentsWithinMicros,
        greaterThan(shownOn),
      );
    });

    test('🚨a picture is shown on the vblank claimed, and its frame handed '
        'over at the latch for it', () {
      final claim = claimOnIt(PresentClaims(), vblank + 1000);
      final shownOn = claim.shownAtMicros.toDouble();
      expect(
        ((shownOn - vblank) / refresh) % 1,
        closeTo(0, 1e-3),
        reason: 'one of the screen\'s own vblanks, not one on past it',
      );
      expect(claim.vblankMicros, latchOf(shownOn));
      expect(claim.handOffMicros, (latchOf(shownOn) + handOff).round());
    });

    test('🚨a look claims the earliest vblank it can make: a lead of a look '
        'is no refresh there, and a refresh of it only holds the frame', () {
      const now = vblank + 5000;
      expect(
        indexOf(claimOnIt(PresentClaims(), now).shownAtMicros),
        earliestAt(now),
      );
    });

    test('🚨the looks of one refresh all claim its vblank — they come faster '
        'than the vblanks, and do not run on ahead of them', () {
      final claims = PresentClaims();
      for (var i = 0; i < 60; i += 1) {
        final now = vblank + i * period;
        expect(indexOf(claimOnIt(claims, now).shownAtMicros), earliestAt(now));
      }
    });

    test('🚨a look after a change takes the next vblank: the one it claimed '
        'carries the picture already', () {
      final claims = PresentClaims();
      final first = claimOnIt(claims, vblank + 1000);
      claims.changed();
      final next = claimOnIt(claims, vblank + 1000 + period);
      expect(
        indexOf(next.shownAtMicros),
        indexOf(first.shownAtMicros) + 1,
      );
    });

    test('🚨what a look is worth of a refresh is what is kept: 120Hz under '
        '143.9 has no lead and one vblank of reserve', () {
      const fast = 8333.0;
      final claims = PresentClaims();
      int claimed() {
        final claim = claimOnIt(claims, vblank + 1000, screen: fast);
        return ((claim.shownAtMicros - vblank) / fast).round();
      }

      final first = claimed();
      expect(claimed(), first + 1);
      expect(claimed(), first + 1, reason: 'reserve spent: the same again');
    });
  });
}
