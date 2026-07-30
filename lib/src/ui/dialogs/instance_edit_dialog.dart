import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../widgets/app_window.dart';

/// The "instance edit" family's window — one layer kind's entry being
/// created or edited (an SE line, a camera key, an instruction mark).
///
/// It owns no chrome of its own: [AppWindow] draws the window and this
/// holds what the FAMILY shares — the stable action keys every kind's
/// tests and muscle memory rely on, the optional Delete, and the live
/// preview slot below the fields.
///
/// Keys: 'instance-edit-dialog' on the surface and
/// 'instance-edit-ok/cancel/delete-button' on the actions.
class InstanceEditDialogShell extends StatelessWidget {
  const InstanceEditDialogShell({
    super.key,
    required this.title,
    this.titleIcon,
    required this.body,
    this.preview,
    required this.onSubmit,
    this.onDelete,
    this.submitLabel,
    this.deleteLabel,
  });

  final String title;
  final IconData? titleIcon;

  /// Kind-specific field column; scrolls when tall (long SE dialogue), the
  /// preview below keeps its height.
  final Widget body;

  /// Live preview pane ([InstanceEditPreview] usually); null hides the slot.
  final Widget? preview;

  /// Null disables the confirm action (e.g. nothing selected yet).
  final VoidCallback? onSubmit;

  /// Non-null shows the Delete action.
  final VoidCallback? onDelete;

  /// Null takes the tabled Save verb in the program language.
  final String? submitLabel;

  /// Null takes the tabled Delete verb. Kinds whose secondary action is
  /// not a deletion (the SE tag's "Reset") name it instead, so a
  /// danger-styled button never lies about what it does.
  final String? deleteLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppText.strings;
    final preview = this.preview;
    final onDelete = this.onDelete;
    return AppWindow(
      windowKey: const ValueKey<String>('instance-edit-dialog'),
      title: title,
      titleIcon: titleIcon,
      onClose: () => Navigator.of(context).pop(),
      minWidth: 380,
      maxWidth: 560,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          if (preview != null) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                strings.commonPreview,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 6),
            preview,
          ],
        ],
      ),
      actions: [
        if (onDelete != null)
          AppWindowAction(
            label: deleteLabel ?? strings.commonDelete,
            actionKey: const ValueKey<String>('instance-edit-delete-button'),
            emphasis: AppWindowActionEmphasis.danger,
            onPressed: onDelete,
          ),
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('instance-edit-cancel-button'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: submitLabel ?? strings.commonSave,
          actionKey: const ValueKey<String>('instance-edit-ok-button'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: onSubmit,
        ),
      ],
    );
  }
}
