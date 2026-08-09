import 'package:flutter/material.dart';

import '../theme/app_scroll_behavior.dart';
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
    );
  }
}
