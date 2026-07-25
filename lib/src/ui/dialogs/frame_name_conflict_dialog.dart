import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import 'app_confirm_dialog.dart';

/// Asks whether to link to an existing frame that already uses the entered
/// name so identical names share the same material. Pops `true` to link.
class FrameNameConflictDialog extends StatelessWidget {
  const FrameNameConflictDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppConfirmDialog(
      windowKey: const ValueKey<String>('frame-name-conflict-dialog'),
      title: strings.frameNameConflictTitle,
      titleIcon: Icons.link_outlined,
      message: strings.frameNameConflictBody,
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>(
            'frame-name-conflict-cancel-button',
          ),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppWindowAction(
          label: strings.commonLink,
          actionKey: const ValueKey<String>('frame-name-conflict-link-button'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
