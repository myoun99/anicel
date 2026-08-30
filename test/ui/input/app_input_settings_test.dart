import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_input_settings_store.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';

/// UI-R22 #6 / UI-R22F #1: ONE owner decides what a touch contact means
/// on the timeline — scroll (the PRODUCT default) or edit (the R17-⑥
/// pen-as-touch contract, the corpus baseline via flutter_test_config).
void main() {
  tearDown(() {
    // Back to the CORPUS baseline (OFF), not the product default.
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  test('the edit device set releases touch exactly when the finger is NOT '
      'the pointer', () {
    // 🚨ONE SWITCH now (유저 2026-08-29): `touchTimelineScroll` is gone and
    // 1핑거 드로잉 answers for it. The corpus baseline draws with one
    // finger, so touch EDITS.
    expect(AppInput.touchDraws, isTrue);
    expect(AppInput.timelineEditPanDevices, contains(PointerDeviceKind.touch));

    // Drawing off: the edit gestures ignore touch — finger pans reach the
    // scroll viewports uncontested.
    AppInput.settings.value = const AppInputSettings(
      touchDragOneFinger: CanvasTouchDragAction.flip,
    );
    expect(
      AppInput.timelineEditPanDevices,
      isNot(contains(PointerDeviceKind.touch)),
    );
    // The pen never leaves the edit set either way.
    expect(AppInput.timelineEditPanDevices, contains(PointerDeviceKind.stylus));
  });

  test('json + store round-trips', () async {
    const settings = AppInputSettings(
      touchDragOneFinger: CanvasTouchDragAction.flip,
    );
    expect(AppInputSettings.fromJson(settings.toJson()), settings);

    final dir = await Directory.systemTemp.createTemp('input');
    addTearDown(() => dir.delete(recursive: true));
    final store = AppInputSettingsStore(
      filePath: '${dir.path}/input_settings.json',
    );
    expect(await store.load(), isNull);
    await store.save(settings);
    expect(await store.load(), settings);
  });

  test('PEN-15: stored snap lists matching a LEGACY default upgrade to the '
      'current default; customized lists persist', () {
    final legacy = AppInputSettings.fromJson(const {
      'zoomSnapPercents': [50, 75, 100, 125, 150, 200, 300, 400],
      'brushSizeSnaps': [2, 4, 8, 16, 32, 64],
    });
    expect(
      legacy.zoomSnapPercents,
      AppInputSettings.defaultZoomSnapPercents,
      reason: 'the expanded default (10/25 added) reaches old files',
    );
    expect(
      legacy.brushSizeSnaps,
      AppInputSettings.defaultBrushSizeSnaps,
      reason: 'the extended ladder (128/256/512) reaches old files',
    );

    final custom = AppInputSettings.fromJson(const {
      'zoomSnapPercents': [33, 66, 99],
      'brushSizeSnaps': [5, 10, 20],
    });
    expect(custom.zoomSnapPercents, [33, 66, 99]);
    expect(custom.brushSizeSnaps, [5, 10, 20]);
  });

  test('PEN-15: the default zoom list reaches below 50% (the "snaps to 50" '
      'report) and the brush ladder past 64', () {
    expect(AppInputSettings.defaultZoomSnapPercents, contains(10));
    expect(AppInputSettings.defaultZoomSnapPercents, contains(25));
    expect(AppInputSettings.defaultBrushSizeSnaps, containsAll([128, 256]));
  });

  test('🚨every field is in == and in the round trip — a missing one is a '
      'setting that cannot be changed', () {
    // ⛔THIS IS NOT PEDANTRY, it is the bug I shipped and caught in a test
    // fixture (I-10, 2026-08-31). `autoCreateFrameOnDraw` went into the
    // class, `copyWith`, `toJson` and `fromJson` — and not into `==`.
    //
    // `ValueNotifier.value =` RETURNS EARLY when the new value equals the
    // old one, so `AppInput.settings.value = old.copyWith(flag: true)` did
    // nothing at all: the toggle would have looked wired and moved nothing.
    // ⚠️Nothing in the app would have failed, and no widget test would have
    // caught it either — the switch reads the notifier it just failed to
    // write.
    //
    // ★So every bool field is flipped one at a time and the pair must
    // disagree. Adding a field without adding it to `==` fails HERE.
    const base = AppInputSettings();
    final flipped = <String, AppInputSettings>{
      'extraFingerModifier': base.copyWith(
        extraFingerModifier: !base.extraFingerModifier,
      ),
      'flipHaptics': base.copyWith(flipHaptics: !base.flipHaptics),
      'autoCreateFrameOnDraw': base.copyWith(
        autoCreateFrameOnDraw: !base.autoCreateFrameOnDraw,
      ),
      'navigationRotationEnabled': base.copyWith(
        navigationRotationEnabled: !base.navigationRotationEnabled,
      ),
      'navigationModifierRotationLock': base.copyWith(
        navigationModifierRotationLock: !base.navigationModifierRotationLock,
      ),
    };
    flipped.forEach((field, other) {
      expect(
        other == base,
        isFalse,
        reason:
            '$field is missing from `==` — a settings write with only '
            'this field changed would be silently dropped',
      );
      expect(
        AppInputSettings.fromJson(other.toJson()) == other,
        isTrue,
        reason: '$field does not survive the round trip',
      );
    });
  });
}
