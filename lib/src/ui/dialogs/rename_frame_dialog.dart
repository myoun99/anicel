import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import 'app_prompt_dialog.dart';

/// Rename dialog for a frame. Pops the trimmed new name, or nothing on
/// cancel; an empty value is allowed. Lane KEYS wear it too ([target]),
/// with their two sides under the name ([extra]) — a key's name is a link
/// exactly as a frame's is: same name, same value.
class RenameFrameDialog extends StatelessWidget {
  const RenameFrameDialog({
    super.key,
    required this.initialName,
    this.target,
    this.extra,
  });

  final String initialName;

  /// The key window's SIDES, under the name (I-89 ②) — see
  /// [AppPromptDialog.extra]. Null for a frame.
  ///
  /// ↩️Its type stood BESIDE the name (F-17: 「이름변경이랑 오른쪽에 유니언
  /// 타입 변경」) while it was two choices; two rows of them do not fit
  /// there, and the drawing the user chose has them under it (유저 10-10
  /// 「B' 두줄 줄마다 세기로 가자」).
  final Widget? extra;

  /// What the title names it — null for a frame ([AppStrings.tlFrame]).
  final String? target;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppPromptDialog.keyed(
      keyPrefix: 'rename-frame',
      title: strings.windowTitleOn(
        strings.editNameAction,
        target ?? strings.tlFrame,
      ),
      titleIcon: Icons.drive_file_rename_outline,
      initialValue: initialName,
      confirmLabel: strings.commonRename,
      extra: extra,
      // The width the key window took while its type stood beside the
      // name; its rows of choices want the room.
      width: extra == null ? null : 400,
    );
  }
}
