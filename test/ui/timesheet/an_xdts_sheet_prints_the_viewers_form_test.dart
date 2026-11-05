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
import 'package:anicel/src/models/sheet_paint_layer.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/models/timesheet_sheet_kind.dart';
import 'package:anicel/src/models/transition_geometry.dart';
import 'package:anicel/src/models/xdts_sheet_form.dart';
import 'package:anicel/src/models/xdts_viewer_sheet.dart';
import 'package:anicel/src/services/export/xdts_viewer_ink.dart';
import 'package:anicel/src/ui/sheet/sheet_image_cache.dart'
    show SheetImageLookup;
import 'package:anicel/src/ui/theme/app_theme.dart' show AppTypography;
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

import '../../helpers/app_faces.dart';

/// 🚨AN XDTS SHEET PRINTS THE VIEWER'S FORM, LINE FOR LINE (I-162, 유저
/// 2026-11-05: 「서식 바꾸면 xdts의 해당 서식에서 보는거랑 똑같은 화면」).
///
/// The sheet is laid in the viewer's own 250dpi pixels and scaled so a
/// frame row is ours: printed back at the viewer's pixels, every rule lands
/// where the viewer's does (the spec's tables, `an_xdts_sheet_lands_on_the_
/// viewers_pixels_test.dart`) — and the cells, the spans and the header's
/// values sit in the template's cells, the same code laying them as on our
/// own form.
void main() {
  setUpAll(loadTheAppFaces);

  /// A cut of [cels] 原画 rows on [kind], the first exposing its drawings
  /// 1 and 2 six frames each, then [inbetweens] 動画 rows exposing a
  /// drawing six frames — [duration] frames long from frame [at] of its
  /// track, which [spans] cross — of a work whose logo is [logo].
  TimesheetDocument sheet({
    TimesheetSheetKind kind = TimesheetSheetKind.xdtsA3SixSeconds,
    int cels = 1,
    int inbetweens = 0,
    int duration = 30,
    int at = 0,
    List<TransitionSpan> spans = const [],
    String? logo,
  }) => TimesheetDocument.fromCut(
    cutStartFrame: at,
    transitionSpans: spans,
    cut: Cut(
      id: const CutId('cut'),
      name: '12',
      duration: duration,
      canvasSize: const CanvasSize(width: 1920, height: 1080),
      metadata: CutMetadata(sheetKind: kind),
      layers: [
        for (var index = 0; index < cels; index += 1)
          Layer(
            id: LayerId('cel-$index'),
            name: String.fromCharCode(65 + index),
            kind: LayerKind.animation,
            frames: [
              Frame(id: FrameId('$index-1'), duration: 1, strokes: const []),
              Frame(id: FrameId('$index-2'), duration: 1, strokes: const []),
            ],
            timeline: index == 0
                ? const {
                    0: TimelineExposure.drawing(FrameId('0-1'), length: 6),
                    6: TimelineExposure.drawing(FrameId('0-2'), length: 6),
                  }
                : const {},
          ),
        for (var index = 0; index < inbetweens; index += 1)
          Layer(
            id: LayerId('inbetween-$index'),
            name: 'IB$index',
            kind: LayerKind.animation,
            mark: const LayerMark(process: LayerProcess.inbetween),
            frames: [
              Frame(id: FrameId('ib$index'), duration: 1, strokes: const []),
            ],
            timeline: {
              0: TimelineExposure.drawing(FrameId('ib$index'), length: 6),
            },
          ),
      ],
    ),
    projectName: 'P',
    fps: 24,
    info: TimesheetInfo(title: 'T', episode: '3', logoAssetPath: logo),
  );

  /// A viewer pixel's length on the sheet: its frame row is 18 units.
  double unitOf(TimesheetDocumentLayout layout) =>
      TimesheetDocumentLayout.rowHeight / layout.document.xdtsForm!.rowHeight;

  group('the layout', () {
    test('the page is the template\'s paper at the timesheet\'s 150dpi — '
        'widened as the viewer widens it for the blocks\' rows', () {
      expect(
        TimesheetDocumentLayout(document: sheet()).paperPixelSize,
        const CanvasSize(width: 1754, height: 2480),
      );
      for (final kind in [
        TimesheetSheetKind.xdtsB4ThreeSeconds,
        TimesheetSheetKind.xdtsB4SixSeconds,
        TimesheetSheetKind.xdtsPonocSixSeconds,
      ]) {
        expect(
          TimesheetDocumentLayout(document: sheet(kind: kind)).paperPixelSize,
          const CanvasSize(width: 1518, height: 2150),
          reason: '$kind',
        );
      }
      // Ten 原画 rows: A3's seven ACTION columns and eight CELL ones both
      // widen to ten — 2923 + 2 × (3 × 44 + 2 × 79) = 3503 viewer pixels.
      final wide = TimesheetDocumentLayout(document: sheet(cels: 10));
      expect(
        wide.paperPixelSize,
        const CanvasSize(width: 2102, height: 2480),
      );
      expect(
        wide.paperWidth * wide.paperScale,
        closeTo(2102, 1e-6),
      );
      // A pixel of the paper is a pixel of the page (F-294): the paper is
      // the form, to within one of its pixels.
      expect(wide.paperWidth, closeTo(wide.formWidth, 1 / wide.paperScale));
      expect(wide.paperHeight, closeTo(wide.formHeight, 1 / wide.paperScale));
    });

    test('the halves, the rows and the columns stand on the viewer\'s '
        'pixels — the frame numbers\' column after the ACTION block, the '
        'rows by a second\'s double rule sharing its gap', () {
      final layout = TimesheetDocumentLayout(document: sheet());
      final unit = unitOf(layout);
      final page = layout.pageRect(0);
      double x(double units) => (units - page.left) / unit;
      double y(double units) => (units - page.top) / unit;

      expect(x(layout.halfLeft(0, 0)), closeTo(89, 1e-9));
      expect(x(layout.halfLeft(0, 1)), closeTo(1511, 1e-9));
      expect(y(layout.halfRowsTop(0)), closeTo(1009, 1e-9));
      expect(y(layout.gridTop(0)), closeTo(945, 1e-9));
      expect(y(layout.lettersTop(0)), closeTo(977, 1e-9));
      expect(y(layout.frameRowTop(23)), closeTo(1009 + 23 * 42, 1e-9));
      expect(y(layout.frameRowBottom(23)), closeTo(2017 + 3, 1e-9));
      expect(y(layout.frameRowTop(24)), closeTo(2020, 1e-9));
      expect(y(layout.frameRowBottom(24)), closeTo(2065, 1e-9));
      // Frame 72 opens the second body, level with the first.
      expect(layout.positionOfFrame(72).half, 1);
      expect(y(layout.frameRowTop(72)), closeTo(1009, 1e-9));

      final columns = layout.document.columns;
      double leftOf(TimesheetColumnKind kind) => layout.columnLeftInHalf(
        columns.indexWhere((column) => column.kind == kind),
      );
      expect(leftOf(TimesheetColumnKind.action) / unit, closeTo(0, 1e-9));
      expect(leftOf(TimesheetColumnKind.se) / unit, closeTo(377, 1e-9));
      expect(leftOf(TimesheetColumnKind.cel) / unit, closeTo(485, 1e-9));
      expect(leftOf(TimesheetColumnKind.camera) / unit, closeTo(1117, 1e-9));
      expect(
        layout.columnWidthFor(TimesheetColumnKind.cel) / unit,
        closeTo(79, 1e-9),
      );
      expect(layout.halfWidth / unit, closeTo(1354, 1e-9));
    });

    test('a view of some rows reaches those rows, a row of slack each side '
        '— the double rules counted', () {
      final layout = TimesheetDocumentLayout(document: sheet());
      final rows = layout.halfRows(0);
      final (first, last) = rows.reached(
        Rect.fromLTRB(0, rows.topOf(30) + 1, 100, rows.bottomOf(40) - 1),
        72,
      );
      expect(first, inInclusiveRange(28, 30));
      expect(last, inInclusiveRange(41, 43));
    });

    // I-162-Q5 (유저 2026-11-05): 「회사 로고를 찍는다」 — the logo's place
    // prints the company logo, and the title, which the form has no box
    // for, is not printed. ↩️It stood on the logo's place (I-162-Q2).
    test('the header\'s boxes are the template\'s — each value in the row '
        'under its label — and none is the title', () {
      final layout = TimesheetDocumentLayout(document: sheet());
      final unit = unitOf(layout);
      final page = layout.pageRect(0).topLeft;
      Rect pixels(Rect units) => Rect.fromLTRB(
        (units.left - page.dx) / unit,
        (units.top - page.dy) / unit,
        (units.right - page.dx) / unit,
        (units.bottom - page.dy) / unit,
      );
      final boxes = {
        for (final box in layout.headerFieldBoxes(0)) box.field: box,
      };
      expect(
        layout.document.visibleHeaderFields,
        contains(TimesheetHeaderField.title),
        reason: 'the premise: the work shows its title',
      );
      expect(boxes.keys, [
        TimesheetHeaderField.episode,
        TimesheetHeaderField.scene,
        TimesheetHeaderField.cut,
        TimesheetHeaderField.time,
        TimesheetHeaderField.name,
        TimesheetHeaderField.sheet,
      ]);
      Rect near(Rect rect) => Rect.fromLTRB(
        rect.left.roundToDouble(),
        rect.top.roundToDouble(),
        rect.right.roundToDouble(),
        rect.bottom.roundToDouble(),
      );
      expect(
        near(pixels(boxes[TimesheetHeaderField.time]!.rect)),
        const Rect.fromLTWH(1663, 49, 541, 167),
      );
      expect(
        near(pixels(boxes[TimesheetHeaderField.time]!.value)),
        const Rect.fromLTWH(1663, 93, 541, 123),
      );
      expect(
        near(pixels(layout.memoBandRect(0))),
        const Rect.fromLTWH(89, 275, 2776, 640),
      );
    });

    test('a hidden field\'s box keeps its place in the form and prints no '
        'value', () {
      final document = TimesheetDocument.fromCut(
        cut: Cut(
          id: const CutId('cut'),
          name: '12',
          duration: 24,
          canvasSize: const CanvasSize(width: 1920, height: 1080),
          metadata: const CutMetadata(
            sheetKind: TimesheetSheetKind.xdtsA3SixSeconds,
          ),
          layers: const [],
        ),
        projectName: 'P',
        fps: 24,
        info: const TimesheetInfo(
          hiddenFields: {TimesheetHeaderField.episode},
        ),
      );
      final layout = TimesheetDocumentLayout(document: document);
      expect(
        [for (final box in layout.headerFieldBoxes(0)) box.field],
        isNot(contains(TimesheetHeaderField.episode)),
      );
    });
  });

  group('the print', () {
    /// [layers] of page 0 of [document] printed back at the viewer's own
    /// pixels, from [origin] [size] large — of its values, [parts] alone
    /// where they are named.
    Future<(Uint8List, int)> printed(
      WidgetTester tester,
      TimesheetDocument document,
      Set<SheetPaintLayer> layers, {
      required Offset origin,
      required Size size,
      Set<TimesheetContentPart>? parts,
      SheetImageLookup? imageFor,
    }) async {
      final layout = TimesheetDocumentLayout(document: document);
      final unit = unitOf(layout);
      final page = layout.pageRect(0);
      final painter = TimesheetDocumentPainter(
        document: document,
        layout: layout,
        face: const TextStyle(
          fontFamily: AppTypography.bundledFamily,
          fontFamilyFallback: AppTypography.bundledFallback,
        ),
        words: timesheetWordsIn(AppLanguage.ja),
        layers: layers,
        contentParts: parts,
        imageFor: imageFor,
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..translate(-origin.dx, -origin.dy)
        ..scale(1 / unit)
        ..translate(-page.left, -page.top);
      painter.paint(canvas, layout.documentSize);
      final picture = recorder.endRecording();
      final width = size.width.toInt();
      final bytes = (await tester.runAsync(() async {
        final image = await picture.toImage(width, size.height.toInt());
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return data!.buffer.asUint8List();
      }))!;
      picture.dispose();
      return (bytes, width);
    }

    /// The pixel at viewer pixel ([x], [y]) of a print from [origin].
    ui.Color pixelAt((Uint8List, int) print, Offset origin, int x, int y) {
      final (bytes, width) = print;
      final row = y - origin.dy.toInt();
      final at = (row * width + x - origin.dx.toInt()) * 4;
      return ui.Color.fromARGB(
        bytes[at + 3],
        bytes[at],
        bytes[at + 1],
        bytes[at + 2],
      );
    }

    /// Whether a print from [origin] holds anything in [rect].
    bool inkedIn((Uint8List, int) print, Offset origin, Rect rect) {
      for (var y = rect.top.toInt(); y < rect.bottom; y += 1) {
        for (var x = rect.left.toInt(); x < rect.right; x += 1) {
          if (pixelAt(print, origin, x, y).a != 0) {
            return true;
          }
        }
      }
      return false;
    }

    const line = ui.Color(0xFF9CC862);

    /// A square logo in three bands: black, mid grey, and white over clear.
    Future<ui.Image> logoImage(WidgetTester tester) async {
      final image = (await tester.runAsync(() {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder)
          ..drawRect(
            const Rect.fromLTWH(0, 0, 8, 24),
            Paint()..color = const Color(0xFF000000),
          )
          ..drawRect(
            const Rect.fromLTWH(8, 0, 8, 24),
            Paint()..color = const Color(0xFF808080),
          )
          ..drawRect(
            const Rect.fromLTWH(16, 0, 8, 12),
            Paint()..color = const Color(0xFFFFFFFF),
          );
        final picture = recorder.endRecording();
        return picture.toImage(24, 24).whenComplete(picture.dispose);
      }))!;
      addTearDown(image.dispose);
      return image;
    }

    /// The logo [image] as the pool hands it, at `logo.png`.
    SheetImageLookup logoAt(ui.Image image) =>
        (path, {width}) => path == 'logo.png' ? image : null;

    testWidgets('the form\'s rules land on the viewer\'s pixels, in its line '
        'colour — row rules thin and thick by the sixth, none across the '
        'dialogue column, the walls, the outline, the half-second mark',
        (tester) async {
      const origin = Offset.zero;
      final print = await printed(
        tester,
        sheet(),
        {SheetPaintLayer.form},
        origin: origin,
        size: const Size(1700, 2100),
      );
      ui.Color at(int x, int y) => pixelAt(print, origin, x, y);

      // A thin rule under the first row, a thick one under the sixth.
      expect(at(600, 1051), line);
      expect(at(600, 1047), isNot(line));
      expect(at(600, 1261), line);
      expect(at(600, 1259), line, reason: 'five pixels wide');
      expect(at(600, 1256).a, 0);
      // The dialogue column has no rows.
      expect(at(520, 1051).a, 0);
      expect(at(520, 1261).a, 0);
      // The walls: between cel columns, the ACTION block's right border,
      // the body's outline — and the second body's.
      expect(at(653, 1100), line);
      expect(at(640, 1100).a, 0);
      // … and on up through the head's lower half, not its upper.
      expect(at(653, 993), line);
      expect(at(653, 960).a, 0);
      expect(at(466, 1100), line);
      expect(at(88, 1500), line);
      expect(at(1512, 1500), line);
      // The first second's half-second mark, pointing right on the
      // dialogue column's wall at its twelfth row.
      expect(at(556, 1513), line);
      expect(at(540, 1513).a, 0);
      // The info header: its top and the rule under its labels, the
      // length box's left wall.
      expect(at(1690, 49), line);
      expect(at(1690, 93), line);
      expect(at(1663, 150), line);
    });

    testWidgets('the length\'s and the sheet count\'s marks stand in the '
        'values\' row where the viewer sets them — 秒 at the left half\'s '
        'right, ＋ under コマ from the left — and the stroke rises to the '
        'right', (tester) async {
      const origin = Offset(1600, 40);
      final print = await printed(
        tester,
        sheet(),
        {SheetPaintLayer.form},
        origin: origin,
        size: const Size(1300, 190),
      );
      bool inked(Rect rect) => inkedIn(print, origin, rect);

      expect(inked(const Rect.fromLTRB(1880, 95, 1931, 150)), isTrue);
      expect(inked(const Rect.fromLTRB(1935, 160, 1980, 200)), isTrue);
      expect(inked(const Rect.fromLTRB(2100, 160, 2200, 210)), isFalse);
      // The stroke from (2776, 93) to (2604, 215).
      expect(inked(const Rect.fromLTRB(2764, 95, 2780, 100)), isTrue);
      expect(inked(const Rect.fromLTRB(2610, 200, 2630, 208)), isTrue);
    });

    // I-162-Q7 (유저 2026-11-05): 「뷰어의 OL 표시를 우리 O.L 로 채운다」.
    group('the O.L, as the viewer draws the lengths it is told', () {
      // From frame 10 of its track, 30 frames: an O.L from 6 to 14 crosses
      // its start (4 frames of のりしろ, an O.L of 8 told), one from 37 to
      // 43 its end (3, an O.L of 6) — 37 rows drawn, the end's O.L on
      // rows 31 to 36.
      const spans = [
        (start: 6, length: 8, mark: CameraInstructionMarkType.ol),
        (start: 37, length: 6, mark: CameraInstructionMarkType.ol),
      ];
      const origin = Offset(1200, 1000);
      const size = Size(250, 1700);

      Rect rowOf(XdtsSheetForm form, int row) => Rect.fromLTRB(
        (form.bodyLeft(0) + form.cameraLeft).toDouble(),
        (form.rowsTop + form.rowTop(row)).toDouble(),
        (form.bodyLeft(0) + form.cameraLeft + form.cameraBlockWidth)
            .toDouble(),
        (form.rowsTop + form.rowBottom(row)).toDouble(),
      );

      test('the lengths are written as the viewer writes them — each end '
          'that has one, in its seconds and its frames', () {
        expect(
          TimesheetDocumentPainter.xdtsOverlapWords((start: 8, end: 30)),
          '（前O.L. 0秒+8コマ）  （後O.L. 1秒+6コマ）',
        );
        expect(
          TimesheetDocumentPainter.xdtsOverlapWords((start: 48, end: 0)),
          '（前O.L. 2秒+0コマ） ',
        );
        expect(
          TimesheetDocumentPainter.xdtsOverlapWords((start: 0, end: 6)),
          ' （後O.L. 0秒+6コマ）',
        );
      });

      test('the lengths told are twice the のりしろ each end draws — the '
          'ink folder\'s settings say the same', () {
        const handles = CutTransitionHandles(head: 4, tail: 3);
        expect(xdtsViewerOverlaps(handles), (start: 8, end: 6));
        final config = xdtsViewerConfig(
          sheet: XdtsViewerSheet.a3SixSeconds,
          handles: handles,
        );
        expect(config, contains('StartOverlapFrameLength=8\n'));
        expect(config, contains('EndOverlapFrameLength=6\n'));
      });

      testWidgets('a grey mark across the camera block on every frame of '
          'each O.L — full at its ends, a point at its middle — and none '
          'past them', (tester) async {
        final document = sheet(at: 10, spans: spans);
        expect(document.drawnFrameCount, 37);
        final form = document.xdtsForm!;
        // The O.L alone: the cut's end line stands on row 37's top.
        final print = await printed(
          tester,
          document,
          SheetStratum.content.layers,
          origin: origin,
          size: size,
          parts: const {TimesheetContentPart.overlaps},
        );
        bool inked(Rect rect) => inkedIn(print, origin, rect);
        Rect centre(int row) => Rect.fromCenter(
          center: rowOf(form, row).center,
          width: 4,
          height: 4,
        );
        Rect topLeft(int row) =>
            Rect.fromLTWH(rowOf(form, row).left + 1, rowOf(form, row).top + 1,
                4, 3);
        Rect bottomLeft(int row) => Rect.fromLTWH(
          rowOf(form, row).left + 1,
          rowOf(form, row).bottom - 4,
          4,
          3,
        );

        for (final row in [0, 1, 2, 3, 4, 5, 6, 7, 31, 32, 33, 34, 35, 36]) {
          expect(inked(centre(row)), isTrue, reason: 'row $row');
        }
        for (final row in [8, 30, 37]) {
          expect(
            inked(rowOf(form, row).deflate(2)),
            isFalse,
            reason: 'row $row',
          );
        }
        Rect topRight(int row) => Rect.fromLTWH(
          rowOf(form, row).right - 5,
          rowOf(form, row).top + 1,
          4,
          3,
        );
        expect(inked(topLeft(0)), isTrue);
        expect(inked(topRight(0)), isTrue);
        expect(inked(topLeft(3)), isFalse);
        expect(inked(topRight(3)), isFalse);
        expect(inked(bottomLeft(3)), isFalse);
        expect(inked(bottomLeft(7)), isTrue);
        expect(inked(topLeft(31)), isTrue);
        expect(inked(bottomLeft(36)), isTrue);
        expect(
          pixelAt(print, origin, centre(0).center.dx.toInt(),
              centre(0).center.dy.toInt()),
          const ui.Color(0xFFA0A0A4),
          reason: 'the viewer\'s grey',
        );
      });

      testWidgets('none on a cut with no O.L, and none on the ink, which '
          'the viewer draws them over itself', (tester) async {
        final plain = await printed(
          tester,
          sheet(),
          SheetStratum.content.layers,
          origin: origin,
          size: size,
        );
        final form = sheet().xdtsForm!;
        expect(inkedIn(plain, origin, rowOf(form, 0).deflate(2)), isFalse);

        final ink = await printed(
          tester,
          sheet(at: 10, spans: spans),
          SheetStratum.content.layers,
          origin: origin,
          size: size,
          parts: xdtsViewerUnprintedParts,
        );
        expect(inkedIn(ink, origin, rowOf(form, 0).deflate(2)), isFalse);
      });

      testWidgets('the Ponoc sheet writes the lengths in their place — no '
          'other sheet has one', (tester) async {
        const kind = TimesheetSheetKind.xdtsPonocSixSeconds;
        final place = sheet(kind: kind).xdtsForm!.overlapLength!;
        expect(place, (left: 1391, top: 171, width: 711, height: 34));
        for (final other in [
          TimesheetSheetKind.xdtsA3SixSeconds,
          TimesheetSheetKind.xdtsB4ThreeSeconds,
          TimesheetSheetKind.xdtsB4SixSeconds,
        ]) {
          expect(sheet(kind: other).xdtsForm!.overlapLength, isNull);
        }
        final box = Rect.fromLTWH(
          place.left.toDouble(),
          place.top.toDouble(),
          place.width.toDouble(),
          place.height.toDouble(),
        );
        const at = Offset(1380, 160);
        const room = Size(740, 60);
        final told = await printed(
          tester,
          sheet(kind: kind, at: 10, spans: spans),
          SheetStratum.content.layers,
          origin: at,
          size: room,
        );
        // Both lengths, across the place's middle.
        expect(
          inkedIn(told, at, Rect.fromLTRB(box.left, box.top, box.center.dx,
              box.bottom)),
          isTrue,
        );
        expect(
          inkedIn(told, at, Rect.fromLTRB(box.center.dx, box.top, box.right,
              box.bottom)),
          isTrue,
        );
        final startOnly = await printed(
          tester,
          sheet(kind: kind, at: 10, spans: [spans.first]),
          SheetStratum.content.layers,
          origin: at,
          size: room,
        );
        expect(
          inkedIn(startOnly, at, Rect.fromLTRB(box.left, box.top,
              box.left + box.width / 8, box.bottom)),
          isFalse,
          reason: 'one length, half as long, on the middle',
        );
        expect(inkedIn(startOnly, at, box), isTrue);
        // Two lengths reach about twice as far out as one; the words stand
        // as tall as the place less half a millimetre lets them.
        double? firstInked(
          (Uint8List, int) print,
          Iterable<double> lines,
          Rect Function(double) line,
        ) {
          for (final at0 in lines) {
            if (inkedIn(print, at, line(at0))) {
              return at0;
            }
          }
          return null;
        }
        Iterable<double> from(double start, double end, double step) sync* {
          for (var x = start; step > 0 ? x < end : x > end; x += step) {
            yield x;
          }
        }
        Rect column(double x) =>
            Rect.fromLTRB(x, box.top, x + 1, box.bottom);
        Rect row(double y) => Rect.fromLTRB(box.left, y, box.right, y + 1);
        final bothLeft =
            firstInked(told, from(box.left, box.right, 1), column)!;
        final oneLeft =
            firstInked(startOnly, from(box.left, box.right, 1), column)!;
        expect(oneLeft - bothLeft, greaterThan(box.width / 6));
        final top = firstInked(told, from(box.top, box.bottom, 1), row)!;
        final bottom =
            firstInked(told, from(box.bottom - 1, box.top, -1), row)!;
        expect(bottom - top, greaterThan(box.height * 0.6));
        final none = await printed(
          tester,
          sheet(kind: kind),
          SheetStratum.content.layers,
          origin: at,
          size: room,
        );
        expect(inkedIn(none, at, box), isFalse);
      });

      // The ink prints the parts the viewer leaves to the hand
      // ([xdtsViewerUnprintedParts]): a part that strayed, or a value no
      // part printed, would be lost from it or printed twice.
      testWidgets('the O.L prints in its own room — over the camera block '
          'and in the lengths\' place — and the parts together print the '
          'values whole, and nothing beside them', (tester) async {
        final document = sheet(
          kind: TimesheetSheetKind.xdtsPonocSixSeconds,
          at: 10,
          spans: spans,
          logo: 'logo.png',
        );
        final logo = logoAt(await logoImage(tester));
        final form = document.xdtsForm!;
        final place = form.overlapLength!;
        // The whole page across, down past the end's O.L.
        final room = Size(
          form.pageWidth.toDouble(),
          (form.rowsTop + form.rowBottom(40)).toDouble(),
        );
        Future<Uint8List> alphasOf(Set<TimesheetContentPart>? parts) async {
          final (bytes, _) = await printed(
            tester,
            document,
            SheetStratum.content.layers,
            origin: Offset.zero,
            size: room,
            parts: parts,
            imageFor: logo,
          );
          return Uint8List.fromList([
            for (var i = 3; i < bytes.length; i += 4) bytes[i],
          ]);
        }

        final width = room.width.toInt();
        final rooms = [
          Rect.fromLTRB(
            rowOf(form, 0).left,
            rowOf(form, 0).top,
            rowOf(form, 36).right,
            rowOf(form, 36).bottom,
          ),
          Rect.fromLTWH(
            place.left.toDouble(),
            place.top.toDouble(),
            place.width.toDouble(),
            place.height.toDouble(),
          ),
        ];
        final overlaps = await alphasOf(const {TimesheetContentPart.overlaps});
        var strayed = 0;
        var marked = 0;
        for (var i = 0; i < overlaps.length; i += 1) {
          if (overlaps[i] == 0) {
            continue;
          }
          marked += 1;
          final pixel = Offset(i % width + 0.5, i ~/ width + 0.5);
          if (!rooms.any((rect) => rect.inflate(1).contains(pixel))) {
            strayed += 1;
          }
        }
        expect(marked, greaterThan(0), reason: 'the premise');
        expect(strayed, 0);

        final whole = await alphasOf(null);
        final inked = Uint8List(whole.length);
        for (final part in TimesheetContentPart.values) {
          final alphas = await alphasOf({part});
          for (var i = 0; i < alphas.length; i += 1) {
            inked[i] |= alphas[i];
          }
        }
        var missing = 0;
        var stray = 0;
        for (var i = 0; i < whole.length; i += 1) {
          if (whole[i] != 0 && inked[i] == 0) {
            missing += 1;
          }
          if (whole[i] == 0 && inked[i] != 0) {
            stray += 1;
          }
        }
        expect([missing, stray], [0, 0]);
      });
    });

    // I-162-Q5 (유저 2026-11-05): 「회사 로고를 찍는다」.
    group('the company logo, as the viewer prints its own', () {
      // A3's logo place: 51 by 17 millimetres from the info header's
      // corner. The square logo fills its height, a band a third of it.
      const place = Rect.fromLTWH(89, 49, 502, 167);
      const third = 167 / 3;
      final origin = place.topLeft - const Offset(4, 4);
      final room = place.size + const Offset(8, 8);
      Rect band(int index, double top, double bottom) => Rect.fromLTRB(
        place.left + third * index + 6,
        place.top + top,
        place.left + third * (index + 1) - 6,
        place.top + bottom,
      );

      testWidgets('from the place\'s corner, as large as fits, its shape '
          'kept — in the line colour, as opaque as it is dark, and clear '
          'where it is clear', (tester) async {
        final logo = logoAt(await logoImage(tester));
        final document = sheet(logo: 'logo.png');
        final form = document.xdtsForm!;
        expect(
          form.logo,
          (left: 89, top: 49, width: 502, height: 167),
          reason: 'the premise',
        );
        Future<(Uint8List, int)> of(Set<TimesheetContentPart>? parts) =>
            printed(
              tester,
              document,
              SheetStratum.content.layers,
              origin: origin,
              size: room,
              parts: parts,
              imageFor: logo,
            );
        final print = await of(null);
        bool inked(Rect rect) => inkedIn(print, origin, rect);
        ui.Color at(Offset point) =>
            pixelAt(print, origin, point.dx.toInt(), point.dy.toInt());

        final black = band(0, 6, 161);
        expect(at(black.center), line, reason: 'black: the line colour');
        expect(
          at(band(1, 6, 161).center).a,
          closeTo(0.5, 0.03),
          reason: 'mid grey: half of it',
        );
        expect(inked(band(2, 6, 77)), isFalse, reason: 'white: nothing');
        expect(inked(band(2, 90, 161)), isFalse, reason: 'clear: nothing');
        expect(
          inked(Rect.fromLTRB(place.left, black.top, place.left + 3,
              black.bottom)),
          isTrue,
          reason: 'from the corner',
        );
        expect(
          inked(Rect.fromLTRB(place.left + place.height + 3, place.top,
              place.right, place.bottom)),
          isFalse,
          reason: 'its shape kept, so the rest of the place is blank',
        );
        expect(
          inked(Rect.fromLTRB(place.left, place.bottom + 1, place.right,
              place.bottom + 4)),
          isFalse,
          reason: 'as large as fits, and no larger',
        );

        // It is a part of its own, which the header's values are not.
        final alone = await of(const {TimesheetContentPart.logo});
        expect(inkedIn(alone, origin, black), isTrue);
        final values = await of(const {TimesheetContentPart.header});
        expect(inkedIn(values, origin, place), isFalse);
      });

      testWidgets('a work with no logo, or one not read yet, leaves the place '
          'blank — and the title is not printed there', (tester) async {
        Future<bool> inkedWith(
          TimesheetDocument document,
          SheetImageLookup? imageFor,
        ) async => inkedIn(
          await printed(
            tester,
            document,
            SheetStratum.content.layers,
            origin: origin,
            size: room,
            imageFor: imageFor,
          ),
          origin,
          place,
        );

        expect(sheet().title, 'T', reason: 'the premise: a title');
        expect(await inkedWith(sheet(), null), isFalse);
        expect(
          await inkedWith(sheet(logo: 'logo.png'), (path, {width}) => null),
          isFalse,
        );
      });

      testWidgets('our sheets print none', (tester) async {
        final logo = logoAt(await logoImage(tester));
        final document = sheet(
          kind: TimesheetSheetKind.sixSeconds,
          logo: 'logo.png',
        );
        final layout = TimesheetDocumentLayout(document: document);
        final size = layout.documentSize;
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder)..scale(0.25);
        TimesheetDocumentPainter(
          document: document,
          layout: layout,
          face: const TextStyle(),
          words: timesheetWordsIn(AppLanguage.ja),
          layers: SheetStratum.content.layers,
          contentParts: const {TimesheetContentPart.logo},
          imageFor: logo,
        ).paint(canvas, size);
        final picture = recorder.endRecording();
        final bytes = (await tester.runAsync(() async {
          final image = await picture.toImage(
            (size.width / 4).ceil(),
            (size.height / 4).ceil(),
          );
          final data = await image.toByteData();
          image.dispose();
          return data!.buffer.asUint8List();
        }))!;
        picture.dispose();
        expect(bytes.any((byte) => byte != 0), isFalse);
      });
    });

    // I-162-Q6 (유저 2026-11-05): 「나누고, 내보내기도 원화 · 동화 두
    // 파일로」 — the viewer prints the 原画 file in the ACTION block and the
    // 動画 file in the CELL block.
    testWidgets('the values sit in the template\'s cells: a 原画 row\'s '
        'drawing in the ACTION block\'s first column and a 動画 row\'s in '
        'the CELL block\'s, each name in the head over it', (tester) async {
      const origin = Offset(80, 960);
      final print = await printed(
        tester,
        sheet(inbetweens: 1),
        SheetStratum.content.layers,
        origin: origin,
        size: const Size(700, 120),
      );
      bool inked(Rect rect) => inkedIn(print, origin, rect);

      // ACTION: 44-pixel columns from 89.
      expect(inked(const Rect.fromLTRB(91, 1011, 131, 1049)), isTrue);
      expect(inked(const Rect.fromLTRB(91, 979, 131, 1007)), isTrue);
      expect(inked(const Rect.fromLTRB(135, 979, 395, 1049)), isFalse);
      // CELL: 79-pixel columns from 574.
      expect(inked(const Rect.fromLTRB(576, 1011, 651, 1049)), isTrue);
      expect(inked(const Rect.fromLTRB(576, 979, 651, 1007)), isTrue);
      expect(inked(const Rect.fromLTRB(655, 979, 730, 1049)), isFalse);
    });

    testWidgets('the length prints its seconds and its frames each in its '
        'half of the box — no seconds under one — and the sheet count its '
        'total over this sheet', (tester) async {
      const origin = Offset(1660, 90);
      Future<bool Function(Rect)> printOf(int duration) async {
        final print = await printed(
          tester,
          sheet(duration: duration),
          SheetStratum.content.layers,
          origin: origin,
          size: const Size(1200, 130),
        );
        return (Rect rect) => inkedIn(print, origin, rect);
      }

      const seconds = Rect.fromLTRB(1665, 95, 1931, 214);
      const frames = Rect.fromLTRB(1935, 95, 2202, 214);
      const total = Rect.fromLTWH(2519, 93, 129, 71);
      const current = Rect.fromLTWH(2691, 144, 129, 71);

      final thirty = await printOf(30);
      expect(thirty(seconds), isTrue);
      expect(thirty(frames), isTrue);
      expect(thirty(total), isTrue);
      expect(thirty(current), isTrue);
      // On the values' row's middle, not the labels': the seconds reach its
      // lower part, and the sheet this is stands under the stroke.
      expect(thirty(const Rect.fromLTRB(1665, 170, 1931, 205)), isTrue);
      expect(thirty(const Rect.fromLTRB(2691, 165, 2820, 200)), isTrue);

      final twelve = await printOf(12);
      expect(twelve(seconds), isFalse);
      expect(twelve(frames), isTrue);
    });

    // I-162-Q1 (유저 2026-11-05): 「XDTS 서식에서만 뷰어 표기」 — 「일단
    // 최대한 서식대로 보여주는게 목표. 보이는그대로 출력이 목표니까」.
    group('the cel columns, written as the viewer writes them', () {
      /// A drawing named [name] exposed [length] frames.
      TimelineExposure cel(
        String name,
        int length, {
        Map<int, InbetweenMark> breakdowns = const {},
      }) => TimelineExposure.drawing(
        FrameId(name),
        length: length,
        breakdownMarks: breakdowns,
      );

      /// The cels 1 and 2 a frame each, over and over to frame 30.
      Map<int, TimelineExposure> alternating() => {
        for (var frame = 0; frame < 30; frame += 1)
          frame: cel(frame.isEven ? '1' : '2', 1),
      };

      /// A cut on [kind] of one 原画 row — a 動画 one, [inbetween] —
      /// exposing [timeline], [duration] frames long.
      TimesheetDocument written(
        Map<int, TimelineExposure> timeline, {
        int duration = 30,
        bool inbetween = false,
        TimesheetSheetKind kind = TimesheetSheetKind.xdtsA3SixSeconds,
      }) => TimesheetDocument.fromCut(
        cut: Cut(
          id: const CutId('cut'),
          name: '12',
          duration: duration,
          canvasSize: const CanvasSize(width: 1920, height: 1080),
          metadata: CutMetadata(sheetKind: kind),
          layers: [
            Layer(
              id: const LayerId('row'),
              name: 'A',
              kind: LayerKind.animation,
              mark: inbetween
                  ? const LayerMark(process: LayerProcess.inbetween)
                  : LayerMark.none,
              frames: [
                for (final name in ['1', '2', '3', '8888'])
                  Frame(
                    id: FrameId(name),
                    name: name,
                    duration: 1,
                    strokes: const [],
                  ),
              ],
              timeline: timeline,
            ),
          ],
        ),
        projectName: 'P',
        fps: 24,
        info: const TimesheetInfo(title: 'T', episode: '3'),
      );

      /// The row's column on [document]'s sheet.
      int rowColumnOf(TimesheetDocument document) =>
          document.columns.indexWhere((column) => column.layerId != null);

      /// Row [row] of the [column]th column on [layout]'s first page, in
      /// the viewer's pixels.
      Rect cellOf(TimesheetDocumentLayout layout, int column, int row) {
        final unit = unitOf(layout);
        final page = layout.pageRect(0);
        final rows = layout.halfRows(0);
        final left = layout.halfLeft(0, 0) + layout.columnLeftInHalf(column);
        final width = layout.columnWidthFor(
          layout.document.columns[column].kind,
        );
        return Rect.fromLTRB(
          (left - page.left) / unit,
          (rows.topOf(row) - page.top) / unit,
          (left + width - page.left) / unit,
          (rows.bottomOf(row) - page.top) / unit,
        );
      }

      bool anything(ui.Color pixel) => pixel.a != 0;
      bool dark(ui.Color pixel) =>
          pixel.a > 0.5 && pixel.r < 0.4 && pixel.g < 0.4 && pixel.b < 0.4;
      bool blue(ui.Color pixel) =>
          pixel.a > 0.5 && pixel.b > 0.7 && pixel.r < 0.3 && pixel.g < 0.3;

      /// The values of [document] printed back from its ACTION block's
      /// first column to the one past its row's, over 34 rows: a cell of
      /// them ([cell], the row's own column unless one is named), a pixel
      /// ([at]), and whether a rectangle holds one of a kind ([anyIn]).
      Future<
        ({
          Rect Function(int row, {int? column}) cell,
          ui.Color Function(Offset point) at,
          bool Function(Rect rect, bool Function(ui.Color) kind) anyIn,
        })
      >
      sheetOf(WidgetTester tester, TimesheetDocument document) async {
        final layout = TimesheetDocumentLayout(document: document);
        final own = rowColumnOf(document);
        final first = cellOf(layout, 0, 0);
        final origin = Offset(first.left - 20, first.top - 20);
        final last = cellOf(layout, own + 1, 34);
        final print = await printed(
          tester,
          document,
          SheetStratum.content.layers,
          origin: origin,
          size: Size(last.right + 20 - origin.dx, last.bottom - origin.dy),
        );
        ui.Color at(Offset point) =>
            pixelAt(print, origin, point.dx.floor(), point.dy.floor());
        return (
          cell: (int row, {int? column}) =>
              cellOf(layout, column ?? own, row),
          at: at,
          anyIn: (Rect rect, bool Function(ui.Color) kind) {
            for (var y = rect.top.ceil(); y < rect.bottom; y += 1) {
              for (var x = rect.left.ceil(); x < rect.right; x += 1) {
                if (kind(at(Offset(x.toDouble(), y.toDouble())))) {
                  return true;
                }
              }
            }
            return false;
          },
        );
      }

      testWidgets('a value, the line it lasts down — nine rows of the ACTION '
          'block — then the null cell\'s ×, and its wave as far', (
        tester,
      ) async {
        final sheet = await sheetOf(tester, written({0: cel('1', 12)}));
        final cell = sheet.cell;

        expect(sheet.anyIn(cell(0), dark), isTrue, reason: 'its number');
        final stem = cell(0).center.dx;
        for (final share in [0.3, 0.7]) {
          final y = cell(0).top + cell(0).height * share;
          expect(
            sheet.anyIn(Rect.fromLTRB(stem - 4, y, stem + 4, y + 2), dark),
            isTrue,
            reason: 'the 1 a row less a millimetre tall, at $share of it',
          );
        }
        expect(sheet.at(cell(4).center), predicate(dark), reason: 'a line');
        expect(
          sheet.anyIn(
            Rect.fromLTRB(
              cell(4).left + 2,
              cell(4).top + 2,
              cell(4).center.dx - 6,
              cell(4).bottom - 2,
            ),
            anything,
          ),
          isFalse,
          reason: 'down the middle alone',
        );
        expect(sheet.anyIn(cell(8).deflate(1), dark), isTrue);
        expect(
          sheet.anyIn(cell(9).deflate(1), anything),
          isFalse,
          reason: 'nine rows, its value\'s included',
        );
        expect(
          sheet.at(cell(12).topLeft + const Offset(3, 3)),
          predicate(dark),
        );
        expect(
          sheet.at(cell(12).topRight + const Offset(-3, 3)),
          predicate(dark),
          reason: 'the ×, corner to corner',
        );
        expect(
          sheet.at(Offset(cell(16).center.dx, cell(16).top + 1)),
          predicate(dark),
          reason: 'the wave',
        );
        Rect lowRightOf(int row) => Rect.fromLTRB(
          cell(row).center.dx + 3.5,
          cell(row).top + cell(row).height * 0.72,
          cell(row).center.dx + 6,
          cell(row).top + cell(row).height * 0.8,
        );
        expect(
          sheet.anyIn(lowRightOf(16), anything),
          isTrue,
          reason: 'the wave bows right low in its row',
        );
        expect(
          sheet.anyIn(lowRightOf(4), anything),
          isFalse,
          reason: 'a line does not',
        );
        expect(sheet.anyIn(cell(20).deflate(1), dark), isTrue);
        expect(
          sheet.anyIn(cell(21).deflate(3), anything),
          isFalse,
          reason: 'nine rows — the wave\'s last pen end leans past its own',
        );
      });

      testWidgets('down the CELL block the line lasts all the way', (
        tester,
      ) async {
        final document = written({0: cel('1', 20)}, inbetween: true);
        expect(
          document.columns[rowColumnOf(document)].kind,
          TimesheetColumnKind.cel,
          reason: '⛔전제',
        );
        final sheet = await sheetOf(tester, document);
        expect(sheet.at(sheet.cell(15).center), predicate(dark));
        expect(sheet.at(sheet.cell(19).center), predicate(dark));
      });

      testWidgets('the column ends under its last frame with the end mark, '
          'and nothing draws a line across the sheet', (tester) async {
        final sheet = await sheetOf(tester, written({0: cel('1', 12)}));
        final below = sheet.cell(29).shift(Offset(0, sheet.cell(29).height));

        expect(
          sheet.at(Offset(below.left + 3, below.top)),
          predicate(dark),
          reason: 'its line across the row below',
        );
        expect(
          sheet.anyIn(
            Rect.fromCenter(center: below.center, width: 3, height: 3),
            anything,
          ),
          isTrue,
          reason: 'its hatch, corner to corner',
        );
        for (final hatch in [
          Offset(below.left + below.width / 4, below.top + below.height / 4),
          Offset(below.right - below.width / 4, below.bottom - below.height / 4),
        ]) {
          expect(
            sheet.anyIn(
              Rect.fromCenter(center: hatch, width: 3, height: 3),
              anything,
            ),
            isTrue,
            reason: 'a hatch through $hatch',
          );
        }
        final next = sheet.cell(29, column: 1);
        expect(
          sheet.anyIn(
            Rect.fromLTRB(
              next.left + 2,
              below.top - 4,
              next.right - 2,
              below.top + 4,
            ),
            anything,
          ),
          isFalse,
          reason: 'the column beside, where our end line would cross',
        );
      });

      testWidgets('a repeat: its next round\'s first value in blue, its '
          'dashes nine rows down from it, the rest nothing to the value that '
          'breaks it — リピート over the dashes under the blue value', (
        tester,
      ) async {
        final sheet = await sheetOf(
          tester,
          written({...alternating(), 30: cel('3', 2)}, duration: 32),
        );
        final cell = sheet.cell;

        expect(sheet.anyIn(cell(0), blue), isFalse);
        expect(sheet.anyIn(cell(2), blue), isTrue, reason: 'the blue value');
        final x = cell(9).center.dx;
        expect(sheet.at(Offset(x, cell(9).top + 3)), predicate(blue));
        expect(
          sheet.at(Offset(x, cell(9).top + 24)).a,
          0,
          reason: 'a dash four pens long, a gap two',
        );
        expect(sheet.at(Offset(x, cell(10).top + 3)), predicate(blue));
        expect(sheet.anyIn(cell(11).deflate(1), anything), isFalse);
        expect(
          sheet.at(Offset(x, cell(4).top + 3)),
          isNot(predicate(blue)),
          reason: 'the word\'s white ground over the dashes',
        );
        expect(
          sheet.anyIn(
            Rect.fromLTRB(
              cell(3).left,
              cell(3).top,
              cell(3).right,
              cell(6).bottom,
            ),
            dark,
          ),
          isTrue,
          reason: 'the word',
        );
        expect(
          sheet.anyIn(
            Rect.fromLTRB(
              cell(5).left,
              cell(5).top + 12,
              cell(5).right,
              cell(6).bottom,
            ),
            dark,
          ),
          isTrue,
          reason: 'リピート runs four letters down',
        );
        expect(sheet.anyIn(cell(30), dark), isTrue);
        expect(sheet.anyIn(cell(30), blue), isFalse);
      });

      testWidgets('a repeat that restarts on the null cell writes its × in '
          'blue, a pixel thin', (tester) async {
        final sheet = await sheetOf(
          tester,
          written({
            for (var frame = 1; frame < 30; frame += 2) frame: cel('1', 1),
          }),
        );
        final restart = sheet.cell(2);
        bool bluish(ui.Color pixel) =>
            pixel.a > 0 &&
            pixel.b > pixel.r + 0.2 &&
            pixel.b > pixel.g + 0.2;

        expect(
          sheet.at(restart.topLeft + const Offset(3, 3)),
          predicate(bluish),
        );
        expect(sheet.at(restart.topLeft + const Offset(3, 6)).a, 0);
      });

      testWidgets('a value too wide for its cell shrinks into it, and a mark '
          'is our own ○ ● on its row\'s middle', (tester) async {
        final sheet = await sheetOf(
          tester,
          written({
            0: cel('8888', 3),
            3: cel('1', 6, breakdowns: {2: InbetweenMark.two}),
          }),
        );
        final cell = sheet.cell;

        expect(sheet.anyIn(cell(0), dark), isTrue);
        expect(
          sheet.anyIn(cell(0, column: 1).deflate(1), anything),
          isFalse,
          reason: 'within its own cell',
        );
        expect(
          sheet.anyIn(
            Rect.fromCenter(center: cell(5).center, width: 4, height: 4),
            dark,
          ),
          isTrue,
          reason: 'the mark',
        );
      });

      testWidgets('one value held through the whole column: 止メ under it, '
          'and nothing more down the column', (tester) async {
        final sheet = await sheetOf(tester, written({0: cel('1', 30)}));
        final cell = sheet.cell;

        expect(
          sheet.anyIn(
            Rect.fromLTRB(
              cell(1).left,
              cell(1).top,
              cell(1).right,
              cell(2).bottom,
            ),
            dark,
          ),
          isTrue,
          reason: 'the word',
        );
        for (final row in [4, 10, 28]) {
          expect(
            sheet.anyIn(cell(row).deflate(1), anything),
            isFalse,
            reason: 'row $row',
          );
        }
      });

      test('the drag print reads what the notation writes in view — its '
          'values, its inks and its words — which a change above it moves', () {
        /// The print of a view of rows [from] and the next of [timeline].
        Object printOf(
          Map<int, TimelineExposure> timeline, {
          required int from,
          TimesheetSheetKind kind = TimesheetSheetKind.xdtsA3SixSeconds,
        }) {
          final document = written(timeline, kind: kind);
          final layout = TimesheetDocumentLayout(document: document);
          final rows = layout.halfRows(0);
          return timesheetDragPrint(
            document: document,
            layout: layout,
            shown: Rect.fromLTRB(
              0,
              rows.topOf(from) + 1,
              layout.documentSize.width,
              rows.bottomOf(from + 1) - 1,
            ),
            cutId: null,
            preview: null,
          );
        }

        /// The cells a view of rows [from] and the next reaches — a row of
        /// slack each side — on [kind].
        List<TimesheetCell> reached(
          Map<int, TimelineExposure> timeline,
          int from, {
          TimesheetSheetKind kind = TimesheetSheetKind.xdtsA3SixSeconds,
        }) => written(
          timeline,
          kind: kind,
        ).columns.first.cells.sublist(from - 1, from + 3);

        final one = {0: cel('1', 12)};
        expect(
          printOf(one, from: 0),
          isNot(printOf({0: cel('2', 12)}, from: 0)),
          reason: 'the value it writes',
        );

        final marked = {
          0: cel('1', 12, breakdowns: {2: InbetweenMark.two}),
        };
        expect(reached(one, 9), reached(marked, 9), reason: '⛔전제');
        expect(
          printOf(one, from: 9),
          isNot(printOf(marked, from: 9)),
          reason: 'the line a mark above lasts down into it',
        );

        // The repeat starts its first round on the cel 2, a frame later.
        final later = {...alternating(), 0: cel('3', 1)};
        for (final kind in [
          TimesheetSheetKind.sixSeconds,
          TimesheetSheetKind.xdtsA3SixSeconds,
        ]) {
          expect(
            reached(alternating(), 5, kind: kind),
            reached(later, 5, kind: kind),
            reason: '⛔전제: the same cells in view',
          );
        }
        expect(
          printOf(alternating(), from: 5),
          isNot(printOf(later, from: 5)),
          reason: 'リピート hangs into it a row lower',
        );
        expect(
          printOf(alternating(), from: 5, kind: TimesheetSheetKind.sixSeconds),
          printOf(later, from: 5, kind: TimesheetSheetKind.sixSeconds),
          reason: 'our sheet prints the cells in view',
        );
      });
    });
  });


  test('our 6-second sheet and the Ponoc sheet can print the same columns '
      'and pages — the form still re-records when the cut switches between '
      'them', () {
    // Eight cel rows, two SE rows, two instruction rows: 8 · 2 · 8 · 3
    // columns on either, 144 frames a page.
    TimesheetDocument shaped(TimesheetSheetKind kind) => TimesheetDocument
        .fromCut(
          cut: Cut(
            id: const CutId('cut'),
            name: '12',
            duration: 24,
            canvasSize: const CanvasSize(width: 1920, height: 1080),
            metadata: CutMetadata(sheetKind: kind),
            layers: [
              for (var index = 0; index < 8; index += 1)
                Layer(
                  id: LayerId('cel-$index'),
                  name: String.fromCharCode(65 + index),
                  frames: const [],
                ),
              for (var index = 0; index < 2; index += 1)
                Layer(
                  id: LayerId('se-$index'),
                  name: 'S${index + 1}',
                  kind: LayerKind.se,
                  frames: const [],
                ),
              for (var index = 0; index < 2; index += 1)
                Layer(
                  id: LayerId('cam-$index'),
                  name: 'CAM${index + 1}',
                  kind: LayerKind.instruction,
                  frames: const [],
                ),
            ],
          ),
          projectName: 'P',
          fps: 24,
        );
    List<(TimesheetColumnKind, int)> shapeOf(TimesheetDocument document) => [
      for (final kind in TimesheetColumnKind.values)
        (
          kind,
          document.columns.where((column) => column.kind == kind).length,
        ),
    ];
    final ours = shaped(TimesheetSheetKind.sixSeconds);
    final ponoc = shaped(TimesheetSheetKind.xdtsPonocSixSeconds);
    expect(shapeOf(ponoc), shapeOf(ours), reason: '⛔전제: the same columns');
    expect(ponoc.pageFrameCount, ours.pageFrameCount);

    Object formOf(TimesheetDocument document) => TimesheetDocumentPainter(
      document: document,
      layout: TimesheetDocumentLayout(document: document),
      face: const TextStyle(),
      words: timesheetWordsIn(AppLanguage.ja),
      layers: const {SheetPaintLayer.form},
    ).props;
    expect(formOf(ponoc), isNot(formOf(ours)));
  });
}
