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

  test('the PRODUCT default dedicates touch to the timeline scroll', () {
    // The class default is the shipped default (UI-R22F #1) — the test
    // corpus runs under OFF only because flutter_test_config pins it.
    expect(const AppInputSettings().touchTimelineScroll, isTrue);
    expect(AppInputSettings.fromJson(const {}).touchTimelineScroll, isTrue);
  });

  test('the edit device set releases touch exactly when the timeline '
      'scroll owns it', () {
    // Corpus baseline OFF: touch EDITS like the pen (the R17-⑥
    // contract — the misreported-pen safety net).
    expect(AppInput.touchTimelineScroll, isFalse);
    expect(AppInput.timelineEditPanDevices, contains(PointerDeviceKind.touch));

    // ON (the product default): the edit gestures ignore touch — finger
    // pans reach the scroll viewports uncontested.
    AppInput.settings.value = const AppInputSettings(touchTimelineScroll: true);
    expect(
      AppInput.timelineEditPanDevices,
      isNot(contains(PointerDeviceKind.touch)),
    );
    // The pen never leaves the edit set either way.
    expect(AppInput.timelineEditPanDevices, contains(PointerDeviceKind.stylus));
  });

  test('json + store round-trips', () async {
    const settings = AppInputSettings(touchTimelineScroll: false);
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
}
