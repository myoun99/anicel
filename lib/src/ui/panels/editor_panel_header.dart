import 'package:flutter/material.dart';

import '../theme/app_scroll_behavior.dart';
import '../widgets/live_sheet.dart';
import '../widgets/static_raster.dart';

/// Slim toolbar strip atop a panel body hosting the panel's controls.
/// The TAB names the panel — this bar never repeats the title.
class EditorPanelHeader extends StatelessWidget {
  const EditorPanelHeader({super.key, required this.trailing});

  final Widget trailing;

  static const double height = 32;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey<String>('editor-panel-header'),
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      // 🚨A SHEET LIES ON ITS GROUND ([LiveSheet]): what a pointer lights
      // on its controls is drawn live on it, and the dock keeps its image
      // (card a-hover-in-a-capsule-or-a-dock-takes-the-regions-image-again,
      // 2026-11-24). It costs the dock's image the controls' box and no
      // more: they stand in a layer of their own (the scroller, a repaint
      // boundary), so what the dock paints after the header — the body, a
      // layer of its own too — touches no part of the sheet and goes down
      // into the part under it (`_Strata._lowest`). ↩️The ground was under
      // nothing, and a pointer passing over the brush library's import and
      // save buttons took the dock's image again at each.
      child: LiveSheet(
        // Right-aligned controls that CLIP on squeezed panels (drop-zone
        // previews shrink panels to ~100px — a bare Row overflowed there).
        child: Align(
          alignment: Alignment.centerRight,
          child: UnbarredScrollable(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              // The header is its own ZONE — a sibling of the panel body,
              // not a wrapper around it, so pressing a control here does
              // not re-bake the whole panel. And the bake goes INSIDE this
              // scroller because a viewport is itself a repaint boundary:
              // wrapped from outside it would find one and silently pay
              // full price, which is exactly what the enforcement test
              // caught the first time this zone was added.
              child: StaticRaster(debugLabel: 'header', child: trailing),
            ),
          ),
        ),
      ),
    );
  }
}
