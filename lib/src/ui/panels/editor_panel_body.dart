import 'package:flutter/material.dart';

import '../widgets/static_raster.dart';

class EditorPanelBody extends StatelessWidget {
  const EditorPanelBody({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(10),
    this.scrollable = true,
    this.debugLabel = 'panel-body',
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Whether the body scrolls its child.
  ///
  /// A panel that scrolls INSIDE itself — a list with its own bar — opts
  /// out, because two scrollers stacked on one axis leave the user guessing
  /// which one the wheel is driving, and the app's scrollbars are always
  /// visible, so the ambiguity would be on screen the whole time. Opting out
  /// also hands the child the section's real height instead of the infinity
  /// a scroll view offers.
  final bool scrollable;

  /// Names this body's bake in the [StaticRaster] report.
  final String debugLabel;

  @override
  Widget build(BuildContext context) {
    // ★The bake goes INSIDE the scroll view, and that placement is the
    // whole trick.
    //
    // A viewport is itself a repaint boundary, so a bake wrapped AROUND
    // a scrolling panel finds one in its subtree and stands down — which
    // is what the tab-level wrapper does here, and why a scrolling panel
    // was still paying its full raster price with the funnel installed.
    //
    // Inside, it is strictly better than that: the viewport paints its
    // child at a shifted offset, so a boundaried child is COMPOSITED at
    // the new place rather than repainted. Scrolling a baked panel is a
    // layer offset and nothing else — no re-record, no re-raster, no
    // re-bake.
    //
    // The cost is that the image is the CONTENT's size, not the
    // viewport's. That is the right trade for panel bodies (a settings
    // column, a preset list) and would not be for something unbounded;
    // if such a body ever appears here, it will dirty on every scroll
    // and [StaticRaster] will stand itself down on its own.
    final baked = StaticRaster(debugLabel: debugLabel, child: child);
    return ClipRect(
      key: const ValueKey<String>('editor-panel-body'),
      child: scrollable
          ? SingleChildScrollView(padding: padding, child: baked)
          : Padding(padding: padding, child: baked),
    );
  }
}
