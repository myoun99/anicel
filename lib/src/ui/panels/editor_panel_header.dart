import 'package:flutter/material.dart';

import '../theme/app_scroll_behavior.dart';

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
            child: trailing,
          ),
        ),
      ),
    );
  }
}
