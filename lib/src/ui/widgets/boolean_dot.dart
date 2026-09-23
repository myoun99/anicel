import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_icon_button.dart';

/// 🚨★★★THE BOOLEAN — a ring, with a dot inside it when it is on.
///
/// 유저 (guide-sym ⑥⑦, 2026-08-31): 「적용 미적용인 이름왼쪽에 동그란 버튼,
/// 지금 상태만으론 적용인지 미적용인지 알기 어려우니 **적용시 안에 동그라미
/// 추가. 구체적으론 환경설정-입력-태블릭서비스의 버튼처럼.** / 그리고 이 on off
/// 버튼, **공용화**시켜서 다른곳에도 쓸수있게. **앞으로 이런 불리언값 바꾸는
/// 버튼은 이걸 공통적으로 사용.**」 — then 「좀 더 적용범위 넓혀서 **진짜
/// 불리언값 모든곳에 적용** … 동일한 on off 버튼 전수조사해서 적용」.
///
/// The control they pointed at is a radio's: an empty ring off, a ring with a
/// filled dot on. So 「적용인지 미적용인지」 is answered by the GLYPH rather
/// than by remembering what a colour meant. ⛔A RING either way, and the dot
/// is what changes — swapping the outer shape would make the two states two
/// different pictures, and a check mark is what 「선택 표시는 색상만」 names
/// outright.
///
/// ## Two modes, and they are the user's own rule
///
/// 「on함으로서 다른게 off되는 **하나만 선택하는 그룹**의 버튼이면 비활성화될때
/// 색도 비활성화색으로 어둡게. **아니면** 비활성화되도 색 변하지않고 흰색
/// 그대로」 ⇒ [inPickOneGroup] is that question and nothing else. A member of
/// a pick-one group is dim when off, because something ELSE in the group is
/// on and that is where the eye should go; a standalone flag keeps its colour,
/// because off is an ordinary state of it and nothing else is speaking.
///
/// 🚨AND IT HOLDS NO `Opacity` (board `a-panel-with-a-switch-can-never-bake`).
/// Material's `Switch` always wraps itself in one — at opacity 1 when enabled
/// — and an `Opacity` is a repaint boundary at any alpha above zero, so a
/// panel with a switch in it could never bake and paid its full raster price
/// on every frame. Everything here dims by COLOUR.
///
/// This is the LOOK alone: a row whose whole surface is the control
/// ([SettingsSwitchRow], a menu toggle) draws it and keeps the press for
/// itself. A control of its own is [BooleanDotButton].
class BooleanDot extends StatelessWidget {
  const BooleanDot({
    super.key,
    required this.value,
    this.inPickOneGroup = false,
    this.enabled = true,
    this.size,
  });

  final bool value;

  /// Whether turning this ON turns something else OFF.
  final bool inPickOneGroup;

  /// False paints [AppColors.glyphDisabled], on or off — the GLYPH still
  /// says which.
  final bool enabled;

  /// Null takes the surrounding [IconTheme]'s size.
  final double? size;

  /// ⛔EVERY STATE NAMES ITS COLOUR — never `null` (T16, the law at
  /// [AppColors.glyphDisabled]). A null hands the dot to whatever ink
  /// surrounds it: a third colour to cross through and, in a bar that
  /// bakes, to freeze on. And the surroundings disagree — a `ListTile` inks
  /// its trailing glyph in the DIM `onSurfaceVariant`, which would have
  /// dimmed exactly the standalone flag 유저 said stays 「흰색 그대로」.
  @override
  Widget build(BuildContext context) => Icon(
    value ? Icons.radio_button_checked : Icons.radio_button_unchecked,
    size: size,
    color: switch ((enabled, value, inPickOneGroup)) {
      (false, _, _) => AppColors.glyphDisabled,
      (true, true, _) => AppColors.accent,
      (true, false, true) => AppColors.text.withValues(
        alpha: AppColors.offAlpha,
      ),
      (true, false, false) => AppColors.text,
    },
  );
}

/// [BooleanDot] as a control of its own — pressed, it hands [onChanged] the
/// value it does not hold.
///
/// ⛔[inPickOneGroup] is NOT 「is this disabled」. A disabled control passes a
/// null [onChanged], which [AppIconButton] already renders (and claims the
/// press for, like every control in the app) — two questions, two inputs, so
/// neither can answer for the other.
class BooleanDotButton extends StatelessWidget {
  const BooleanDotButton({
    super.key,
    required this.keyValue,
    required this.value,
    required this.onChanged,
    required this.tooltip,
    this.inPickOneGroup = false,
    this.size = AppIconButtonSize.bar,
  });

  final String keyValue;
  final bool value;

  /// Null disables the button.
  final ValueChanged<bool>? onChanged;

  final String tooltip;

  /// See [BooleanDot.inPickOneGroup].
  final bool inPickOneGroup;

  /// 「크기는 알아서」 — the default suits a settings row; a lane value cell
  /// passes its own.
  final AppIconButtonMetrics size;

  @override
  Widget build(BuildContext context) {
    final changed = onChanged;
    return AppIconButton(
      keyValue: keyValue,
      tooltip: tooltip,
      size: size,
      icon: BooleanDot(
        value: value,
        inPickOneGroup: inPickOneGroup,
        enabled: changed != null,
      ),
      onPressed: changed == null ? null : () => changed(!value),
    );
  }
}
