// timesheet-sheet-kind-ink-Q1 (유저 2026-09-27): 「프레임을 따라 옮겨 붙인다」
// · 「g셀만큼 그린게 3초시트로 늘리면 g셀까지만 보이게 똑같이 하면 늘리던
// 다시 줄이던 동일하잖아」.
//
// THE WRITING STAYS ON ITS CELLS: it lives on 6-second band surfaces
// whatever the sheet, and the 3-second sheet shows it through windows that
// stretch each run of columns as wide as its cells print — so a switch moves
// no stroke off its frame or its cell, and switching back is the same
// paper, pixel for pixel.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/models/timesheet_sheet_kind.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_bands.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_layer.dart';

const _cutId = CutId('cut');

TimesheetDocumentLayout _layout(TimesheetSheetKind kind) =>
    TimesheetDocumentLayout(
      document: TimesheetDocument.fromCut(
        cut: Cut(
          id: _cutId,
          name: '1',
          duration: 200,
          canvasSize: const CanvasSize(width: 1920, height: 1080),
          metadata: CutMetadata(sheetKind: kind),
          layers: [
            for (var index = 0; index < 3; index += 1)
              Layer(
                id: LayerId('cel-$index'),
                name: String.fromCharCode(65 + index),
                frames: const [],
              ),
          ],
        ),
        projectName: 'P',
        fps: 24,
      ),
    );

/// The middle of cell ([column], [frame]) on [layout]'s paper.
Offset _cell(TimesheetDocumentLayout layout, int column, int frame) {
  final at = layout.positionOfFrame(frame);
  final kind = layout.document.columns[column].kind;
  return Offset(
    layout.halfLeft(at.page, at.half) +
        layout.columnLeftInHalf(column) +
        layout.columnWidthFor(kind) / 2,
    layout.frameRowTop(frame) + TimesheetDocumentLayout.rowHeight / 2,
  );
}

/// The band surface and the surface pixel [layout]'s strip windows keep
/// [paper] on.
(String, Offset) _pixel(TimesheetDocumentLayout layout, Offset paper) {
  final window = timesheetInkWindows(
    layout: layout,
    pagedLayout: layout,
    cutId: _cutId,
  ).singleWhere(
    (window) =>
        window.plane == TimesheetInkPlane.strip &&
        window.documentRect.contains(paper),
  );
  return (window.key.frameId.value, window.placement.pixelOf(paper));
}

/// [column] of [kind] block on [layout]'s strip.
int _column(TimesheetDocumentLayout layout, TimesheetColumnKind kind, int at) {
  var seen = 0;
  for (var index = 0; index < layout.document.columns.length; index += 1) {
    if (layout.document.columns[index].kind == kind && seen++ == at) {
      return index;
    }
  }
  throw StateError('no $kind column $at');
}

void main() {
  test('on the 6-second sheet a strip is ONE run: the surface is laid out '
      'as the strip is', () {
    final layout = _layout(TimesheetSheetKind.sixSeconds);
    final run = timesheetInkRuns(layout).single;
    expect((run.first, run.end), (0, layout.document.columns.length));
    expect((run.surfaceLeft, run.stretch), (0.0, 1.0));
    expect(run.width, closeTo(layout.halfWidth, 1e-9));
  });

  test('a cell\'s writing lies on the SAME surface pixel on either sheet — '
      'every block, both halves of a 6-second page', () {
    final six = _layout(TimesheetSheetKind.sixSeconds);
    final three = _layout(TimesheetSheetKind.threeSeconds);
    for (final (kind, at) in [
      (TimesheetColumnKind.action, 0),
      (TimesheetColumnKind.action, 6),
      (TimesheetColumnKind.se, 1),
      (TimesheetColumnKind.cel, 2),
      (TimesheetColumnKind.cel, 7),
      (TimesheetColumnKind.camera, 1),
    ]) {
      // Frame 10 is the first strip on both sheets; frame 100 the 6-second
      // page's right half and the second 3-second page; frame 150 the
      // second 6-second band.
      for (final frame in [10, 100, 150]) {
        final onSix = _pixel(six, _cell(six, _column(six, kind, at), frame));
        final onThree = _pixel(
          three,
          _cell(three, _column(three, kind, at), frame),
        );
        expect(onThree.$1, onSix.$1, reason: '$kind $at @$frame: the band');
        expect(
          (onThree.$2 - onSix.$2).distance,
          lessThan(1e-6),
          reason: '$kind $at @$frame: the pixel',
        );
      }
    }
  });

  test('the columns only the 3-second sheet prints keep their writing past '
      'the 6-second strip, on a surface wide enough for them however the '
      'cut is printed now', () {
    final six = _layout(TimesheetSheetKind.sixSeconds);
    final three = _layout(TimesheetSheetKind.threeSeconds);
    final surface = timesheetInkStripWidth(six.document);
    expect(surface, timesheetInkStripWidth(three.document));
    // The surface is kept at the paper's grade: its pixels, back in the
    // sheet's units.
    final scale = three.paperScale;
    expect(scale, six.paperScale, reason: 'one paper, either sheet');
    for (final kind in [TimesheetColumnKind.action, TimesheetColumnKind.cel]) {
      for (var at = 8; at < 12; at += 1) {
        final pixel = _pixel(three, _cell(three, _column(three, kind, at), 10));
        final across = pixel.$2.dx / scale;
        expect(across, greaterThan(six.halfWidth), reason: '$kind $at');
        expect(across, lessThan(surface), reason: '$kind $at');
      }
    }
  });

  test('a 3-second window shows its surface stretched to its cells, and '
      'its brush writes through the same stretch', () {
    final three = _layout(TimesheetSheetKind.threeSeconds);
    final window = timesheetInkWindows(
      layout: three,
      pagedLayout: three,
      cutId: _cutId,
    ).firstWhere((window) => window.plane == TimesheetInkPlane.strip);
    final placement = window.placement;
    final stretch = TimesheetDocumentLayout.columnScaleOf(
      TimesheetSheetKind.threeSeconds,
    );
    expect(placement.stretch, stretch);
    expect(window.stretch, stretch);
    // Round trip, and a surface pixel — one of the paper's — is [stretch]
    // of its own width across on the sheet.
    final scale = three.paperScale;
    expect(placement.scale, scale);
    const paper = Offset(300, 900);
    expect(
      (placement.paperOf(placement.pixelOf(paper)) - paper).distance,
      lessThan(1e-9),
    );
    expect(
      placement.paperOf(const Offset(11, 0)).dx -
          placement.paperOf(const Offset(10, 0)).dx,
      closeTo(stretch / scale, 1e-9),
    );
    expect(
      placement.surfaceRect.width,
      closeTo(window.documentRect.width * scale / stretch, 1e-9),
    );
    // The brush sees the surface unstretched; the layer lays it wider.
    final unstretched = placement.unstretched;
    expect(unstretched.stretch, 1);
    expect(unstretched.window.left, placement.window.left);
    expect(unstretched.surfaceRect, placement.surfaceRect);
  });

  test('the ink-keys stay the 6-second band\'s: the 3-second second page '
      'writes on band 0\'s lower rows', () {
    final three = _layout(TimesheetSheetKind.threeSeconds);
    final (band, pixel) = _pixel(three, _cell(three, 0, 80));
    expect(band, timesheetInkStripKey(_cutId, 0).frameId.value);
    expect(
      pixel.dy,
      closeTo(
        (80 + 0.5) * TimesheetDocumentLayout.rowHeight * three.paperScale,
        1e-9,
      ),
    );
  });

  testWidgets('a stroke on the 3-second sheet lands under the pen — on a '
      'column the 6-second strip has too and on one only the 3-second sheet '
      'prints — and the 6-second sheet shows it on the same cell', (
    tester,
  ) async {
    final three = _layout(TimesheetSheetKind.threeSeconds);
    final six = _layout(TimesheetSheetKind.sixSeconds);
    final controller = TimesheetInkController()..syncGeometry(three);
    addTearDown(controller.dispose);
    final strokeActive = ValueNotifier<bool>(false);
    addTearDown(strokeActive.dispose);
    final size = three.documentSize;
    await tester.binding.setSurfaceSize(
      Size(size.width + 40, size.height + 40),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: TimesheetInkLayer(
                controller: controller,
                layout: three,
                pagedLayout: three,
                cutId: _cutId,
                brushToolState: ValueNotifier(BrushToolState.defaults),
                historyManager: HistoryManager(),
                viewport: CanvasViewport(),
                strokeActive: strokeActive,
              ),
            ),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byType(TimesheetInkLayer));

    bool inkUnder(TimesheetDocumentLayout layout, Offset paper) {
      final window = timesheetInkWindows(
        layout: layout,
        pagedLayout: layout,
        cutId: _cutId,
      ).singleWhere(
        (window) =>
            window.plane == TimesheetInkPlane.strip &&
            window.documentRect.contains(paper),
      );
      final surface = controller
          .sessionStateFor(TimesheetInkPlane.strip, window.key)
          .canvasState
          .currentSurface;
      final pixel = window.placement.pixelOf(paper);
      return (surfacePixelRgba(
                surface,
                pixel.dx.floor(),
                pixel.dy.floor(),
              ) ??
              0) !=
          0;
    }

    // Down the middle of ACTION C and of ACTION J, rows 10 to 14.
    for (final column in [2, 9]) {
      final top = _cell(three, column, 10);
      final bottom = _cell(three, column, 14);
      final gesture = await tester.startGesture(
        origin + top,
        pointer: 7 + column,
      );
      await tester.pump();
      for (var step = 1; step <= 4; step += 1) {
        await gesture.moveTo(origin + Offset.lerp(top, bottom, step / 4)!);
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
      expect(
        inkUnder(three, _cell(three, column, 12)),
        isTrue,
        reason: 'column $column, under the pen',
      );
    }
    expect(
      inkUnder(six, _cell(six, 2, 12)),
      isTrue,
      reason: 'C on the 6-second sheet: the same cell',
    );
    expect(inkUnder(three, _cell(three, 4, 12)), isFalse);
    expect(inkUnder(six, _cell(six, 4, 12)), isFalse);
  });
}
