part of '../timesheet_document_painter.dart';

/// THE VALUES THE XDTS VIEWER WRITES INTO ITS HEADER — the cut's length and
/// the sheet count — as it writes them: each number as large as its half
/// of the box lets it be (I-162). The rest of the header's values are ours
/// and set our way ([_TimesheetBandsPass]).
class _XdtsCountsPass {
  _XdtsCountsPass(this._page);

  final _XdtsPage _page;

  XdtsSheetForm get _form => _page.form;

  /// Whether the header box of [field] holds a value the viewer counts
  /// and writes its own way.
  static bool writes(TimesheetHeaderField field) =>
      field == TimesheetHeaderField.time || field == TimesheetHeaderField.sheet;

  /// The value of [field]'s box on page [pageIndex].
  void paint(Canvas canvas, TimesheetHeaderField field, int pageIndex) {
    for (final place in _form.info) {
      if (place.box.field != field) {
        continue;
      }
      final box = _page.valueBox(place);
      _page.on(canvas, pageIndex, () {
        switch (field) {
          case TimesheetHeaderField.time:
            _paintLength(canvas, box);
          case TimesheetHeaderField.sheet:
            _paintSheetCount(canvas, box, pageIndex);
          case _:
            break;
        }
      });
    }
  }

  /// The cut's length: its whole seconds over the left half — from a
  /// second on — and the frames past them over the right.
  void _paintLength(Canvas canvas, XdtsPixelRect box) {
    final frames = _page._painter.livePlaybackFrameCount;
    const perSecond = XdtsSheetForm.rowsPerSecond;
    final half = (box.width ~/ 2).toDouble();
    final left = box.left.toDouble();
    final top = box.top.toDouble();
    final height = box.height.toDouble();
    if (frames >= perSecond) {
      _page.fitted(
        canvas,
        '${frames ~/ perSecond}',
        Rect.fromLTWH(left, top, half, height),
        TextAlign.center,
      );
    }
    if (frames > 0) {
      _page.fitted(
        canvas,
        '${frames % perSecond}',
        Rect.fromLTWH(left + half, top, half, height),
        TextAlign.center,
      );
    }
  }

  /// The sheets the cut fills, centred, and the one this is, from the
  /// left — over and under the stroke as the marks say
  /// ([XdtsViewerSheet.totalOverCurrent]).
  void _paintSheetCount(Canvas canvas, XdtsPixelRect box, int pageIndex) {
    final width = 3 * (box.width ~/ 8).toDouble();
    final height = (box.height ~/ 2 + _XdtsPage.px(1)).toDouble();
    final over = Rect.fromLTWH(
      box.left.toDouble(),
      box.top.toDouble(),
      width,
      height,
    );
    final under = Rect.fromLTWH(
      (box.left + box.width ~/ 2).toDouble(),
      (box.top + box.height ~/ 2 - _XdtsPage.px(1)).toDouble(),
      width,
      height,
    );
    final totalOver = _form.template.totalOverCurrent;
    _page.fitted(
      canvas,
      '${_page._painter.livePageCount}',
      totalOver ? over : under,
      TextAlign.center,
    );
    _page.fitted(
      canvas,
      '${pageIndex + 1}',
      totalOver ? under : over,
      TextAlign.left,
    );
  }
}
