import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/ui/export/export_timesheet_render.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppTypography;
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

import '../../helpers/app_faces.dart';

/// 🗣️I-161-Q3 · Q4 (유저 2026-11-05): an XDTS viewer's ink page carries the
/// sheet's SE and CAM columns and its 겸용 line — what the viewer leaves to
/// the hand — and none of what the viewer prints itself. So the values print
/// a part at a time ([TimesheetContentPart]): each part prints where it
/// stands on the sheet, and the parts together print the values whole and
/// nothing beside them.
void main() {
  setUpAll(loadTheAppFaces);

  Frame cel(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const []);
  final document = TimesheetDocument.fromCut(
    cut: Cut(
      id: const CutId('cut'),
      name: '12',
      duration: 24,
      canvasSize: const CanvasSize(width: 1920, height: 1080),
      metadata: const CutMetadata(pageNotes: ['O.L']),
      layers: [
        Layer(
          id: const LayerId('a'),
          name: 'A',
          kind: LayerKind.animation,
          frames: [cel('a-1'), cel('a-2')],
          timeline: const {
            0: TimelineExposure.drawing(FrameId('a-1'), length: 6),
            6: TimelineExposure.drawing(FrameId('a-2'), length: 6),
          },
        ),
        Layer(
          id: const LayerId('book'),
          name: 'BOOK',
          kind: LayerKind.image,
          mark: const LayerMark(process: LayerProcess.art),
          frames: [cel('book-1')],
          timeline: const {
            0: TimelineExposure.drawing(FrameId('book-1'), length: 24),
          },
        ),
        Layer(
          id: const LayerId('c'),
          name: 'C',
          kind: LayerKind.animation,
          mark: const LayerMark(process: LayerProcess.inbetween),
          frames: [cel('c-1')],
          timeline: const {
            0: TimelineExposure.drawing(FrameId('c-1'), length: 8),
          },
        ),
        Layer(
          id: const LayerId('s'),
          name: 'S1',
          kind: LayerKind.se,
          frames: [
            Frame(
              id: const FrameId('s-1'),
              duration: 1,
              strokes: const [],
              name: 'あいうえお',
            ),
            Frame(
              id: const FrameId('s-2'),
              duration: 1,
              strokes: const [],
              name: 'かきく',
            ),
          ],
          // The second runs past the cut's end: a `~` stands on its line.
          timeline: const {
            2: TimelineExposure.drawing(FrameId('s-1'), length: 8),
            20: TimelineExposure.drawing(FrameId('s-2'), length: 8),
          },
        ),
        Layer(
          id: const LayerId('cam'),
          name: 'CAM',
          kind: LayerKind.instruction,
          frames: const [],
          timeline: const {},
          instructions: {
            0: const InstructionEvent(instructionId: 'pan', length: 6),
          },
        ),
      ],
    ),
    projectName: 'P',
    fps: 24,
    info: const TimesheetInfo(title: 'T'),
    instructionDefById: CameraInstructionSet.standard.defById,
    linkedCuts: const ['13', '14'],
  );
  final layout = TimesheetDocumentLayout(document: document);
  final size = layout.documentSize;
  final width = size.width.ceil();
  const face = TextStyle(
    fontFamily: AppTypography.bundledFamily,
    fontFamilyFallback: AppTypography.bundledFallback,
  );
  final words = timesheetWordsIn(AppLanguage.ja);

  /// The values of [parts] alone — all of them where null.
  TimesheetDocumentPainter valuesOf(Set<TimesheetContentPart>? parts) =>
      TimesheetDocumentPainter(
        document: document,
        layout: layout,
        face: face,
        words: words,
        layers: const {SheetPaintLayer.content},
        contentParts: parts,
      );

  /// The alphas the values print, of [parts] alone — all of them where null.
  Future<Uint8List> printed(
    WidgetTester tester,
    Set<TimesheetContentPart>? parts,
  ) async {
    final recorder = ui.PictureRecorder();
    valuesOf(parts).paint(ui.Canvas(recorder), size);
    final picture = recorder.endRecording();
    final rgba = (await tester.runAsync(() async {
      final image = await picture.toImage(width, size.height.ceil());
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
    picture.dispose();
    return Uint8List.fromList([
      for (var i = 3; i < rgba.length; i += 4) rgba[i],
    ]);
  }

  /// Where [alphas] hold anything, or null where nowhere.
  Rect? inkOf(Uint8List alphas) {
    Rect? ink;
    for (var i = 0; i < alphas.length; i += 1) {
      if (alphas[i] == 0) {
        continue;
      }
      final pixel = Rect.fromLTWH(
        (i % width).toDouble(),
        (i ~/ width).toDouble(),
        1,
        1,
      );
      ink = ink?.expandToInclude(pixel) ?? pixel;
    }
    return ink;
  }

  /// The room the columns of [kind] take on each half, over its rows.
  List<Rect> blockOf(TimesheetColumnKind kind) {
    final columns = [
      for (final (index, column) in document.columns.indexed)
        if (column.kind == kind) index,
    ];
    return [
      for (final strip in layout.halfStrips)
        Rect.fromLTRB(
          layout.halfLeft(0, strip.half) +
              layout.columnLeftInHalf(columns.first),
          layout.gridTop(0),
          layout.halfLeft(0, strip.half) +
              layout.columnLeftInHalf(columns.last) +
              layout.columnWidthFor(kind),
          layout.pageRect(0).bottom,
        ),
    ];
  }

  /// How many pixels [alphas] ink outside every one of [rooms].
  int outside(Uint8List alphas, List<Rect> rooms) {
    var count = 0;
    for (var i = 0; i < alphas.length; i += 1) {
      final pixel = Offset(i % width + 0.5, i ~/ width + 0.5);
      if (alphas[i] != 0 &&
          !rooms.any((room) => room.inflate(1).contains(pixel))) {
        count += 1;
      }
    }
    return count;
  }

  testWidgets('🎯each part prints where it stands on the sheet', (
    tester,
  ) async {
    final header = layout.headerBandRect(0);
    final memo = layout.memoBandRect(0);
    final cutBox = layout
        .headerFieldBoxes(0)
        .firstWhere((box) => box.field == TimesheetHeaderField.cut)
        .rect;
    final end = layout.cutEndLineFor(document.playbackFrameCount);
    final where = {
      TimesheetContentPart.header: [header],
      TimesheetContentPart.linkedCuts: [
        Rect.fromLTRB(cutBox.left - 12, cutBox.top, cutBox.right, memo.bottom),
      ],
      TimesheetContentPart.memo: [memo],
      TimesheetContentPart.action: blockOf(TimesheetColumnKind.action),
      TimesheetContentPart.cel: blockOf(TimesheetColumnKind.cel),
      TimesheetContentPart.books: [
        Rect.fromLTRB(header.left, memo.top, header.right, layout.gridTop(0)),
      ],
      TimesheetContentPart.se: blockOf(TimesheetColumnKind.se),
      TimesheetContentPart.camera: blockOf(TimesheetColumnKind.camera),
      TimesheetContentPart.cutEnd: [
        Rect.fromLTRB(
          layout.halfLeft(0, end.half),
          end.y - 2,
          layout.halfLeft(0, end.half) + layout.halfWidth,
          end.y + 2,
        ),
      ],
    };
    expect(where.keys, TimesheetContentPart.values, reason: 'every part');

    final printedOf = <TimesheetContentPart, Uint8List>{};
    for (final MapEntry(key: part, value: rooms) in where.entries) {
      final alphas = printedOf[part] = await printed(tester, {part});
      expect(inkOf(alphas), isNotNull, reason: '$part prints something');
      expect(outside(alphas, rooms), 0, reason: '$part prints in its room');
    }
    // The 겸용 line hangs under the cut's name, in the header's room: the
    // two share no pixel.
    final values = printedOf[TimesheetContentPart.header]!;
    final linked = printedOf[TimesheetContentPart.linkedCuts]!;
    expect(
      [
        for (var i = 0; i < values.length; i += 1)
          if (values[i] != 0 && linked[i] != 0) i,
      ],
      isEmpty,
    );
  });

  testWidgets('🎯the parts together print the values whole, and nothing '
      'beside them', (tester) async {
    final whole = await printed(tester, null);
    final parts = [
      for (final part in TimesheetContentPart.values)
        await printed(tester, {part}),
    ];

    var missing = 0;
    var stray = 0;
    for (var i = 0; i < whole.length; i += 1) {
      final inked = parts.any((alphas) => alphas[i] != 0);
      if (whole[i] != 0 && !inked) {
        missing += 1;
      }
      if (whole[i] == 0 && inked) {
        stray += 1;
      }
    }
    expect(inkOf(whole), isNotNull, reason: 'the premise');
    expect([missing, stray], [0, 0]);
  });

  test('a paint of other parts is another picture', () {
    expect(
      valuesOf({TimesheetContentPart.se}).shouldRepaint(
        valuesOf({TimesheetContentPart.camera}),
      ),
      isTrue,
    );
    expect(valuesOf(null).shouldRepaint(valuesOf(null)), isFalse);
  });

  testWidgets('an exported page prints the parts it is handed alone', (
    tester,
  ) async {
    Future<int> inked(Set<TimesheetContentPart>? parts) async =>
        (await tester.runAsync(() async {
          final image = await renderTimesheetPageImage(
            document: document,
            layout: layout,
            pageIndex: 0,
            words: words,
            face: face,
            layers: const {SheetPaintLayer.content},
            contentParts: parts,
          );
          final rgba = (await image.toByteData())!.buffer.asUint8List();
          image.dispose();
          return [
            for (var i = 3; i < rgba.length; i += 4)
              if (rgba[i] != 0) i,
          ].length;
        }))!;

    expect(await inked(null), greaterThan(0), reason: 'the premise');
    expect(await inked(const {}), 0);
  });
}
