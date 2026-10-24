import 'dart:io' show Platform;

/// Whether this process is a `flutter test` run.
///
/// 🚨THE ONE PLACE THE APP READS IT (board
/// `capture-spells-out-its-own-test-gate`, 2026-10-23). Fifteen places in
/// lib read `FLUTTER_TEST` for themselves — the audio device's three on the
/// microphone side beside its own gate among them. Each asks a question of
/// its own (may this reach the real speakers, the user's files, the
/// keyboard's hardware, a decoder?), and each still answers it where it
/// stands; the fact they ask it of is read here.
/// `one_test_run_flag_test` holds the line.
bool get underFlutterTest => Platform.environment['FLUTTER_TEST'] == 'true';
