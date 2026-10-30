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
  cameraRoom: ConteCameraRoom.grows,
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

  /// [picture]'s frame sits inside its slot and is larger every way than
  /// [inTheBlack]'s.
  void expectLargerThanInTheBlack(
    SheetPicture picture,
    SheetPicture inTheBlack,
    String what,
  ) {
    final (slot, frame) = (picture.slot.inflate(1e-9), picture.frame);
    expect(
      (
        frame.left >= slot.left,
        frame.top >= slot.top,
        frame.right <= slot.right,
        frame.bottom <= slot.bottom,
      ),
      (true, true, true, true),
      reason: '$what: $frame inside its slot $slot',
    );
    expect(
      (
        picture.frame.width > inTheBlack.frame.width,
        picture.frame.height > inTheBlack.frame.height,
      ),
      (true, true),
      reason: '$what: ${picture.frame} against ${inTheBlack.frame}',
    );
  }

  /// The rules across the body — the cuts' ends and the empty rows'.
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

    // 🗣️유저 2026-10-21 (I-118): 「컷이 없는 공간도 1칸마다 가로선 긋도록.
    // 지금 컷 없으면 가로선 없으니까」.
    test('a rule under every row no cut takes, as under a cut — on a page '
        'with no cut at all too', () {
      final short = ConteSheetSource(
        framesPerSecond: 24,
        cuts: source.cuts.take(1).toList(),
      );
      final ends = cutEnds(
        marksOf(pageIn(ConteSheetForm.digital, of: short), of: short),
      );
      expect(
        {for (final rule in ends) rule.rect.center.dy},
        {m.rowTop(3), m.rowTop(4)},
        reason: 'A ends on the fourth row; the fourth is empty',
      );
      expect(
        {for (final rule in ends) (rule.rect.left, rule.rect.right)},
        {(m.cutColumnLeft, m.pictureLeft), (m.actionLeft, m.bodyRight)},
        reason: 'not over the black',
      );

      const none = ConteSheetSource(framesPerSecond: 24, cuts: []);
      final bare = pageIn(ConteSheetForm.digital, of: none);
      expect(bare.cutBands, isEmpty, reason: 'fixture');
      expect(
        {
          for (final rule in cutEnds(marksOf(bare, of: none)))
            rule.rect.center.dy,
        },
        {for (var row = 1; row < m.rowsPerPage; row += 1) m.rowTop(row)},
      );
      expect(
        cutEnds(
          marksOf(pageIn(ConteSheetForm.analog, of: none), of: none),
        ),
        isEmpty,
        reason: 'the analog form rules no row',
      );
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

        // 🗣️유저 2026-10-21 (I-118): 「외곽선 적용은 외곽선 영역이 추가되니
        // 그만큼 그림이 작아지는것임. 미적용은 외곽선 영역이 없으니 화면
        // 칸에 맞춰서 그림이 위치하도록. 즉 적용에 비해서 커짐. 그러니
        // 그렇게 하고 괘선은 삭제.」
        test('no black and no rule round a window: a picture takes its cell '
            'inside the cell\'s rules, larger than in the black, the table '
            'laid as the black lays it', () {
          expect(
            marks.whereType<SheetFill>().where((fill) => fill.argb == _black),
            isEmpty,
          );
          final w = m.ruleWidth;
          for (var row = 0; row < m.rowsPerPage; row += 1) {
            expect(
              m.windowRect(row),
              Rect.fromLTRB(
                m.pictureLeft,
                m.rowTop(row),
                m.actionLeft,
                m.rowTop(row + 1),
              ).deflate(w),
              reason: 'row $row',
            );
          }
          final column = Rect.fromLTRB(
            m.pictureLeft + w,
            m.bodyTop,
            m.actionLeft - w,
            m.bodyBottom - w,
          );
          expect(
            [
              for (final rule in rules)
                if (rule.layer == SheetPaintLayer.form &&
                    rule.rect.overlaps(column))
                  rule.rect,
            ],
            isEmpty,
            reason: 'no rule stands in the picture column',
          );
          final black = pageIn(form);
          expect(
            (m.pictureLeft, m.actionLeft, m.rowHeight),
            (
              black.metrics.pictureLeft,
              black.metrics.actionLeft,
              black.metrics.rowHeight,
            ),
          );
          for (final (index, cell) in page.cells.indexed) {
            expectLargerThanInTheBlack(
              contePictureOf(cell, m),
              contePictureOf(black.cells[index], black.metrics),
              '${cell.cutId}${cell.cellIndex}',
            );
            expect(
              contePictureOf(cell, m).frame.width,
              closeTo(m.windowRect(0).width, 1e-9),
              reason: 'as wide as its cell holds it',
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

        test('a cell whose camera moves shows its window as paper over the '
            'columns it grew into, no rule round it, its picture larger '
            'than in the black', () {
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
          final window = contePictureSlot(cell, page.metrics);
          expect(window, cell.pictureRect.deflate(page.metrics.ruleWidth));
          expect(
            [
              for (final fill in pictures.whereType<SheetFill>())
                (fill.rect, fill.argb),
            ],
            [(window, _paper)],
            reason: 'the window is paper over the rules beneath it',
          );
          expect(pictures.whereType<SheetRule>(), isEmpty);
          final black = pageIn(form, of: moving);
          final picture = contePictureOf(cell, page.metrics);
          expectLargerThanInTheBlack(
            picture,
            contePictureOf(black.cells.single, black.metrics),
            'the moving camera\'s picture',
          );
          expect(
            picture.frame.topLeft,
            window.topLeft,
            reason: 'from the top of its window',
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
