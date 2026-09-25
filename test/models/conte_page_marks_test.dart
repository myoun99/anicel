import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/app_corner_radii.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/conte/conte_notation.dart';
import 'package:anicel/src/models/conte/conte_page_marks.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/models/sheet_paint_layer.dart';

/// The conte body page, as the marks every printer replays.
///
/// 유저 2026-09-25 — the first preset's page (「위에 헤더에 컷 화면 내용 초 …
/// 아래부분은 가로선으로 칸이 나뉘어져있지않아 … 컷 칸은 화면/내용/초랑 공간
/// 떨어져있어」), its lines (「헤더의 사각형 실루엣 선이랑 아래쪽 본문이랑
/// 라인이 … 절대 어긋나지않도록」) and its time column (「해당 패널 … 의
/// 길이도 … 마지막 블록에 컷 전체 길이 … 블록이 하나면 … 블록길이
/// 안보이게」).
ConteCellSource _cell(int start, int end) =>
    ConteCellSource(startFrame: start, endFrameExclusive: end, pictureFrame: 0);

ConteCutSource _cut(String id, List<ConteCellSource> cells) => ConteCutSource(
  cutId: CutId(id),
  name: id,
  durationFrames: cells.last.endFrameExclusive,
  cumulativeEndFrames: cells.last.endFrameExclusive,
  cells: cells,
);

void main() {
  final source = ConteSheetSource(
    framesPerSecond: 24,
    logoAssetPath: 'logo.png',
    cuts: [
      // Three blocks: 1+0, 0+12, 1+12 — the cut is 3+0.
      _cut('A', [_cell(0, 24), _cell(24, 36), _cell(36, 72)]),
      // One block: its length IS the cut's.
      _cut('B', [_cell(0, 30)]),
    ],
  );
  final page = layoutConteSheet(source).single;
  final m = page.metrics;
  final marks = contePageMarks(page, source);
  final rules = marks.whereType<SheetRule>().toList();
  final words = marks.whereType<SheetWords>().toList();

  group('the lines', () {
    final silhouette = marks
        .whereType<SheetFill>()
        .firstWhere((fill) => fill.argb == 0xFF101010)
        .rect;

    test('every text-column boundary is ONE rule from the header\'s top to '
        'the body\'s foot', () {
      for (final x in [m.dialogueLeft, m.timeLeft]) {
        final at = rules.where(
          (rule) => rule.isUpright && (rule.rect.center.dx - x).abs() < 1e-9,
        );
        expect(at, hasLength(1), reason: 'one mark at x=$x, not two halves');
        expect(at.single.rect.top, m.tableTop);
        expect(at.single.rect.bottom, m.bodyBottom);
      }
      final edge = rules.where(
        (rule) => rule.isUpright && rule.rect.right == m.bodyRight,
      );
      expect(edge, hasLength(1));
      expect(edge.single.rect.top, m.tableTop);
      expect(edge.single.rect.bottom, m.bodyBottom);
    });

    test('where the silhouette is the edge, the rule ENDS on the black\'s own '
        'number and holds it — the head\'s picture-column sides and its '
        'underside', () {
      final sides = [
        for (final rule in rules)
          if (rule.isUpright &&
              rule.rect.left >= m.pictureLeft &&
              rule.rect.right <= m.actionLeft)
            rule,
      ];
      expect(sides, hasLength(2), reason: 'fixture: left side and right side');
      // The SAME double, not a close one: a close one rounds apart.
      expect(sides.first.rect.left, silhouette.left);
      expect(sides.first.hold, SheetRuleHold.near);
      expect(sides.last.rect.right, silhouette.right);
      expect(sides.last.hold, SheetRuleHold.far);
      for (final side in sides) {
        expect(
          side.rect.bottom,
          silhouette.top,
          reason: 'below the head the silhouette is the edge — no rule '
              'over its black',
        );
      }
      final underside = rules.where(
        (rule) =>
            !rule.isUpright &&
            rule.rect.left == m.pictureLeft &&
            rule.rect.bottom == silhouette.top,
      );
      expect(underside, hasLength(1));
      expect(underside.single.hold, SheetRuleHold.far);
    });

    test('the picture windows — and the pictures cut to them — wear the '
        'app\'s window corner; the black around them keeps its own', () {
      // 유저 2026-09-25: 「지브리콘티처럼 모서리 둥글게하자. 우리 앱 통일
      // 모서리 따라서」 · 「기존 상태에서 둥글게만」.
      final fills = marks.whereType<SheetFill>();
      final windows = fills.where((fill) => fill.argb == 0xFFEDEDED);
      expect(windows, hasLength(m.rowsPerPage));
      for (final window in windows) {
        expect(window.cornerRadius, AppCornerRadii.window);
      }
      expect(silhouette, fills.firstWhere((f) => f.argb == 0xFF101010).rect);
      expect(
        fills.firstWhere((fill) => fill.argb == 0xFF101010).cornerRadius,
        0,
        reason: 'the column meets the head\'s rules square, as before',
      );
      for (final picture in marks.whereType<SheetPicture>()) {
        expect(picture.cornerRadius, AppCornerRadii.window);
      }
    });

    test('the film\'s pictures — with the camera work written on them — are '
        'their own stratum, apart from the typed values and never on them',
        () {
      // 유저 2026-09-25: 「흰 배경/ 용지서식(칸이나 픽쳐 텍스트나 이런거)/그림
      // 이런식으로. psd출력할때 이런느낌으로」 · 「그림 수정하거나 텍스트
      // 바뀌거나 하는데 용지 리빌드하면 너무 비효율적」.
      final panned = ConteSheetSource(
        framesPerSecond: 24,
        cuts: [
          ConteCutSource(
            cutId: const CutId('P'),
            name: 'P',
            durationFrames: 24,
            cumulativeEndFrames: 24,
            cells: const [
              ConteCellSource(
                startFrame: 0,
                endFrameExclusive: 24,
                pictureFrame: 0,
                action: 'ハヤト走る',
                cameraLabels: ['PAN→', 'T.U'],
              ),
            ],
          ),
        ],
      );
      final framed = contePageMarks(layoutConteSheet(panned).single, panned);
      final pictures = framed.where(
        (mark) => mark.layer == SheetPaintLayer.picture,
      );
      expect(pictures.whereType<SheetPicture>(), hasLength(1));
      expect(
        pictures.whereType<SheetWords>().map((words) => words.text),
        ['PAN→', 'T.U'],
        reason: 'the camera work is written ON the picture',
      );
      final values = framed.where(
        (mark) => mark.layer == SheetPaintLayer.content,
      );
      expect(values.whereType<SheetPicture>(), isEmpty);
      expect(
        values.whereType<SheetWords>().map((words) => words.text),
        contains('ハヤト走る'),
      );
      Rect placeOf(SheetMark mark) => switch (mark) {
        SheetPicture(:final slot) => slot,
        SheetWords(:final slot) => slot,
        SheetFill(:final rect) => rect,
        SheetImage(:final slot) => slot,
        _ => Rect.zero,
      };
      for (final picture in pictures) {
        for (final value in values.whereType<SheetWords>()) {
          if (value.text.isEmpty) {
            continue;
          }
          expect(
            placeOf(picture).overlaps(value.slot),
            isFalse,
            reason: '「${value.text}」 lies off every picture, so the two '
                'strata stack either way',
          );
        }
      }
    });

    test('the body has no row rules — only the head\'s and the foot', () {
      final across = rules.where(
        (rule) =>
            !rule.isUpright &&
            rule.rect.top > m.bodyTop + 0.5 &&
            rule.rect.bottom < m.bodyBottom - 0.001,
      );
      expect(across, isEmpty);
    });

    test('the cut box stands apart: none of its rules touch the table', () {
      final cutBox = rules.where(
        (rule) => rule.rect.right <= m.cutColumnRight,
      );
      expect(cutBox, hasLength(5), reason: 'four sides and the head');
      for (final rule in cutBox) {
        expect(rule.rect.right, lessThan(m.pictureLeft));
      }
    });

    test('the form never reads the film: an empty page prints the same '
        'form', () {
      final empty = ContePageLayout(
        pageIndex: 0,
        cells: const [],
        cutBands: const [],
        emptyRowsFrom: 0,
        metrics: m,
      );
      // Every form mark by what it prints and where — not a count.
      String form(List<SheetMark> of) => [
        for (final mark in of)
          if (mark.layer == SheetPaintLayer.form)
            switch (mark) {
              SheetFill(:final rect, :final argb) => 'fill $rect $argb',
              SheetRule(:final rect, :final hold) => 'rule $rect $hold',
              SheetWords(:final text, :final slot) => 'words $text $slot',
              _ => '${mark.runtimeType}',
            },
      ].join('\n');
      expect(
        form(contePageMarks(empty, const ConteSheetSource(cuts: []))),
        form(marks),
      );
    });
  });

  group('the time column', () {
    // The column's BODY — its head prints 秒 above it.
    bool inTheColumn(SheetWords word) =>
        word.slot.left >= m.timeLeft - 0.001 &&
        word.slot.top >= m.bodyTop - 0.001 &&
        word.slot.bottom <= m.bodyBottom + 0.001;

    List<SheetWords> inTimeColumn() => words.where(inTheColumn).toList();

    test('a cut of several blocks prints each block\'s length, small and '
        'light, and its total, bold, under the last', () {
      final a = inTimeColumn().take(4).toList();
      expect(a.map((word) => word.text), ['1+0', '0+12', '1+12', '3+0']);
      expect(
        inTimeColumn().every((word) => word.fit == SheetWordsFit.oneLine),
        isTrue,
        reason: 'a length is one word — broken, 「3+1」 over 「2」 sat on '
            'the block length above it',
      );
      for (final block in a.take(3)) {
        expect(block.bold, isFalse);
        expect(block.size, lessThan(a.last.size));
        expect(block.argb, isNot(a.last.argb));
      }
      expect(a.last.bold, isTrue);
      expect(
        a[2].slot.bottom,
        lessThanOrEqualTo(a.last.slot.bottom - 10),
        reason: 'the last block\'s length stands above the total',
      );
    });

    test('a cut of one block prints only its total — the two would say '
        'the same thing', () {
      final b = inTimeColumn().skip(4).toList();
      expect(b.map((word) => word.text), ['1+6']);
      expect(b.single.bold, isTrue);
    });

    test('a length drag moves the cut\'s total and its last block, and '
        'nothing else', () {
      final dragged = contePageMarks(
        page,
        source,
        liveFramesOf: (cutId) => cutId == 'A' ? 96 : null,
      ).whereType<SheetWords>();
      final times = [
        for (final word in dragged.where(inTheColumn)) word.text,
      ];
      expect(times, ['1+0', '0+12', '2+12', '4+0', '1+6']);
    });
  });

  test('top-left, the page among the body\'s pages; top-right, the logo', () {
    final number = words.firstWhere((word) => word.slot == m.pageNumberSlot);
    expect(number.text, '1 / 1');
    final logo = marks.whereType<SheetImage>().single;
    expect(logo.assetPath, 'logo.png');
    expect(logo.slot, m.logoSlot);
    expect(
      contePageMarks(
        page,
        ConteSheetSource(cuts: source.cuts),
      ).whereType<SheetImage>(),
      isEmpty,
      reason: 'no logo registered prints no logo',
    );
  });

  group('the book\'s first two pages', () {
    final bookSource = ConteSheetSource(
      framesPerSecond: 24,
      title: 'チェンソーマン',
      episode: '13',
      coverImagePath: 'cover.png',
      logoAssetPath: 'logo.png',
      conteStaffName: '吉原',
      cuts: source.cuts,
    );
    final book = layoutConteBook(bookSource);

    test('the cover: the work, the episode, its picture, the book\'s cuts '
        'and running time, the conte artist — and no page number', () {
      final cover = contePageMarks(book.first, bookSource);
      final texts = cover.whereType<SheetWords>().map((word) => word.text);
      expect(texts, [
        'チェンソーマン',
        '13',
        // Two cuts, 72 + 30 frames at 24fps = 4 seconds and 6 frames.
        '2cut      0:04+6',
        'コンテ      吉原',
      ]);
      expect(
        cover.whereType<SheetImage>().map((image) => image.assetPath),
        ['cover.png'],
        reason: 'the cover\'s own picture, not the logo',
      );
      expect(cover.whereType<SheetRule>(), isEmpty, reason: 'no table');
    });

    test('the cover is laid about its picture: the picture on the page\'s '
        'middle, the title large and shrinking to fit with the episode right '
        'under it above, the closing lines set alike in the middle of the '
        'room below', () {
      // 유저 2026-09-25: 「작품제목 더 크게하고, 길어져서 다 안들어가면 크기
      // 작게하는방향 … 화수는 좀 더 타이틀이랑 붙여서」 · 「표지 컷이랑
      // 콘티랑 같은 폰트로. 크기나 이런거 전부」 · 「컷이랑 콘티는 중앙아래
      // 느낌 … 로고랑 밑 공간의 중앙쯤? 로고도 좀 더 내리자. 중앙느낌」.
      final cover = contePageMarks(book.first, bookSource);
      final words = cover.whereType<SheetWords>().toList();
      final (title, episode, cuts, staff) = (
        words[0],
        words[1],
        words[2],
        words[3],
      );
      expect(title.size, greaterThan(44), reason: 'larger than it was');
      expect(title.bold, isTrue);
      expect(title.fit, SheetWordsFit.shrink);
      expect(episode.fit, SheetWordsFit.shrink);
      expect(episode.slot.top, title.slot.bottom, reason: 'right under it');
      for (final closing in [cuts, staff]) {
        expect(
          (closing.size, closing.bold, closing.fit, closing.argb),
          (cuts.size, cuts.bold, SheetWordsFit.oneLine, cuts.argb),
        );
      }
      final picture = cover.whereType<SheetImage>().single.slot;
      final pageHeight = book.first.metrics.pageHeight;
      expect(picture.center.dy, closeTo(pageHeight / 2, 1e-9));
      expect(
        (cuts.slot.top + staff.slot.bottom) / 2,
        closeTo((picture.bottom + pageHeight) / 2, 1e-9),
        reason: 'the closing lines in the middle of the room below it',
      );
      // Top to bottom, nothing overlapping.
      expect(title.slot.bottom, lessThanOrEqualTo(episode.slot.top));
      expect(episode.slot.bottom, lessThanOrEqualTo(picture.top));
      expect(picture.bottom, lessThanOrEqualTo(cuts.slot.top));
      expect(cuts.slot.bottom, lessThanOrEqualTo(staff.slot.top));
    });

    test('the blank page prints nothing but its paper', () {
      final blank = contePageMarks(book[1], bookSource);
      expect(
        blank.where((mark) => mark is! SheetInk).map((mark) => mark.layer),
        [SheetPaintLayer.paper],
      );
    });

    test('the body\'s first page is 「1 / N」 though it is the third sheet '
        'of paper', () {
      final body = contePageMarks(book[2], bookSource);
      final number = body.whereType<SheetWords>().firstWhere(
        (word) => word.slot == book[2].metrics.pageNumberSlot,
      );
      expect(number.text, '1 / 1');
    });

    test('the running time reads minutes, seconds and frames', () {
      expect(conteRunningTimeLabel(30004, 24), '20:50+4');
      expect(conteRunningTimeLabel(23, 24), '0:00+23');
      expect(conteRunningTimeLabel(24 * 61 + 12, 24), '1:01+12');
    });
  });

  test('the head prints in the NOTATION language — 内容 · セリフ in Japanese, '
      '내용 · 대사 in Korean, ACTION · DIALOGUE in English', () {
    // 유저 2026-09-25: 「액션/다이얼로그 이런거 고정이아니라 출력용
    // 언어설정있잖아. 그거따르게하고 일본어는 内容, セリフ로 가자. 한국어는
    // 내용 대사, 영어는 액션 다이얼로그」.
    List<String> headIn(ConteNotation notation) => [
      for (final word in contePageMarks(
        page,
        source,
        notation: notation,
      ).whereType<SheetWords>())
        if (word.layer == SheetPaintLayer.form) word.text,
    ];
    expect(headIn(ConteNotation.ja), ['カット', '画面', '内容', 'セリフ', '秒']);
    expect(headIn(ConteNotation.ko), ['컷', '화면', '내용', '대사', '초']);
    expect(headIn(ConteNotation.en), [
      'CUT',
      'PICTURE',
      'ACTION',
      'DIALOGUE',
      'TIME',
    ]);
    for (final language in AppLanguage.values) {
      expect(ConteNotation.of(language).name, language.name);
    }
  });

  test('the words the head prints', () {
    final head = [
      for (final word in words)
        if (word.layer == SheetPaintLayer.form) word.text,
    ];
    expect(head, ['カット', '画面', '内容', 'セリフ', '秒']);
    expect(
      words
          .where((word) => word.layer == SheetPaintLayer.form)
          .every((word) => word.fit == SheetWordsFit.shrink),
      isTrue,
      reason: 'a head word longer than its column is set smaller, not '
          'broken — 「TIME」 over the slim time column',
    );
    for (final word in words.where((w) => w.layer == SheetPaintLayer.form)) {
      expect(
        word.slot,
        predicate<Rect>((slot) => slot.top == m.tableTop),
        reason: 'the head row, above the body',
      );
    }
  });
}
