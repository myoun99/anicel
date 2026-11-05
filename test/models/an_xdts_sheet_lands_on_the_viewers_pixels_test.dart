import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/xdts_sheet_form.dart';
import 'package:anicel/src/models/xdts_viewer_sheet.dart';

/// I-162 (유저 2026-11-05): 「서식 바꾸면 xdts의 해당 서식에서 보는거랑
/// 똑같은 화면이었으면해」 — an XDTS sheet is laid out as the XDTS Viewer
/// lays it, in its 250dpi pixels, every length rounded on its own.
///
/// The numbers are the viewer's own, worked out from its source by the
/// spec this round was built from (its §7 tables, one per template) — not
/// from the millimetres, which land as much as half a millimetre off them.
void main() {
  ({List<int> x, List<int> y}) lines(XdtsSheetForm form, int body) {
    final left = form.bodyLeft(body);
    return (
      x: [
        left,
        left + form.keyColumns * form.keyColWidth,
        left + form.dialogLeft,
        left + form.cellsLeft,
        left + form.cameraLeft,
        left + form.cameraLeft + form.cameraBlockWidth,
        left + form.bodyWidth,
      ],
      y: [
        form.infoTop,
        form.infoTitleBottom,
        form.infoBottom,
        form.bodyTop,
        form.rowsTop,
        form.rowsTop + form.rowBottom(XdtsSheetForm.bodyRows - 1),
        form.bodyTop + form.bodyHeight,
      ],
    );
  }

  List<(int, int)> infoBoxes(XdtsSheetForm form) => [
    for (final place in form.info) (place.left, place.width),
  ];

  test('the A3 6-second sheet', () {
    final form = XdtsSheetForm(XdtsViewerSheet.a3SixSeconds, columns: 0);
    expect((form.pageWidth, form.pageHeight), (2923, 4134));
    expect((form.originLeft, form.originTop), (89, 49));
    expect(lines(form, 0).x, [89, 397, 466, 574, 1206, 1443, 1442]);
    expect(lines(form, 1).x, [1511, 1819, 1888, 1996, 2628, 2865, 2864]);
    expect(lines(form, 0).y, [49, 93, 216, 945, 1009, 4045, 4050]);
    expect(infoBoxes(form), [
      (640, 354),
      (994, 295),
      (1289, 374),
      (1663, 541),
      (2204, 315),
      (2519, 344),
    ]);
  });

  test('the B4 3-second sheet', () {
    final form = XdtsSheetForm(XdtsViewerSheet.b4ThreeSeconds, columns: 0);
    expect((form.pageWidth, form.pageHeight), (2530, 3583));
    expect((form.originLeft, form.originTop), (74, 59));
    expect(lines(form, 0).x, [74, 760, 824, 937, 2071, 2450, 2456]);
    expect(lines(form, 0).y, [59, 103, 187, 399, 483, 3519, 3524]);
    expect(infoBoxes(form), [
      (930, 261),
      (1191, 177),
      (1368, 182),
      (1550, 394),
      (1944, 256),
      (2200, 256),
    ]);
  });

  test('the B4 6-second sheet', () {
    final form = XdtsSheetForm(XdtsViewerSheet.b4SixSeconds, columns: 0);
    expect((form.pageWidth, form.pageHeight), (2530, 3583));
    expect((form.originLeft, form.originTop), (94, 59));
    expect(lines(form, 0).x, [94, 290, 359, 457, 947, 1241, 1246]);
    expect(lines(form, 1).x, [1295, 1491, 1560, 1658, 2148, 2442, 2447]);
    expect(lines(form, 0).y, [59, 103, 187, 418, 482, 3518, 3523]);
    expect(infoBoxes(form), [
      (921, 256),
      (1177, 182),
      (1359, 182),
      (1541, 394),
      (1935, 256),
      (2191, 256),
    ]);
  });

  test('the Ponoc 6-second sheet — its frame numbers have no column', () {
    final form = XdtsSheetForm(XdtsViewerSheet.ponocSixSeconds, columns: 0);
    expect((form.pageWidth, form.pageHeight), (2530, 3583));
    expect((form.originLeft, form.originTop), (73, 39));
    expect(form.lastKeyColWidth, 0);
    expect(lines(form, 0).x, [73, 385, 385, 473, 991, 1213, 1209]);
    expect(lines(form, 1).x, [1333, 1645, 1645, 1733, 2251, 2473, 2469]);
    expect(lines(form, 0).y, [39, 72, 164, 474, 559, 3507, 3505]);
    expect(infoBoxes(form), [
      (1184, 363),
      (1547, 397),
      (1944, 252),
      (2196, 252),
    ]);
  });

  test('the rows by a second\'s double rule share its gap — the Ponoc '
      'sheet\'s, a second shorter than its rows, gives a pixel each', () {
    final a3 = XdtsSheetForm(XdtsViewerSheet.a3SixSeconds, columns: 0);
    // The A3 sheet's spec example: the second second's first row is
    // 2020…2065, reaching 3 px up into the gap.
    expect(a3.rowsTop + a3.rowTop(24), 2020);
    expect(a3.rowsTop + a3.rowBottom(24), 2065);
    expect(a3.rowsTop + a3.rowBottom(23), 2020);
    expect(a3.rowsTop + a3.rowTop(1), 1009 + 42);
    final ponoc = XdtsSheetForm(
      XdtsViewerSheet.ponocSixSeconds,
      columns: 0,
    );
    expect(ponoc.heightAdjust, -1);
    expect(ponoc.rowBottom(23), 983);
    expect(ponoc.rowTop(24), 983);
    // Before the first row and past the last, the same rule runs on — a
    // span begun in an earlier half lies where it began.
    expect(a3.rowTop(-1), -1014 + 23 * 42);
    expect(a3.rowTop(72), 3 * 1014 - 3);
  });

  test('the rows tile a body: each starts where the one before ends', () {
    for (final template in [
      XdtsViewerSheet.a3SixSeconds,
      XdtsViewerSheet.b4ThreeSeconds,
      XdtsViewerSheet.b4SixSeconds,
      XdtsViewerSheet.ponocSixSeconds,
    ]) {
      final form = XdtsSheetForm(template, columns: 0);
      expect(form.rowTop(0), 0, reason: template.label);
      for (var row = 1; row < XdtsSheetForm.bodyRows; row += 1) {
        expect(
          form.rowTop(row),
          form.rowBottom(row - 1),
          reason: '${template.label} row $row',
        );
        expect(
          form.rowBottom(row),
          greaterThan(form.rowTop(row)),
          reason: '${template.label} row $row',
        );
      }
    }
  });

  // I-162-Q6 (유저 2026-11-05): 「나누고, 내보내기도 원화 · 동화 두
  // 파일로」 — and the viewer widens both blocks of such a pair.
  test('a block with more cel columns than it holds widens BOTH blocks to '
      'as many, and the paper by the bodies\' widening — as the viewer '
      'widens a 原画 · 動画 pair', () {
    // A3: ACTION 7 columns of 44 px and the numbers' 69, CELL 8 of 79.
    final form = XdtsSheetForm(XdtsViewerSheet.a3SixSeconds, columns: 10);
    expect((form.keyColumns, form.cellsColumns), (10, 10));
    expect(form.bodyWidth, 1353 + 3 * 44 + 2 * 79);
    expect(form.pageWidth, 2923 + 2 * (3 * 44 + 2 * 79));
    expect(form.bodyLeft(1), 89 + form.bodyWidth + 69);
    expect(form.dialogLeft, 10 * 44 + 69);
    expect(form.cameraLeft, 10 * 44 + 69 + 108 + 10 * 79);
    expect(form.pageHeight, 4134);
    // The info header stands where it stood.
    expect(
      infoBoxes(form),
      infoBoxes(XdtsSheetForm(XdtsViewerSheet.a3SixSeconds, columns: 0)),
    );
    // Each block past its own count only: eight widen the ACTION block's
    // seven, and the CELL block holds them.
    final eight = XdtsSheetForm(XdtsViewerSheet.a3SixSeconds, columns: 8);
    expect((eight.keyColumns, eight.cellsColumns), (8, 8));
    expect(eight.bodyWidth, 1353 + 44);
    // Blocks that hold them are left as they are.
    final fits = XdtsSheetForm(XdtsViewerSheet.a3SixSeconds, columns: 7);
    expect((fits.keyColumns, fits.cellsColumns), (7, 8));
    expect(fits.bodyWidth, 1353);
  });
}
