import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

import '../../helpers/camera_key_names.dart';

/// 🗣️I-89 ⑤ (유저 2026-10-10): 「헤더이름따라서 이름 적고, 없거나 하면 아까
/// 정한대로 12f 이런식으로 프레임 번호」 — and again, the sheet still dotting
/// them (유저 2026-10-13): 「아직도 타임시트 용지패널에 카메라 키가 동그란 점을
/// 찍거든? 분명 이름없으면 궤적쪽이랑 똑같은 규칙으로 프레임번호, 있으면
/// 이름으로 하라고했는데」.
///
/// A key's row in the first CAM column writes the key as the camera's path
/// and the conte write it — the name its lanes agree on, else the frame it
/// stands on — where it printed a dot.
///
/// The camera keys 2 → 8 → 14 on a 24-frame cut: a pan, then a zoom in.
void main() {
  CameraPose at(double x, {double zoom = 1}) =>
      CameraPose(center: CanvasPoint(x: x, y: 0), zoom: zoom);

  final moving = CutCamera(
    keyframes: {2: at(0), 8: at(30), 14: at(30, zoom: 2)},
  );
  const keys = [2, 8, 14];

  TimesheetDocument sheetOf(CutCamera camera) => TimesheetDocument.fromCut(
    cut: Cut(
      id: const CutId('cut'),
      name: '1',
      duration: 24,
      canvasSize: const CanvasSize(width: 1920, height: 1080),
      layers: const [],
      camera: camera,
    ),
    projectName: 'P',
    fps: 24,
    pageSeconds: 6,
    instructionDefById: CameraInstructionSet.standard.defById,
  );

  int cameraColumnOf(TimesheetDocument document) => document.columns
      .indexWhere((column) => column.kind == TimesheetColumnKind.camera);

  test('🎯a key\'s row carries the name its lanes agree on, else the frame '
      'it stands on — and no other row carries one', () {
    final document = sheetOf(
      cameraKeyNamed(
        cameraKeyNamed(moving, 8, position: 'A', scale: 'A', rotation: 'A'),
        14,
        position: 'B',
        scale: 'C',
        rotation: 'B',
      ),
    );
    final cells = document.columns[cameraColumnOf(document)].cells;

    expect(
      [
        for (final (row, cell) in cells.indexed)
          if (cell.keyLabel != null) (row, cell.kind, cell.keyLabel),
      ],
      [
        (2, TimesheetCellKind.cameraKey, '3f'),
        (8, TimesheetCellKind.cameraKey, 'A'),
        (14, TimesheetCellKind.cameraKey, '15f'),
      ],
      reason:
          '2 and 8 begin a move, whose name their rows carry as well; 14\'s '
          'lanes are called apart — its header\'s 「...」 — so it reads as an '
          'unnamed key does',
    );
    expect(
      (cells[8].label, cells[2].label),
      ('T.U', 'PAN'),
      reason: '⛔전제: the moves\' names are on the key rows too',
    );
  });

  /// What [document] writes centred on the first CAM column's line at the
  /// top of each key's row — the width of each word, by key — and whether
  /// anything is dotted on the line there.
  ({Map<int, List<double>> words, bool dotted}) keysAsPrinted(
    TimesheetDocument document,
  ) {
    final ink = _Ink();
    final layout = TimesheetDocumentLayout(document: document);
    TimesheetDocumentPainter(
      words: timesheetWordsIn(AppLanguage.en),
      face: const TextStyle(),
      document: document,
      layout: layout,
    ).paint(ink, layout.documentSize);

    final column = cameraColumnOf(document);
    final columnWidth = layout.columnWidthFor(TimesheetColumnKind.camera);
    final words = <int, List<double>>{};
    var dotted = false;
    for (final key in keys) {
      final (:page, :half, row: _) = layout.positionOfFrame(key);
      final lineX =
          layout.halfLeft(page, half) +
          layout.columnLeftInHalf(column) +
          columnWidth / 2;
      final top = layout.frameRowTop(key);
      words[key] = [
        for (final word in ink.words)
          if ((word.at.dy - (top + 3)).abs() < 0.01 &&
              (word.at.dx + word.width / 2 - lineX).abs() < 0.5)
            word.width,
      ];
      dotted =
          dotted ||
          ink.dots.any(
            (dot) =>
                (dot.dx - lineX).abs() < 0.5 &&
                dot.dy > top &&
                dot.dy < top + TimesheetDocumentLayout.rowHeight,
          );
    }
    return (words: words, dotted: dotted);
  }

  test('🎯a key\'s row writes its key over the line — no dot — and a named '
      'one writes its name where an unnamed one writes its frame', () {
    final unnamed = keysAsPrinted(sheetOf(moving));
    final named = keysAsPrinted(
      sheetOf(
        cameraKeyNamed(moving, 8, position: 'A', scale: 'A', rotation: 'A'),
      ),
    );

    expect(unnamed.dotted, isFalse);
    expect(named.dotted, isFalse);
    for (final key in keys) {
      expect(unnamed.words[key], hasLength(1), reason: 'key $key');
      expect(named.words[key], hasLength(1), reason: 'key $key');
    }
    final [three, nine, fifteen] = [
      for (final key in keys) unnamed.words[key]!.single,
    ];
    expect(nine, three, reason: '「9f」 is as wide as 「3f」');
    expect(fifteen, greaterThan(nine), reason: '「15f」 has a digit more');
    expect(
      [for (final key in keys) named.words[key]!.single],
      [three, lessThan(nine), fifteen],
      reason: 'only 8 is called — 「A」 where it wrote 「9f」',
    );
  });
}

/// The words and dots a sheet prints, where.
class _Ink implements Canvas {
  final words = <({Offset at, double width})>[];
  final dots = <Offset>[];

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) =>
      words.add((at: offset, width: paragraph.longestLine));

  @override
  void drawCircle(Offset c, double radius, Paint paint) => dots.add(c);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
