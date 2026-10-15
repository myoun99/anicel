import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/take_head.dart';

/// 🚨A take's head is what the microphone had taken in when its anchor was
/// HEARD (take-head-trims-at-the-playback-start).
void main() {
  test('read at the moment the anchor is heard, the head is what the '
      'microphone had taken in then', () {
    expect(
      samplesBeforeTheAnchor(
        heard: 96000,
        anchor: 96000,
        deviceRate: 48000,
        captured: 30000,
        captureRate: 48000,
      ),
      30000,
    );
  });

  test('read later, the time since the anchor was heard comes off what was '
      'taken in — in the microphone\'s own samples', () {
    // A tenth of a second after the anchor, on a 44.1k device; the
    // microphone takes in 48k.
    expect(
      samplesBeforeTheAnchor(
        heard: 4410 + 4410,
        anchor: 4410,
        deviceRate: 44100,
        captured: 30000,
        captureRate: 48000,
      ),
      30000 - 4800,
    );
  });

  test('an anchor heard before the microphone opened is a head below '
      'nothing — the silence that goes before the take', () {
    expect(
      samplesBeforeTheAnchor(
        heard: 48000 + 2400,
        anchor: 48000,
        deviceRate: 48000,
        captured: 1200,
        captureRate: 48000,
      ),
      -1200,
    );
  });
}
