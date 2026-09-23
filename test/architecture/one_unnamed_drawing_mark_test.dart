import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨★★ONE ANSWER TO 「DOES THIS DRAWING HAVE A NAME」, AND ONE MARK FOR NO.
///
/// `celNumberOf` (beside `Frame.celNumber`) says whether a drawing has a cel
/// number, and `celNumberOrMark` what it prints when it has none. Until
/// C-save-percent (2026-09-15) seven places on screen spelled the mark
/// themselves after their own `frameName.isEmpty`, so a name of spaces
/// printed as spaces on the timeline and as the mark on the sheet — and a
/// save's notice listing lost drawings was about to be the eighth.
///
/// 🚨★★AND THE MARK IS ●, ONE GLYPH FOR BOTH IN-BETWEEN MARKS (F-149).
/// 유저 2026-09-16: 「프레임 이름 없는 기본 상태도 중간나누기 마크(속이 빈
/// 동그라미)고, 중간나누기 마크(속이 찬 동그라미)도 중간나누기 마크인건
/// 맞는데, 중간나누기 설정은 2개로 두고싶지만, 일단 이름 없는 기본상태를
/// 속이 찬 동그라미로 통일적용. 추후 두번째 중간나누기 마크(속이 빈)를
/// 활용할지도 모르겠지만 당장은 제거」.
///
/// So there are TWO names — what an unnamed drawing prints and the dot
/// inside a block — and ONE glyph behind both, spelled once in the home.
/// The hollow ○ is spelled nowhere. Splitting them again, the day 유저
/// wants the second mark back, is one line in the home.
///
/// ⛔SO THIS SCANS SOURCE: copies that agree today all pass a behaviour
/// test. The glyph spelled outside the home, or a
/// `frameName == null || frameName.isEmpty` anywhere, has started the next
/// copy.
void main() {
  const home = 'lib/src/models/frame.dart';
  const mark = '●';
  const retired = '○';

  /// The one other ● in lib, and why it is not the mark.
  const notTheMark = <String, String>{
    'lib/src/ui/panels/onion_skin_panel.dart':
        'the onion panel\'s CURRENT column — where you stand, not a drawing',
  };

  final blankNameCheck = RegExp(
    r'frameName\s*==\s*null\s*\|\|\s*frameName\.isEmpty',
  );

  /// The code on each line of [file] with its comment cut off — a comment
  /// may NAME the mark, and several explain it.
  Iterable<(int, String)> codeLines(File file) sync* {
    final lines = file.readAsLinesSync();
    for (var index = 0; index < lines.length; index += 1) {
      final comment = lines[index].indexOf('//');
      yield (
        index + 1,
        comment == -1 ? lines[index] : lines[index].substring(0, comment),
      );
    }
  }

  test('premise: the mark and the answer have their one home', () {
    final text = File(home).readAsStringSync();
    expect(text, contains('String? celNumberOf('));
    expect(
      text,
      contains('String? get celNumber => celNumberOf(name);'),
      reason:
          'the getter the sheet and the export read asks the same answer — '
          'a body of its own is the copy no behaviour test can see',
    );
    final spelled = [
      for (final (_, code) in codeLines(File(home)))
        if (code.contains(mark)) code,
    ];
    expect(
      spelled,
      hasLength(1),
      reason: 'the scan below assumes the one mark is spelled here, once',
    );
    expect(
      text,
      contains('const String unnamedDrawingMark = inbetweenMark;'),
      reason:
          '🚨유저: 「이름 없는 기본상태를 속이 찬 동그라미로 통일적용」 — the '
          'unnamed drawing prints the in-between mark itself, not a glyph '
          'of its own',
    );
  });

  test('nobody else spells the mark, nobody spells the retired one, and '
      'nobody asks whether a frame name is empty', () {
    final offenders = <String>[];
    var scanned = 0;
    for (final file in dartFilesUnder('lib')) {
      scanned += 1;
      final path = libPath(file);
      for (final (line, code) in codeLines(file)) {
        if (path != home &&
            !notTheMark.containsKey(path) &&
            code.contains(mark)) {
          offenders.add('$path:$line spells the mark');
        }
        if (code.contains(retired)) {
          offenders.add('$path:$line spells the retired hollow mark');
        }
        if (blankNameCheck.hasMatch(code)) {
          offenders.add('$path:$line asks frameName.isEmpty');
        }
      }
    }
    expect(scanned, greaterThan(100), reason: '⛔빈 것을 쟀다');
    expect(
      offenders,
      isEmpty,
      reason:
          'ask celNumberOrMark / inbetweenMark — 유저: 「당장은 제거」 for ○',
    );
  });

  test('the ledger names only files that still spell a ● of their own', () {
    for (final path in notTheMark.keys) {
      expect(
        File(path).readAsStringSync(),
        contains(mark),
        reason: '$path no longer spells ● — take its line out of the ledger',
      );
    }
  });
}
