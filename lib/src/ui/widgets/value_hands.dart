import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../theme/app_theme.dart' show AppColors;
import 'app_icon_button.dart';

/// THE HANDS A VALUE IS TURNED BY, beside it: its +/− ([ValueSteps]) and
/// its pencil ([ValuePencil]) — the same two for a settings bar and for a
/// number box, so the two read as one kind of control.
///
/// 🗣️tool-settings-panel-tidy (유저 2026-10-10): 「모든 드래그+편집이 가능한
/// 박스를 구조를 나누고싶어 … 지금의 박스는 그냥 드래그만 하고, 편집창
/// 여는건 그 옆에 편집아이콘 둬서」 · 「상자에 한걸음 올리기 내리기버튼들도
/// 동일하게 넣고싶어」 · 막대에도 연필을 「달도록」.
///
/// How far a value's hands reach past it — its steps and its pencil. A
/// settings grid keeps this much at the end of every row
/// (`ToolSettingEnd`), so a bar's hands and a box's stand in one column.
const double valueHandsReach = ValueSteps.reach + ValuePencil.reach;

/// The +/− pair (유저 확정 2026-09-08: 「+버튼을 세로로 위아래로 나눠서 위에
/// +버튼, 아래 -버튼」).
///
/// ⛔It fires its host's own step, NOT arithmetic of its own — one notch
/// here is one notch of the wheel, which is the whole of 유저's third 착수
/// 결정 (「`+1` = 휠과 같은 걸음」). A second implementation would be one
/// question with two answers.
///
/// The two cells split the value's thickness, so a row is exactly as tall
/// with the steps as without them and nothing below shifts. ↩️It was the
/// settings bar's own (`_FieldSliderStepper`) until the number box took the
/// same pair (2026-10-10).
class ValueSteps extends StatelessWidget {
  const ValueSteps({
    super.key,
    required this.keyPrefix,
    required this.height,
    required this.enabled,
    required this.onStep,
    this.axis = Axis.horizontal,
  });

  /// `<keyPrefix>-up` and `<keyPrefix>-down` key the two cells.
  final String keyPrefix;

  /// The value's thickness — its height lying down, its width stood up.
  final double height;
  final bool enabled;
  final ValueChanged<int> onStep;

  /// Which way the value runs. A stood value (the canvas's brush pill,
  /// I-34) has the pair UNDER it, turned with it: − then +, side by side,
  /// the cells splitting its width as they split a lying one's height.
  final Axis axis;

  /// Narrow on purpose: this sits in panels already budgeted to the pixel,
  /// and it is a nudge, not a target you aim at from across the screen.
  /// Stood, it is how tall the pair lies.
  static const double width = 14;

  /// The gap to the value, so the buttons never look like part of it.
  static const double _gap = 3;

  /// What the pair takes of its value's run.
  static const double reach = _gap + width;

  @override
  Widget build(BuildContext context) {
    final stood = axis == Axis.vertical;
    // 🚨THE PLUS WEARS THE ACCENT, like every other ＋ in the app (유저 확정
    // 2026-08-10: 「＋가있는 모든곳. 공통적으로」). The MINUS does not: the
    // accent rule is the plus's alone, and its twin — the red one — is for
    // DELETE, which this is not. The pair looking uneven is the law's own
    // shape, not an oversight.
    final up = _cell(
      Icons.add,
      1,
      color: AppColors.addGlyph(enabled: enabled),
    );
    final down = _cell(Icons.remove, -1);
    return Padding(
      padding: stood
          ? const EdgeInsets.only(top: _gap)
          : const EdgeInsets.only(left: _gap),
      child: SizedBox(
        width: stood ? height : width,
        height: stood ? width : height,
        child: stood
            ? Row(children: [down, up])
            : Column(children: [up, down]),
      ),
    );
  }

  /// One cell: half the value's thickness, the glyph 1 short of the cell's
  /// edge at each end of that half, lying or stood (유저 2026-10-18 of the
  /// pill's: 「+-버튼은 … 더 작게해도되니까 안에 들어가도록하자」).
  ///
  /// ⚠️ACROSS the pair — the [width] it lies — a thick bar's glyph BOX runs
  /// past the cell (the strip's bars, 42 thick; the pill's at twice the OS
  /// text) while its INK stays inside: a ＋ is 14 of its 24. Holding the box
  /// inside as well would shrink the strip's ±, which nobody asked for
  /// (measured 2026-10-19, I-34).
  Widget _cell(IconData icon, int direction, {Color? color}) {
    final half = height / 2;
    final stood = axis == Axis.vertical;
    return AppIconButton(
      keyValue: '$keyPrefix-${direction > 0 ? 'up' : 'down'}',
      tooltip: direction > 0
          ? AppText.strings.stepUp
          : AppText.strings.stepDown,
      size: AppIconButtonBox(
        width: stood ? half : width,
        height: stood ? width : half,
        iconSize: half - 2,
      ),
      icon: Icon(icon, color: color),
      onPressed: enabled ? () => onStep(direction) : null,
    );
  }
}

/// The PENCIL that opens a value's typed field — the number alone
/// (`readoutParts`), selected, the whole box a field with no name and no
/// unit beside it.
///
/// A press is the pencil's whole meaning, so it fires as every button
/// fires: on the press on a rail's row, on the release inside everywhere
/// else (`ControlPressClaim`). ↩️The field opened on a tap of the value
/// itself, which had to wait for the release to know a tap from a drag and
/// took a pen's wobble for a drag (유저 2026-10-10: 「펜같은거로 클릭할땐
/// 항상 흔들리잖아」).
class ValuePencil extends StatelessWidget {
  const ValuePencil({
    super.key,
    required this.keyValue,
    required this.height,
    required this.enabled,
    required this.onPressed,
    this.axis = Axis.horizontal,
  });

  final String keyValue;

  /// The value's thickness, as [ValueSteps.height].
  final double height;
  final bool enabled;
  final VoidCallback onPressed;

  /// Which way the value runs — stood, the pencil is under it, as
  /// [ValueSteps.axis].
  final Axis axis;

  /// Stood, how tall the pencil lies.
  static const double width = 18;
  static const double _gap = 3;

  /// What the pencil takes of its value's run.
  static const double reach = _gap + width;

  /// The glyph inside the cell — a settings box's own size of mark.
  static const double _glyph = 14;

  @override
  Widget build(BuildContext context) {
    final stood = axis == Axis.vertical;
    return Padding(
      padding: stood
          ? const EdgeInsets.only(top: _gap)
          : const EdgeInsets.only(left: _gap),
      child: AppIconButton(
        keyValue: keyValue,
        tooltip: AppText.strings.valueTypeIn,
        size: AppIconButtonBox(
          width: stood ? height : width,
          height: stood ? width : height,
          iconSize: _glyph,
        ),
        icon: const Icon(Icons.edit_outlined),
        onPressed: enabled ? onPressed : null,
      ),
    );
  }
}
