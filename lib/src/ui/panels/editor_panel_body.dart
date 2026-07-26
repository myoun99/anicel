import 'package:flutter/material.dart';

class EditorPanelBody extends StatelessWidget {
  const EditorPanelBody({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(10),
    this.scrollable = true,
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

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      key: const ValueKey<String>('editor-panel-body'),
      child: scrollable
          ? SingleChildScrollView(padding: padding, child: child)
          : Padding(padding: padding, child: child),
    );
  }
}
