import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';

TimesheetDocument _document({
  int duration = 150,
  TimesheetInfo info = TimesheetInfo.empty,
}) {
  return TimesheetDocument.fromCut(
    cut: Cut(
      id: const CutId('cut-1'),
      name: 'Cut 1',
      layers: const [],
      duration: duration,
      canvasSize: const CanvasSize(width: 1280, height: 720),
    ),
    projectName: 'Project',
    fps: 24,
    info: info,
  );
}

void main() {
  group('TimesheetDocumentLayout continuous mode', () {
    test('keeps the paged paper width and header geometry (user rule: the '
        'view toggle never resizes the paper)', () {
      final document = _document();
      final paged = TimesheetDocumentLayout(document: document);
      final continuous = TimesheetDocumentLayout(
        document: document,
        continuous: true,
      );

      expect(continuous.paperWidth, paged.paperWidth);

      final pagedRect = paged.pageRect(0);
      final continuousRect = continuous.pageRect(0);
      expect(continuousRect.left, pagedRect.left);
      expect(continuousRect.top, pagedRect.top);
      expect(continuousRect.width, pagedRect.width);
    });

    test('only the body below the header changes: one strip in page half '
        '0\'s geometry, extending with the row count', () {
      final document = _document();
      final paged = TimesheetDocumentLayout(document: document);
      final continuous = TimesheetDocumentLayout(
        document: document,
        continuous: true,
      );

      expect(continuous.halfLeft(0, 0), paged.halfLeft(0, 0));
      expect(continuous.halfRowsTop(0), paged.halfRowsTop(0));
      expect(
        continuous.paperHeight,
        greaterThan(paged.paperHeight),
        reason: 'the 288-row strip runs down a single page block',
      );
      expect(continuous.positionOfFrame(200), (page: 0, half: 0, row: 200));
      expect(
        continuous.frameRowTop(1) - continuous.frameRowTop(0),
        TimesheetDocumentLayout.rowHeight,
      );
    });
  });

  group('TimesheetDocumentLayout memo band', () {
    test('sits under the header band and pushes the rows down', () {
      final layout = TimesheetDocumentLayout(document: _document());

      final band = layout.memoBandRect(0);
      final page = layout.pageRect(0);
      expect(
        band.top,
        page.top +
            TimesheetDocumentLayout.pagePadding +
            TimesheetDocumentLayout.headerBandHeight,
      );
      expect(band.height, TimesheetDocumentLayout.memoBandHeight);
      expect(
        layout.halfRowsTop(0),
        band.bottom +
            TimesheetDocumentLayout.headerGap +
            layout.columnsHeaderHeight,
      );
    });
  });

  group('TimesheetDocumentLayout header alignment', () {
    test('header and memo bands share the grid\'s vertical edges (user fix: '
        'the paper form left-aligns the header table with the ACTION block, '
        'the number gutter stays outside both)', () {
      final layout = TimesheetDocumentLayout(document: _document());

      final header = layout.headerBandRect(0);
      final memo = layout.memoBandRect(0);
      expect(header.left, layout.halfLeft(0, 0));
      expect(memo.left, layout.halfLeft(0, 0));
      expect(header.right, layout.halfLeft(0, 1) + layout.halfWidth);
      expect(memo.right, header.right);

      final pageTwo = layout.headerBandRect(1);
      expect(pageTwo.left, layout.halfLeft(1, 0));
    });

    test(
      'continuous mode keeps the same left alignment on the fixed paper',
      () {
        final layout = TimesheetDocumentLayout(
          document: _document(),
          continuous: true,
        );

        expect(layout.headerBandRect(0).left, layout.halfLeft(0, 0));
        expect(layout.memoBandRect(0).left, layout.halfLeft(0, 0));
      },
    );
  });

  group('TimesheetDocumentLayout header field boxes', () {
    test('all boxes print by default, tiling the band exactly in order', () {
      final layout = TimesheetDocumentLayout(document: _document());

      final band = layout.headerBandRect(0);
      final boxes = layout.headerFieldBoxes(0);
      expect(
        boxes.map((box) => box.field).toList(),
        TimesheetHeaderField.values,
      );
      expect(boxes.first.rect.left, band.left);
      expect(boxes.last.rect.right, band.right);
      for (var index = 1; index < boxes.length; index += 1) {
        expect(
          boxes[index].rect.left,
          boxes[index - 1].rect.right,
          reason: 'boxes tile without gaps',
        );
      }
    });

    test('hidden boxes drop out and the rest renormalize over the band', () {
      final layout = TimesheetDocumentLayout(
        document: _document(
          info: const TimesheetInfo(
            hiddenFields: {
              TimesheetHeaderField.scene,
              TimesheetHeaderField.episode,
              TimesheetHeaderField.sheet,
            },
          ),
        ),
      );

      final band = layout.headerBandRect(0);
      final boxes = layout.headerFieldBoxes(0);
      expect(boxes.map((box) => box.field).toList(), const [
        TimesheetHeaderField.title,
        TimesheetHeaderField.cut,
        TimesheetHeaderField.time,
        TimesheetHeaderField.name,
      ]);
      expect(boxes.first.rect.left, band.left);
      expect(boxes.last.rect.right, band.right);
    });
  });

  group('TimesheetDocumentLayout cut-end line', () {
    test('lands at the bottom edge of the last playback frame row', () {
      final layout = TimesheetDocumentLayout(document: _document());

      // duration 150 → last frame 149 = page 1, half 0, row 5.
      final line = layout.cutEndLine;
      expect(line.page, 1);
      expect(line.half, 0);
      expect(
        line.y,
        layout.halfRowsTop(1) + 6 * TimesheetDocumentLayout.rowHeight,
      );
    });

    test('spans into the second half and closes a full half cleanly', () {
      final second = TimesheetDocumentLayout(
        document: _document(duration: 100),
      );
      // last frame 99 → half 1, row 27.
      expect(second.cutEndLine.half, 1);
      expect(
        second.cutEndLine.y,
        second.halfRowsTop(0) + 28 * TimesheetDocumentLayout.rowHeight,
      );

      final boundary = TimesheetDocumentLayout(
        document: _document(duration: 72),
      );
      // exactly one half used → the line closes half 0's bottom.
      expect(boundary.cutEndLine.half, 0);
      expect(
        boundary.cutEndLine.y,
        boundary.halfRowsTop(0) + 72 * TimesheetDocumentLayout.rowHeight,
      );
    });

    test('continuous mode maps it onto the single strip', () {
      final layout = TimesheetDocumentLayout(
        document: _document(),
        continuous: true,
      );

      expect(layout.cutEndLine.page, 0);
      expect(layout.cutEndLine.half, 0);
      expect(
        layout.cutEndLine.y,
        layout.halfRowsTop(0) + 150 * TimesheetDocumentLayout.rowHeight,
      );
    });
  });

  group('B4 paper width vs instruction rows', () {
    TimesheetDocument documentWithInstructionLayers(int count) {
      return TimesheetDocument.fromCut(
        cut: Cut(
          id: const CutId('cut-cam'),
          name: 'Cut CAM',
          layers: [
            for (var index = 0; index < count; index += 1)
              Layer(
                id: LayerId('cam-$index'),
                name: 'CAM ${index + 1}',
                kind: LayerKind.instruction,
                frames: const [],
                timeline: const {},
              ),
          ],
          duration: 48,
          canvasSize: const CanvasSize(width: 1280, height: 720),
        ),
        projectName: 'Project',
        fps: 24,
      );
    }

    test('adding instruction layers NEVER widens the paper: the CAM group '
        'keeps its fixed width and its columns narrow instead', () {
      final base = TimesheetDocumentLayout(
        document: documentWithInstructionLayers(0),
      );
      final crowded = TimesheetDocumentLayout(
        document: documentWithInstructionLayers(5),
      );

      expect(crowded.paperWidth, base.paperWidth);
      expect(crowded.halfWidth, base.halfWidth);

      // 1 keyframe column + 5 instruction columns share the two-slot
      // allotment.
      expect(
        crowded.columnWidthFor(TimesheetColumnKind.camera) * 6,
        moreOrLessEquals(TimesheetDocumentLayout.cameraGroupWidth),
      );
      expect(
        base.columnWidthFor(TimesheetColumnKind.camera),
        TimesheetDocumentLayout.cameraColumnWidth,
      );
    });

    test('R27 #32: adding SE tracks NEVER lengthens the paper either — the '
        'SE group keeps its fixed width and its columns narrow instead', () {
      TimesheetDocument documentWithSeLayers(int count) {
        return TimesheetDocument.fromCut(
          cut: Cut(
            id: const CutId('cut-se'),
            name: 'Cut SE',
            layers: [
              for (var index = 0; index < count; index += 1)
                Layer(
                  id: LayerId('se-$index'),
                  name: 'S${index + 1}',
                  kind: LayerKind.se,
                  frames: const [],
                  timeline: const {},
                ),
            ],
            duration: 48,
            canvasSize: const CanvasSize(width: 1280, height: 720),
          ),
          projectName: 'Project',
          fps: 24,
        );
      }

      final base = TimesheetDocumentLayout(document: documentWithSeLayers(2));
      final crowded = TimesheetDocumentLayout(
        document: documentWithSeLayers(6),
      );

      // (Sub-picometre float drift from the 40/6 split, not a layout change.)
      expect(crowded.paperWidth, moreOrLessEquals(base.paperWidth));
      expect(crowded.halfWidth, moreOrLessEquals(base.halfWidth));
      expect(
        crowded.columnWidthFor(TimesheetColumnKind.se) * 6,
        moreOrLessEquals(TimesheetDocumentLayout.seGroupWidth),
      );
      expect(
        base.columnWidthFor(TimesheetColumnKind.se),
        TimesheetDocumentLayout.seColumnWidth,
      );
    });
  });
}
