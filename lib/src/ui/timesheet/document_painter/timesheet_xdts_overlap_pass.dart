part of '../timesheet_document_painter.dart';

/// THE O.L THE XDTS VIEWER DRAWS OF A CUT (I-162-Q7, 유저 2026-11-05:
/// 「뷰어의 OL 표시를 우리 O.L 로 채운다」) — the lengths it is told
/// ([xdtsViewerOverlaps]) as it draws them: on every frame of an O.L a grey
/// mark across the camera block, narrowing to the O.L's middle and
/// widening again, and on a sheet with the place for them the lengths in
/// its words.
class _XdtsOverlapPass {
  _XdtsOverlapPass(this._page);

  final _XdtsPage _page;

  XdtsSheetForm get _form => _page.form;

  /// The viewer's mark: its grey, multiplied into what lies under it.
  static final Paint _mark = Paint()
    ..color = const Color(0xFFA0A0A4)
    ..blendMode = BlendMode.multiply;

  static const String _startWord = '前O.L.';
  static const String _endWord = '後O.L.';

  /// Page [pageIndex]'s O.L: the marks on its frames, and the lengths.
  void paintPage(Canvas canvas, int pageIndex) {
    final painter = _page._painter;
    final overlaps = xdtsViewerOverlaps(painter.document.transitionHandles);
    if (overlaps.start <= 0 && overlaps.end <= 0) {
      return;
    }
    final drawn = painter.liveDrawnFrameCount;
    final pageFrames = painter.document.pageFrameCount;
    final first = pageIndex * pageFrames;
    final last = math.min(first + pageFrames, drawn);
    final startTo = math.min(last, overlaps.start);
    final endFrom = drawn - overlaps.end;
    _page.on(canvas, pageIndex, () {
      for (var frame = first; frame < startTo; frame += 1) {
        _paintMark(canvas, frame - first, frame, overlaps.start);
      }
      for (var frame = math.max(first, endFrom); frame < last; frame += 1) {
        _paintMark(canvas, frame - first, frame - endFrom, overlaps.end);
      }
      _paintLengths(canvas, overlaps);
    });
  }

  /// The mark on row [onPage] of the page — frame [into] of an O.L
  /// [length] long: as wide as the camera block at the O.L's ends, a
  /// point at its middle.
  void _paintMark(Canvas canvas, int onPage, int into, int length) {
    final body = onPage ~/ XdtsSheetForm.bodyRows;
    final row = onPage % XdtsSheetForm.bodyRows;
    final left = (_form.bodyLeft(body) + _form.cameraLeft).toDouble();
    final width = _form.cameraBlockWidth.toDouble();
    final top = (_form.rowsTop + _form.rowTop(row)).toDouble();
    final bottom = (_form.rowsTop + _form.rowBottom(row)).toDouble();
    final from = into / length;
    final to = (into + 1) / length;
    canvas.drawPath(
      Path()
        ..moveTo(left + width * from, top)
        ..lineTo(left + width * (1 - from), top)
        ..lineTo(left + width * (1 - to), bottom)
        ..lineTo(left + width * to, bottom)
        ..close(),
      _mark,
    );
  }

  /// The lengths as the viewer writes them, on the middle of their place
  /// as large as it is less half a millimetre.
  void _paintLengths(Canvas canvas, ({int start, int end}) overlaps) {
    final place = _form.overlapLength;
    if (place == null) {
      return;
    }
    String said(String side, int frames) =>
        '（$side ${frames ~/ XdtsSheetForm.rowsPerSecond}'
        '${_XdtsFormPass._secondsWord}+'
        '${frames % XdtsSheetForm.rowsPerSecond}'
        '${_XdtsFormPass._framesWord}）';
    final text = [
      if (overlaps.start > 0) '${said(_startWord, overlaps.start)} ',
      if (overlaps.end > 0) ' ${said(_endWord, overlaps.end)}',
    ].join();
    _page.words(
      canvas,
      text,
      Rect.fromLTWH(
        place.left.toDouble(),
        place.top.toDouble(),
        place.width.toDouble(),
        place.height.toDouble(),
      ),
      (
        size: (place.height - _XdtsPage.px(0.5)).toDouble(),
        color: TimesheetDocumentPainter._ink,
        across: TextAlign.center,
        middle: true,
      ),
    );
  }
}
