import 'package:flutter/widgets.dart';

/// Where a canvas panel's content may stand on its STAGE rather than on its
/// page: the window it is seen through ([canvasVisibleRect] — the panel less
/// its pill's band, its lanes, its transport and what lies on the floor over
/// it), less the band the document's name stands in along its foot. In the
/// panel's own coordinates, which are the content's.
///
/// For content that neither pans nor scales with the view — a sound's face
/// (F-71-Q7), which lays its rows out here and reads only the view's zoom.
/// A page is framed into the window by Fit instead, and never asks.
class CanvasStage extends InheritedWidget {
  const CanvasStage({super.key, required this.rect, required super.child});

  final Rect rect;

  /// The stage around [context], or null outside a canvas panel's content.
  static Rect? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasStage>()?.rect;

  @override
  bool updateShouldNotify(CanvasStage oldWidget) => oldWidget.rect != rect;
}
