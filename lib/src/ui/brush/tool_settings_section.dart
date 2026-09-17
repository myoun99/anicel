import 'package:flutter/material.dart';

import '../widgets/content_scrollbar.dart';

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
      // H35: the tool settings panel's content keeps its bar in view.
      return ContentScrollbar(
        builder: (context, controller) => ListView(
          key: keyFor(tool),
          controller: controller,
          padding: inset,
          children: rows,
        ),
      );
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

/// THE preview at the top of the tool settings panel — one box, one size,
/// whichever tool is showing.
///
/// 🚨★★★I-33 (유저 2026-09-16): 「도구 설정 패널에 **프리뷰 항목 신설**.
/// 잘라내기도구의 스탬프도 이거 재사용? … **아무튼 통일하고 필요없어지는
/// 잔재제거**. 프리뷰 항목은 일단 **스탬프도구, 브러시/지우개**의 도구설정에서
/// 비추게. 위치는 **도구 설정의 맨 위**. **「프리뷰」라는 텍스트는 필요없음.**
/// 세련되게」.
///
/// ⛔**NO LABEL**, and not only because the user said so: a box showing the
/// brush you are holding does not need a word telling you it is a preview
/// (⛔설명 문구 금지 is the same rule).
///
/// ⚠️It sits ABOVE the section rather than inside it, which is what makes it
/// stay put while the settings scroll — 「맨 위」. The stamp used to write
/// its own copy inside its list, and that copy scrolled away.
class ToolSettingsPreview extends StatelessWidget {
  const ToolSettingsPreview({super.key, required this.child});

  /// One height for every tool: the stamp's own 88, kept, because a held
  /// piece is the thing that most needs room and a stroke reads fine in it.
  static const double height = 88;

  /// The handle tests find the slot by — and the one that says a tool has
  /// NO preview when it is absent.
  static const Key slotKey = ValueKey<String>('tool-settings-preview');

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      key: slotKey,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: child,
        ),
      ),
    );
  }
}
