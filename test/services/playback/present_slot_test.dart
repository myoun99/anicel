import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/present_slot.dart';

/// WHICH VBLANK EACH LOOK OF A CLOCK FILLS (유저 2026-10-11: 「144hz든
/// 몇이든 확실하게 근본/구조적으로 해결하도록」): one look, one real vblank,
/// one after another — whatever the engine's own vsync grid does — and a
/// hand-off window that lands a raster of the measured spread on it.
void main() {
  const vblank = 5000000;
  const period = 6948.6; // a 143.9Hz screen, as DWM says it
  const budget = 3000;
  const low = 3500, high = 7500;

  int vblankIndexOf(num micros) => ((micros - vblank) / period).round();

  /// A claim for a look made at [now].
  PresentClaim claimAt(PresentClaims claims, num now) => claims.claim(
    nowMicros: now.round(),
    vblankMicros: vblank,
    periodMicros: period,
    budgetMicros: budget,
    rasterLowMicros: low,
    rasterHighMicros: high,
  );

  /// The vblank a claim's picture is shown on.
  int shownOn(PresentClaim claim) => vblankIndexOf(claim.shownAtMicros);

  test('🚨a raster of the spread handed over anywhere in the window ends '
      'between the latch\'s edges of the vblank before the one it is shown '
      'on', () {
    final claims = PresentClaims();
    final claim = claimAt(claims, vblank + 300 * period + 1234);
    final before =
        claim.shownAtMicros - presentShownAfterVblanks * period;
    for (final handOff in [claim.handOffFromMicros, claim.handOffByMicros]) {
      expect(handOff + low - before, greaterThanOrEqualTo(presentLatchEarlyMicros - 1));
      expect(
        before + period - (handOff + high),
        greaterThanOrEqualTo(presentLatchLateMicros - 1),
      );
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
    final at = vblank + 3000 * period + 100;
    final first = shownOn(claimAt(claims, at));
    final late = shownOn(claimAt(claims, at + period + 0.9 * period));
    expect(late, first + 1);
  });

  test('🚨the look after a change takes the lead back — passing over one '
      'vblank, the one right after the change, and no more', () {
    final claims = PresentClaims();
    final at = vblank + 4000 * period + 2500;
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

  test('a look that comes long after the last — a run started again — '
      'starts the chain afresh, with its lead', () {
    final claims = PresentClaims();
    claimAt(claims, vblank + 5000 * period);
    final fresh = PresentClaims();
    final later = vblank + 6000 * period + 1000;
    expect(
      shownOn(claimAt(claims, later)),
      shownOn(claimAt(fresh, later)),
    );
  });

  test('a look that comes early claims the last vblank again, never one '
      'more than the reserve past what it can make', () {
    final claims = PresentClaims();
    final at = vblank + 7000 * period + 3000;
    final first = shownOn(claimAt(claims, at));
    // Two looks within the same refresh: the second claims the same.
    final again = shownOn(claimAt(claims, at + 10));
    expect(again - first, lessThanOrEqualTo(1));
    final more = shownOn(claimAt(claims, at + 20));
    expect(more, again, reason: 'the reserve stops the chain running ahead');
  });

  test('a spread wider than the latch leaves is handed over at the window\'s '
      'middle — the best a hand-off can do', () {
    final claims = PresentClaims();
    final claim = claims.claim(
      nowMicros: (vblank + 100 * period).round(),
      vblankMicros: vblank,
      periodMicros: period,
      budgetMicros: budget,
      rasterLowMicros: 1000,
      rasterHighMicros: 9000,
    );
    expect(claim.handOffFromMicros, claim.handOffByMicros);
    final before = claim.shownAtMicros - presentShownAfterVblanks * period;
    final middle = claim.handOffFromMicros + (1000 + 9000) / 2;
    final windowMiddle =
        (before + presentLatchEarlyMicros + before + period -
            presentLatchLateMicros) /
        2;
    expect((middle - windowMiddle).abs(), lessThanOrEqualTo(1));
  });

  group('the raster\'s spread', () {
    test('reads what the latch was measured with until eight frames have '
        'said', () {
      final spread = RasterSpread();
      for (var i = 0; i < 7; i += 1) {
        spread.add(4000);
      }
      expect(spread.lowMicros, RasterSpread.unmeasuredLowMicros);
      expect(spread.highMicros, RasterSpread.unmeasuredHighMicros);
      spread.add(4000);
      expect(spread.lowMicros, 4000);
      expect(spread.highMicros, 4000);
    });

    test('🚨quantiles, not extremes: one raster an upload landed in does not '
        'move the window', () {
      final spread = RasterSpread();
      for (var i = 0; i < 60; i += 1) {
        spread.add(3500 + (i % 10) * 200);
      }
      spread.add(13000);
      expect(spread.highMicros, lessThanOrEqualTo(5300));
      expect(spread.lowMicros, greaterThanOrEqualTo(3500));
    });

    test('follows the last frames only — an old spread is forgotten', () {
      final spread = RasterSpread(capacity: 16);
      for (var i = 0; i < 16; i += 1) {
        spread.add(9000);
      }
      for (var i = 0; i < 16; i += 1) {
        spread.add(4000);
      }
      expect(spread.highMicros, 4000);
    });
  });
}
