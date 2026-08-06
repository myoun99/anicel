import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
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
import 'package:anicel/src/ui/conte/conte_page_painter.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';

/// The conte's four strata, and the rule that gives the split its point:
/// **the form layer never reads project data.**
///
/// Three things used to break it, all of them the same shape — a mark that
/// existed only where the film did. They are gone (user, 2026-08-06): the
/// big X over empty rows, the heavier box redrawn wherever a cut started,
/// and the picture border that appeared only where a cell was.
void main() {
  Project project({int cutCount = 1}) => Project(
    id: const ProjectId('conte-layers'),
    name: 'Conte',
    cameraSize: const CanvasSize(width: 32, height: 18),
    createdAt: DateTime.utc(2026, 8, 6),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Video',
        cuts: [
          for (var index = 0; index < cutCount; index += 1)
            Cut(
              id: CutId('c$index'),
              name: '${index + 1}',
              duration: 6,
              canvasSize: const CanvasSize(width: 64, height: 36),
              layers: [
                Layer(
                  id: LayerId('c$index-sb'),
                  name: 'SB',
                  kind: LayerKind.storyboard,
                  frames: [
                    Frame(
                      id: FrameId('c$index-f'),
                      duration: 1,
                      strokes: const [],
                    ),
                  ],
                  timeline: {
                    0: TimelineExposure.drawing(
                      FrameId('c$index-f'),
                      length: 6,
                    ),
                  },
                ),
              ],
            ),
        ],
      ),
    ],
  );

  (ConteSheetSource, ContePageLayout) sheet({int cutCount = 1}) {
    final source = buildConteSheetSource(project(cutCount: cutCount));
    final pages = layoutConteSheet(
      source,
      metrics: const ConteSheetMetrics(cameraAspect: 16 / 9),
    );
    return (source, pages.first);
  }

  Future<ui.Image> render(
    ConteSheetSource source,
    ContePageLayout page, {
    Set<SheetPaintLayer>? layers,
  }) async {
    final metrics = page.metrics;
    final width = metrics.pageWidth.round();
    final height = metrics.pageHeight.round();
    final recorder = ui.PictureRecorder();
    ContePagePainter(
      page: page,
      source: source,
      layers: layers,
    ).paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  Future<(int, int, int, int)> pixelAt(
    ui.Image image,
    double x,
    double y,
  ) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final offset = (y.round() * image.width + x.round()) * 4;
    return (
      data!.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
      data.getUint8(offset + 3),
    );
  }

  testWidgets('the form prints every picture frame, on the rows a cut '
      'reaches and the ones it does not', (tester) async {
    await tester.runAsync(() async {
      // One cut fills one row; four rows of the five stay empty.
      final (source, page) = sheet();
      final metrics = page.metrics;
      final image = await render(
        source,
        page,
        layers: const {SheetPaintLayer.paper, SheetPaintLayer.form},
      );
      addTearDown(image.dispose);

      for (var row = 0; row < metrics.rowsPerPage; row += 1) {
        final centre = Offset(
          (metrics.pictureLeft + metrics.actionLeft) / 2,
          metrics.rowTop(row) + metrics.rowHeight / 2,
        );
        final pixel = await pixelAt(image, centre.dx, centre.dy);
        expect(
          pixel.$1,
          lessThan(250),
          reason: 'row $row: the picture well is toned, not bare paper',
        );
        expect(pixel.$4, 255, reason: 'row $row: and it is on the paper');
      }
    });
  });

  testWidgets('an EMPTY page draws the same form as a full one — no X, no '
      'box that appeared because a cut did', (tester) async {
    await tester.runAsync(() async {
      final (source, page) = sheet();
      final full = await render(
        source,
        page,
        layers: const {SheetPaintLayer.paper, SheetPaintLayer.form},
      );
      addTearDown(full.dispose);
      final bytes = await full.toByteData(format: ui.ImageByteFormat.rawRgba);

      // The same page, with NOTHING placed on it: the form stratum has to
      // come out byte-identical, which is the whole contract.
      final emptyPage = ContePageLayout(
        pageIndex: page.pageIndex,
        metrics: page.metrics,
        cells: const [],
        cutBands: const [],
        emptyRowsFrom: 0,
        pageTotalLabel: page.pageTotalLabel,
      );
      final empty = await render(
        const ConteSheetSource(cuts: []),
        emptyPage,
        layers: const {SheetPaintLayer.paper, SheetPaintLayer.form},
      );
      addTearDown(empty.dispose);
      final emptyBytes = await empty.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );

      expect(
        emptyBytes!.buffer.asUint8List(),
        bytes!.buffer.asUint8List(),
        reason: 'the form does not read the film',
      );
    });
  });

  testWidgets('the content stratum alone carries no rules — only what the '
      'project says', (tester) async {
    await tester.runAsync(() async {
      final (source, page) = sheet();
      final metrics = page.metrics;
      final image = await render(
        source,
        page,
        layers: const {SheetPaintLayer.content},
      );
      addTearDown(image.dispose);

      // The body's outer rule is form: nothing on the content layer.
      final onRule = await pixelAt(
        image,
        metrics.bodyLeft,
        metrics.bodyTop + metrics.rowHeight,
      );
      expect(onRule.$4, 0, reason: 'a rule is form, and form is not here');
    });
  });
}
