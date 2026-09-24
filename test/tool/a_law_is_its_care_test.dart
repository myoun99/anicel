import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_say.dart';

/// 🚨A LAW IS ITS `care` (law-notes-are-invisible, 실측 2026-09-17).
///
/// 「작업전 확인」 draws a law card's LAST `care` line and no other field. So
/// a law written as a `note` reached no screen at all — timeline 8 lines,
/// panel 7, structure 5, media 3 and rendering 1 were found buried that way
/// — and a `care` that carried only the newest law wiped every law before it
/// off the card (rendering and brush, 09-16·17, rebuilt by hand).
void main() {
  const law = 'law-패널';

  test('a law written as a note is refused, and told where a law goes', () {
    final why = recordRefusal(
      {'kind': 'law', 'id': law, 'tag': '패널', 'note': '새 법'},
      1,
    );
    expect(why, contains('care'));
    expect(
      recordRefusal({'kind': 'law', 'id': law, 'tag': '패널', 'care': '새 법'}, 1),
      isNull,
      reason: 'the same law as its care is the way in',
    );
    expect(
      recordRefusal({'kind': 'item', 'id': 'W', 'note': '할 것'}, 1),
      isNull,
      reason: 'a WORK card\'s note is its story — only a law\'s is buried',
    );
  });

  test('a care shorter than the one it replaces is written — and said, with '
      'how much went', () {
    const before = '옛 법 하나 · 옛 법 둘 · 새 법';
    const after = '새 법';
    final r = boardSayAppend(
      ['{"kind":"law","id":"$law","tag":"패널","care":"$after"}'],
      DateTime(2026, 9, 24),
      lawCare: {law: before},
    );
    expect(r.refusal, isNull, reason: 'a law can be retired: not a refusal');
    expect(r.bytes, isNotNull);
    expect(r.warnings, hasLength(1));
    expect(r.warnings.single, contains(law));
    expect(
      r.warnings.single,
      contains('${before.length}자 → ${after.length}자'),
    );
  });

  test('a care that keeps what was there says nothing', () {
    final r = boardSayAppend(
      ['{"kind":"law","id":"$law","tag":"패널","care":"옛 법 · 새 법"}'],
      DateTime(2026, 9, 24),
      lawCare: {law: '옛 법'},
    );
    expect(r.warnings, isEmpty);
  });

  test('a batch that writes one law twice is measured against its own last '
      'line', () {
    final r = boardSayAppend(
      [
        '{"kind":"law","id":"$law","tag":"패널","care":"옛 법 · 새 법 · 또"}',
        '{"kind":"law","id":"$law","tag":"패널","care":"옛 법 · 새 법"}',
      ],
      DateTime(2026, 9, 24),
      lawCare: {law: '옛 법'},
    );
    expect(r.warnings, hasLength(1));
    expect(r.warnings.single, startsWith('2번째 줄'));
  });
}
