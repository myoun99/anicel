import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/conte/conte_page_marks.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/models/sheet_paint_layer.dart';
import 'package:anicel/src/ui/conte/conte_words_in.dart';

import '../helpers/conte_camera.dart';

/// 🗣️유저 2026-10-21 (I-118): 「콘티용지의 새로운 서식. 지금은 아날로그식? …
/// 그리고 디지털식? 요즘에 맞게 컷번호 항목도 본문인 화면쪽이랑 붙어있고, 컷
/// 마다 가로로 선 그어서 칸 제대로 나누는방식. 그리고 서식 옵션으로
/// 공통적용되게 화면에 검은 외곽선 적용/미적용 버튼」 — the sheet prints in
/// the form the work keeps, with or without the black round its pictures.
ConteCellSource _cell(int start, int end, {ConteCameraWork? camera}) =>
    ConteCellSource(
      startFrame: start,
      endFrameExclusive: end,
      pictureFrame: 0,
      camera: camera,
    );

ConteCutSource _cut(String id, List<ConteCellSource> cells) => ConteCutSource(
  cutId: CutId(id),
  name: id,
  durationFrames: cells.last.endFrameExclusive,
  cumulativeEndFrames: cells.last.endFrameExclusive,
  cells: cells,
);

final _ja = conteWordsIn(AppLanguage.ja);

const _black = 0xFF101010;
const _paper = 0xFFFFFFFF;

void main() {
  // A on rows 0–2, B on row 3, and the fifth row empty.
  final source = ConteSheetSource(
    framesPerSecond: 24,
    cuts: [
      _cut('A', [_cell(0, 24), _cell(24, 36), _cell(36, 72)]),
      _cut('B', [_cell(0, 30)]),
    ],
  );

  ContePageLayout pageIn(
    ConteSheetForm form, {
    bool outlined = true,
    ConteSheetSource? of,
  }) => layoutConteSheet(
    of ?? source,
    metrics: ConteSheetMetrics(form: form, outlined: outlined),
  ).single;

  List<SheetMark> marksOf(ContePageLayout page, {ConteSheetSource? of}) =>
      contePageMarks(page, of ?? source, words: _ja);

  /// What [marks] print on [layer], each by what it prints and where.
  String printed(Iterable<SheetMark> marks, SheetPaintLayer layer) => [
    for (final mark in marks)
      if (mark.layer == layer)
        switch (mark) {
          SheetFill(:final rect, :final argb) => 'fill $rect $argb',
          SheetRule(:final rect, :final hold) => 'rule $rect $hold',
          SheetWords(:final text, :final slot) => 'words $text $slot',
          _ => '${mark.runtimeType}',
        },
  ].join('\n');

  /// The rules across the body — the cuts' ends.
  List<SheetRule> cutEnds(List<SheetMark> marks) => [
    for (final rule in marks.whereType<SheetRule>())
      if (!rule.isUpright && rule.layer == SheetPaintLayer.content) rule,
  ];

  group('the digital form', () {
    final page = pageIn(ConteSheetForm.digital);
    final m = page.metrics;
    final marks = marksOf(page);
    final rules = marks.whereType<SheetRule>().toList();

    test('the cut column stands against the picture column, under one '
        'head', () {
      expect(m.cutColumnRight, m.pictureLeft);
      final analog = pageIn(ConteSheetForm.analog).metrics;
      expect(
        analog.cutColumnRight,
        lessThan(analog.pictureLeft),
        reason: 'the analog cut box stands apart',
      );
      for (final (name, edgeOf) in [
        ('the table\'s top', (Rect rect) => rect.top == m.tableTop),
        ('the head\'s underside', (Rect rect) => rect.bottom == m.bodyTop),
      ]) {
        final across = [
          for (final rule in rules)
            if (!rule.isUpright && edgeOf(rule.rect)) rule.rect,
        ];
        expect(across, hasLength(1), reason: '$name is one rule');
        expect(
          (across.single.left, across.single.right),
          (m.cutColumnLeft, m.bodyRight),
          reason: '$name from the cut column on',
        );
      }
      final between = [
        for (final rule in rules)
          if (rule.isUpright &&
              rule.rect.right > m.cutColumnRight - 1 &&
              rule.rect.left < m.pictureLeft + 1)
            rule,
      ];
      expect(
        between,
        hasLength(1),
        reason: 'one rule between the two, not the box\'s and the table\'s',
      );
      expect(
        (between.single.rect.left, between.single.rect.bottom),
        (m.pictureLeft, m.bodyTop),
        reason: 'over the head only — below it the black is the edge',
      );
    });

    test('a rule across the table ends every cut above the foot, and not '
        'over the black', () {
      final ends = cutEnds(marks);
      expect(
        {for (final rule in ends) rule.rect.center.dy},
        {m.rowTop(3), m.rowTop(4)},
        reason: 'A ends on the fourth row, B on the fifth',
      );
      expect(
        {for (final rule in ends) (rule.rect.left, rule.rect.right)},
        {(m.cutColumnLeft, m.pictureLeft), (m.actionLeft, m.bodyRight)},
      );
      expect(cutEnds(marksOf(pageIn(ConteSheetForm.analog))), isEmpty);
    });

    test('a cut that ends on the foot has the foot for its rule', () {
      final full = ConteSheetSource(
        framesPerSecond: 24,
        cuts: [
          ...source.cuts.take(1),
          _cut('C', [_cell(0, 12), _cell(12, 24)]),
        ],
      );
      final ends = cutEnds(
        marksOf(pageIn(ConteSheetForm.digital, of: full), of: full),
      );
      expect({for (final rule in ends) rule.rect.center.dy}, {m.rowTop(3)});
    });

    test('a cut\'s words stop on its rule — in the analog form they run to '
        'the foot', () {
      final analog = pageIn(ConteSheetForm.analog);
      for (final (index, cell) in page.cells.indexed) {
        final end = m.rowTop(cell.cutId == 'A' ? 3 : 4);
        expect(
          (cell.actionRect.bottom, cell.dialogueRect.bottom),
          (end, end),
          reason: '${cell.cutId}${cell.cellIndex}',
        );
        final ran = analog.cells[index];
        expect(
          (ran.actionRect.bottom, ran.dialogueRect.bottom),
          (m.bodyBottom, m.bodyBottom),
        );
        expect(
          (cell.actionRect.top, cell.dialogueRect.top),
          (ran.actionRect.top, ran.dialogueRect.top),
          reason: 'a cell\'s words start where they did',
        );
      }
    });
  });

  group('without the black', () {
    for (final form in ConteSheetForm.values) {
      group('in the ${form.name} form', () {
        final page = pageIn(form, outlined: false);
        final m = page.metrics;
        final marks = marksOf(page);
        final rules = marks.whereType<SheetRule>().toList();

        test('no black: each window is ruled just outside it, and a picture '
            'lands where it lands in the black', () {
          expect(
            marks.whereType<SheetFill>().where((fill) => fill.argb == _black),
            isEmpty,
          );
          for (var row = 0; row < m.rowsPerPage; row += 1) {
            final window = m.windowRect(row);
            final round = [
              for (final rule in rules)
                if (rule.layer == SheetPaintLayer.form &&
                    rule.rect.overlaps(window.inflate(m.ruleWidth)) &&
                    !rule.rect.overlaps(window))
                  rule.rect,
            ];
            expect(
              round.any((rect) => rect.bottom == window.top),
              isTrue,
              reason: 'row $row: above',
            );
            expect(
              round.any((rect) => rect.top == window.bottom),
              isTrue,
              reason: 'row $row: below',
            );
            expect(
              round.any((rect) => rect.right == window.left),
              isTrue,
              reason: 'row $row: left',
            );
            expect(
              round.any((rect) => rect.left == window.right),
              isTrue,
              reason: 'row $row: right',
            );
          }
          final black = pageIn(form);
          for (final (index, cell) in page.cells.indexed) {
            expect(
              contePictureOf(cell, m).slot,
              contePictureOf(black.cells[index], black.metrics).slot,
            );
          }
        });

        test('the picture column is ruled head to foot, and the foot runs '
            'under it', () {
          final sides = [
            for (final rule in rules)
              if (rule.isUpright &&
                  (rule.rect.left == m.pictureLeft ||
                      rule.rect.right == m.actionLeft))
                rule.rect,
          ];
          expect(sides, hasLength(2));
          for (final side in sides) {
            expect((side.top, side.bottom), (m.tableTop, m.bodyBottom));
          }
          expect(
            rules.where(
              (rule) =>
                  !rule.isUpright &&
                  rule.rect.bottom == m.bodyBottom &&
                  rule.rect.left <= m.pictureLeft &&
                  rule.rect.right == m.bodyRight,
            ),
            hasLength(1),
          );
        });

        test('the form never reads the film', () {
          final empty = ContePageLayout(
            pageIndex: 0,
            cells: const [],
            cutBands: const [],
            emptyRowsFrom: 0,
            metrics: m,
          );
          expect(
            printed(
              contePageMarks(
                empty,
                const ConteSheetSource(cuts: []),
                words: _ja,
              ),
              SheetPaintLayer.form,
            ),
            printed(marks, SheetPaintLayer.form),
          );
        });

        test('a cell whose camera moves stands in paper, its window ruled as '
            'every window is', () {
          final moving = ConteSheetSource(
            framesPerSecond: 24,
            cuts: [
              _cut('A', [_cell(0, 24, camera: conteCameraPan(across: 1))]),
            ],
          );
          final page = pageIn(form, outlined: false, of: moving);
          final cell = page.cells.single;
          final marks = marksOf(page, of: moving);
          final pictures = [
            for (final mark in marks)
              if (mark.layer == SheetPaintLayer.picture) mark,
          ];
          expect(
            pictures.whereType<SheetFill>().where(
              (fill) => fill.argb == _black,
            ),
            isEmpty,
          );
          expect(
            pictures.whereType<SheetFill>().where(
              (fill) => fill.rect == cell.pictureRect && fill.argb == _paper,
            ),
            hasLength(1),
            reason: 'the box is paper over the rules beneath it',
          );
          final window = contePictureSlot(cell, page.metrics);
          final round = [
            for (final rule in pictures.whereType<SheetRule>())
              if (rule.rect.overlaps(window.inflate(page.metrics.ruleWidth)) &&
                  !rule.rect.overlaps(window))
                rule.rect,
          ];
          expect(
            (
              round.any((rect) => rect.bottom == window.top),
              round.any((rect) => rect.top == window.bottom),
              round.any((rect) => rect.right == window.left),
              round.any((rect) => rect.left == window.right),
            ),
            (true, true, true, true),
          );
        });
      });
    }

    test('in the digital form a cut\'s rule runs across the pictures too — '
        'nothing parts them else', () {
      final page = pageIn(ConteSheetForm.digital, outlined: false);
      final m = page.metrics;
      expect(
        {
          for (final rule in cutEnds(marksOf(page)))
            (rule.rect.left, rule.rect.right),
        },
        {(m.cutColumnLeft, m.bodyRight)},
      );
    });
  });
}
