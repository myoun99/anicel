import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/se_sound.dart';

/// An SE row's SOUND (I-140): its keyed volume and its one pan — what the
/// row plays, one reading for the lane, the graph and the mix.
void main() {
  test('an unkeyed sound plays as recorded, centred', () {
    const sound = SeSound();
    expect(sound.volumeAt(0), 1.0);
    expect(sound.volumeAt(37.5), 1.0);
    expect(sound.pan, 0.0);
    expect(sound.isKeyed, isFalse);
  });

  test('a keyed volume is read between its keys, and held inside 0–200 %', () {
    final ramp = SeSound(
      volume: PropertyTrack<double>(
        keys: {0: const PropertyKey(0.0), 10: const PropertyKey(1.0)},
      ),
    );
    expect(ramp.isKeyed, isTrue);
    expect(ramp.volumeAt(5), closeTo(0.5, 1e-9));
    expect(ramp.volumeAt(2.5), closeTo(0.25, 1e-9), reason: 'between frames');
    expect(ramp.volumeAt(40), 1.0, reason: 'held past the last key');

    final loud = SeSound(
      volume: PropertyTrack<double>(keys: {0: const PropertyKey(3.0)}),
    );
    expect(loud.volumeAt(0), SeSound.maxVolume);
    final under = SeSound(
      volume: PropertyTrack<double>(keys: {0: const PropertyKey(-1.0)}),
    );
    expect(under.volumeAt(0), 0.0);
  });

  test('it round-trips through JSON, and a default sound writes nothing', () {
    final shaped = SeSound(
      pan: -0.25,
      volume: PropertyTrack<double>(
        keys: {
          2: const PropertyKey(0.5, name: 'N'),
          9: const PropertyKey(1.5),
        },
      ),
    );
    expect(SeSound.fromJson(shaped.toJson()), shaped);

    expect(const SeSound().toJson(), isEmpty);
    expect(const SeSound(pan: 0.5).toJson().keys, ['pan']);
    expect(SeSound.fromJson(const {}), const SeSound());
  });

  // 🗣️I-145-Q1 (유저 2026-10-30): 「따로 한 값 — 두 입구」.
  test('the total is one value over the keys — 100 % unless set, written '
      'only when set, and read back inside 0–200 %', () {
    expect(const SeSound().totalVolume, 1.0);
    const quiet = SeSound(totalVolume: 0.4);
    expect(quiet.toJson(), {'totalVolume': 0.4});
    expect(SeSound.fromJson(quiet.toJson()), quiet);
    expect(quiet, isNot(const SeSound()));
    expect(
      const SeSound().copyWith(pan: 0.5).copyWith(totalVolume: 0.4),
      const SeSound(pan: 0.5, totalVolume: 0.4),
      reason: 'copyWith keeps what it was not given',
    );
    expect(SeSound.fromJson(const {'totalVolume': 5}).totalVolume, 2.0);
    expect(SeSound.fromJson(const {'totalVolume': -1}).totalVolume, 0.0);
  });

  test('an empty volume is no volume — one sound, however it was made', () {
    expect(SeSound(volume: PropertyTrack<double>.empty()), const SeSound());
    expect(
      const SeSound().copyWith(pan: 0.5),
      const SeSound(pan: 0.5),
      reason: 'copyWith keeps what it was not given',
    );
    expect(const SeSound(pan: 0.5), isNot(const SeSound()));
  });
}
