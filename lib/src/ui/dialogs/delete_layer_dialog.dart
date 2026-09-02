import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import 'app_confirm_dialog.dart';

/// Confirmation dialog for deleting a layer. Pops `true` to confirm.
class DeleteLayerDialog extends StatelessWidget {
  const DeleteLayerDialog({super.key, required this.layerName});

  final String layerName;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppConfirmDialog(
      windowKey: const ValueKey<String>('delete-layer-dialog'),
      title: strings.deleteLayerTitle,
      titleIcon: Icons.delete_outline,
      message: strings.deleteLayerMessageTemplate.replaceAll(
        '{name}',
        layerName,
      ),
      actions: confirmActions(
        context,
        declineLabel: strings.commonCancel,
        declineKey: const ValueKey<String>('delete-layer-cancel-button'),
        acceptLabel: strings.commonDelete,
        acceptKey: const ValueKey<String>('delete-layer-confirm-button'),
      ),
    );
  }
}
