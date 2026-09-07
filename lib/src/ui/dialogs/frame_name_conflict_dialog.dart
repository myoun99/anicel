import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import 'app_confirm_dialog.dart';

/// Asks whether to link to an existing frame that already uses the entered
/// name so identical names share the same material. Pops `true` to link.
class FrameNameConflictDialog extends StatelessWidget {
  const FrameNameConflictDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    // ⚠️Spelled out rather than `confirmDialogKeys`: the accept answers
    // `-link-button`, not `-confirm-button`, so this window is not that
    // convention and keeps its own trio.
    const keys = (
      window: ValueKey<String>('frame-name-conflict-dialog'),
      decline: ValueKey<String>('frame-name-conflict-cancel-button'),
      accept: ValueKey<String>('frame-name-conflict-link-button'),
    );
    return AppConfirmDialog(
      windowKey: keys.window,
      title: strings.frameNameConflictTitle,
      titleIcon: Icons.link_outlined,
      message: strings.frameNameConflictBody,
      actions: confirmActions(
        context,
        keys: keys,
        decline: ConfirmChoice(strings.commonCancel),
        accept: ConfirmChoice(strings.commonLink),
      ),
    );
  }
}
