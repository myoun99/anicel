import 'cut_envelope_form.dart';

/// A box placed on paper: the form's fractions turned into paper units.
class PlacedEnvelopeBox {
  const PlacedEnvelopeBox({
    required this.box,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final EnvelopeBox box;
  final double x;
  final double y;
  final double width;
  final double height;

  double get right => x + width;
  double get bottom => y + height;

  bool contains(double px, double py) =>
      px >= x && px < right && py >= y && py < bottom;
}

/// A form ruled onto one sheet of paper.
///
/// The paper is chosen by the caller — a real 봉투 size, or the cut's own
/// canvas so the exported image drops straight into a working file as a
/// layer. The form keeps its aspect ratio either way and whatever the
/// paper has left over stays margin: "여백은 여백인 채로" (user rule).
class CutEnvelopeLayout {
  CutEnvelopeLayout._({
    required this.form,
    required this.paperWidth,
    required this.paperHeight,
    required this.formX,
    required this.formY,
    required this.formWidth,
    required this.formHeight,
  });

  factory CutEnvelopeLayout.fit({
    required CutEnvelopeForm form,
    required double paperWidth,
    required double paperHeight,
  }) {
    if (paperWidth <= 0 || paperHeight <= 0) {
      throw ArgumentError('Paper must have a positive size.');
    }
    // Contain, never cover: a cropped form would lose boxes at the edge.
    final byWidth = paperWidth / form.aspectRatio <= paperHeight;
    final width = byWidth ? paperWidth : paperHeight * form.aspectRatio;
    final height = byWidth ? paperWidth / form.aspectRatio : paperHeight;
    return CutEnvelopeLayout._(
      form: form,
      paperWidth: paperWidth,
      paperHeight: paperHeight,
      formX: (paperWidth - width) / 2,
      formY: (paperHeight - height) / 2,
      formWidth: width,
      formHeight: height,
    );
  }

  final CutEnvelopeForm form;

  final double paperWidth;
  final double paperHeight;

  /// The form's own rectangle inside the paper.
  final double formX;
  final double formY;
  final double formWidth;
  final double formHeight;

  /// Whether the paper's shape left any margin at all.
  bool get hasMargin =>
      formWidth < paperWidth - 0.5 || formHeight < paperHeight - 0.5;

  /// Form-space text sizes are quoted at the form's design width, so they
  /// scale with it like every other measurement.
  double get textScale => formWidth / _designWidth;

  /// The design width form text sizes are quoted against — the presets are
  /// authored at this width, so a 10pt label reads as 10pt there.
  static const double _designWidth = 660;

  PlacedEnvelopeBox place(EnvelopeBox box) => PlacedEnvelopeBox(
    box: box,
    x: formX + box.rect.x * formWidth,
    y: formY + box.rect.y * formHeight,
    width: box.rect.width * formWidth,
    height: box.rect.height * formHeight,
  );

  List<PlacedEnvelopeBox> get placedBoxes => [
    for (final box in form.boxes) place(box),
  ];

  /// The ink box a point lands in.
  ///
  /// Boxes are searched in REVERSE order so a small cell drawn over a
  /// larger one wins — the presets stack a length cell under its three
  /// readings, and the reading boxes take no ink at all, so what is left
  /// is the innermost box that actually wants strokes.
  EnvelopeBox? inkBoxAt(double x, double y) {
    for (var index = form.boxes.length - 1; index >= 0; index -= 1) {
      final box = form.boxes[index];
      if (!box.takesInk) {
        continue;
      }
      if (place(box).contains(x, y)) {
        return box;
      }
    }
    return null;
  }
}
