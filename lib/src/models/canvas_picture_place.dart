import 'canvas_resize_anchor.dart';
import 'canvas_size.dart';
import 'media_asset.dart' show MediaFitMode;

/// Where a cut's picture goes on a canvas it is resized to: kept to one of
/// the nine anchors (the size window), moved by an offset (the edges
/// dragged on the canvas, I-79) — both as it was born, nothing in it
/// changed — or fitted to the new canvas as an import fits a picture
/// (I-180).
///
/// 🗣️I-180-Q5 a 「늘 가운데(임포트와 같음)」 · Q6 a 「끈 만큼의 옮기기는
/// 원본 크기일 때만」: a fit stands the picture in the middle whatever an
/// anchor or the edges dragged say, so a fit carries neither — no place
/// holds a fit and an offset at once ([under] is where the two meet).
sealed class CanvasPicturePlace {
  const CanvasPicturePlace();

  /// [born] where [fit] keeps the picture as it was born, else that fit —
  /// what a window or the canvas's edges, which hold both while one is
  /// picked, hand a resize.
  static CanvasPicturePlace under(
    MediaFitMode fit,
    CanvasPicturePlace born,
  ) => fit == MediaFitMode.born ? born : PictureFittedBy(fit);

  /// How far the picture moves on a canvas resized [from] → [to]: where the
  /// old canvas's top left lands on the new one.
  ({double dx, double dy}) offsetFrom(CanvasSize from, CanvasSize to);

  /// How the picture goes onto the new canvas — born for a place that
  /// moves it as it was born.
  MediaFitMode get fit => MediaFitMode.born;
}

/// The picture kept to [anchor] ([CanvasResizeAnchor.contentOffset]).
final class PictureKeptTo extends CanvasPicturePlace {
  const PictureKeptTo(this.anchor);

  final CanvasResizeAnchor anchor;

  @override
  ({double dx, double dy}) offsetFrom(CanvasSize from, CanvasSize to) =>
      anchor.contentOffset(from: from, to: to);
}

/// The picture moved by [offset], whatever the sizes.
final class PictureMovedBy extends CanvasPicturePlace {
  const PictureMovedBy(this.offset);

  /// Kept where it was, at the top left.
  static const none = PictureMovedBy((dx: 0.0, dy: 0.0));

  final ({double dx, double dy}) offset;

  @override
  ({double dx, double dy}) offsetFrom(CanvasSize from, CanvasSize to) =>
      offset;
}

/// The picture fitted to the new canvas by [fit] — centred, so it moves by
/// no offset of its own.
final class PictureFittedBy extends CanvasPicturePlace {
  const PictureFittedBy(this.fit)
    : assert(fit != MediaFitMode.born, 'born keeps or moves the picture');

  @override
  final MediaFitMode fit;

  @override
  ({double dx, double dy}) offsetFrom(CanvasSize from, CanvasSize to) =>
      (dx: 0.0, dy: 0.0);
}
