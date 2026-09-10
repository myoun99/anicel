import 'package:flutter/material.dart';

/// THE shell a tool's settings section wears inside the tool settings panel.
///
/// 🚨ONE PLACE FOR THREE FACTS, because eight sections had written all three
/// by hand: the KEY the panel is found by, the INSET it is read at, and the
/// STYLE of the line that says which tool is showing. A ninth tool would have
/// copied whichever neighbour it was written beside, and two of the eight had
/// already drifted apart — one reached for `Padding` where the rest used a
/// list, and one wrote its heading in a different style.
///
/// ⛔[scrolls] IS NOT A LOOK, it is whether the content can outgrow the panel.
/// A section that cannot must not take a viewport, or it stretches to the
/// panel's full height and the panel ends up with two scrollers on one axis —
/// which the app forbids, because its scrollbars are always visible and the
/// user would be left guessing which one the wheel drives.
/// `EditorPanelBody.scrollable` says the same sentence one level up.
///
/// ⚠️THE HEADING IS A STYLE, NOT A LAYOUT. It renders the line and stops
/// there: the gap under it belongs to [children], because the sections do not
/// agree on what comes next (the shape fill puts its polygon confirm between
/// the two). A shell that also owned the gap would have moved every one of
/// those by eight pixels to look tidier in this file.
class ToolSettingsSection extends StatelessWidget {
  const ToolSettingsSection({
    super.key,
    required this.tool,
    this.title,
    this.scrolls = true,
    required this.children,
  });

  /// Names the section: `cut-stamp` keys it `tool-settings-cut-stamp`.
  ///
  /// ⚠️It is the SECTION's name, not the tool enum's — two tools share the
  /// cut piece and the shape fill has a section the plain fill does not.
  final String tool;

  /// The line that says which tool is showing. Null for a section whose
  /// first row already says it (the stamp names what it is holding).
  final String? title;

  /// See the class comment: a content question, not a style one.
  final bool scrolls;

  final List<Widget> children;

  /// The inset every tool's settings are read at.
  static const EdgeInsets inset = EdgeInsets.all(12);

  /// The key a section wears — the handle its tests find it by, and the one
  /// a section too empty to use the shell still has to wear.
  static Key keyFor(String tool) => ValueKey<String>('tool-settings-$tool');

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    final rows = <Widget>[
      if (title != null)
        Text(title, style: Theme.of(context).textTheme.titleSmall),
      ...children,
    ];
    if (scrolls) {
      return ListView(key: keyFor(tool), padding: inset, children: rows);
    }
    return Padding(
      key: keyFor(tool),
      padding: inset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
    );
  }
}
