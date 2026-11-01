import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/conte/conte_page_marks.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/sheet_fixed_lines.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/ui/conte/conte_words_in.dart';

/// 🗣️I-93 (유저 2026-10-12): 「콘티용지패널 내용란에 고정텍스트로 … 각
/// FIX PAN 이런거마다 개행되고」 · 「고정텍스트 표기할지 안할지
/// 콘티용지패널에 설정할수있도록」 — a cell's camera lines stand at the top
/// of its ACTION column, a line each, and the words typed there begin under
/// them; taken out, the words are back at the top.
void main() {
  const action = 'ハヤト走る';
  const camera = ['FIX (0+5)', 'PAN (0+11)', 'FIX (0+8)'];
  const line = conteCellTextSize * conteLineHeight;
  final ja = conteWordsIn(AppLanguage.ja);
  final ko = conteWordsIn(AppLanguage.ko);

  ConteSheetSource sourceOf(
    List<String> lines, {
    List<String> transitions = const [],
    List<String> linked = const [],
    List<String> heads = const [],
    List<String> tails = const [],
  }) => ConteSheetSource(
    cuts: [
      ConteCutSource(
        cutId: const CutId('A'),
        name: 'A',
        durationFrames: 24,
        cumulativeEndFrames: 24,
        cells: [
          ConteCellSource(
            startFrame: 0,
            endFrameExclusive: 24,
            pictureFrame: 0,
            action: action,
            fixedLines: SheetFixedLines(
              camera: lines,
              transitions: transitions,
              linkedCuts: linked,
              cutHead: heads,
              cutTail: tails,
            ),
          ),
        ],
      ),
    ],
  );

  /// The page [source] lays, its one cell and every word it prints.
  ({ContePlacedCell cell, List<SheetWords> words}) printed(
    ConteSheetSource source,
  ) {
    final page = layoutConteSheet(source).single;
    return (
      cell: page.cells.single,
      words: contePageMarks(
        page,
        source,
        words: ja,
      ).whereType<SheetWords>().toList(),
    );
  }

  SheetWords wordsSaying(List<SheetWords> words, String text) =>
      words.singleWhere((each) => each.text == text);

  void expectRect(Rect actual, Rect expected, {String? reason}) {
    for (final (got, want) in [
      (actual.left, expected.left),
      (actual.top, expected.top),
      (actual.right, expected.right),
      (actual.bottom, expected.bottom),
    ]) {
      expect(got, closeTo(want, 1e-9), reason: reason);
    }
  }

  test('🎯each line stands one conte line under the one before, from the '
      'top of the ACTION words, on one line, in their ink', () {
    final (:cell, :words) = printed(sourceOf(camera));
    final slot = cell.actionRect.deflate(4);
    final typed = wordsSaying(words, action);

    for (final (index, text) in camera.indexed) {
      final mark = wordsSaying(words, text);
      expectRect(
        mark.slot,
        Rect.fromLTRB(
          slot.left,
          slot.top + index * line,
          slot.right,
          slot.top + (index + 1) * line,
        ),
        reason: text,
      );
      expect(mark.fit, SheetWordsFit.shrink, reason: 'never broken');
      expect(
        (mark.layer, mark.argb, mark.size, mark.bold),
        (typed.layer, typed.argb, typed.size, typed.bold),
        reason: 'set as the words typed there',
      );
    }
  });

  test('🎯the words typed in the cell begin under its lines — at the drop '
      'the field types at', () {
    final source = sourceOf(camera);
    final (:cell, :words) = printed(source);
    final slot = cell.actionRect.deflate(4);

    expect(
      conteActionWordsDrop(cell, words: ja),
      closeTo(3 * line, 1e-9),
    );
    expectRect(
      wordsSaying(words, action).slot,
      Rect.fromLTRB(slot.left, slot.top + 3 * line, slot.right, slot.bottom),
    );
  });

  test('with no line to write the words are at the top', () {
    final source = sourceOf(const []);
    final (:cell, :words) = printed(source);

    expect(cell.source.fixedLines.writtenIn(ja), isEmpty);
    expect(conteActionWordsDrop(cell, words: ja), 0);
    for (final text in camera) {
      expect(words.where((each) => each.text == text), isEmpty, reason: text);
    }
    expect(wordsSaying(words, action).slot, cell.actionRect.deflate(4));
  });

  test('🗣️its transitions stand under its camera lines, a line each, the '
      'words under them — and go with them when the sheet leaves them out '
      '(I-93-Q1)', () {
    const transitions = ['WI (0+2)', 'c1 × c2 カットO.L (0+12)'];
    final source = sourceOf(camera, transitions: transitions);
    final (:cell, :words) = printed(source);
    final slot = cell.actionRect.deflate(4);

    for (final (index, text) in transitions.indexed) {
      final at = camera.length + index;
      expect(
        wordsSaying(words, text).slot.top,
        closeTo(slot.top + at * line, 1e-9),
        reason: text,
      );
    }
    expect(
      conteActionWordsDrop(cell, words: ja),
      closeTo(5 * line, 1e-9),
    );
  });

  // 🗣️F-540 (유저 2026-11-02): 「カット頭 F.I (0+6) 이런식으로 컷 머리 라고
  // 씀. 뒤는 カット尻 이렇게. 한국어는 컷 앞 컷 뒤」 · 「텍스트 위치는
  // 고정적으로 고정텍스트 공간 내에서 맨 위나 맨 아래」.
  test('🎯a fade on its cut\'s head opens the lines and one on its tail '
      'closes them, each under its end\'s word', () {
    const transitions = ['c1 × c2 カットO.L (1+0)'];
    final source = sourceOf(
      camera,
      transitions: transitions,
      linked: const ['c2'],
      heads: const ['FI (0+6)'],
      tails: const ['FO (0+8)'],
    );
    final cell = printed(source).cell;
    expect(cell.source.fixedLines.writtenIn(ja), [
      'カット頭 FI (0+6)',
      ...camera,
      ...transitions,
      '${ja.linked} c2',
      'カット尻 FO (0+8)',
    ]);
    final korean = cell.source.fixedLines.writtenIn(ko);
    expect(korean.first, '컷 앞 FI (0+6)');
    expect(korean.last, '컷 뒤 FO (0+8)');
    expect(
      conteActionWordsDrop(cell, words: ja),
      (camera.length + 4) * line,
      reason: 'the typed words begin under the last of them',
    );
  });

  test('lines that outrun the column end at its foot, and the words typed '
      'there have no room left', () {
    final probe = printed(sourceOf(const []));
    final room = probe.cell.actionRect.deflate(4).height;
    final lines = [
      for (var index = 0; index < (room / line).ceil() + 2; index += 1)
        'PAN (0+$index)',
    ];
    final (:cell, :words) = printed(sourceOf(lines));
    final slot = cell.actionRect.deflate(4);

    for (final text in lines) {
      final mark = wordsSaying(words, text);
      expect(mark.slot.top, lessThanOrEqualTo(slot.bottom), reason: text);
      expect(mark.slot.bottom, lessThanOrEqualTo(slot.bottom), reason: text);
      expect(mark.slot.height, greaterThanOrEqualTo(0), reason: text);
    }
    expect(
      wordsSaying(words, lines.last).printsNothing,
      isTrue,
      reason: 'a line past the foot prints nothing',
    );
    expect(wordsSaying(words, action).printsNothing, isTrue);
  });
}
