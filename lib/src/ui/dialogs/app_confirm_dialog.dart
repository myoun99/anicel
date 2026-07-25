import 'package:flutter/material.dart';

import '../widgets/app_window.dart';

/// The "answer a question" window: a sentence and the ways out of it.
///
/// The width follows the action COUNT rather than the prose, because the
/// footer splits its width evenly — a four-way exit prompt needs room its
/// two-way cousins do not.
class AppConfirmDialog extends StatelessWidget {
  const AppConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.actions,
    this.titleIcon,
    this.windowKey,
    this.width,
  });

  final String title;
  final IconData? titleIcon;
  final String message;

  /// Left to right; the one that answers 'yes' goes last and carries
  /// [AppWindowActionEmphasis.primary].
  final List<AppWindowAction> actions;

  final Key? windowKey;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return AppWindow(
      windowKey: windowKey,
      title: title,
      titleIcon: titleIcon,
      width: width ?? (actions.length > 2 ? 480.0 : 380.0),
      body: Text(message, style: Theme.of(context).textTheme.bodyMedium),
      actions: actions,
    );
  }
}
