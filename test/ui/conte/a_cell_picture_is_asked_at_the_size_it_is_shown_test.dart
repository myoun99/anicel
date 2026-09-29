import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_page_marks.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/canvas/viewport_canvas_transform.dart';
import 'package:anicel/src/ui/conte/conte_page_painter.dart';
import 'package:anicel/src/ui/conte/conte_words_in.dart';

/// 🗣️유저 2026-09-25 (conte-picture-resolution-Q1): 「화면이 필요한
/// 만큼(최대 원본)」. A cell asks for its picture at the device pixels its
/// window shows it — a zoom asks a sharper one, and so does a denser screen.
/// ↩️It asked one 640px picture whatever the zoom, which a cell zoomed past
/// about 2.4× stretched.
void main() {
  final source = ConteSheetSource(
    cuts: [
      ConteCutSource(
        cutId: const CutId('a'),
        name: '1',
        durationFrames: 24,
        cumulativeEndFrames: 24,
        cells: const [
          ConteCellSource(
            startFrame: 0,
            endFrameExclusive: 24,
            pictureFrame: 0,
          ),
        ],
      ),
    ],
  );
  final page = layoutConteSheet(source).single;
  final frame = contePictureOf(page.cells.single, page.metrics).frame;

  /// The height the page asks its one picture at, printed through a view
  /// at [zoom] on a screen of [ratio].
  double askedAt(double zoom, double ratio) {
    final view = renderSnappedViewport(
      CanvasViewport(zoom: zoom, panX: 11, panY: 7),
      ratio,
    );
    final m = page.metrics;
    final size = Size(
      view.panX + view.zoom * m.pageWidth,
      view.panY + view.zoom * m.pageHeight,
    );
    final asked = <double>[];
    final recorder = ui.PictureRecorder();
    ContePagePainter(
      page: page,
      source: source,
      words: conteWordsIn(AppLanguage.ja),
      viewport: view,
      effectiveRatio: ratio,
      pictureFor: (_, shownHeight) {
        asked.add(shownHeight);
        return null;
      },
    ).paint(Canvas(recorder), size);
    recorder.endRecording().dispose();
    expect(asked, hasLength(1), reason: 'the one cell asks once');
    return asked.single;
  }

  test('a cell asks at its frame\'s height in device pixels: twice the zoom '
      'or twice the density asks twice as tall', () {
    expect(askedAt(1, 1), closeTo(frame.height, 1));
    expect(askedAt(2, 1), closeTo(frame.height * 2, 1));
    expect(askedAt(1, 2), closeTo(frame.height * 2, 1));
    expect(askedAt(3, 2), closeTo(frame.height * 6, 1));
  });
}
