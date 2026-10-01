import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_frame_grid_settings.dart';

/// 🗣️유저 2026-10-01: 「환경설정-화면-블록안 프레임 선을 기본값 off로」 — the
/// frame lines inside blocks are OFF by default, and a store that holds
/// nothing reads as that same default (↩️ON until then).
void main() {
  test('off by default', () {
    expect(const AppFrameGridSettings().blockFrameLines, isFalse);
  });

  test('a store with nothing in it is the default; one with a value keeps '
      'it', () {
    expect(
      AppFrameGridSettings.fromJson(const {}),
      const AppFrameGridSettings(),
    );
    expect(
      AppFrameGridSettings.fromJson(const {'blockFrameLines': true}),
      const AppFrameGridSettings(blockFrameLines: true),
    );
  });
}
