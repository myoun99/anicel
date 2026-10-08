import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/dart_sources.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🚨EVERY TEST THAT WAITS OUT THE WAIT WINDOW ENDS BY STOPPING PLAYBACK'S
/// WARMER — see `pumpPastTheWaitWindow`.
///
/// The failure it closes is a flake, and that is why it is a scan: the
/// warmer starts on the REAL clock, so a body that forgot the stop passes on
/// a quiet machine and fails on a busy one (「A Timer is still pending even
/// after the widget tree was disposed」 — 2026-10-08: the PDF % test, 2 runs
/// in 8 on one master, 1 in 8 on another lane of it, every one at the
/// warmer's step between two pictures). Twenty-three tests waited out the
/// window that day, and not one of them stopped it.
void main() {
  /// Each `testWidgets(…)` under [dir] — `'test'` spelled out, for the
  /// affected-tests selector — that waits out the window, as 「file:line」,
  /// with whether its body stops the warmer.
  Map<String, bool> windowTestsUnder(String dir) => {
    for (final file in dartFilesUnder(dir))
      for (final (line, body) in _testWidgetsCalls(file.readAsStringSync()))
        if (body.contains('pumpPastTheWaitWindow(tester)'))
          '${file.path.replaceAll(r'\', '/')}:$line': body.contains(
            'prerenderScheduler.cancel()',
          ),
  };

  test('the scan: a test is its whole call, a skip after its body too', () {
    final folder = Directory.systemTemp.createTempSync('warmer-scan');
    deleteAfterSessionEnds(folder);
    // ⚠️Spelled with a stand-in: this file is under `test` too, and a
    // fixture written out as calls would be read as three tests of its own.
    File('${folder.path}/a_test.dart').writeAsStringSync('''
void main() {
  TW('stops', (tester) async {
    await pumpPastTheWaitWindow(tester);
    s.playbackRig.prerenderScheduler.cancel();
  });
  TW('forgets', (tester) async {
    await pumpPastTheWaitWindow(tester);
  }, skip: false);
  TW('never waits', (tester) async {});
}
'''.replaceAll('TW(', 'testWidgets('));

    expect(windowTestsUnder(folder.path).values.toList(), [true, false]);
  });

  test('⛔premise: the scan finds the family', () {
    expect(windowTestsUnder('test'), hasLength(greaterThanOrEqualTo(23)));
  });

  test('🚨and every one of them stops the warmer', () {
    expect(
      [
        for (final MapEntry(:key, :value) in windowTestsUnder('test').entries)
          if (!value) key,
      ],
      isEmpty,
      reason: 'end the body with session.playbackRig.prerenderScheduler'
          '.cancel() — see pumpPastTheWaitWindow',
    );
  });
}

/// Every `testWidgets(…)` call in [text]: the line it starts on and its
/// whole text, the arguments after the body included.
Iterable<(int, String)> _testWidgetsCalls(String text) sync* {
  var from = 0;
  while (true) {
    final at = text.indexOf('testWidgets(', from);
    if (at < 0) return;
    from = at + 1;
    var depth = 0;
    for (var i = at + 'testWidgets'.length; i < text.length; i++) {
      final c = text[i];
      if (c == '(') depth++;
      if (c == ')' && --depth == 0) {
        final line = '\n'.allMatches(text.substring(0, at)).length + 1;
        yield (line, text.substring(at, i + 1));
        break;
      }
    }
  }
}
