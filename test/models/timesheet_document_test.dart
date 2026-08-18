import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/models/transition_geometry.dart';

Layer _layer(
  String id, {
  LayerKind kind = LayerKind.animation,
  bool onTimesheet = true,
  List<Frame> frames = const [],
  Map<int, TimelineExposure>? timeline,
}) {
  return Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    onTimesheet: onTimesheet,
    frames: frames,
    timeline: timeline ?? const {},
  );
}

Cut _cut({
  List<Layer> layers = const [],
  int duration = 48,
  CutCamera? camera,
}) {
  return Cut(
    id: const CutId('cut-1'),
    name: 'Cut 1',
    layers: layers,
    duration: duration,
    canvasSize: const CanvasSize(width: 1280, height: 720),
    camera: camera,
  );
}

TimesheetDocument _document(
  Cut cut, {
  int fps = 24,
  int pageSeconds = 6,
  TimesheetInfo info = TimesheetInfo.empty,
}) {
  return TimesheetDocument.fromCut(
    cut: cut,
    projectName: 'Project',
    fps: fps,
    pageSeconds: pageSeconds,
    info: info,
  );
}

TimesheetColumn _firstActionColumn(TimesheetDocument document) {
  return document.columns.firstWhere(
    (column) => column.kind == TimesheetColumnKind.action,
  );
}

void main() {
  group('TimesheetDocument pages', () {
    test('splits into pageSeconds*fps pages, padding the last', () {
      final document = _document(_cut(duration: 150));

      expect(document.pageFrameCount, 144);
      expect(document.pages, hasLength(2));
      expect(document.pages[1].startFrame, 144);
      expect(document.rowCount, 288);
      expect(document.playbackFrameCount, 150);
    });

    test('short cut still fills one page', () {
      final document = _document(_cut(duration: 10));

      expect(document.pages, hasLength(1));
      expect(document.rowCount, 144);
    });

    test('duration label uses the sheet 초+コマ notation', () {
      expect(_document(_cut(duration: 60)).durationLabel, '2+12');
      expect(_document(_cut(duration: 48)).durationLabel, '2+0');
    });

    test('a page splits into two 72-row halves', () {
      expect(_document(_cut()).halfFrameCount, 72);
    });

    test('header reads TimesheetInfo, title falling back to the project', () {
      final plain = _document(_cut());
      expect(plain.title, 'Project');
      expect(plain.episode, '');
      expect(plain.artist, '');

      final overridden = _document(
        _cut(),
        info: const TimesheetInfo(
          title: 'YOASOBI',
          episode: 'MV',
          artist: 'MYOUN',
        ),
      );
      expect(overridden.title, 'YOASOBI');
      expect(overridden.episode, 'MV');
      expect(overridden.artist, 'MYOUN');
    });
  });

  group('TimesheetDocument columns', () {
    test('onTimesheet animation layers fill the ACTION slots in order, headed '
        'by their real names; unbacked slots and the CELL block print no '
        'placeholder letters', () {
      final document = _document(
        _cut(
          layers: [
            _layer('Line'),
            _layer('hidden', onTimesheet: false),
            _layer('board', kind: LayerKind.storyboard),
            _layer('Color'),
          ],
        ),
      );

      final actionColumns = document.columns
          .where((column) => column.kind == TimesheetColumnKind.action)
          .toList();
      expect(actionColumns, hasLength(8), reason: 'fixed ACTION slots');
      expect(actionColumns[0].label, 'Line');
      expect(actionColumns[0].layerName, 'Line');
      expect(actionColumns[1].label, 'Color');
      expect(actionColumns[1].layerName, 'Color');
      expect(actionColumns[2].label, isEmpty, reason: 'no A/B/C letters');
      expect(actionColumns[2].layerName, isNull);

      final celColumns = document.columns
          .where((column) => column.kind == TimesheetColumnKind.cel)
          .toList();
      expect(celColumns, hasLength(8), reason: 'CELL form columns');
      // The CELL headers mirror the ACTION layer names (UI-R10 #10); the
      // content stays blank handwriting space.
      expect(celColumns[0].label, 'Line');
      expect(celColumns[1].label, 'Color');
      expect(celColumns[2].label, isEmpty);
      expect(
        celColumns.every(
          (column) =>
              column.layerName == null &&
              column.cells.every(
                (cell) => cell.kind == TimesheetCellKind.empty,
              ),
        ),
        isTrue,
        reason: 'headers only — no backing layer, no content',
      );
      expect(
        document.columns
            .where((column) => column.kind == TimesheetColumnKind.se)
            .map((column) => column.label),
        ['S1', 'S2'],
      );
      expect(
        document.columns
            .where((column) => column.kind == TimesheetColumnKind.camera)
            .map((column) => column.label),
        ['1', '2'],
      );
    });

    test('extra animation layers grow the ACTION block past the fixed 8', () {
      final document = _document(
        _cut(layers: [for (var i = 0; i < 10; i += 1) _layer('L$i')]),
      );

      final actionColumns = document.columns
          .where((column) => column.kind == TimesheetColumnKind.action)
          .toList();
      expect(actionColumns, hasLength(10));
      expect(actionColumns[9].layerName, 'L9');
    });

    test('SE layers fill the S slots and extra ones grow the section', () {
      final twoSe = _document(
        _cut(layers: [_layer('se1', kind: LayerKind.se)]),
      );
      final seColumns = twoSe.columns
          .where((column) => column.kind == TimesheetColumnKind.se)
          .toList();
      expect(seColumns, hasLength(2));
      expect(seColumns[0].layerName, 'se1');
      expect(seColumns[1].layerName, isNull);

      final threeSe = _document(
        _cut(
          layers: [
            for (var i = 0; i < 3; i += 1) _layer('se$i', kind: LayerKind.se),
          ],
        ),
      );
      expect(
        threeSe.columns
            .where((column) => column.kind == TimesheetColumnKind.se)
            .length,
        3,
      );
    });
  });

  group('TimesheetDocument cells', () {
    test('drawing starts write the frame NAME verbatim; unnamed cels print '
        'the in-between division mark (R5-④ — no invented numbers)', () {
      final document = _document(
        _cut(
          layers: [
            _layer(
              'A',
              frames: [
                Frame(
                  id: const FrameId('f1'),
                  duration: 1,
                  name: 'A1',
                  strokes: const [],
                ),
                Frame(id: const FrameId('f2'), duration: 1, strokes: const []),
              ],
              timeline: {
                0: const TimelineExposure.drawing(FrameId('f1'), length: 3),
                4: const TimelineExposure.drawing(FrameId('f2'), length: 2),
              },
            ),
          ],
          duration: 8,
        ),
      );

      final cells = _firstActionColumn(document).cells;
      expect(cells[0].kind, TimesheetCellKind.drawing);
      expect(cells[0].label, 'A1');
      expect(cells[1].kind, TimesheetCellKind.held);
      expect(cells[2].kind, TimesheetCellKind.held);
      expect(cells[4].kind, TimesheetCellKind.drawing);
      expect(cells[4].label, '○', reason: 'unnamed = in-between mark glyph');
      expect(cells[5].kind, TimesheetCellKind.held);
    });

    test('X sits only on the first row of an empty run; block-owned dots '
        'show ● on their held rows', () {
      final document = _document(
        _cut(
          layers: [
            _layer(
              'A',
              frames: [
                Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
              ],
              timeline: {
                0: const TimelineExposure.drawing(
                  FrameId('f1'),
                  length: 3,
                  breakdownOffsets: [1],
                ),
              },
            ),
          ],
          duration: 6,
        ),
      );

      final cells = _firstActionColumn(document).cells;
      expect(cells[0].kind, TimesheetCellKind.drawing);
      expect(cells[1].kind, TimesheetCellKind.mark);
      expect(cells[1].spanOffset, 1, reason: 'dot rows keep their span data');
      expect(cells[2].kind, TimesheetCellKind.held);
      expect(cells[3].kind, TimesheetCellKind.emptyRunStart);
      expect(
        cells[4].kind,
        TimesheetCellKind.empty,
        reason: 'one X per empty run',
      );
    });

    test('SE columns carry the name/dialogue label and never mark X runs', () {
      final document = _document(
        _cut(
          layers: [
            _layer(
              'voice',
              kind: LayerKind.se,
              frames: [
                Frame(
                  id: const FrameId('se-f1'),
                  duration: 3,
                  name: '안녕하세요',
                  strokes: const [],
                ),
              ],
              timeline: {
                2: const TimelineExposure.drawing(FrameId('se-f1'), length: 3),
              },
            ),
          ],
          duration: 12,
        ),
      );

      final seColumn = document.columns.firstWhere(
        (column) => column.kind == TimesheetColumnKind.se,
      );
      expect(seColumn.cells[2].kind, TimesheetCellKind.drawing);
      expect(seColumn.cells[2].label, '안녕하세요');
      expect(seColumn.cells[3].kind, TimesheetCellKind.held);
      // SE columns stay blank between entries on paper — no X anywhere.
      expect(
        seColumn.cells.where(
          (cell) => cell.kind == TimesheetCellKind.emptyRunStart,
        ),
        isEmpty,
      );
    });

    test('instruction rows fill CAM 2+ with writing, mark span and A→B', () {
      final document = TimesheetDocument.fromCut(
        cut: _cut(
          layers: [
            _layer('A'),
            Layer(
              id: const LayerId('cam-inst'),
              name: 'CAM 1',
              kind: LayerKind.instruction,
              frames: const [],
              timeline: const {},
              instructions: {
                2: const InstructionEvent(
                  instructionId: 'pan',
                  length: 4,
                  valueA: 'A',
                  valueB: 'B',
                ),
                10: const InstructionEvent(
                  instructionId: 'fi',
                  length: 1,
                  text: 'ゆっくりFI',
                ),
              },
            ),
          ],
          duration: 24,
        ),
        projectName: 'Project',
        fps: 24,
        pageSeconds: 6,
        instructionDefById: CameraInstructionSet.standard.defById,
      );

      final cameraColumns = document.columns
          .where((column) => column.kind == TimesheetColumnKind.camera)
          .toList();
      expect(cameraColumns, hasLength(2));
      expect(cameraColumns[1].layerName, 'CAM 1');

      final cells = cameraColumns[1].cells;
      expect(cells[2].kind, TimesheetCellKind.instructionStart);
      expect(cells[2].label, 'PAN', reason: 'vocabulary-name fallback');
      expect(cells[2].spanLength, 4);
      expect(cells[2].valueA, 'A');
      expect(cells[2].markType, CameraInstructionMarkType.bar);
      expect(cells[3].kind, TimesheetCellKind.instructionSpan);
      expect(cells[5].kind, TimesheetCellKind.instructionEnd);
      expect(cells[5].valueB, 'B');
      // Every covered row re-derives the span's mark geometry (page-half
      // crossing rule): offset within the span plus the full extent.
      expect(
        [
          for (final row in [2, 3, 4, 5]) cells[row].spanOffset,
        ],
        [0, 1, 2, 3],
      );
      expect(
        [
          for (final row in [3, 4, 5]) cells[row].spanLength,
        ],
        [4, 4, 4],
      );
      // Free per-event text wins over the vocabulary name; the FI def
      // carries its fade-wedge mark onto the cells.
      expect(cells[10].kind, TimesheetCellKind.instructionStart);
      expect(cells[10].label, 'ゆっくりFI');
      expect(cells[10].spanLength, 1);
      expect(cells[10].markType, CameraInstructionMarkType.fi);
      expect(cells[11].kind, TimesheetCellKind.empty);
    });

    test('D31: the transition row prints as one more CAM column through '
        'the instruction recipe, at its PROJECTED cut-local position', () {
      // The clone the session's cut-view projection hands over: an O.L
      // that really crosses the cut end, re-keyed to its cut-local start.
      final transition = Layer(
        id: const LayerId('t-transitions'),
        name: 'Transition',
        kind: LayerKind.transition,
        frames: const [],
        timeline: const {},
        instructions: {
          20: const InstructionEvent(instructionId: 'ol', length: 6),
        },
      );
      final document = TimesheetDocument.fromCut(
        cut: _cut(duration: 24),
        projectName: 'Project',
        fps: 24,
        pageSeconds: 6,
        instructionDefById: CameraInstructionSet.standard.defById,
        transitionLayer: transition,
      );

      final cameraColumns = document.columns
          .where((column) => column.kind == TimesheetColumnKind.camera)
          .toList();
      expect(cameraColumns, hasLength(2), reason: 'the spare fixed slot '
          'absorbs the transition — no layout change');
      expect(cameraColumns[1].layerName, 'Transition');
      final cells = cameraColumns[1].cells;
      expect(cells[20].kind, TimesheetCellKind.instructionStart);
      expect(cells[20].spanLength, 6);
      expect(cells[20].markType, CameraInstructionMarkType.ol);
      expect(
        cells[25].kind,
        TimesheetCellKind.instructionEnd,
        reason: 'the mark legitimately runs into the のりしろ rows',
      );
    });

    test('D31: no transition layer (or its timesheet flag off — the '
        'caller\'s gate) keeps the CAM block exactly as before', () {
      final document = _document(_cut());
      expect(
        document.columns
            .where((column) => column.kind == TimesheetColumnKind.camera)
            .length,
        2,
      );
      expect(
        document.columns
            .where((column) => column.kind == TimesheetColumnKind.camera)
            .map((column) => column.layerName)
            .toList(),
        [null, null],
      );
    });

    test('a third instruction row grows the CAM block past the fixed 2', () {
      Layer instruction(String id) => Layer(
        id: LayerId(id),
        name: id,
        kind: LayerKind.instruction,
        frames: const [],
        timeline: const {},
      );
      final document = _document(
        _cut(layers: [instruction('cam-1'), instruction('cam-2')]),
      );

      expect(
        document.columns
            .where((column) => column.kind == TimesheetColumnKind.camera)
            .length,
        3,
        reason: 'camera keys + two instruction rows',
      );
    });

    test('drawing starts carry spanLength for vertical sheet text', () {
      final document = _document(
        _cut(
          layers: [
            _layer(
              'voice',
              kind: LayerKind.se,
              frames: [
                Frame(
                  id: const FrameId('f1'),
                  duration: 5,
                  name: 'せりふ',
                  strokes: const [],
                ),
              ],
              timeline: {
                1: const TimelineExposure.drawing(FrameId('f1'), length: 5),
              },
            ),
          ],
          duration: 12,
        ),
      );

      final seColumn = document.columns.firstWhere(
        (column) => column.kind == TimesheetColumnKind.se,
      );
      expect(seColumn.cells[1].spanLength, 5);
    });

    test('rows beyond the playback range stay paper-blank', () {
      final document = _document(_cut(layers: [_layer('A')], duration: 10));

      final cells = _firstActionColumn(document).cells;
      expect(cells[0].kind, TimesheetCellKind.emptyRunStart);
      expect(cells[10].kind, TimesheetCellKind.empty);
      expect(cells[143].kind, TimesheetCellKind.empty);
    });

    test('camera keyframes land in the first camera column with spans', () {
      final document = _document(
        _cut(
          duration: 12,
          camera: CutCamera(
            keyframes: {
              2: CameraPose(center: CanvasPoint(x: 0, y: 0)),
              6: CameraPose(center: CanvasPoint(x: 5, y: 5), zoom: 2),
            },
          ),
        ),
      );

      final cameraColumns = document.columns
          .where((column) => column.kind == TimesheetColumnKind.camera)
          .toList();
      final cells = cameraColumns.first.cells;
      expect(cells[2].kind, TimesheetCellKind.cameraKey);
      expect(cells[3].kind, TimesheetCellKind.cameraSpan);
      expect(cells[5].kind, TimesheetCellKind.cameraSpan);
      expect(cells[6].kind, TimesheetCellKind.cameraKey);
      expect(cells[7].kind, TimesheetCellKind.empty);
      expect(
        cameraColumns[1].cells[2].kind,
        TimesheetCellKind.empty,
        reason: 'the second camera slot stays blank',
      );
    });
  });

  group('TimesheetDocument header fields', () {
    test('scene passes through from info; the memo text is the cut note', () {
      final document = TimesheetDocument.fromCut(
        cut: Cut(
          id: const CutId('cut-1'),
          name: 'Cut 1',
          layers: const [],
          duration: 48,
          canvasSize: const CanvasSize(width: 1280, height: 720),
          metadata: const CutMetadata(note: 'カットO.L'),
        ),
        projectName: 'Project',
        fps: 24,
        info: const TimesheetInfo(scene: 'S12'),
      );

      expect(document.scene, 'S12');
      expect(document.memoText, 'カットO.L');
    });

    test('visibleHeaderFields keeps printing order minus hidden boxes', () {
      final all = _document(_cut());
      expect(all.visibleHeaderFields, TimesheetHeaderField.values);

      final trimmed = _document(
        _cut(),
        info: const TimesheetInfo(
          hiddenFields: {
            TimesheetHeaderField.scene,
            TimesheetHeaderField.sheet,
          },
        ),
      );
      // R7-⑥: the episode box (Ep.no) leads, like the reference forms.
      expect(trimmed.visibleHeaderFields, const [
        TimesheetHeaderField.episode,
        TimesheetHeaderField.title,
        TimesheetHeaderField.cut,
        TimesheetHeaderField.time,
        TimesheetHeaderField.name,
      ]);
    });
  });

  group('SE globalization on the printed sheet', () {
    // A 24-frame cut starting at global 24. The track SE row: a sound
    // spilling in from the previous cut, one CROSSING this cut's end
    // (starts frame 40, runs to 52), and one wholly in the NEXT cut (50…
    // no — 56, past the cut end at 48).
    Layer trackSe() => Layer(
      id: const LayerId('track-se'),
      name: 'S1',
      kind: LayerKind.se,
      frames: [
        Frame(id: const FrameId('sp'), duration: 8, strokes: const []),
        Frame(id: const FrameId('cr'), duration: 12, strokes: const []),
        Frame(id: const FrameId('nx'), duration: 4, strokes: const []),
      ],
      timeline: {
        20: const TimelineExposure.drawing(FrameId('sp'), length: 8),
        40: const TimelineExposure.drawing(FrameId('cr'), length: 12),
        56: const TimelineExposure.drawing(FrameId('nx'), length: 4),
      },
    );

    TimesheetColumn seColumn() => TimesheetDocument.fromCut(
      cut: _cut(duration: 24),
      projectName: 'Project',
      fps: 24,
      pageSeconds: 1,
      trackSeLayers: [trackSe()],
      cutStartFrame: 24,
    ).columns.firstWhere((column) => column.kind == TimesheetColumnKind.se);

    test('the sheet stays the CUT\'s page: the display window is open-'
        'ended now, but sounds starting at or past the cut end stay off '
        'the printed rows', () {
      final column = seColumn();
      // The next cut's sound (global 56 = local 32, past duration 24)
      // must not land in ANY row — the sheet's rowCount (a page multiple)
      // is larger than the cut, and its slack rows print nothing.
      for (var row = 24; row < column.cells.length; row += 1) {
        expect(
          column.cells[row].kind == TimesheetCellKind.drawing,
          isFalse,
          reason: 'row $row must not carry the next cut\'s entry',
        );
      }
      // The crossing sound (local 16, runs to 28) still prints, held rows
      // past the red line included.
      expect(column.cells[16].kind, TimesheetCellKind.drawing);
    });

    test('the sheet carries the timeline\'s crossing marks: ~ flags for '
        'the cut-end crossing AND the spill-in start', () {
      final column = seColumn();
      expect(column.crossesCutEnd, isTrue, reason: 'sound runs past 48');
      expect(column.spillsInAtStart, isTrue, reason: 'sound from before 24');
    });
  });

  group('のりしろ on the sheet', () {
    // The design's own numbers: this cut is c21, 3+0 long, sitting at
    // global 48; a 1+0 O.L centred on that boundary runs [36, 60).
    const fps = 24;
    const cutStart = 48;
    final cut = Cut(
      id: const CutId('c21'),
      name: 'c21',
      layers: const [],
      duration: 3 * fps,
      canvasSize: const CanvasSize(width: 100, height: 100),
    );

    TimesheetDocument sheet({List<TransitionSpan> spans = const []}) =>
        TimesheetDocument.fromCut(
          cut: cut,
          projectName: 'p',
          fps: fps,
          cutStartFrame: cutStart,
          transitionSpans: spans,
        );

    test('no transition means no のりしろ — the sheet is the conte 尺', () {
      final document = sheet();

      expect(document.transitionHandles, CutTransitionHandles.none);
      expect(document.drawnFrameCount, document.playbackFrameCount);
    });

    test('a span inside the cut still means nothing', () {
      // [72, 96) — comfortably inside c21, crossing neither boundary.
      final document = sheet(spans: const [(start: 72, length: 24, mark: CameraInstructionMarkType.ol)]);

      expect(document.transitionHandles, CutTransitionHandles.none);
      expect(document.drawnFrameCount, 3 * fps);
    });

    test('an O.L across the cut head adds 0+12 to what the sheet asks for', () {
      final document = sheet(spans: const [(start: 36, length: 24, mark: CameraInstructionMarkType.ol)]);

      expect(document.transitionHandles.head, 12);
      // 3+0 (3+12): the conte 尺 is untouched, the drawn 尺 is longer.
      expect(document.playbackFrameCount, 3 * fps);
      expect(document.drawnFrameCount, 3 * fps + 12);
      expect(document.durationLabel, '3+0');
      expect(document.drawnDurationLabel, '3+12');
    });

    test('a sheet without transitions prints one number, as it always did', () {
      expect(sheet().durationLabel, '3+0');
      expect(sheet().drawnDurationLabel, isNull);
    });

    test('のりしろ can push the sheet onto another page', () {
      // A cut exactly one page long: the handle has nowhere to go but a
      // second sheet of paper, and 撮ま! says the rows must be there
      // ("シートは必ずここまで記入する").
      final onePage = Cut(
        id: const CutId('c30'),
        name: 'c30',
        layers: const [],
        duration: 6 * fps,
        canvasSize: const CanvasSize(width: 100, height: 100),
      );
      final document = TimesheetDocument.fromCut(
        cut: onePage,
        projectName: 'p',
        fps: fps,
        cutStartFrame: 0,
        // Crosses the cut's END at 144, reaching 12 frames past it.
        transitionSpans: const [(start: 132, length: 24, mark: CameraInstructionMarkType.ol)],
      );

      expect(document.transitionHandles.tail, 12);
      expect(document.drawnFrameCount, 6 * fps + 12);
      expect(document.pages.length, 2);
      expect(document.rowCount, greaterThanOrEqualTo(document.drawnFrameCount));
    });
  });
}
