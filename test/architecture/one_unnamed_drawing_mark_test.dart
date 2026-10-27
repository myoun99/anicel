import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

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
/// inside a block — for ONE value of `InbetweenMark`, and the ● is that mark
/// written as TEXT, spelled once in the home.
///
/// 🚨★★AND THERE ARE TWO MARKS (I-130). 유저 2026-10-25: 「지금의 속이 찬
/// 점을 마크2, 속이 빈 그냥 선으로 된 원을 마크1 … 일단은 모양이 다를뿐인
/// 같은 중간나누기임」. The hollow ○ came back as the second value, mark 1;
/// the unnamed head keeps the filled ●, which is mark 2 now. ↩️Until then the
/// ● was mark 1 and the ○ was spelled nowhere.
///
/// 🚨★★AND ONE DEFAULT MARK (F-469 · I-130-csp-import-Q2). 유저 2026-10-25:
/// 「이름없는 프레임의 기본마크, 앞으로 마크1 사용 … 다른곳도 같은곳있으면
/// 확인해서 법 통일」, and 10-27 for a dot a file does not say the kind of:
/// 「모를 때는 ○마크1」. F-469 left the answer spelled twice — the unnamed
/// head and the mark-every window, each its own `InbetweenMark.one` — and the
/// TVPaint and Clip Studio imports each spelled the ● the one mark had been.
/// Now `defaultInbetweenMark` in the home is the one answer — the Clip
/// Studio import asks it no more, reading each label's kind off its file
/// (I-130-csp-import-Q1).
///
/// 🚨★★AND THE UNNAMED HEAD'S MARK IS A PICK (F-489). 유저 2026-10-27:
/// 「이름 없는 블록의 기본 마크1,2인지 설정할수있게 … 기본값은 마크2로 둠」 —
/// Preferences ▸ Display holds it (`AppFrameGridSettings.unnamedMark`), its
/// first value `defaultUnnamedDrawingMark` beside the enum in the marks'
/// own file, and `unnamedDrawingMark` in the home is the live pick. The
/// mark-every window opens on it until one is picked (F-489-Q1 「둘 다
/// 따라간다」); `defaultInbetweenMark` is the TVPaint import's alone until the
/// save lane moves that line onto the pick too.
///
/// ⛔SO THIS SCANS SOURCE: copies that agree today all pass a behaviour
/// test. Either glyph spelled outside the home, a
/// `frameName == null || frameName.isEmpty` anywhere, the unnamed mark
/// named anywhere but the home — a surface deciding for itself that a drawing
/// with no number wears it — or a mark handed out as a value of its own
/// (`= InbetweenMark.one`, `?? …`, `offset: …`) has started the next copy.
void main() {
  const home = 'lib/src/models/frame.dart';

  /// The marks' own file: the enum, each glyph, the unnamed head's first
  /// value — apart from the home so the setting that holds the pick can
  /// name the type without importing the home that reads it.
  const markHome = 'lib/src/models/inbetween_mark.dart';
  const homes = {home, markHome};
  const marks = ['●', '○'];

  /// The one other ● in lib, and why it is not the mark.
  const notTheMark = <String, String>{
    'lib/src/ui/panels/onion_skin_panel.dart':
        'the onion panel\'s CURRENT column — where you stand, not a drawing',
  };

  final blankNameCheck = RegExp(
    r'frameName\s*==\s*null\s*\|\|\s*frameName\.isEmpty',
  );

  /// A mark given as a value — a default, a fallback, a map's entry — not
  /// one a `switch` arm answers for its case or a button names as its own.
  final aMarkOfItsOwn = RegExp(r'(=|\?\?|:)\s*InbetweenMark\.(one|two)\b');

  /// The code on each line of [file] with its comment cut off — a comment
  /// may NAME the mark, and several explain it.
  Iterable<(int, String)> codeLines(File file) sync* {
    final lines = file.readAsLinesSync();
    for (var index = 0; index < lines.length; index += 1) {
      yield (index + 1, codeOf(lines[index]));
    }
  }

  test('premise: the mark and the answer have their one home', () {
    // One line end whichever a checkout wrote: two pins span lines.
    final text = File(home).readAsStringSync().replaceAll('\r\n', '\n');
    expect(text, contains('String? celNumberOf('));
    expect(
      text,
      contains('String? get celNumber => celNumberOf(name);'),
      reason:
          'the getter the sheet and the export read asks the same answer — '
          'a body of its own is the copy no behaviour test can see',
    );
    expect(text, contains('DrawingHead drawingHeadOf('));
    expect(
      text,
      contains(
        '  required LayerKind kind,\n'
        '  required InbetweenMark unnamedMark,',
      ),
      reason:
          'a surface hands the head the mark its host heard, so a pick anew '
          'draws it again (F-489)',
    );
    final markText = File(markHome).readAsStringSync();
    for (final mark in marks) {
      final spelled = [
        for (final (_, code) in codeLines(File(markHome)))
          if (code.contains(mark)) code,
      ];
      expect(
        spelled,
        hasLength(1),
        reason: 'the scan below assumes $mark is spelled here, once',
      );
    }
    expect(
      markText,
      contains(
        'const InbetweenMark defaultUnnamedDrawingMark = InbetweenMark.two;',
      ),
      reason:
          'the unnamed head wears mark 2, the ●, until another is picked '
          '(F-489 「업계일반적으론 마크2가 보통이라서 기본값은 마크2로 둠」)',
    );
    expect(
      text,
      contains(
        'InbetweenMark get unnamedDrawingMark =>\n'
        '    AppFrameGridSettings.settings.value.unnamedMark;',
      ),
      reason:
          '🚨유저: 「중간나누기 마크1로서 작동했으면」 — the unnamed drawing '
          'wears a mark itself, as data, not a glyph of its own: the one '
          'Preferences ▸ Display picks (F-489)',
    );
    expect(
      text,
      contains('const InbetweenMark defaultInbetweenMark = InbetweenMark.one;'),
      reason:
          'a TVPaint dot whose kind its file does not say is mark 1, the ○ '
          '(I-130-csp-import-Q2 「모를 때는 ○마크1」) — until the save lane '
          'moves it onto the pick (F-489-Q1)',
    );
    expect(markText, contains("InbetweenMark.one => '○'"));
    expect(
      markText,
      contains("InbetweenMark.two => '●'"),
      reason: 'each mark written as text is its one glyph',
    );
  });

  test('nobody else spells a mark, nobody asks whether a frame name is '
      'empty, nobody else hands a drawing the unnamed mark, and nobody hands '
      'out a mark as a value of its own — and the ledger names only files '
      'that still spell a mark of their own', () {
    final offenders = <String>[];
    final spellers = <String, List<int>>{};
    var scanned = 0;
    for (final file in dartFilesUnder('lib')) {
      scanned += 1;
      final path = libPath(file);
      for (final (line, code) in codeLines(file)) {
        if (!homes.contains(path) && marks.any(code.contains)) {
          (spellers[path] ??= []).add(line);
        }
        if (blankNameCheck.hasMatch(code)) {
          offenders.add('$path:$line asks frameName.isEmpty');
        }
        if (path != home && code.contains('unnamedDrawingMark')) {
          offenders.add(
            '$path:$line hands out the unnamed mark — ask drawingHeadOf',
          );
        }
        if (!homes.contains(path) && aMarkOfItsOwn.hasMatch(code)) {
          offenders.add(
            '$path:$line hands out a mark of its own — read the pick '
            '(AppFrameGridSettings.unnamedMark)',
          );
        }
      }
    }
    expect(scanned, greaterThan(100), reason: '⛔빈 것을 쟀다');
    expect(
      offenders,
      isEmpty,
      reason: 'ask drawingHeadOf / celNumberOrMark / InbetweenMark.glyph',
    );
    // Asked of the code the scan reads, a comment cut off: a ● only a
    // comment of a ledgered file still names is no ● of its own.
    expectSetMatchesLedger(
      spellers.keys,
      notTheMark.keys,
      unledgered:
          'these spell a mark — ask drawingHeadOf / celNumberOrMark / '
          'InbetweenMark.glyph',
      paidOff:
          'these no longer spell a mark — take their lines out of the ledger',
      hits: spellers,
    );
  });
}
