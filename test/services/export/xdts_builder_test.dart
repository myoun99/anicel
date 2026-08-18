import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/export/xdts_builder.dart';

Cut _cut() {
  return Cut(
    id: const CutId('xdts-cut'),
    name: 'Cut 3',
    duration: 12,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      Layer(
        id: const LayerId('cel-a'),
        name: 'A',
        frames: [
          Frame(
            id: const FrameId('a1'),
            duration: 3,
            name: 'A1',
            strokes: const [],
          ),
          Frame(id: const FrameId('a2'), duration: 4, strokes: const []),
        ],
        timeline: {
          // A1 at 0..3, gap at 3..5, unnamed second frame at 5..9, empty on.
          0: const TimelineExposure.drawing(FrameId('a1'), length: 3),
          5: const TimelineExposure.drawing(FrameId('a2'), length: 4),
        },
      ),
      Layer(
        id: const LayerId('cel-hidden'),
        name: 'Hidden',
        frames: const [],
        timeline: const {},
        onTimesheet: false,
      ),
      Layer(
        id: const LayerId('se-1'),
        name: 'S1',
        kind: LayerKind.se,
        frames: [
          Frame(
            id: const FrameId('se-f'),
            duration: 4,
            name: 'こんにちは',
            strokes: const [],
          ),
        ],
        timeline: {
          // Starts past frame 0 → a leading SYMBOL_NULL_CELL entry.
          2: const TimelineExposure.drawing(FrameId('se-f'), length: 4),
        },
      ),
      Layer(
        id: const LayerId('cam-inst'),
        name: 'CAM 1',
        kind: LayerKind.instruction,
        frames: const [],
        timeline: const {},
        instructions: SplayTreeMap.of({
          0: const InstructionEvent(
            instructionId: 'pan',
            length: 6,
            valueA: 'A',
            valueB: 'B',
          ),
          8: const InstructionEvent(
            instructionId: 'fi',
            length: 4,
            text: 'ゆっくりFI',
          ),
        }),
      ),
    ],
  );
}

void main() {
  test('XDTS content: identifier line + spec-shaped JSON with CELL/DIALOG/'
      'CAMERAWORK fields', () {
    final content = buildXdtsContent(
      cut: _cut(),
      cutLabel: '3',
      instructionDefById: CameraInstructionSet.standard.defById,
    );

    final lines = content.split('\n');
    expect(lines.first, 'exchangeDigitalTimeSheet Save Data');

    final json = jsonDecode(lines.skip(1).join('\n')) as Map<String, dynamic>;
    expect(json['version'], 5);
    expect(json['header'], {'cut': '3', 'scene': '1'});

    final timeTable =
        (json['timeTables'] as List<dynamic>).single as Map<String, dynamic>;
    expect(timeTable['duration'], 12);
    expect(timeTable['name'], 'Cut 3');

    final headers = (timeTable['timeTableHeaders'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(headers, hasLength(3));
    // Hidden (onTimesheet=false) cels stay off the sheet.
    expect(headers[0], {
      'fieldId': 0,
      'names': ['A'],
    });
    expect(headers[1], {
      'fieldId': 3,
      'names': ['S1'],
    });
    expect(headers[2], {
      'fieldId': 5,
      'names': ['CAM 1'],
    });

    final fields = (timeTable['fields'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    Map<String, dynamic> fieldById(int id) =>
        fields.firstWhere((field) => field['fieldId'] == id);
    List<dynamic> trackFrames(int fieldId) =>
        ((fieldById(fieldId)['tracks'] as List<dynamic>).single
                as Map<String, dynamic>)['frames']
            as List<dynamic>;
    (int, String) frameValue(Map<String, dynamic> entry) => (
      entry['frame'] as int,
      (((entry['data'] as List<dynamic>).single
                      as Map<String, dynamic>)['values']
                  as List<dynamic>)
              .single
          as String,
    );

    // CELL: only value-change frames — named cel, gap, positional
    // fallback, trailing gap.
    final cel = trackFrames(0).cast<Map<String, dynamic>>();
    expect(cel.map(frameValue), [
      (0, 'A1'),
      (3, 'SYMBOL_NULL_CELL'),
      (5, '2'),
      (9, 'SYMBOL_NULL_CELL'),
    ]);

    // DIALOG: a leading empty stretch precedes the serifu.
    final dialog = trackFrames(3).cast<Map<String, dynamic>>();
    expect(dialog.map(frameValue), [
      (0, 'SYMBOL_NULL_CELL'),
      (2, 'こんにちは'),
      (6, 'SYMBOL_NULL_CELL'),
    ]);

    // CAMERAWORK: vocabulary name with A→B, then free text, adjacent gap.
    final camerawork = trackFrames(5).cast<Map<String, dynamic>>();
    expect(camerawork.map(frameValue), [
      (0, 'PAN (A→B)'),
      (6, 'SYMBOL_NULL_CELL'),
      (8, 'ゆっくりFI'),
    ]);
  });

  test('an image row stays out of the CELL field even with its sheet '
      'toggle ON — layerTakesSheetCelColumn is the ONE gate (D24)', () {
    final cut = _cut();
    final withImage = Cut(
      id: cut.id,
      name: cut.name,
      duration: cut.duration,
      canvasSize: cut.canvasSize,
      layers: [
        ...cut.layers,
        Layer(
          id: const LayerId('bg'),
          name: 'BG',
          kind: LayerKind.image,
          onTimesheet: true,
          frames: [
            Frame(id: const FrameId('bg-cel'), duration: 1, strokes: const []),
          ],
          timeline: const {
            0: TimelineExposure.drawing(FrameId('bg-cel'), length: 1),
          },
        ),
      ],
    );

    final content = buildXdtsContent(cut: withImage, cutLabel: '3');
    final json =
        jsonDecode(content.split('\n').skip(1).join('\n'))
            as Map<String, dynamic>;
    final timeTable =
        (json['timeTables'] as List<dynamic>).single as Map<String, dynamic>;
    final cellHeader = (timeTable['timeTableHeaders'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((header) => header['fieldId'] == 0);
    expect(
      cellHeader['names'],
      ['A'],
      reason: 'a picture row is never a cel, whatever its toggle says',
    );
  });

  test('TRACK SE lanes reach the DIALOG column through the cut window — '
      'spill-in rebased to 0, crossings kept whole, starts past the end '
      'clipped (the print sheet\'s own projection)', () {
    Layer trackLane(
      String id, {
      required Map<int, TimelineExposure> timeline,
      List<Frame> frames = const [],
      bool onTimesheet = true,
    }) => Layer(
      id: LayerId(id),
      name: id.toUpperCase(),
      kind: LayerKind.se,
      frames: frames,
      timeline: timeline,
      onTimesheet: onTimesheet,
    );

    final content = buildXdtsContent(
      cut: Cut(
        id: const CutId('windowed'),
        name: 'Cut 7',
        duration: 12,
        canvasSize: const CanvasSize(width: 100, height: 100),
        layers: [
          Layer(
            id: const LayerId('cel'),
            name: 'A',
            frames: const [],
            timeline: const {},
          ),
        ],
      ),
      cutLabel: '7',
      // The cut starts at global 20 on its track's axis.
      cutStartFrame: 20,
      trackSeLayers: [
        trackLane(
          's1',
          frames: [
            Frame(
              id: const FrameId('spill'),
              duration: 1,
              name: 'ただいま',
              strokes: const [],
            ),
            Frame(
              id: const FrameId('inside'),
              duration: 1,
              name: 'おかえり',
              strokes: const [],
            ),
          ],
          timeline: {
            // Starts at global 18, BEFORE the cut: spills in, rebased to
            // local 0 with the remaining 6 frames.
            18: const TimelineExposure.drawing(FrameId('spill'), length: 8),
            // Entirely inside: global 26 = local 6.
            26: const TimelineExposure.drawing(FrameId('inside'), length: 4),
          },
        ),
        trackLane(
          's2',
          frames: [
            Frame(
              id: const FrameId('crossing'),
              duration: 1,
              name: 'いくぞ',
              strokes: const [],
            ),
            Frame(id: const FrameId('past'), duration: 1, strokes: const []),
          ],
          timeline: {
            // Starts inside (local 10) and runs past the cut end: kept,
            // true length — the hold simply carries off the sheet.
            30: const TimelineExposure.drawing(FrameId('crossing'), length: 8),
            // Starts past the cut end (local 18 ≥ 12): clipped off.
            38: const TimelineExposure.drawing(FrameId('past'), length: 2),
          },
        ),
        trackLane('hidden', timeline: const {}, onTimesheet: false),
      ],
    );

    final json =
        jsonDecode(content.split('\n').skip(1).join('\n'))
            as Map<String, dynamic>;
    final timeTable =
        (json['timeTables'] as List<dynamic>).single as Map<String, dynamic>;
    final headers = (timeTable['timeTableHeaders'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(headers[1], {
      'fieldId': 3,
      'names': ['S1', 'S2'],
    });

    final fields = (timeTable['fields'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final dialogTracks =
        (fields.firstWhere(
                  (field) => field['fieldId'] == 3,
                )['tracks']
                as List<dynamic>)
            .cast<Map<String, dynamic>>();
    List<(int, String)> frameValues(Map<String, dynamic> track) => [
      for (final entry in (track['frames'] as List<dynamic>)
          .cast<Map<String, dynamic>>())
        (
          entry['frame'] as int,
          (((entry['data'] as List<dynamic>).single
                          as Map<String, dynamic>)['values']
                      as List<dynamic>)
                  .single
              as String,
        ),
    ];

    expect(frameValues(dialogTracks[0]), [
      (0, 'ただいま'),
      (6, 'おかえり'),
      (10, 'SYMBOL_NULL_CELL'),
    ]);
    expect(frameValues(dialogTracks[1]), [
      (0, 'SYMBOL_NULL_CELL'),
      (10, 'いくぞ'),
    ]);
  });

  test('an empty cut still writes a valid sheet with a null-cell entry', () {
    final content = buildXdtsContent(
      cut: Cut(
        id: const CutId('empty'),
        name: 'Empty',
        duration: 6,
        canvasSize: const CanvasSize(width: 100, height: 100),
        layers: [
          Layer(
            id: const LayerId('cel'),
            name: 'A',
            frames: const [],
            timeline: const {},
          ),
        ],
      ),
      cutLabel: '1',
    );

    final json =
        jsonDecode(content.split('\n').skip(1).join('\n'))
            as Map<String, dynamic>;
    final timeTable =
        (json['timeTables'] as List<dynamic>).single as Map<String, dynamic>;
    final fields = (timeTable['fields'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final frames =
        ((fields.single['tracks'] as List<dynamic>).single
                as Map<String, dynamic>)['frames']
            as List<dynamic>;
    expect(frames, hasLength(1));
    expect((frames.single as Map<String, dynamic>)['frame'], 0);
  });
}
