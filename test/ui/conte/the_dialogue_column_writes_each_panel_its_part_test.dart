import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/se_dialogue_spacing.dart';
import 'package:anicel/src/models/se_line_type.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';

/// 🗣️F-501 (유저 2026-10-29): 「콘티용지패널에 들어가는 se는 컷별로
/// 구분하는게 아니라 통일해서 패널별로 … 컷1 패널에 이름「ab / 컷2 패널에
/// cd」 즉 이어지면 앞의 이름이랑 대사 표시 글자가 안적힘 … 컷1 패널1
/// 이름「a / 컷1 패널2 b / 컷2 패널1 c / 컷2 패널2 d」 … 글자가 위치할때만임.
/// 만약 블록 자체가 이어져있는데 해당 패널의 부분에만 띄어쓰기같은거로 인해
/// 글자가 없으면 안적히고, 다음 패널에서 이름「 이게 다시 들어감」.
///
/// Read off the sheet's builder: what each cut's dialogue column writes, as
/// (the frame it stands on, what it prints).
void main() {
  /// A cut of [duration] frames, its storyboard row divided at [divisions].
  Cut cut(String id, List<int> divisions, {int duration = 12}) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      Layer(
        id: LayerId('$id-sb'),
        name: 'SB',
        kind: LayerKind.storyboard,
        frames: [
          for (final start in divisions)
            Frame(id: FrameId('$id-$start'), duration: 1, strokes: const []),
        ],
        timeline: {
          for (final (index, start) in divisions.indexed)
            start: TimelineExposure.drawing(
              FrameId('$id-$start'),
              length:
                  (index + 1 < divisions.length
                      ? divisions[index + 1]
                      : duration) -
                  start,
            ),
        },
      ),
    ],
  );

  /// What each of two cuts' dialogue columns writes of one line over all 24
  /// of their frames, six frames a glyph: glyph `i` stands on frame `6i`.
  List<List<(int, String)>> written(
    String line, {
    required List<int> panels,
    String speaker = 'A子',
    SeLineTypes seTypes = SeLineTypes.allOn,
  }) {
    final project = Project(
      id: const ProjectId('p'),
      name: 'P',
      createdAt: DateTime.utc(2026, 10, 29),
      tracks: [
        Track(
          id: const TrackId('t'),
          name: 'V',
          cuts: [cut('c1', panels), cut('c2', panels)],
          seLayers: [
            Layer(
              id: const LayerId('se'),
              name: 'S1',
              kind: LayerKind.se,
              frames: [
                Frame(
                  id: const FrameId('se-f'),
                  duration: 24,
                  strokes: const [],
                  name: line,
                  seName: speaker,
                  seTypes: seTypes,
                  seSpacing: const SeDialogueSpacing(komaPerGlyph: 6),
                ),
              ],
              timeline: {
                0: const TimelineExposure.drawing(FrameId('se-f'), length: 24),
              },
            ),
          ],
        ),
      ],
    );
    return [
      for (final source in buildConteSheetSource(project).cuts)
        [for (final part in source.dialogue) (part.startFrame, part.printed)],
    ];
  }

  test('one panel a cut: the first writes the speaker and the words on its '
      'frames, the next carries on with the rest', () {
    expect(written('abcd', panels: [0]), [
      [(0, 'A子「ab')],
      [(0, 'cd」')],
    ], reason: '↩️both cuts wrote A子「abcd」');
  });

  test('two panels a cut: each panel its glyph, the speaker once, the line '
      'closed once', () {
    expect(written('abcd', panels: [0, 6]), [
      [(0, 'A子「a'), (6, 'b')],
      [(0, 'c'), (6, 'd」')],
    ]);
  });

  test('a panel the line has no glyph on — a space — writes nothing, and '
      'the next one with a glyph speaks again', () {
    expect(written('a bc', panels: [0, 6]), [
      [(0, 'A子「a」')],
      [(0, 'A子「b'), (6, 'c」')],
    ]);
  });

  test('a speaker\'s delivery opens where the speaker is written, in the '
      'cut of the panel that writes it', () {
    expect(
      written(
        'a bc',
        panels: [0, 6],
        seTypes: SeLineTypes(byCut: {const CutId('c2'): SeLineType.off}),
      ),
      [
        [(0, 'A子「a」')],
        [(0, 'A子(OFF)「b'), (6, 'c」')],
      ],
    );
  });

  test('a track\'s last panel has none after it on the next track — the '
      'line closes there', () {
    Track track(String id, Cut cut, List<Layer> se) =>
        Track(id: TrackId(id), name: id, cuts: [cut], seLayers: se);
    final line = Layer(
      id: const LayerId('se'),
      name: 'S1',
      kind: LayerKind.se,
      frames: [
        Frame(
          id: const FrameId('se-f'),
          duration: 12,
          strokes: const [],
          name: 'ab',
          seName: 'A子',
          seSpacing: const SeDialogueSpacing(komaPerGlyph: 6),
        ),
      ],
      timeline: {
        0: const TimelineExposure.drawing(FrameId('se-f'), length: 12),
      },
    );
    // The next track's one cut runs longer: its panel holds the frame the
    // first track's ends on.
    final longer = cut('c2', [0], duration: 24);
    final project = Project(
      id: const ProjectId('p'),
      name: 'P',
      createdAt: DateTime.utc(2026, 10, 29),
      tracks: [
        track('t1', cut('c1', [0]), [line]),
        track('t2', longer, [line]),
      ],
    );
    expect(
      buildConteSheetSource(project).cuts.first.dialogue.single.printed,
      'A子「ab」',
    );
  });

  Project oneLine(
    List<Cut> cuts, {
    required int length,
    required String line,
  }) => Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026, 10, 29),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'V',
            cuts: cuts,
            seLayers: [
              Layer(
                id: const LayerId('se'),
                name: 'S1',
                kind: LayerKind.se,
                frames: [
                  Frame(
                    id: const FrameId('se-f'),
                    duration: length,
                    strokes: const [],
                    name: line,
                    seName: 'A子',
                    seSpacing: const SeDialogueSpacing(komaPerGlyph: 6),
                  ),
                ],
                timeline: {
                  0: TimelineExposure.drawing(
                    const FrameId('se-f'),
                    length: length,
                  ),
                },
              ),
            ],
          ),
        ],
      );
  List<List<(int, String)>> partsOf(Project project) => [
    for (final source in buildConteSheetSource(project).cuts)
      [for (final part in source.dialogue) (part.startFrame, part.printed)],
  ];

  test('a gap between two cuts is no panel: the line closes before it and '
      'speaks again after it', () {
    // c → frame 12, in the six frames between the cuts: no panel writes it.
    final project = oneLine(
      [cut('c1', [0]), cut('c2', [0]).copyWith(leadingGapFrames: 6)],
      length: 30,
      line: 'abcd',
    );
    expect(partsOf(project), [
      [(0, 'A子「ab」')],
      [(0, 'A子「d」')],
    ]);
  });

  test('a glyph sharing a frame stands in the panel holding its centre — '
      'where its frame begins in the panel before', () {
    // Five glyphs in four frames: 0.8 a glyph, centres 0.4, 1.2, 2.0 … —
    // the third begins at 1.6, in the first panel, centred in the second.
    final project = oneLine(
      [cut('c1', [0, 2])],
      length: 4,
      line: 'abcde',
    );
    expect(partsOf(project), [
      [(0, 'A子「ab'), (2, 'cde」')],
    ]);
  });

  test('an unnamed line prints its parts bare', () {
    expect(written('abcd', panels: [0, 6], speaker: ''), [
      [(0, 'a'), (6, 'b')],
      [(0, 'c'), (6, 'd')],
    ]);
  });
}
