import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import 'app_prompt_dialog.dart';

/// Rename dialog for a drawing guide. Pops the trimmed new name, or nothing
/// on cancel. Rejects an empty name inline.
///
/// 유저 (guide-sym): 「대칭/퍼스 버튼에서 비지블버튼 왼쪽에 이름변경 버튼
/// 추가해서 **공통 이름변경ui창** 띄우도록. 이름은 **중복이어도 상관없도록**」.
///
/// ✅Duplicates already work: a guide's name is a plain `String` with no
/// uniqueness rule anywhere in the model, so that half asked for nothing.
class RenameGuideDialog extends StatelessWidget {
  const RenameGuideDialog({super.key, required this.initialName});

  final String initialName;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppPromptDialog(
      windowKey: const ValueKey<String>('rename-guide-dialog'),
      title: strings.renameGuideTitle,
      titleIcon: Icons.drive_file_rename_outline,
      fieldLabel: strings.renameGuideField,
      initialValue: initialName,
      confirmLabel: strings.commonRename,
      emptyError: strings.renameGuideEmpty,
      fieldKey: const ValueKey<String>('rename-guide-text-field'),
      cancelKey: const ValueKey<String>('rename-guide-cancel-button'),
      confirmKey: const ValueKey<String>('rename-guide-ok-button'),
    );
  }
}
