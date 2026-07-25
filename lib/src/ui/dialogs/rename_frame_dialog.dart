import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import 'app_prompt_dialog.dart';

/// Rename dialog for a frame. Pops the trimmed new name, or nothing on
/// cancel. SE rows reuse it with sheet wording ([title]/[fieldLabel]
/// overrides) — the frame name IS the sheet's name/dialogue text there,
/// which is also why an empty value is allowed here: clearing a sheet cell
/// is a real edit.
class RenameFrameDialog extends StatelessWidget {
  const RenameFrameDialog({
    super.key,
    required this.initialName,
    this.title,
    this.fieldLabel,
  });

  final String initialName;

  /// Null takes the tabled frame wording in the program language.
  final String? title;
  final String? fieldLabel;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppPromptDialog(
      windowKey: const ValueKey<String>('rename-frame-dialog'),
      title: title ?? strings.renameFrameTitle,
      titleIcon: Icons.drive_file_rename_outline,
      fieldLabel: fieldLabel ?? strings.renameFrameField,
      initialValue: initialName,
      confirmLabel: strings.commonRename,
      fieldKey: const ValueKey<String>('rename-frame-text-field'),
      cancelKey: const ValueKey<String>('rename-frame-cancel-button'),
      confirmKey: const ValueKey<String>('rename-frame-ok-button'),
    );
  }
}
