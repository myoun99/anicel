import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🗣️I-93 (유저 2026-10-12): 「컷OL이나 FO같은 트랜지션레이어도
/// 고정텍스트」 · I-93-Q1 (10-30): 「앞 컷에만, 전체 길이로」 + 「대상도
/// 적어주는거 잊지말고. c1 c2 カットO.L (1+0) 이런식. 컷이름사이에 ol처럼
/// 보이는 특수문자 넣으면 좋고」 — a cut's ACTION column writes the
/// transitions written on it under its camera lines: an O.L on the last
/// cell of the cut it leaves, the two cuts crossed and its whole length.
/// 🗣️F-540 (유저 2026-11-02): 「FI나 FO같은건 컷 앞이랑 뒤에 고정적으로
/// 붙는것임」 — a fade on its cut's first cell or its last, whichever end its
/// side says.
void main() {
  const olWord = 'カットO.L';

  /// A cut [name] of 24 frames whose conte is a block to each of [cells].
  Cut cut(String name, {List<int> cells = const [24]}) {
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

  /// The cells of each cut — cuts `1` (two cells, 12 and 12) and `2` on
  /// frames 0–23 and 24–47 — under [transitions] on the track's axis.
  List<List<ConteCellSource>> cellsOf(
    Map<int, InstructionEvent> transitions, {
    String? word = olWord,
  }) {
    final bare = Track(
      id: const TrackId('t'),
      name: 'Video',
      cuts: [
        cut('1', cells: const [12, 12]),
        cut('2'),
      ],
    );
    final project = Project(
      id: const ProjectId('transition-lines'),
      name: 'Transition lines',
      createdAt: DateTime.utc(2026, 10, 30),
      tracks: [
        bare.copyWith(
          transitionLayer: bare.transitionLayer.copyWith(
            instructions: transitions,
          ),
        ),
      ],
    );
    return [
      for (final cut in buildConteSheetSource(project, olWord: word).cuts)
        cut.cells,
    ];
  }

  /// The join lines each cell of each cut writes.
  List<List<List<String>>> linesOf(
    Map<int, InstructionEvent> transitions, {
    String? word = olWord,
  }) => [
    for (final cells in cellsOf(transitions, word: word))
      [for (final cell in cells) cell.transitionLines],
  ];

  /// The head lines each cell of each cut writes.
  List<List<List<String>>> headsOf(Map<int, InstructionEvent> transitions) => [
    for (final cells in cellsOf(transitions))
      [for (final cell in cells) cell.cutHeadLines],
  ];

  /// The tail lines each cell of each cut writes.
  List<List<List<String>>> tailsOf(Map<int, InstructionEvent> transitions) => [
    for (final cells in cellsOf(transitions))
      [for (final cell in cells) cell.cutTailLines],
  ];

  test('🎯an O.L is written on the last cell of the cut it leaves — the two '
      'cuts crossed, its word and its whole length — and not on the cut it '
      'enters', () {
    expect(
      linesOf({18: const InstructionEvent(instructionId: 'ol', length: 12)}),
      [
        [
          <String>[],
          ['c1 × c2 カットO.L (0+12)'],
        ],
        [<String>[]],
      ],
    );
  });

  test('🎯a fade in is written on its cut\'s head, a fade out on its tail: '
      "the first cell and the last, its term's name and its length, wherever "
      'in the cut it starts', () {
    final fades = {
      0: const InstructionEvent(instructionId: 'fi', length: 6),
      40: const InstructionEvent(instructionId: 'fo', length: 8),
      8: const InstructionEvent(instructionId: 'wo', length: 2),
    };
    expect(headsOf(fades), [
      [
        ['FI (0+6)'],
        <String>[],
      ],
      [<String>[]],
    ]);
    expect(tailsOf(fades), [
      [
        <String>[],
        ['WO (0+2)'],
      ],
      [
        ['FO (0+8)'],
      ],
    ]);
    expect(
      linesOf(fades).expand((cut) => cut).expand((cell) => cell),
      isEmpty,
      reason: 'a fade joins no cuts',
    );
  });

  test('on a cut of one cell, both ends are that cell\'s', () {
    final fades = {
      24: const InstructionEvent(instructionId: 'fi', length: 6),
      40: const InstructionEvent(instructionId: 'fo', length: 8),
    };
    expect(headsOf(fades).last.single, ['FI (0+6)']);
    expect(tailsOf(fades).last.single, ['FO (0+8)']);
  });

  test('a fade reaching past its own cut applies to none, and none writes '
      'it — as the sheet prints none', () {
    final none = [
      [<String>[], <String>[]],
      [<String>[]],
    ];
    for (final term in ['fo', 'wi']) {
      final past = {20: InstructionEvent(instructionId: term, length: 8)};
      expect(headsOf(past), none, reason: term);
      expect(tailsOf(past), none, reason: term);
    }
  });

  test('two on one end are written in the order they start', () {
    expect(
      headsOf({
        8: const InstructionEvent(instructionId: 'fi', length: 2),
        2: const InstructionEvent(instructionId: 'wi', length: 2),
      })[0][0],
      ['WI (0+2)', 'FI (0+2)'],
    );
  });

  test("with no word given, an O.L is the program's word", () {
    expect(
      linesOf({
        18: const InstructionEvent(instructionId: 'ol', length: 12),
      }, word: null)[0][1],
      ['c1 × c2 ${AppText.strings.tlTransitionCutOl} (0+12)'],
    );
  });
}
