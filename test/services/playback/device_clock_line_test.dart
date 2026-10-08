import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/device_clock_line.dart';

/// 유저 2026-10-08: 「늦게바뀌는건 좀 많이 신경쓰이는데. 근본/구조적으로
/// 어떻게 안되나」 → 「소리 싱크나 영상이나 뭐 그런거 정확하기만하면되.」
///
/// The device's count is a stair — one step an audio callback. The line
/// through it is what the picture reads, and these are the four things it
/// holds to.
void main() {
  // 48 kHz: a 10ms callback hands 480 samples, and the device carries 30ms
  // of them (three periods) — the shape of the output this runs on.
  const rate = 48000;
  const step = 480;
  const carries = 1440;
  const second = Duration.microsecondsPerSecond;
  const t = 5 * second;

  int ms(num milliseconds) => (milliseconds * 1000).round();

  ({int positionSamples, int atMicros}) point(int samples, int at) =>
      (positionSamples: samples, atMicros: at);

  group('a device that plays to its end', () {
    late DeviceClockLine line;
    setUp(
      () => line = DeviceClockLine()
        ..arm(deviceRate: rate, carriesFor: carries),
    );

    int read({
      required int stair,
      ({int positionSamples, int atMicros})? at,
      required int now,
    }) => line.read((point: at, stairSamples: stair, nowMicros: now));

    test('before any callback has spoken the count is the stair, and it '
        'stands', () {
      expect(read(stair: 240, now: t), 240);
      expect(read(stair: 240, now: t + ms(50)), 240);
    });

    test('🚨at a callback the line is at the stair, and between two it runs '
        'on at the rate the device plays — where the stair stands still', () {
      expect(read(stair: step, at: point(step, t), now: t), step);

      expect(
        read(stair: step, at: point(step, t), now: t + ms(5)),
        step + 240,
        reason: '5ms at 48k is 240 samples',
      );

      expect(
        read(stair: step, at: point(step, t), now: t + ms(10)),
        2 * step,
        reason: 'by the next callback it is where the stair will step to',
      );
    });

    test('🚨never behind the stair: a stair that has stepped past its point '
        'is believed', () {
      // The callback under way has stored its block; its point is not
      // written until it returns.
      expect(
        read(stair: 2 * step, at: point(step, t), now: t + ms(1)),
        2 * step,
      );
    });

    test('🚨never ahead of the sound: it runs on only as far as the device '
        'carries, and then stands', () {
      expect(
        read(stair: step, at: point(step, t), now: t + ms(20)),
        step + 960,
      );

      // No callback for 100ms: the buffer ran dry 30ms in.
      expect(
        read(stair: step, at: point(step, t), now: t + ms(100)),
        step + carries,
      );
      expect(
        read(stair: step, at: point(step, t), now: t + ms(900)),
        step + carries,
        reason: 'and there it stands',
      );
    });

    // 🔬The null device asks 7 to 14ms apart where 10 is due (2026-10-08).
    test('🚨a callback asked for late does not pull the line down: the '
        'device went on playing while it was late', () {
      expect(
        read(stair: step, at: point(step, t), now: t + ms(11.5)),
        step + 552,
      );

      // The next callback, 2ms late: its own point lies under the line.
      final late = point(2 * step, t + ms(12));
      expect(
        read(stair: 2 * step, at: late, now: t + ms(12)),
        step + 576,
        reason: 'where the device has got to in 12ms — not back to the '
            'stair\'s 960, and not held at 1032 either',
      );
      expect(
        read(stair: 2 * step, at: late, now: t + ms(14)),
        step + 672,
      );

      // The one after comes on time, and lies on the same line.
      final onTime = point(3 * step, t + ms(20));
      expect(
        read(stair: 3 * step, at: onTime, now: t + ms(20)),
        3 * step,
      );
    });

    test('🚨never a step back: when the point the line rested on grows old, '
        'the line is the highest that is left — and the count waits for it '
        'rather than dip', () {
      // One callback on time, and then every one of them 2ms late: their
      // points lie on a line 96 samples under the first.
      read(stair: step, at: point(step, t), now: t);
      ({int positionSamples, int atMicros}) late(int k) =>
          point(step + k * step, t + ms(10 * k + 2));
      for (var k = 1; k <= 49; k += 1) {
        final each = late(k);
        read(stair: each.positionSamples, at: each, now: each.atMicros);
      }

      // Still on the first point's line, half a second on.
      final onTheOldLine = read(
        stair: late(49).positionSamples,
        at: late(49),
        now: t + ms(501.9),
      );
      expect(onTheOldLine, step + 24091);

      // The fiftieth is 502ms after the first: the first is forgotten.
      final dropped = read(
        stair: late(50).positionSamples,
        at: late(50),
        now: late(50).atMicros,
      );
      expect(
        dropped,
        step + 24091,
        reason: 'the lower line says 24480 here; the count does not go back',
      );
      expect(
        read(
          stair: late(50).positionSamples,
          at: late(50),
          now: t + ms(504.1),
        ),
        step + 50 * step + 100,
        reason: 'on along the lower line once it has passed the mark',
      );
    });

    // The time is read after the point, so this does not happen — and
    // needs no guard of its own: the count is never behind its point.
    test('a point stamped after now runs on by nothing', () {
      expect(read(stair: step, at: point(step, t), now: t - ms(5)), step);
    });

    test('🚨a new arm is another run: the furthest count and the points of '
        'the run before it are forgotten', () {
      // A run far along, its line a callback old.
      read(stair: 96000, at: point(96000, t), now: t + ms(5));

      // Started afresh from the top, 20ms later.
      line.arm(deviceRate: rate, carriesFor: carries);
      expect(
        read(stair: 0, now: t + ms(20)),
        0,
        reason: 'the furthest count of the run before is not this one\'s',
      );
      expect(
        read(stair: step, at: point(step, t + ms(30)), now: t + ms(30)),
        step,
        reason: 'nor are its points: the old run\'s line stands 96000 '
            'samples over this one, and on it the count would run on by all '
            'the device carries at once',
      );
    });
  });

  group('a device that loops', () {
    // A loop of 100ms from the top: ten callbacks to the lap.
    const lap = 4800;
    late DeviceClockLine line;
    setUp(
      () => line = DeviceClockLine()
        ..arm(
          deviceRate: rate,
          carriesFor: carries,
          lapSamples: lap,
        ),
    );

    int read({
      required int stair,
      required ({int positionSamples, int atMicros})? at,
      required int now,
    }) => line.read((point: at, stairSamples: stair, nowMicros: now));

    test('🚨the device wraps its own count; this one counts on through the '
        'lap', () {
      // The callback that hands the lap's last block leaves the stair AT
      // the end; the next one wraps it and hands a block from the top.
      expect(read(stair: lap, at: point(lap, t), now: t), lap);
      expect(read(stair: lap, at: point(lap, t), now: t + ms(5)), lap + 240);
      expect(
        read(stair: step, at: point(step, t + ms(10)), now: t + ms(10)),
        lap + step,
      );
      expect(
        read(stair: step, at: point(step, t + ms(10)), now: t + ms(15)),
        lap + step + 240,
      );
    });

    test('a stair a callback under way has wrapped already is a lap further '
        'on than it reads', () {
      expect(read(stair: 240, at: point(lap, t), now: t + ms(1)), lap + 240);
    });

    test('a stair read just before its point adds nothing — it is not a lap '
        'ahead', () {
      expect(
        read(stair: step, at: point(2 * step, t), now: t + ms(1)),
        2 * step + 48,
      );
    });

    test('🚨a new arm of a looping run: the laps counted and the point '
        'last read are of the run before it', () {
      // Through one wrap, and on into the second lap.
      read(stair: lap, at: point(lap, t), now: t);
      read(stair: step, at: point(step, t + ms(10)), now: t + ms(10));
      read(stair: 5 * step, at: point(5 * step, t + ms(50)), now: t + ms(50));

      // Started afresh from the top — long enough after for the old run's
      // points to have grown old by themselves.
      line.arm(deviceRate: rate, carriesFor: carries, lapSamples: lap);
      expect(
        read(stair: step, at: point(step, t + ms(700)), now: t + ms(700)),
        step,
        reason: 'not a lap further on: no lap of THIS run has gone by, and '
            'a first point under the old run\'s last one is no wrap',
      );
    });

    test('a second lap is counted like the first', () {
      read(stair: lap, at: point(lap, t), now: t);
      read(stair: step, at: point(step, t + ms(10)), now: t + ms(10));
      read(stair: lap, at: point(lap, t + ms(100)), now: t + ms(100));
      expect(
        read(stair: step, at: point(step, t + ms(110)), now: t + ms(110)),
        2 * lap + step,
      );
    });
  });

  group('a place in the loop', () {
    const lap = 4800;
    int folded(int samples, {int lapSamples = lap}) =>
        (DeviceClockLine()..arm(
              deviceRate: rate,
              carriesFor: carries,
              lapSamples: lapSamples,
            ))
            .foldedIntoTheLap(samples);

    test('a count inside the first lap is where it is, a later one is where '
        'that lap has got to', () {
      expect(folded(0), 0);
      expect(folded(lap - 1), lap - 1);
      expect(folded(lap), 0);
      expect(folded(2 * lap + 240), 240);
    });

    test('a count not yet at the loop stays where it is — the sound of the '
        'arm has not been heard yet', () {
      expect(folded(-300), -300);
    });

    test('a device that does not loop has no lap to fold into', () {
      expect(folded(9000, lapSamples: 0), 9000);
    });

    // What is HEARD trails what is handed by the device's latency.
    test('🚨the latency comes off BEFORE the fold: when the lap\'s last '
        'sample has just been handed, what is heard is still the lap\'s '
        'tail — and its first sample is heard a latency later', () {
      const latency = carries;
      int heardAt(int count) => folded(count - latency);

      // ↩️Folded first, the count read 0 here and the picture went back to
      // its first frame 30ms before the lap had been heard out.
      expect(heardAt(lap), lap - latency);
      expect(
        heardAt(lap),
        greaterThan(lap - 2000),
        reason: 'inside the lap\'s last frame (a frame is 2000 samples at 24 '
            'a second)',
      );

      expect(heardAt(lap + latency), 0);
      expect(heardAt(lap + latency + 240), 240);
    });
  });
}
