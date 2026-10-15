import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import 'app_icon_button.dart';

/// THE SCALE CHAIN — After Effects' mark beside a pair of scales. One press
/// flips the link, and on and off are told by colour alone
/// ([AppIconButton.isSelected]).
///
/// 🗣️`transform-fx-scale-x-y-Q1` (유저 2026-10-07): 「Scale 행에 사슬 버튼 —
/// 변형 도구의 「배율 연동」과 한 스위치」 — and tool-settings-panel-tidy
/// (유저 2026-10-10, 「다 추천대로」): the transform tool wears it too, beside
/// its 「배율」, in place of the switch row it had. ONE switch, so ONE face:
/// the timeline's Scale row and the tool settings both build this.
class ScaleChainButton extends StatelessWidget {
  const ScaleChainButton({
    super.key,
    required this.keyValue,
    required this.isOn,
    required this.onPressed,
  });

  final String keyValue;
  final bool isOn;

  /// Null shows the chain greyed — a host that cannot write the switch.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => AppIconButton(
    keyValue: keyValue,
    tooltip: AppText.strings.trScaleLink,
    size: AppIconButtonSize.micro,
    isSelected: isOn,
    onPressed: onPressed,
    icon: const Icon(Icons.link),
  );
}
