import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import 'app_icon_button.dart';

/// A layer's FILL-REFERENCE flag as a button (R20-C2): the bucket on every
/// drawing row of the rail, and — I-36, 유저 2026-09-24 「활성 레이어의 참조
/// 버튼을 둔다」 — the same bucket for the ACTIVE layer in the fill's tool
/// settings. One face, so the two cannot come to disagree about what "on"
/// looks like; both press the one verb that flips the flag.
class FillReferenceButton extends StatelessWidget {
  const FillReferenceButton({
    super.key,
    required this.keyValue,
    required this.isOn,
    required this.onPressed,
    this.size = AppIconButtonSize.bar,
  });

  final String keyValue;
  final bool isOn;
  final VoidCallback? onPressed;
  final AppIconButtonMetrics size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppIconButton(
      keyValue: keyValue,
      tooltip: isOn
          ? AppText.strings.railFillReferenceOn
          : AppText.strings.railFillReference,
      size: size,
      icon: Icon(
        Icons.format_color_fill,
        color: isOn
            ? colorScheme.primary
            : colorScheme.outline.withValues(alpha: 0.45),
      ),
      onPressed: onPressed,
    );
  }
}
