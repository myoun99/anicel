import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/storyboard_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/camera_key_names.dart';

/// 🗣️I-93 (유저 2026-10-12): 「콘티용지패널 내용란에 고정텍스트로 PAN이나
/// TU나 추가로 콘티엔 시간정보가 같은 칸내에선 없으니 FIX부분 도 … 예를들어
/// 1f부터 5f까지 키가 없고, 6f에 키가있고, 16f에 작아지는 키가 있고, 24f가
/// 컷의 끝이라면, FIX (0+5), PAN (0+11), FIX (0+8) 이런식 … 각 FIX PAN
/// 이런거마다 개행되고」 — what the camera does while a conte cell is on,
/// a line to each move and each stretch it stands still, in the cell's
/// own frames.
///
/// 🗣️I-93 (유저 2026-10-30): 「패널에서 카메라 아무것도 안했으면 안적는다」 ·
/// 「액션쪽도 카메라레이어 움직임인거니까 그거 시트off되면 사라지게」 ·
/// 「컷ol처럼 이런거 대상도 적도록. 픽스는 예외. 1f-5f T.U 이런식. 이름있으면
/// A-B T.U가 되겟고」.
///
/// 🗣️F-622 (유저 2026-11-19): 「컷 양 끝에 걸쳐 키가 하나씩 있으면
/// 타임시트용지패널이랑 똑같이 대상-대상 T.B (全尺) … 패널이 2개이상이면 …
/// 첫번째패널은 1f-73f T.B (해당 길이) 두번째는 74f-144f (해당길이)」 ·
/// 「패널마다 전체라고 쓰면안됨」.
void main() {
  CameraPose at(double x, {double zoom = 1, double turn = 0}) => CameraPose(
    center: CanvasPoint(x: x, y: 0),
    zoom: zoom,
    rotationDegrees: turn,
  );

  CutCamera called(CutCamera camera, int frame, String name) =>
      cameraKeyNamed(
        camera,
        frame,
        position: name,
        scale: name,
        rotation: name,
      );

  /// A work of one cut — one block to each of [lengths], in order, the cut
  /// as long as they are together — whose camera is keyed [keys] and named
  /// as [named] names it.
  Project workOf(
    Map<int, CameraPose> keys, {
    List<int> lengths = const [24],
    bool bypassed = false,
    bool onSheet = true,
    CameraInstructionSet? glossary,
    CutCamera Function(CutCamera camera)? named,
  }) {
    final keyed = CutCamera(keyframes: keys);
    final camera = named?.call(keyed) ?? keyed;
    final frames = <Frame>[];
    final timeline = <int, TimelineExposure>{};
    var start = 0;
    for (final (index, length) in lengths.indexed) {
      final id = FrameId('f$index');
      frames.add(Frame(id: id, duration: 1, strokes: const []));
      timeline[start] = TimelineExposure.drawing(id, length: length);
      start += length;
    }
    final project = Project(
      id: const ProjectId('camera-lines'),
      name: 'Camera lines',
      createdAt: DateTime.utc(2026, 10, 30),
      cameraInstructions: glossary,
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Video',
          cuts: [
            Cut(
              id: const CutId('c'),
              name: '1',
              duration: lengths.fold(0, (sum, length) => sum + length),
              canvasSize: const CanvasSize(width: 640, height: 360),
              camera: camera,
              layers: [
                Layer(
                  id: const LayerId('sb'),
                  name: 'SB',
                  kind: LayerKind.storyboard,
                  frames: frames,
                  timeline: timeline,
                ),
                Layer(
                  id: const LayerId('camera'),
                  name: 'Camera',
                  kind: LayerKind.camera,
                  frames: const [],
                  timeline: const {},
                  transformEnabled: !bypassed,
                  onTimesheet: onSheet,
                ),
              ],
            ),
          ],
        ),
      ],
    );
    return project;
  }

  /// The lines each cell of [work]'s cut writes, in [words].
  List<List<String>> linesIn(
    Project work, {
    PaperWords words = (ol: 'O.L', wholeCut: '全尺'),
  }) => [
    for (final cell in buildConteSheetSource(
      work,
      words: words,
    ).cuts.single.cells)
      cell.fixedLines.camera,
  ];

  /// The lines each cell writes of [workOf]'s work.
  List<List<String>> linesOf(
    Map<int, CameraPose> keys, {
    List<int> lengths = const [24],
    bool bypassed = false,
    bool onSheet = true,
    CameraInstructionSet? glossary,
    CutCamera Function(CutCamera camera)? named,
  }) => linesIn(
    workOf(
      keys,
      lengths: lengths,
      bypassed: bypassed,
      onSheet: onSheet,
      glossary: glossary,
      named: named,
    ),
  );

  test('🎯the user\'s example: no key 1f to 5f, a key on 6f and on 16f, the '
      'cut ending on 24f — FIX (0+5), 6f-16f PAN (0+11), FIX (0+8)', () {
    // The 16f key the user called 「작아지는」 moves the camera here: the
    // rule settled on 10-08 calls a zoom T.U or T.B, and the user wrote PAN.
    expect(linesOf({5: at(0), 15: at(40)}), [
      ['FIX (0+5)', '6f-16f PAN (0+11)', 'FIX (0+8)'],
    ]);
  });

  test('🎯a move names the two keys it runs between, by their names where '
      'they have them — 「1f-5f T.U 이런식. 이름있으면 A-B T.U」 — and a FIX '
      'names none', () {
    final keys = {0: at(0), 4: at(0, zoom: 2)};

    expect(linesOf(keys), [
      ['1f-5f T.U (0+5)', 'FIX (0+19)'],
    ]);
    expect(
      linesOf(keys, named: (camera) => called(called(camera, 0, 'A'), 4, 'B')),
      [
        ['A-B T.U (0+5)', 'FIX (0+19)'],
      ],
    );
    expect(linesOf(keys, named: (camera) => called(camera, 4, 'B')), [
      ['1f-B T.U (0+5)', 'FIX (0+19)'],
    ]);
  });

  test('a key whose lanes disagree on its name is called by its frame, as '
      'on every surface', () {
    final lines = linesOf(
      {0: at(0), 4: at(0, zoom: 2)},
      named: (camera) => cameraKeyNamed(
        camera,
        4,
        position: 'B',
        scale: 'C',
        rotation: 'B',
      ),
    );

    expect(lines, [
      ['1f-5f T.U (0+5)', 'FIX (0+19)'],
    ]);
  });

  test('🎯a move two panels share is a line in each, as long as each holds '
      'it — named by the part it holds: a key where it holds one, else its '
      'own first or last frame (F-622 — ↩️each named the move\'s two keys)',
      () {
    expect(linesOf({6: at(0), 18: at(40)}, lengths: const [12, 12]), [
      ['FIX (0+6)', '7f-12f PAN (0+6)'],
      ['13f-19f PAN (0+7)', 'FIX (0+5)'],
    ]);
  });

  test('🎯the user\'s example: keys on the cut\'s two ends, its panels '
      'ending on 73f and 144f — 1f-73f T.B, 74f-144f T.B, each with its '
      'length (「지시명 빠진건 그냥 줄임이야」)', () {
    expect(
      linesOf({0: at(0), 143: at(0, zoom: 0.5)}, lengths: const [73, 71]),
      [
        ['1f-73f T.B (3+1)'],
        ['74f-144f T.B (2+23)'],
      ],
    );
  });

  test('a move whose last key stands on the next panel\'s first frame: the '
      'panel before writes up to its own last frame, and the next holds the '
      'key — the frame a move ends on is its own (I-93)', () {
    expect(linesOf({0: at(0), 12: at(40)}, lengths: const [12, 12]), [
      ['1f-12f PAN (0+12)'],
      ['13f-13f PAN (0+1)', 'FIX (0+11)'],
    ]);
  });

  test('a part keeps the names of the keys it holds, and a frame names the '
      'end it does not', () {
    expect(
      linesOf(
        {0: at(0), 23: at(40)},
        lengths: const [12, 12],
        named: (camera) => called(called(camera, 0, 'A'), 23, 'B'),
      ),
      [
        ['A-12f PAN (0+12)'],
        ['13f-B PAN (0+12)'],
      ],
    );
  });

  group('🎯(全尺): a cut of one panel and a move from its first frame to its '
      'last writes it as its timesheet does — (全尺) for its length', () {
    test('says so, by the keys\' names where they have them', () {
      expect(linesOf({0: at(0), 143: at(0, zoom: 0.5)}, lengths: const [144]), [
        ['1f-144f T.B (全尺)'],
      ]);
      expect(
        linesOf(
          {0: at(0), 23: at(40)},
          named: (camera) => called(called(camera, 0, 'A'), 23, 'B'),
        ),
        [
          ['A-B PAN (全尺)'],
        ],
      );
    });

    test('in the paper\'s word, read again when the paper\'s words change',
        () {
      final work = workOf({0: at(0), 23: at(40)});

      expect(linesIn(work), [
        ['1f-24f PAN (全尺)'],
      ]);
      expect(linesIn(work, words: (ol: 'O.L', wholeCut: 'Full cut')), [
        ['1f-24f PAN (Full cut)'],
      ]);
    });

    test('⛔short of either end does not: its length, as before', () {
      expect(linesOf({1: at(0), 23: at(40)}), [
        ['FIX (0+1)', '2f-24f PAN (0+23)'],
      ]);
      expect(linesOf({0: at(0), 22: at(40)}), [
        ['1f-23f PAN (0+23)', 'FIX (0+1)'],
      ]);
    });

    test('⛔two moves that meet are not one', () {
      expect(linesOf({0: at(0), 12: at(40), 23: at(0)}), [
        ['1f-13f PAN (0+12)', '13f-24f PAN (0+12)'],
      ]);
    });

    test('⛔never on a panel — 「패널마다 전체라고 쓰면안됨」: the cut of '
        'more than one writes the part each holds, each panel the move fills '
        'that move alone', () {
      expect(linesOf({0: at(0), 23: at(40)}, lengths: const [8, 8, 8]), [
        ['1f-8f PAN (0+8)'],
        ['9f-16f PAN (0+8)'],
        ['17f-24f PAN (0+8)'],
      ]);
    });
  });

  test('🎯a panel the camera does nothing in writes nothing, and the panel '
      'the move is in writes it where it stands', () {
    expect(linesOf({14: at(0), 20: at(40)}, lengths: const [12, 12]), [
      <String>[],
      ['FIX (0+2)', '15f-21f PAN (0+7)', 'FIX (0+3)'],
    ]);
  });

  // 🗣️I-93-Q2 (유저 2026-10-30): 「안 적는다 — 아무것도 안 한 패널은 언제나
  // 빈칸」.
  test('a move that ends on the last frame of its panel leaves the panel '
      'after it blank, and one that starts on the first of a panel the '
      'panel before it', () {
    expect(linesOf({0: at(0), 11: at(40)}, lengths: const [12, 12]), [
      ['1f-12f PAN (0+12)'],
      <String>[],
    ]);
    expect(linesOf({12: at(0), 23: at(40)}, lengths: const [12, 12]), [
      <String>[],
      ['13f-24f PAN (0+12)'],
    ]);
  });

  test('a move that starts where another ends takes the key they share — '
      'the lines add up to the cut', () {
    expect(
      linesOf({0: at(0), 10: at(0, zoom: 2), 20: at(50, zoom: 2)}),
      [
        ['1f-11f T.U (0+10)', '11f-21f PAN (0+11)', 'FIX (0+3)'],
      ],
    );
  });

  test('the turn writes 回転, before the T.U · T.B · PAN it changes along '
      'with (I-89: 「회전은 모아트기준대로」)', () {
    expect(
      linesOf({
        0: at(0),
        8: at(0, turn: 20),
        16: at(0, zoom: 0.5, turn: 40),
      }),
      [
        ['1f-9f 回転 (0+8)', '9f-17f 回転 T.B (0+9)', 'FIX (0+7)'],
      ],
    );
  });

  test('every word is the project\'s glossary\'s: a FIX renamed there is '
      'written renamed', () {
    final renamed = CameraInstructionSet(
      defs: [
        for (final def in CameraInstructionSet.standard.defs)
          if (def.id == 'fix')
            const CameraInstructionDef(id: 'fix', name: '止め', iconKey: 'fix')
          else
            def,
      ],
    );

    expect(linesOf({5: at(0), 15: at(40)}, glossary: renamed), [
      ['止め (0+5)', '6f-16f PAN (0+11)', '止め (0+8)'],
    ]);
  });

  test('a camera with no key, one key, keys that hold one pose, or its work '
      'bypassed stands still: nothing is written', () {
    const blank = [<String>[]];
    expect(linesOf(const {}), blank, reason: 'no key');
    expect(linesOf({7: at(30)}), blank, reason: 'one key');
    expect(linesOf({5: at(9), 15: at(9)}), blank, reason: 'one pose');
    expect(
      linesOf({5: at(0), 15: at(40)}, bypassed: true),
      blank,
      reason: 'the camera row switched off',
    );
  });

  test('a camera off the sheet writes nothing, however it moves — the law '
      'of an SE row (F-345)', () {
    expect(linesOf({5: at(0), 15: at(40)}, onSheet: false), [<String>[]]);
    expect(
      linesOf({5: at(0), 15: at(40)}, lengths: const [12, 12], onSheet: false),
      [<String>[], <String>[]],
    );
  });

  test('a cut an O.L arrives into counts its camera from the のりしろ: a '
      'panel writes the camera over the cut\'s frames it shows (F-227)', () {
    // The O.L margin fixture: two 48-frame cuts, each a two-panel conte
    // (20 + 28), and a 24-frame O.L on their boundary — 12 frames of
    // のりしろ before the receiving cut's conte.
    Layer conte(String cut) => Layer(
      id: LayerId('conte-$cut'),
      name: 'conte',
      kind: LayerKind.storyboard,
      frames: [
        Frame(id: FrameId('$cut-p1'), duration: 1, strokes: const []),
        Frame(id: FrameId('$cut-p2'), duration: 1, strokes: const []),
      ],
      timeline: {
        0: TimelineExposure.drawing(FrameId('$cut-p1'), length: 20),
        20: TimelineExposure.drawing(FrameId('$cut-p2'), length: 28),
      },
    );
    Cut cut(String id, {CutCamera? camera}) => Cut(
      id: CutId(id),
      name: id,
      duration: 48,
      canvasSize: const CanvasSize(width: 64, height: 36),
      camera: camera,
      layers: [conte(id)],
    );
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'T',
            cuts: [
              cut('a'),
              // A PAN from the conte's first frame, 10 frames on.
              cut('b', camera: CutCamera(keyframes: {12: at(0), 22: at(9)})),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    session.transitions.updateTransitionInstructions({
      36: const InstructionEvent(instructionId: 'ol', length: 24),
    });
    final project = session.repository.requireProject();
    final receiving = project.tracks.single.cuts.last;
    expect(
      storyboardConteStart(
        receiving.layers
            .firstWhere((layer) => layer.kind == LayerKind.storyboard)
            .timeline,
      ),
      12,
      reason: 'fixture: the conte begins 12 frames into the cut',
    );

    expect(
      [
        for (final cell in buildConteSheetSource(project).cuts.last.cells)
          cell.fixedLines.camera,
      ],
      [
        ['13f-23f PAN (0+11)', 'FIX (0+9)'],
        <String>[],
      ],
    );
  });

  test('🎯(全尺) counts the のりしろ an O.L asks before the conte, as the '
      'sheet counts its rows: a move from the cut\'s first frame to its last '
      'is the one that says so, not one over the conte alone', () {
    // Two 48-frame cuts of one panel each and a 24-frame O.L on their
    // boundary: the second is drawn for 60 frames, 12 of のりしろ first.
    List<String> secondsLines(Map<int, CameraPose> keys) {
      Cut cut(String id, {CutCamera? camera}) => Cut(
        id: CutId(id),
        name: id,
        duration: 48,
        canvasSize: const CanvasSize(width: 64, height: 36),
        camera: camera,
        layers: [
          Layer(
            id: LayerId('conte-$id'),
            name: 'conte',
            kind: LayerKind.storyboard,
            frames: [
              Frame(id: FrameId('$id-p'), duration: 1, strokes: const []),
            ],
            timeline: {
              0: TimelineExposure.drawing(FrameId('$id-p'), length: 48),
            },
          ),
        ],
      );
      final session = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('p'),
          name: 'P',
          createdAt: DateTime.utc(2026),
          tracks: [
            Track(
              id: const TrackId('t'),
              name: 'T',
              cuts: [
                cut('a'),
                cut('b', camera: CutCamera(keyframes: keys)),
              ],
            ),
          ],
        ),
      );
      addTearDown(session.dispose);
      session.transitions.updateTransitionInstructions({
        36: const InstructionEvent(instructionId: 'ol', length: 24),
      });
      return buildConteSheetSource(
        session.repository.requireProject(),
        words: (ol: 'O.L', wholeCut: '全尺'),
      ).cuts.last.cells.single.fixedLines.camera;
    }

    expect(secondsLines({0: at(0), 59: at(9)}), ['1f-60f PAN (全尺)']);
    expect(
      secondsLines({12: at(0), 59: at(9)}),
      ['13f-60f PAN (2+0)'],
      reason: 'the conte\'s frames alone, short of the のりしろ',
    );
  });
}
