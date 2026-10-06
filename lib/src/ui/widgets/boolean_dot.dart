import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../repaint_props.dart';
import '../theme/app_theme.dart';
import 'app_icon_button.dart';

/// 🚨★★★THE BOOLEAN — a ring, with a dot inside it when it is on.
///
/// 유저 (guide-sym ⑥⑧, 2026-08-31): 「적용 미적용인 이름왼쪽에 동그란 버튼,
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
  ///
  /// ⚠️The STATE is said to a screen reader here too — `toggled`, what the
  /// Material switch it replaced said — so every control that draws the dot
  /// reports it without saying it again.
  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    child: Icon(
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
    ),
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
  });

  final String keyValue;
  final bool value;

  /// Null disables the button.
  final ValueChanged<bool>? onChanged;

  final String tooltip;

  /// See [BooleanDot.inPickOneGroup].
  final bool inPickOneGroup;

  @override
  Widget build(BuildContext context) {
    final changed = onChanged;
    return AppIconButton(
      keyValue: keyValue,
      tooltip: tooltip,
      // 「크기는 알아서」 — the bar's size. The dense one left with the export
      // window's ring-only rows, which are settings rows now (유저 09-24,
      // 「설정 줄 하나로」).
      size: AppIconButtonSize.bar,
      icon: BooleanDot(
        value: value,
        inPickOneGroup: inPickOneGroup,
        enabled: changed != null,
      ),
      onPressed: changed == null ? null : () => changed(!value),
    );
  }
}

/// What a switch over SEVERAL things says of them: every one on, every one
/// off, or some of each.
enum BooleanMix {
  off,
  mixed,
  on;

  /// What [values] say together. Nothing at all says [off].
  static BooleanMix of(Iterable<bool> values) {
    var count = 0;
    var lit = 0;
    for (final value in values) {
      count += 1;
      if (value) {
        lit += 1;
      }
    }
    return lit == 0
        ? BooleanMix.off
        : lit == count
        ? BooleanMix.on
        : BooleanMix.mixed;
  }

  /// What a press asks of everything under the switch: on — unless every
  /// one of them already is, and then off.
  bool get pressTurnsOn => this != BooleanMix.on;
}

/// 🚨THE BOOLEAN OVER MANY — [BooleanDot]'s ring, wearing HALF its dot
/// where the things under it disagree.
///
/// 유저 2026-10-06 (F-289-Q13): 「폴더줄의 스위치는 섞임모양 넣는게
/// 나을거같아. 새로운 타입으로 두자. 다른곳에서도 이용가능하게」 — a row that
/// stands for several rows (a folder over its layers) switches them
/// together, and has a third thing to say: some are on.
///
/// ⛔STILL A RING, and the dot is what changes — the law [BooleanDot] is
/// built on. On and off ARE that control, drawn by it; the mixed state is
/// the same ring on the same grid with the left half of the same dot, so
/// the three read as one control in three states rather than as a second
/// one beside it. ↩️The export window's own list drew a nine-pixel square,
/// half filled.
///
/// A switch over many is never one of a pick-one group — there is nothing
/// beside it to send the eye to — so it has no `inPickOneGroup`.
///
/// This is the LOOK alone; the control is [BooleanMixDotButton].
class BooleanMixDot extends StatelessWidget {
  const BooleanMixDot({
    super.key,
    required this.value,
    this.enabled = true,
    this.size,
  });

  final BooleanMix value;

  /// False paints [AppColors.glyphDisabled] — the GLYPH still says which.
  final bool enabled;

  /// Null takes the surrounding [IconTheme]'s size.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final whole = switch (value) {
      BooleanMix.on => true,
      BooleanMix.off => false,
      BooleanMix.mixed => null,
    };
    if (whole != null) {
      return BooleanDot(value: whole, enabled: enabled, size: size);
    }
    return Semantics(
      mixed: true,
      child: CustomPaint(
        size: Size.square(size ?? IconTheme.of(context).size ?? 24),
        painter: _HalfDotPainter(
          enabled ? AppColors.accent : AppColors.glyphDisabled,
        ),
      ),
    );
  }
}

/// The ring [BooleanDot] wears with the left half of its dot, on the grid
/// its two glyphs are drawn on — twenty-four units a side, the ring two
/// units thick with its outside ten from the centre, the dot five.
class _HalfDotPainter extends CustomPainter with RepaintOnProps {
  const _HalfDotPainter(this.color);

  final Color color;

  @override
  Object get props => (color,);

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 24;
    final centre = size.center(Offset.zero);
    canvas.drawCircle(
      centre,
      9 * unit,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * unit,
    );
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: 5 * unit),
      math.pi / 2,
      math.pi,
      true,
      Paint()..color = color,
    );
  }
}

/// [BooleanMixDot] as a control of its own — pressed, it hands [onChanged]
/// what every thing under it should become ([BooleanMix.pressTurnsOn]).
class BooleanMixDotButton extends StatelessWidget {
  const BooleanMixDotButton({
    super.key,
    required this.keyValue,
    required this.value,
    required this.onChanged,
    required this.tooltip,
  });

  final String keyValue;
  final BooleanMix value;

  /// Null disables the button.
  final ValueChanged<bool>? onChanged;

  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final changed = onChanged;
    return AppIconButton(
      keyValue: keyValue,
      tooltip: tooltip,
      size: AppIconButtonSize.bar,
      icon: BooleanMixDot(value: value, enabled: changed != null),
      onPressed: changed == null ? null : () => changed(value.pressTurnsOn),
    );
  }
}
