import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨★★ONE ANSWER TO 「DOES THIS DRAWING HAVE A NAME」, AND ONE MARK FOR NO.
///
/// `celNumberOf` (beside `Frame.celNumber`) says whether a drawing has a cel
/// number, and `drawingHeadOf` what its head wears when it has none. Until
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
/// 🚨★★AND ONE MARK AS DATA (2026-09-24). 유저: 「데이터적으로도 같은
/// 취급시키는거 맞지? 중간나누기 마크1로서 작동했으면하는데. 마크2는 토에이
/// 타임시트에 속이 빈 동그라미가 있어서 그게 될 예정」. F-149 had made the two
/// share a GLYPH: the unnamed head printed ● as its name while the dot inside
/// a block was a mark, so every surface drew them apart — the sheet at two
/// sizes. Now there are TWO names — what an unnamed drawing wears and the dot
/// inside a block — for ONE value, mark 1 of `InbetweenMark`, and the ● is
/// that mark written as TEXT, spelled once in the home. The hollow ○ is
/// spelled nowhere: mark 2 arrives as a second value of the enum.
///
/// ⛔SO THIS SCANS SOURCE: copies that agree today all pass a behaviour
/// test. The glyph spelled outside the home, a
/// `frameName == null || frameName.isEmpty` anywhere, or the unnamed mark
/// named anywhere but the home — a surface deciding for itself that a drawing
/// with no number wears it — has started the next copy.
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
    expect(
      text,
      contains(
        'DrawingHead drawingHeadOf(String? name, {required LayerKind kind})',
      ),
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
      contains('const InbetweenMark unnamedDrawingMark = InbetweenMark.one;'),
      reason:
          '🚨유저: 「중간나누기 마크1로서 작동했으면」 — the unnamed drawing '
          'wears mark 1 itself, as data, not a glyph of its own',
    );
    expect(
      text,
      contains('InbetweenMark.one => inbetweenMark'),
      reason: 'and mark 1 written as text is the one ●',
    );
  });

  test('nobody else spells the mark, nobody spells the retired one, nobody '
      'asks whether a frame name is empty, and nobody else hands a drawing '
      'the unnamed mark', () {
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
        if (path != home && code.contains('unnamedDrawingMark')) {
          offenders.add(
            '$path:$line hands out the unnamed mark — ask drawingHeadOf',
          );
        }
      }
    }
    expect(scanned, greaterThan(100), reason: '⛔빈 것을 쟀다');
    expect(
      offenders,
      isEmpty,
      reason:
          'ask drawingHeadOf / celNumberOrMark / inbetweenMark — 유저: '
          '「당장은 제거」 for ○',
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
