import 'package:flutter/painting.dart'
    show Color, TextDirection, TextPainter, TextSpan, TextStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_page_marks.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/conte/conte_words.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/sheet_fixed_lines.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/conte/conte_words_in.dart';
import 'package:anicel/src/ui/sheet_painting.dart';

/// 🗣️F-531 (유저 2026-11-01): 「콘티용지패널, 겸용컷일경우 내용란에
/// 고정텍스트로 대상 컷들 적어주기. 겸용 c컷이름. 예를들어 c98, c100, c102가
/// 겸용컷이면 콘티용지패널에서 c98의 칸에는 한국어면 겸용 c100,c102 이런식.
/// 다른 겸용컷 전부 보여줌. 일본어면 兼用 c100,c102. c100의 칸에는 겸용
/// c98,c102 이런식. 해당 컷의 첫번째 패널에만 적어줌」.
void main() {
  const track = TrackId('t');
  final korean = conteWordsIn(AppLanguage.ko);
  final japanese = conteWordsIn(AppLanguage.ja);

  /// A cut [name] of 24 frames whose conte is a block to each of [cells].
  Cut cutNamed(String name, {List<int> cells = const [24]}) {
    final frames = <Frame>[];
    final timeline = <int, TimelineExposure>{};
    var start = 0;
    for (final (index, length) in cells.indexed) {
      final id = FrameId('$name-$index');
      frames.add(Frame(id: id, duration: 1, strokes: const []));
      timeline[start] = TimelineExposure.drawing(id, length: length);
      start += length;
    }
    return Cut(
      id: CutId(name),
      name: name,
      duration: 24,
      canvasSize: const CanvasSize(width: 64, height: 36),
      layers: [
        Layer(
          id: LayerId('$name-sb'),
          name: 'SB',
          kind: LayerKind.storyboard,
          frames: frames,
          timeline: timeline,
        ),
      ],
    );
  }

  /// The project of [cuts], the ones named in [linked] 겸용 together.
  Project projectOf(List<Cut> cuts, {List<String> linked = const []}) =>
      Project(
        id: const ProjectId('linked-conte'),
        name: 'Linked conte',
        createdAt: DateTime.utc(2026, 11, 1),
        tracks: [Track(id: track, name: 'Video', cuts: cuts)],
        linkRegistry: LayerLinkRegistry(
          groups: [
            if (linked.isNotEmpty)
              LayerLinkGroup(
                id: 'g',
                members: [
                  for (final name in linked)
                    LayerLinkMember(
                      trackId: track,
                      cutId: CutId(name),
                      layerId: LayerId('$name-sb'),
                    ),
                ],
              ),
          ],
        ),
      );

  final cuts = [
    for (final name in ['97', '98', '99', '100', '101', '102']) cutNamed(name),
  ];
  const linked = ['98', '100', '102'];

  /// The fixed lines [cutId]'s cell [cellIndex] prints on [project]'s sheet.
  List<String> linesOn(
    Project project,
    String cutId, {
    int cellIndex = 0,
    ConteWords? words,
  }) {
    final source = buildConteSheetSource(project);
    final cell = layoutConteSheet(source)
        .expand((page) => page.cells)
        .firstWhere(
          (each) => each.cutId == cutId && each.cellIndex == cellIndex,
        );
    return cell.source.fixedLines.writtenIn(words ?? korean);
  }

  group('🎯the sheet writes the OTHER cuts of its group', () {
    test('each cut names every other, in the order they stand, comma with '
        'no space', () {
      final project = projectOf(cuts, linked: linked);

      expect(linesOn(project, '98'), contains('겸용 c100,c102'));
      expect(linesOn(project, '100'), contains('겸용 c98,c102'));
      expect(linesOn(project, '102'), contains('겸용 c98,c100'));
    });

    test('whatever order the link holds them in', () {
      final project = projectOf(cuts, linked: const ['102', '98', '100']);

      expect(linesOn(project, '100'), contains('겸용 c98,c102'));
    });

    test('a member no track holds is left out', () {
      final project = projectOf(cuts, linked: const ['98', 'gone', '100']);

      expect(linesOn(project, '98'), contains('겸용 c100'));
    });

    test('in the notation language: 兼用 in Japanese, from the same source', () {
      final project = projectOf(cuts, linked: linked);

      expect(
        linesOn(project, '98', words: japanese),
        contains('兼用 c100,c102'),
      );
    });

    test('a cut linked to none writes nothing, and its neighbours stay out '
        'of the line', () {
      final project = projectOf(cuts, linked: linked);

      expect(linesOn(project, '97'), isEmpty);
      expect(linesOn(project, '101'), isEmpty);
    });

    test('the line follows a rename of the cut it names', () {
      final renamed = [
        for (final cut in cuts)
          if (cut.name == '100') cut.copyWith(name: '100A') else cut,
      ];

      expect(
        linesOn(projectOf(renamed, linked: linked), '98'),
        contains('겸용 c100A,c102'),
      );
    });
  });

  test('🎯only the first panel of the cut writes it — the others print none '
      'and their words stay at the top', () {
    final project = projectOf([
      cutNamed('98', cells: const [8, 8, 8]),
      cutNamed('100'),
    ], linked: const ['98', '100']);
    final source = buildConteSheetSource(project);
    final cells = source.cuts.first.cells;

    expect(cells.map((cell) => cell.fixedLines.linkedCuts), [
      ['c100'],
      isEmpty,
      isEmpty,
    ]);
    expect(linesOn(project, '98'), contains('겸용 c100'));
    expect(linesOn(project, '98', cellIndex: 1), isEmpty);
    expect(linesOn(project, '98', cellIndex: 2), isEmpty);
  });

  group('it is a fixed line of the cell', () {
    const action = 'ハヤト走る';
    const camera = ['FIX (0+5)', 'PAN (0+11)'];
    const transitions = ['c1 × c2 カットO.L (0+12)'];

    ConteSheetSource sourceOf({
      SheetFixedLines lines = const SheetFixedLines(
        camera: camera,
        transitions: transitions,
        linkedCuts: ['c100', 'c102'],
      ),
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
              fixedLines: lines,
            ),
          ],
        ),
      ],
    );

    test('it stands under the camera and the transitions, a line of its '
        'own, and the typed words begin under it', () {
      final source = sourceOf();
      final page = layoutConteSheet(source).single;
      final cell = page.cells.single;
      final words = contePageMarks(
        page,
        source,
        words: korean,
      ).whereType<SheetWords>().toList();
      final slot = cell.actionRect.deflate(4);
      const line = conteCellTextSize * conteLineHeight;

      expect(cell.source.fixedLines.writtenIn(korean), [
        ...camera,
        ...transitions,
        '겸용 c100,c102',
      ]);
      expect(
        words.singleWhere((each) => each.text == '겸용 c100,c102').slot.top,
        closeTo(slot.top + 3 * line, 1e-9),
      );
      expect(
        conteActionWordsDrop(cell, words: korean),
        closeTo(4 * line, 1e-9),
      );
      expect(
        words.singleWhere((each) => each.text == action).slot.top,
        closeTo(slot.top + 4 * line, 1e-9),
      );
    });

    test('taken out of the sheet with the others, the words are back at the '
        'top', () {
      final source = sourceOf(lines: SheetFixedLines.none);
      final page = layoutConteSheet(source).single;
      final cell = page.cells.single;

      expect(cell.source.fixedLines.writtenIn(korean), isEmpty);
      expect(conteActionWordsDrop(cell, words: korean), 0);
      expect(
        contePageMarks(
          page,
          source,
          words: korean,
        ).whereType<SheetWords>().where((each) => each.text.contains('겸용')),
        isEmpty,
      );
    });
  });

  group('🎯「다른 겸용컷 전부 보여줌」: a long line is never cut off', () {
    TextStyle style(double size, {required bool bold, required Color color}) =>
        TextStyle(fontSize: size, color: color);

    /// The printed line of a cut 겸용 with [others].
    SheetWords lineNaming(List<String> others) {
      final source = ConteSheetSource(
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
                fixedLines: SheetFixedLines(linkedCuts: others),
              ),
            ],
          ),
        ],
      );
      final page = layoutConteSheet(source).single;
      return contePageMarks(
        page,
        source,
        words: korean,
      ).whereType<SheetWords>().singleWhere((each) => each.text.contains('겸용'));
    }

    double widthOf(SheetWords mark, double size) {
      final painter = TextPainter(
        text: TextSpan(text: mark.text, style: TextStyle(fontSize: size)),
        textDirection: TextDirection.ltr,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    testWidgets('it prints smaller, whole, on its one line', (tester) async {
      final mark = lineNaming([for (var cut = 0; cut < 60; cut++) 'c$cut']);
      final size = sheetWordsSize(mark, style);

      expect(size, lessThan(mark.size));
      expect(widthOf(mark, size), lessThanOrEqualTo(mark.slot.width));
      expect(mark.text, endsWith('c58,c59'));
    });

    testWidgets('a short one keeps the size of the words typed there', (
      tester,
    ) async {
      final mark = lineNaming(const ['c100']);

      expect(sheetWordsSize(mark, style), conteCellTextSize);
    });
  });

  test('two sets of words apart only in it are not the same words', () {
    ConteWords saying(
      String linked, {
      String cutHead = 'h',
      String cutTail = 't',
      String wholeCut = 'w',
    }) => ConteWords(
      cut: 'c',
      picture: 'p',
      action: 'a',
      dialogue: 'd',
      seconds: 's',
      cutsSuffix: 'x',
      artist: 'r',
      linked: linked,
      cutHead: cutHead,
      cutTail: cutTail,
      wholeCut: wholeCut,
    );

    expect(saying('겸용'), isNot(saying('兼用')));
    expect(saying('겸용'), isNot(saying('겸용', wholeCut: '全尺')));
    expect(saying('겸용'), saying('겸용'));
    expect(saying('겸용'), isNot(saying('겸용', cutHead: '컷 앞')));
    expect(saying('겸용'), isNot(saying('겸용', cutTail: '컷 뒤')));
  });

  test('every language has its word', () {
    for (final language in AppLanguage.values) {
      final words = conteWordsIn(language);
      expect(words.linked, isNotEmpty, reason: '$language');
      expect(words.cutHead, isNotEmpty, reason: '$language');
      expect(words.cutTail, isNotEmpty, reason: '$language');
    }
    expect(korean.linked, '겸용');
    expect(japanese.linked, '兼用');
    expect(korean, isNot(japanese));
  });
}
