import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/conte/conte_ink_windows.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';

/// 🚨A PAGE WHOSE INK WALK DIFFERS BETWEEN SCREEN AND PRINT PRINTS
/// SOMETHING THE USER NEVER SAW.
///
/// The panel painter and the PDF writer both walk this, so it is one
/// function — and the ORDER is part of it, because the page ink lies under
/// the rows.
void main() {
  const metrics = ConteSheetMetrics();

  ContePlacedCell cell({
    required String cutId,
    required int rowOnPage,
    String? frameId,
    int rowSpan = 1,
  }) => ContePlacedCell(
    cutId: cutId,
    cutName: cutId,
    cellIndex: 0,
    source: ConteCellSource(
      startFrame: 0,
      endFrameExclusive: 12,
      pictureFrame: 0,
      frameId: frameId == null ? null : FrameId(frameId),
      rowSpan: rowSpan,
    ),
    pictureRect: Rect.zero,
    actionRect: Rect.zero,
    dialogueRect: Rect.zero,
    rowOnPage: rowOnPage,
  );

  ContePageLayout page(List<ContePlacedCell> cells, {int pageIndex = 0}) =>
      ContePageLayout(
        pageIndex: pageIndex,
        cells: cells,
        cutBands: const [],
        emptyRowsFrom: cells.length,
        pageTotalLabel: '',
        metrics: metrics,
      );

  test('the PAGE ink comes first and covers the whole page — it lies under '
      'the rows', () {
    final windows = conteInkWindows(page(const []), metrics).toList();

    expect(windows, hasLength(1));
    expect(windows.single.key, conteInkPageKey(0));
    expect(
      windows.single.rect,
      Rect.fromLTWH(0, 0, metrics.pageWidth, metrics.pageHeight),
    );
  });

  test('each cell adds its ROW BAND, after the page and in cell order', () {
    final windows = conteInkWindows(
      page([
        cell(cutId: 'c1', rowOnPage: 0, frameId: 'f1'),
        cell(cutId: 'c2', rowOnPage: 1, frameId: 'f2'),
      ]),
      metrics,
    ).toList();

    expect(windows.map((w) => w.key), [
      conteInkPageKey(0),
      conteInkRowKey(const CutId('c1'), const FrameId('f1')),
      conteInkRowKey(const CutId('c2'), const FrameId('f2')),
    ]);
  });

  test('⛔a cell with NO frame is skipped — both walkers did this, and the '
      'one that stopped would print a band the screen never showed', () {
    final windows = conteInkWindows(
      page([
        cell(cutId: 'c1', rowOnPage: 0),
        cell(cutId: 'c2', rowOnPage: 1, frameId: 'f2'),
      ]),
      metrics,
    ).toList();

    expect(windows.map((w) => w.key), [
      conteInkPageKey(0),
      conteInkRowKey(const CutId('c2'), const FrameId('f2')),
    ]);
  });

  test('the band is the cell\'s ROWS, so a two-row cell gets a taller one', () {
    final windows = conteInkWindows(
      page([cell(cutId: 'c1', rowOnPage: 0, frameId: 'f1', rowSpan: 2)]),
      metrics,
    ).toList();

    final band = windows.last.rect;
    expect(band.top, metrics.rowTop(0));
    expect(band.bottom, metrics.rowTop(2));
    expect(band.left, metrics.cutColumnLeft);
    expect(band.right, metrics.bodyRight);
  });

  test('the page key follows the PAGE INDEX — page two must not ink over '
      'page one', () {
    final windows = conteInkWindows(
      page(const [], pageIndex: 2),
      metrics,
    ).toList();

    expect(windows.single.key, conteInkPageKey(2));
    expect(windows.single.key, isNot(conteInkPageKey(0)));
  });

  test('a row key is the CUT and the FRAME — the same drawing under two '
      'cuts is two windows', () {
    expect(
      conteInkRowKey(const CutId('a'), const FrameId('f')),
      isNot(conteInkRowKey(const CutId('b'), const FrameId('f'))),
    );
  });
}
