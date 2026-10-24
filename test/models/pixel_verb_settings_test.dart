import 'package:anicel/src/models/pixel_verb_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/json_round_trip.dart';

/// 🗣️I-13-Q2 (유저 2026-10-16): 「기억한다(앱 설정에 저장)」 — what the colour
/// edit list's knobs hold comes back from its file as it went in, and a
/// file that cannot say it comes back as the defaults.
void main() {
  test('what was saved reads back as it was saved', () {
    expectJsonRoundTrip(
      const PixelVerbSettings(
        binarizeThreshold: 179,
        deleteColourTolerance: 4,
        keepColourTolerance: 9,
      ),
      PixelVerbSettings.fromJson,
    );
  });

  test('every byte a knob reaches reads back — the ends included', () {
    for (final settings in const [
      PixelVerbSettings(
        binarizeThreshold: PixelVerbSettings.lowestBinarizeThreshold,
      ),
      PixelVerbSettings(
        binarizeThreshold: 255,
        deleteColourTolerance: 255,
        keepColourTolerance: 255,
      ),
    ]) {
      expect(PixelVerbSettings.fromJson(settings.toJson()), settings);
    }
  });

  test('a field missing or out of reach reads as its default — ⛔a cut of 0 '
      'included, which would turn the paper into drawing', () {
    expect(
      PixelVerbSettings.fromJson({
        'binarizeThreshold': 0,
        'deleteColourTolerance': 256,
        'keepColourTolerance': '9',
      }),
      const PixelVerbSettings(),
    );
    expect(
      PixelVerbSettings.fromJson({'binarizeThreshold': 256}),
      const PixelVerbSettings(),
    );
    expect(PixelVerbSettings.fromJson({}), const PixelVerbSettings());
  });

  test('the defaults are the list as it was before it had knobs: half for '
      'the cut, the colour itself for each reach', () {
    const defaults = PixelVerbSettings();
    expect(defaults.binarizeThreshold, 128);
    expect(defaults.deleteColourTolerance, 0);
    expect(defaults.keepColourTolerance, 0);
  });
}
