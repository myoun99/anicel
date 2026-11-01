import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_frame_count_settings.dart';
import 'package:anicel/src/models/frame.dart' show InbetweenMark;

/// 🗣️F-489-Q1 (유저 2026-10-27 「둘 다 따라간다」) — the mark-every window
/// opens on the unnamed drawing's mark until one is picked, so a store that
/// holds no pick holds no mark at all: the window asks the unnamed
/// drawing's then. ↩️It held mark 1, the ○, in its place (F-469).
void main() {
  test('a store with no mark in it holds none; one with a pick keeps it', () {
    expect(AppFrameCountSettings.fromJson(const {}).lastEveryMark, isNull);
    expect(
      AppFrameCountSettings.fromJson(const {
        'lastEveryMark': 'two',
      }).lastEveryMark,
      InbetweenMark.two,
    );
  });

  test('nothing picked writes no mark, and a pick writes itself', () {
    expect(
      const AppFrameCountSettings().toJson(),
      isNot(contains('lastEveryMark')),
    );
    for (final mark in InbetweenMark.values) {
      final settings = AppFrameCountSettings(lastEveryMark: mark);
      expect(
        AppFrameCountSettings.fromJson(settings.toJson()),
        settings,
        reason: mark.name,
      );
    }
  });

  test('🗣️F-518: a store with no count holds 3; an applied one keeps itself '
      'across a restart', () {
    expect(AppFrameCountSettings.fromJson(const {}).lastEveryCount, 3);
    const applied = AppFrameCountSettings(lastEveryCount: 5);
    expect(AppFrameCountSettings.fromJson(applied.toJson()), applied);
    expect(applied, isNot(const AppFrameCountSettings()));
    expect(applied.copyWith().lastEveryCount, 5);
  });
}
