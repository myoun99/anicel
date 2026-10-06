import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import 'cel_text_commands.dart';
import 'text_tool_options.dart';
import 'tool_settings_section.dart';

/// The TEXT tool's settings (R9-rest) — mounted by the tool settings panel
/// like every other tool's (유저: 툴 설정은 툴 설정 패널에).
///
/// What it shows is the text in hand when there is one, and what the next
/// text will start as when there is none ([TextToolOptions]); a change is
/// made on both — the text in hand, by the one rule every letter setting
/// keeps (`celTextLettersSpokenFor`), and the next text's values.
class TextToolSettings extends StatelessWidget {
  const TextToolSettings({
    super.key,
    required this.options,
    required this.commands,
  });

  /// The next text's values. Null in a host that does not own them: the
  /// section shows the defaults and changes nothing.
  final ValueNotifier<TextToolOptions>? options;

  /// The channel to the text the canvas holds. Null where there is no
  /// canvas to hold one.
  final CelTextCommands? commands;

  @override
  Widget build(BuildContext context) {
    return ToolSettingsSection(
      tool: 'text',
      title: AppText.strings.toolText,
      children: const [],
    );
  }
}
