import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_input_settings_store.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import '../helpers/project_scratch_folder.dart';
import '../helpers/temp_dir.dart';

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
    deleteAfterSessionEnds(dir);
    final store = AppInputSettingsStore(
      filePath: '${dir.path}/input_settings.json',
    );
    expect(await store.load(), isNull);
    await store.save(settings);
    expect(await store.load(), settings);
  });

  // 🗣️I-15 follow-up (유저 2026-09-11): 「휠클릭은 왜 남아있는거지? 잔재
  // 삭제해주고」 — the wheel's old default PAN leaves the files that kept it.
  group("the wheel click's old default pan", () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('wheel-remnant');
    });
    tearDown(() => deleteTempQuietly(dir));

    AppInputSettingsStore store() =>
        AppInputSettingsStore(filePath: '${dir.path}/input_settings.json');

    Future<AppInputSettings?> loadVersionOne(CanvasPointerAction wheel) {
      File(store().filePath).writeAsStringSync(
        jsonEncode({
          'version': 1,
          ...AppInputSettings(
            canvasWheelClick: CanvasPointerMapping(action: wheel),
          ).toJson(),
        }),
      );
      return store().load();
    }

    test('leaves a version-1 file: it is the default sitting there', () async {
      final loaded = await loadVersionOne(CanvasPointerAction.pan);
      expect(loaded!.canvasWheelClick.action, CanvasPointerAction.none);
    });

    test('keeps any other wheel mapping a version-1 file holds', () async {
      final loaded = await loadVersionOne(CanvasPointerAction.undo);
      expect(loaded!.canvasWheelClick.action, CanvasPointerAction.undo);
    });

    test('from version 2 a file keeps what is mapped, the pan too', () async {
      await store().save(
        const AppInputSettings(
          canvasWheelClick: CanvasPointerMapping(
            action: CanvasPointerAction.pan,
          ),
        ),
      );
      final loaded = await store().load();
      expect(loaded!.canvasWheelClick.action, CanvasPointerAction.pan);
    });
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

  group('🗣️I-19: the zoom step walks the snap list 「설정에 줌 스냅 설정한대로」',
      () {
    const list = AppInputSettings.defaultZoomSnapPercents;
    double? step(double value, {required bool up}) =>
        AppInput.stepThroughList(value, list, up: up);

    test('from an entry it moves to the NEXT one, either way', () {
      expect(step(100, up: true), 125);
      expect(step(100, up: false), 75);
    });

    test('between entries it moves to the nearest one that way', () {
      expect(step(110, up: true), 125);
      expect(step(110, up: false), 100);
      expect(step(37, up: true), 50);
      expect(step(37, up: false), 25);
    });

    test('a value that came back through the unit conversions is still ON '
        'its entry', () {
      expect(step(100.0000001, up: true), 125);
      expect(step(99.9999999, up: false), 75);
    });

    test('past either end there is no step', () {
      expect(step(400, up: true), isNull);
      expect(step(10, up: false), isNull);
      expect(step(1600, up: false), 400);
      expect(AppInput.stepThroughList(100, const [], up: true), isNull);
    });

    test('the list is read as a set of rungs, not in its stored order', () {
      expect(
        AppInput.stepThroughList(100, const [300, 50, 150, 75], up: true),
        150,
      );
    });
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
