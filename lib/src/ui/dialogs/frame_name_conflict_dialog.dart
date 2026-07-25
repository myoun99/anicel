import 'package:flutter/material.dart';

import '../widgets/app_window.dart';
import 'app_confirm_dialog.dart';

/// Asks whether to link to an existing frame that already uses the entered
/// name so identical names share the same material. Pops `true` to link.
class FrameNameConflictDialog extends StatelessWidget {
  const FrameNameConflictDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AppConfirmDialog(
      windowKey: const ValueKey<String>('frame-name-conflict-dialog'),
      title: 'Frame name already exists',
      titleIcon: Icons.link_outlined,
      message:
          'This name is already used by another frame in this layer. Link to '
          'the existing named frame so the same name shares the same material?',
      actions: [
        AppWindowAction(
          label: 'Cancel',
          actionKey: const ValueKey<String>(
            'frame-name-conflict-cancel-button',
          ),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppWindowAction(
          label: 'Link',
          actionKey: const ValueKey<String>('frame-name-conflict-link-button'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
