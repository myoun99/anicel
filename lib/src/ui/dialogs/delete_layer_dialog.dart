import 'package:flutter/material.dart';

import '../widgets/app_window.dart';
import 'app_confirm_dialog.dart';

/// Confirmation dialog for deleting a layer. Pops `true` to confirm.
class DeleteLayerDialog extends StatelessWidget {
  const DeleteLayerDialog({super.key, required this.layerName});

  final String layerName;

  @override
  Widget build(BuildContext context) {
    return AppConfirmDialog(
      windowKey: const ValueKey<String>('delete-layer-dialog'),
      title: 'Delete layer',
      titleIcon: Icons.delete_outline,
      message: 'Delete layer "$layerName"?',
      actions: [
        AppWindowAction(
          label: 'Cancel',
          actionKey: const ValueKey<String>('delete-layer-cancel-button'),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppWindowAction(
          label: 'Delete',
          actionKey: const ValueKey<String>('delete-layer-confirm-button'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
