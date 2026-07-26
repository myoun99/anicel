import 'package:flutter/material.dart';

import 'editor_panel_body.dart';
import 'editor_panel_header.dart';

/// A panel's content shell: flush body on the shared panel surface, with
/// an optional [EditorPanelHeader] toolbar when the panel has [trailing]
/// controls. The hosting TAB names the panel, so the frame renders no
/// title of its own (a title bar here would just repeat the tab right
/// below it); [title] only keys the frame for tests.
class EditorPanelFrame extends StatelessWidget {
  const EditorPanelFrame({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.bodyPadding = const EdgeInsets.all(10),
    this.bodyScrolls = true,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry bodyPadding;

  /// See [EditorPanelBody.scrollable]: false for a panel that owns its own
  /// scrolling, so the two never stack.
  final bool bodyScrolls;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final trailing = this.trailing;
    return DecoratedBox(
      key: ValueKey<String>('editor-panel-frame-$title'),
      decoration: BoxDecoration(color: colorScheme.surface),
      child: trailing == null
          ? EditorPanelBody(
              padding: bodyPadding,
              scrollable: bodyScrolls,
              child: child,
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final hasBoundedHeight = constraints.hasBoundedHeight;
                final maxHeight = hasBoundedHeight
                    ? constraints.maxHeight
                          .clamp(0.0, double.infinity)
                          .toDouble()
                    : double.infinity;
                final headerHeight = hasBoundedHeight
                    ? EditorPanelHeader.height.clamp(0.0, maxHeight).toDouble()
                    : EditorPanelHeader.height;
                final body = EditorPanelBody(
                  padding: bodyPadding,
                  scrollable: bodyScrolls,
                  child: child,
                );

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: headerHeight,
                      child: EditorPanelHeader(trailing: trailing),
                    ),
                    if (hasBoundedHeight)
                      SizedBox(
                        height: (maxHeight - headerHeight)
                            .clamp(0.0, double.infinity)
                            .toDouble(),
                        child: body,
                      )
                    else
                      body,
                  ],
                );
              },
            ),
    );
  }
}
