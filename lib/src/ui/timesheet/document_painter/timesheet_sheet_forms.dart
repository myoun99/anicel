part of '../timesheet_document_painter.dart';

/// A header box on the sheet: the field it prints, the box, and where its
/// value is set — ONE answer for the painter and the tap-to-edit layer.
typedef TimesheetHeaderBox = ({
  TimesheetHeaderField field,
  Rect rect,
  Rect value,
});

/// The FORM a sheet's rows are laid on — our own sheet's, or the XDTS
/// Viewer's (I-162, 유저 2026-11-05: 「서식 바꾸면 xdts의 해당 서식에서
/// 보는거랑 똑같은 화면」): where its blocks, its rows, its boxes and its
/// memo stand, and the paper it lies on.
///
/// The cells, the spans, the playhead and the ink are laid by the layout
/// from these answers — the same code on either form, which differs only
/// in where things stand.
///
/// Measures are in the form's units — a frame row is
/// [TimesheetDocumentLayout.rowHeight] high on both — from the FORM's
/// corner; the layout lays the form on its pages.
sealed class _SheetForm {
  /// The form's size.
  Size get size;

  /// The form on its paper.
  SheetPaperFit get onPaper;

  /// The paper of a page, in pixels.
  CanvasSize get paperPixelSize;

  /// A column of [kind]'s width before its group shares it out
  /// ([TimesheetDocumentLayout.columnWidthFor]).
  double columnWidth(TimesheetColumnKind kind);

  /// The frame numbers' column after the ACTION block — none on our own
  /// form, whose numbers stand left of the half.
  double get numbersColumnWidth;

  /// The left of half [half]'s first column, the half [halfWidth] wide.
  double halfLeft(int half, double halfWidth);

  /// The top of a half's first row; the head over the rows, and the row
  /// of column titles at its foot.
  double get rowsTop;
  double get headHeight;
  double get titleRowHeight;

  /// The top and the bottom of row [row] of a half, below its first row's
  /// top — of any row, before the first or past the last as well.
  double rowTopIn(int row);
  double rowBottomIn(int row);

  /// How many rows of a half lie above [offset] below its first row's
  /// top, a part of a row counted as such.
  double rowsAbove(double offset);

  /// The header's band, and the boxes of [shown] in it.
  Rect get headerBand;
  List<TimesheetHeaderBox> headerBoxes(List<TimesheetHeaderField> shown);

  /// Where the memo is written.
  Rect get memoBand;
}

/// Our own sheet's form (A-1/IG style): a padded page whose header band
/// and memo band stand over strips side by side, each with its frame
/// numbers bare on the paper left of it.
final class _OurSheetForm extends _SheetForm {
  _OurSheetForm(this._layout);

  final TimesheetDocumentLayout _layout;

  static const double _rowHeight = TimesheetDocumentLayout.rowHeight;
  static const double _padding = TimesheetDocumentLayout.pagePadding;
  static const double _gutter = TimesheetDocumentLayout.frameNumberGutterWidth;

  int get _strips => _layout.document.sheetKind.strips;

  /// The printed form's width: its strips, the gap between them and the
  /// padding round them.
  double get _width =>
      _padding * 2 +
      (_gutter + _layout.halfWidth) * _strips +
      TimesheetDocumentLayout.halfGap * (_strips - 1);

  /// What the form prints over its rows, and the padding round it all: the
  /// header band, the memo band and the gap under them.
  static const double _headHeight =
      _padding * 2 +
      TimesheetDocumentLayout.headerBandHeight +
      TimesheetDocumentLayout.memoBandHeight +
      TimesheetDocumentLayout.headerGap;

  int get _maxHalfRows => math.max(
    _layout.halfRowCount(0),
    _layout.halfRowCount(1),
  );

  /// The printed form's height: its head and a page's body.
  double get _height => _headHeight + headHeight + _maxHalfRows * _rowHeight;

  @override
  late final Size size = Size(_width, _height);

  /// The form on the timesheet's paper (`SheetPaper.timesheet`): as large
  /// as fits, centred.
  @override
  late final SheetPaperFit onPaper = SheetPaper.timesheet.around(size);

  @override
  CanvasSize get paperPixelSize => SheetPaper.timesheet.pixelSize;

  @override
  double columnWidth(TimesheetColumnKind kind) => switch (kind) {
    TimesheetColumnKind.action => TimesheetDocumentLayout.actionColumnWidth,
    TimesheetColumnKind.se => TimesheetDocumentLayout.seColumnWidth,
    TimesheetColumnKind.cel => TimesheetDocumentLayout.celColumnWidth,
    TimesheetColumnKind.camera => TimesheetDocumentLayout.cameraColumnWidth,
  };

  @override
  double get numbersColumnWidth => 0;

  @override
  double halfLeft(int half, double halfWidth) =>
      _padding +
      _gutter +
      half * (_gutter + halfWidth + TimesheetDocumentLayout.halfGap);

  @override
  double get rowsTop => _headHeight - _padding + headHeight;

  @override
  double get headHeight =>
      TimesheetDocumentLayout.groupRowHeight +
      TimesheetDocumentLayout.letterRowHeight;

  @override
  double get titleRowHeight => TimesheetDocumentLayout.letterRowHeight;

  @override
  double rowTopIn(int row) => row * _rowHeight;

  @override
  double rowBottomIn(int row) => (row + 1) * _rowHeight;

  @override
  double rowsAbove(double offset) => offset / _rowHeight;

  /// The header band — its LEFT edge sits on the grid's left bold line
  /// (the paper form's header table left-aligns with the ACTION block; the
  /// number gutter stays outside both — user fix), its right edge on the
  /// last half's right bold line.
  @override
  Rect get headerBand => Rect.fromLTRB(
    _padding + _gutter,
    _padding,
    size.width - _padding,
    _padding + TimesheetDocumentLayout.headerBandHeight,
  );

  /// Width fractions of the header boxes when all print; hiding boxes
  /// renormalizes the rest over the band. Proportions follow the user's
  /// reference sheets (R7-⑥): a slim Ep.no box, the Title clearly widest,
  /// then compact Cut/Duration/Name/Page boxes.
  static const Map<TimesheetHeaderField, double> _fractions = {
    TimesheetHeaderField.episode: 0.08,
    TimesheetHeaderField.title: 0.32,
    TimesheetHeaderField.scene: 0.10,
    TimesheetHeaderField.cut: 0.11,
    TimesheetHeaderField.time: 0.12,
    TimesheetHeaderField.name: 0.17,
    TimesheetHeaderField.sheet: 0.10,
  };

  @override
  List<TimesheetHeaderBox> headerBoxes(List<TimesheetHeaderField> shown) {
    final band = headerBand;
    var total = 0.0;
    for (final field in shown) {
      total += _fractions[field]!;
    }
    final boxes = <TimesheetHeaderBox>[];
    var x = band.left;
    for (var index = 0; index < shown.length; index += 1) {
      // The last box closes exactly on the band edge (no rounding drift).
      final right = index == shown.length - 1
          ? band.right
          : x + band.width * (_fractions[shown[index]]! / total);
      final rect = Rect.fromLTRB(x, band.top, right, band.bottom);
      boxes.add((
        field: shown[index],
        rect: rect,
        value: TimesheetDocumentPainter.headerValueRect(rect),
      ));
      x = right;
    }
    return boxes;
  }

  /// Directly under the header band, on its edges.
  @override
  Rect get memoBand => Rect.fromLTWH(
    headerBand.left,
    headerBand.bottom,
    headerBand.width,
    TimesheetDocumentLayout.memoBandHeight,
  );
}

/// The XDTS Viewer's form ([XdtsSheetForm]): its page, laid in its own
/// pixels and scaled so a frame row is ours — the rows of every cell sit
/// where the viewer's do, the double rule of a second's end and all.
final class _XdtsSheetForm extends _SheetForm {
  _XdtsSheetForm(this.form);

  final XdtsSheetForm form;

  /// The units a pixel of the viewer's page is.
  late final double unit = TimesheetDocumentLayout.rowHeight / form.rowHeight;

  /// The viewer's pixels to the timesheet paper's.
  static final double _toPaper = SheetPaper.timesheet.dpi / XdtsSheetForm.dpi;

  double _at(int pixels) => pixels * unit;

  Rect _rectAt(int left, int top, int width, int height) =>
      Rect.fromLTWH(_at(left), _at(top), _at(width), _at(height));

  @override
  late final Size size = Size(_at(form.pageWidth), _at(form.pageHeight));

  /// The page IS the form: the paper at the timesheet's resolution, as
  /// wide as the viewer widens it for the blocks' rows — its pixels
  /// whole, and the page their measure, so a pixel of the ink is a pixel
  /// of the paper (F-294): a hair past the viewer's page at its right and
  /// its foot, where nothing is drawn.
  @override
  late final SheetPaperFit onPaper = () {
    final scale = _toPaper / unit;
    final pixels = paperPixelSize;
    return SheetPaperFit.whole(
      scale: scale,
      sheet: Size(pixels.width / scale, pixels.height / scale),
    );
  }();

  @override
  late final CanvasSize paperPixelSize = CanvasSize(
    width: (form.pageWidth * _toPaper).round(),
    height: (form.pageHeight * _toPaper).round(),
  );

  @override
  double columnWidth(TimesheetColumnKind kind) => _at(switch (kind) {
    TimesheetColumnKind.action => form.keyColWidth,
    TimesheetColumnKind.se => form.dialogColWidth,
    TimesheetColumnKind.cel => form.cellsColWidth,
    TimesheetColumnKind.camera => form.cameraColWidth,
  });

  @override
  double get numbersColumnWidth => _at(form.lastKeyColWidth);

  @override
  double halfLeft(int half, double halfWidth) => _at(form.bodyLeft(half));

  @override
  double get rowsTop => _at(form.rowsTop);

  @override
  double get headHeight => _at(form.headerHeight);

  /// The head's lower half, where the viewer writes a column's name.
  @override
  double get titleRowHeight =>
      _at(form.headerHeight - form.headerHeight ~/ 2);

  @override
  double rowTopIn(int row) => _at(form.rowTop(row));

  @override
  double rowBottomIn(int row) => _at(form.rowBottom(row));

  @override
  double rowsAbove(double offset) {
    final pixels = offset / unit;
    final second = (pixels / form.secondHeight).floor();
    final within = pixels - second * form.secondHeight;
    return second * XdtsSheetForm.rowsPerSecond + within / form.rowHeight;
  }

  /// The info header's boxes, end to end.
  @override
  Rect get headerBand {
    final last = form.info.last;
    return Rect.fromLTRB(
      _at(form.info.first.left),
      _at(form.infoTop),
      _at(last.left + last.width),
      _at(form.infoBottom),
    );
  }

  /// The info header's boxes, their values set in the row under the
  /// labels. The viewer's form has no box for the title: its logo place
  /// prints the company logo ([_XdtsLogoPass], I-162-Q5 「회사 로고를
  /// 찍는다」). ↩️The title stood there (I-162-Q2: 「채운다(제목은 로고
  /// 자리에)」) until that answer.
  @override
  List<TimesheetHeaderBox> headerBoxes(List<TimesheetHeaderField> shown) {
    return [
      for (final place in form.info)
        if (shown.contains(place.box.field))
          (
            field: place.box.field,
            rect: _rectAt(
              place.left,
              form.infoTop,
              place.width,
              form.infoBottom - form.infoTop,
            ),
            value: _rectAt(
              place.left,
              form.infoTitleBottom,
              place.width,
              form.infoBottom - form.infoTitleBottom,
            ),
          ),
    ];
  }

  @override
  Rect get memoBand {
    final memo = form.memo;
    return _rectAt(memo.left, memo.top, memo.width, memo.height);
  }
}
