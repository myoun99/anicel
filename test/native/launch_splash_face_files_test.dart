import 'package:anicel/src/native/launch_splash.dart';
import 'package:flutter_test/flutter_test.dart';

// The splash's stage line speaks in the app's face, handed to the runner
// as files (lib/src/native/launch_splash.dart says why).
void main() {
  const manifest = '''
[
  {"family": "Nanum Gothic", "fonts": [
    {"asset": "assets/fonts/NanumGothic-Regular.ttf"},
    {"asset": "assets/fonts/NanumGothic-Bold.ttf", "weight": 700}]},
  {"family": "BIZ UDPGothic", "fonts": [
    {"asset": "assets/fonts/BIZUDPGothic-Bold.ttf", "weight": 700},
    {"asset": "assets/fonts/BIZUDPGothic-Regular.ttf"}]}
]''';

  test('each family gives its regular file, in the order the face asks', () {
    expect(LaunchSplash.faceFiles(['BIZ UDPGothic', 'Nanum Gothic'], manifest), [
      'assets/fonts/BIZUDPGothic-Regular.ttf',
      'assets/fonts/NanumGothic-Regular.ttf',
    ]);
  });

  test('no families — the OS face — gives no files', () {
    expect(LaunchSplash.faceFiles([], manifest), isEmpty);
  });

  test('a family the manifest lacks gives nothing for it', () {
    expect(LaunchSplash.faceFiles(['Missing', 'Nanum Gothic'], manifest), [
      'assets/fonts/NanumGothic-Regular.ttf',
    ]);
  });
}
