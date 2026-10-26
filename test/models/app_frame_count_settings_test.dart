import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_frame_count_settings.dart';
import 'package:anicel/src/models/frame.dart' show InbetweenMark;

/// 🗣️F-469 (유저 2026-10-25): 「이름없는 프레임의 기본마크, 앞으로 마크1
/// 사용 … 다른곳도 같은곳있으면 확인해서 법 통일」 — the mark-every window
/// opens on mark 1, the ○, until one is picked, and a store that holds no
/// pick reads as that same mark.
void main() {
  test('a store with no mark in it opens on mark 1; one with a pick keeps '
      'it', () {
    expect(
      AppFrameCountSettings.fromJson(const {}).lastEveryMark,
      InbetweenMark.one,
    );
    expect(
      AppFrameCountSettings.fromJson(const {
        'lastEveryMark': 'two',
      }).lastEveryMark,
      InbetweenMark.two,
    );
  });
}
