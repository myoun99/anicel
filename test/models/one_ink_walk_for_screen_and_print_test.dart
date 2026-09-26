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
    String? inkId,
    int startFrame = 0,
    int rowSpan = 1,
  }) => ContePlacedCell(
    cutId: cutId,
    cutName: cutId,
    cellIndex: 0,
    source: ConteCellSource(
      startFrame: startFrame,
      endFrameExclusive: startFrame + 12,
      pictureFrame: startFrame,
      frameId: frameId == null ? null : FrameId(frameId),
      inkId: inkId,
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
        metrics: metrics,
      );

  test('the PAGE ink comes first and covers the whole page — it lies under '
      'the rows', () {
    final windows = conteInkMarks(page(const []), metrics).toList();

    expect(windows, hasLength(1));
    expect(windows.single.key, conteInkPageKey(0));
    expect(
      windows.single.placement.window,
      Rect.fromLTWH(0, 0, metrics.pageWidth, metrics.pageHeight),
    );
  });

  test('each cell adds its ROW BAND, after the page and in cell order', () {
    final windows = conteInkMarks(
      page([
        cell(cutId: 'c1', rowOnPage: 0, frameId: 'f1', inkId: 'i1'),
        cell(cutId: 'c2', rowOnPage: 1, frameId: 'f2', inkId: 'i2'),
      ]),
      metrics,
    ).toList();

    expect(windows.map((w) => w.key), [
      conteInkPageKey(0),
      conteInkRowKey(const CutId('c1'), 'i1'),
      conteInkRowKey(const CutId('c2'), 'i2'),
    ]);
  });

  test('⛔a cell with NO frame is skipped — both walkers did this, and the '
      'one that stopped would print a band the screen never showed', () {
    final windows = conteInkMarks(
      page([
        cell(cutId: 'c1', rowOnPage: 0),
        cell(cutId: 'c2', rowOnPage: 1, frameId: 'f2', inkId: 'i2'),
      ]),
      metrics,
      unwrittenInkIdOf: (placed) => 'named-${placed.cutId}',
    ).toList();

    expect(windows.map((w) => w.key), [
      conteInkPageKey(0),
      conteInkRowKey(const CutId('c2'), 'i2'),
    ]);
  });

  test('a block never written on prints NO band, and the pen writes it '
      'under the name it is given ahead', () {
    final sheet = page([
      cell(cutId: 'c1', rowOnPage: 0, frameId: 'f1', startFrame: 4),
    ]);

    expect(conteInkMarks(sheet, metrics).map((w) => w.key), [
      conteInkPageKey(0),
    ]);
    expect(
      conteInkMarks(
        sheet,
        metrics,
        unwrittenInkIdOf: (placed) =>
            'named-${placed.cutId}-${placed.source.startFrame}',
      ).map((w) => w.key),
      [conteInkPageKey(0), conteInkRowKey(const CutId('c1'), 'named-c1-4')],
    );
  });

  test('a block written on keeps its OWN id — the name ahead is not asked',
      () {
    final windows = conteInkMarks(
      page([cell(cutId: 'c1', rowOnPage: 0, frameId: 'f1', inkId: 'i1')]),
      metrics,
      unwrittenInkIdOf: (_) => 'named',
    ).toList();

    expect(windows.last.key, conteInkRowKey(const CutId('c1'), 'i1'));
  });

  test('🚨two exposures of ONE drawing are two bands — each block writes '
      'for itself', () {
    final windows = conteInkMarks(
      page([
        cell(cutId: 'c1', rowOnPage: 0, frameId: 'f', inkId: 'i1'),
        cell(
          cutId: 'c1',
          rowOnPage: 1,
          frameId: 'f',
          inkId: 'i2',
          startFrame: 12,
        ),
      ]),
      metrics,
    ).toList();

    expect(windows.map((w) => w.key).skip(1), [
      conteInkRowKey(const CutId('c1'), 'i1'),
      conteInkRowKey(const CutId('c1'), 'i2'),
    ]);
  });

  test('the band is the cell\'s ROWS, so a two-row cell gets a taller one', () {
    final windows = conteInkMarks(
      page([
        cell(
          cutId: 'c1',
          rowOnPage: 0,
          frameId: 'f1',
          inkId: 'i1',
          rowSpan: 2,
        ),
      ]),
      metrics,
    ).toList();

    final band = windows.last.placement.window;
    expect(band.top, metrics.rowTop(0));
    expect(band.bottom, metrics.rowTop(2));
    expect(band.left, metrics.cutColumnLeft);
    expect(band.right, metrics.bodyRight);
  });

  test('the page key follows the PAGE INDEX — page two must not ink over '
      'page one', () {
    final windows = conteInkMarks(
      page(const [], pageIndex: 2),
      metrics,
    ).toList();

    expect(windows.single.key, conteInkPageKey(2));
    expect(windows.single.key, isNot(conteInkPageKey(0)));
  });

  test('a row key is the CUT and the BLOCK\'s id — the same id under two '
      'cuts is two windows, and the key reads back its id', () {
    final key = conteInkRowKey(const CutId('a'), 'i');

    expect(key, isNot(conteInkRowKey(const CutId('b'), 'i')));
    expect(conteInkRowIdOf(key), 'i');
    expect(conteInkRowIdOf(conteInkPageKey(0)), isNull);
  });
}
