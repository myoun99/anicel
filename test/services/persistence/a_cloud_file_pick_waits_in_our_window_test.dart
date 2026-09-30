import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🗣️유저 2026-09-27: 「프로젝트파일을 열땐 우리 창으로 클라우드에서
/// 다운중이라고 표시 … 그쪽으로 통합하고싶어」 — a cloud file's download is
/// the APP's wait, said in its own window, not a spinner in the system's
/// panel.
///
/// The half that decides it on macOS is native, and nothing on this
/// workstation can run it, so this reads what the runner sets: NSOpenPanel
/// downloads a file that is not local BEFORE it lets go, unless it is told
/// the app will (`canDownloadUbiquitousContents`, true by default). iOS has
/// no such switch — its picker asks the provider itself — which the iOS
/// runner says beside its own `pickFiles`.
void main() {
  test('the macOS file panel lets a cloud file go as it stands — the app '
      'waits for it', () {
    final runner = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();
    final start = runner.indexOf('func pickFiles(');
    final end = runner.indexOf('func exportFile(', start);
    expect(start, isNot(-1), reason: 'the runner still has its pickFiles');
    expect(end, greaterThan(start), reason: 'and the function after it');

    expect(
      runner.substring(start, end),
      contains('panel.canDownloadUbiquitousContents = false'),
    );
  });
}
