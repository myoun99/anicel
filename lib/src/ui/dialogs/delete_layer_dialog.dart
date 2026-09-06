import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import 'app_confirm_dialog.dart';

/// Confirmation dialog for deleting a layer. Pops `true` to confirm.
class DeleteLayerDialog extends StatelessWidget {
  const DeleteLayerDialog({super.key, required this.layerName});

  final String layerName;

  @override
  Widget build(BuildContext context) {
    final keys = confirmDialogKeys('delete-layer');
    final strings = AppText.strings;
    return AppConfirmDialog(
      windowKey: keys.window,
      title: strings.deleteLayerTitle,
      titleIcon: Icons.delete_outline,
      message: strings.deleteLayerMessageTemplate.replaceAll(
        '{name}',
        layerName,
      ),
      actions: confirmActions(
        context,
        keys: keys,
        decline: ConfirmChoice(strings.commonCancel),
        accept: ConfirmChoice(strings.commonDelete),
      ),
    );
  }
}
