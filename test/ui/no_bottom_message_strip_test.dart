import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F-10 — **no bottom-of-window message strip.**
///
/// 유저 2026-08-24: 「se레이어가 아닌곳에서 녹음버튼누르면 앱 최하단에 메시지
/// 뜨는데 이 메시지 ui 싹 삭제. 다른곳에서 쓰고있으면 그거도 삭제하고 이런
/// 경고문은 공통ui창 띄우는거 사용해서 띄우도록.」
///
/// The strip was Material's `SnackBar` — the one piece of chrome in this app
/// that nothing else looks like. It lands at the far edge of a 1400px window,
/// nowhere near what the user pressed, and it leaves on a timer whether or not
/// it was read. Thirteen call sites had grown one.
///
/// ⇒ `showAppNotice` (the shared window) is the channel now. `cursorNotices`
/// remains a separate and deliberate thing: it answers "why did nothing
/// happen" AT THE POINTER for refusals that happen constantly.
void main() {
  test('nothing in lib/src reaches for a SnackBar', () {
    final offenders = <String>[];

    for (final entry in Directory('lib/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))) {
      final relative = entry.path.replaceAll(r'\', '/');
      final key = relative.substring(relative.indexOf('lib/src'));
      final lines = entry.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) {
          continue;
        }
        if (line.contains('SnackBar(') || line.contains('showSnackBar')) {
          offenders.add('$key:${i + 1}  ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'use showAppNotice (the shared window) for something worth '
          'stopping for, or cursorNotices for a refusal at the pointer. A '
          'strip at the bottom edge is neither',
    );
  });
}
