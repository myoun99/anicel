import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../brush/brush_value_group.dart' show BrushValueBars;
import '../dialogs/app_confirm_dialog.dart' show showAppNotice;
import '../input/control_press_claim.dart';
import '../text/app_strings.dart';
import '../text/readout_text.dart' show columnValueOf;
import '../theme/app_theme.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/face_ink_well.dart';
import '../widgets/number_pad.dart';
import 'editor_panel_frame.dart';

/// **The tool's sizes, as buttons** (I-2).
///
/// 유저 2026-08-24: 「클튜처럼 툴 사이즈 패널 만들고싶음. **프리셋으로서 툴
/// 사이즈.** 브러시면 브러시 사이즈들이 여러개 존재해서 그거 누르면 브러시
/// 사이즈 바뀌는 패널」.
///
/// 🚨★A panel of its own, and the FIRST exception to 「툴 전용 패널을 새로
/// 만들지 않는다」 — 유저 결정 2026-08-25: 「새 패널로 만든다 — 이번은
/// 예외」. The rule stands for tool SETTINGS; this is not a setting, it is a
/// rack of values you reach for while drawing, and a rack has to be visible
/// at the same time as the canvas.
///
/// ⛔**IT NO LONGER READS THE SNAP LIST, AND THAT REVERSAL IS THE USER'S.**
/// This file used to say the sizes *were* `AppInputSettings.brushSizeSnaps`,
/// reasoning that two lists of the same thing would drift. 유저 2026-08-29
/// threw the premise out:
///
/// > 「**목록은 하나여야 한다는게 대체 무슨소리지? 이해안가는데.** 같은것이
/// > 라는게 도대체 뭐지? … 전혀 신경안써도되는데. **그 사이즈를 변경하는
/// > 연결된 패널일뿐임.** 해당 패널은 선택된걸로 브러시 사이즈를 바꿔주는
/// > 것일뿐. **마치 입력을 대신해주는것뿐.**」
///
/// They are not the same thing. A SNAP is a place a drag catches, so it has
/// to be sparse to be usable; a PRESET is a value you point at, so it has to
/// be dense. Nine snaps drawn as a rack is not the rack the user asked for
/// — the screenshot on the card has forty values, and 유저 2026-08-29:
/// 「작업할때는 **무조건 스샷 참고**」.
///
/// ↩️**THE SNAP READS THE RACK NOW — THE USER'S AGAIN** (F-391, 유저
/// 2026-10-17: 「브러시 크기 스냅은 해당 쓰던 로직있으면 툴 사이즈 패널을
/// 바탕으로 사용하도록 변경하고, 설정의 브러시크기스냅은 필요없어지니 잔재
/// 삭제」). The canvas's size drag catches on [presets], as the size bar's
/// ± step through them (F-325), and the settings' list of its own is gone —
/// so 「a snap has to be sparse to be usable」 above was this note's guess,
/// not a rule.
///
/// ⚠️Setting a size here writes it straight onto the tool, so a preset that
/// is not a snap still lands exactly — the caller does not re-snap.
///
/// 🗣️**THE RACK IS THE USER'S TO EDIT** (I-170, 유저 2026-11-13): 「도구
/// 브러시크기 프리셋패널, 슬슬 추가/삭제버튼 추가. 추가버튼 작동시 숫자입력
/// 공용창? 열리고 입력한게 중복된거면 거부. 존재한다는 메시지창과함께.
/// 정상적이면 프리셋에 추가. 삭제는 선택(강조색 되있는)되있는 크기를
/// 삭제하는버튼」. The two stand in the panel's header whatever the rack
/// holds; the delete is grey while no cell is lit. ↩️The rack was a const
/// list here, the same for everyone — the one the app starts with now
/// (`AppInputSettings.defaultToolSizes`).
class ToolSizePresetPanel extends StatelessWidget {
  const ToolSizePresetPanel({
    super.key,
    required this.size,
    required this.onSizeSelected,
    required this.presets,
    required this.onPresetsChanged,
  });

  /// The tool's size right now — the cell matching it reads as selected.
  final double size;
  final ValueChanged<double> onSizeSelected;

  /// The rack as it stands (`AppInputSettings.toolSizes`), smallest first.
  final List<double> presets;

  /// The rack after a size was put on it or taken off it.
  final ValueChanged<List<double>> onPresetsChanged;

  static const String addKey = 'tool-size-preset-add';
  static const String deleteKey = 'tool-size-preset-delete';

  /// How close a size has to be to a preset to read as that preset. The
  /// list is exact and a press writes it verbatim, so this only absorbs
  /// float error.
  static const double _match = 0.01;

  static String label(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';

  /// The preset [value] reads as — the cell that is lit for it, the one
  /// the delete takes off and the one a second ＋ of it would repeat. Null
  /// when the rack holds none.
  double? _presetAt(double value) {
    for (final preset in presets) {
      if ((preset - value).abs() < _match) {
        return preset;
      }
    }
    return null;
  }

  /// The ＋: the number pad under it, opened on the tool's size, and what
  /// it comes back with put on the rack where its size stands — a size the
  /// size bar writes ([BrushValueBars.heldSize]), as every size the tool is
  /// set to is (F-488). One the rack already holds is refused, and said.
  ///
  /// ⚠️AFTER THE PAD HAS CLOSED, not from its `onSubmit`: the pad hands
  /// its number over and then pops the route on top, which would be the
  /// notice.
  Future<void> _add(BuildContext anchor) async {
    String? typed;
    await showNumberPad(
      anchor,
      keyValue: addKey,
      initialText: label(BrushValueBars.heldSize(size)),
      keys: (minus: false, point: true),
      fieldKey: const ValueKey<String>('$addKey-input'),
      onSubmit: (text) => typed = text,
    );
    final value = columnValueOf(typed ?? '');
    if (value == null || !anchor.mounted) {
      return;
    }
    final added = BrushValueBars.heldSize(value);
    if (_presetAt(added) != null) {
      await showAppNotice(
        anchor,
        title: AppText.strings.commonNotice,
        message: AppText.strings.toolSizeAlreadyThere,
      );
      return;
    }
    onPresetsChanged([...presets, added]..sort());
  }

  @override
  Widget build(BuildContext context) {
    final lit = _presetAt(size);
    return EditorPanelFrame(
      title: AppText.strings.panelToolSize,
      bodyPadding: const EdgeInsets.all(8),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Builder(
            builder: (anchor) => AppIconButton(
              keyValue: addKey,
              tooltip: AppText.strings.commonAdd,
              size: AppIconButtonSize.dense,
              // 「＋가 있는 모든 곳, 공통적으로」 — the glyph, not the button.
              icon: Icon(Icons.add, color: AppColors.addGlyph(enabled: true)),
              onPressed: () => _add(anchor),
            ),
          ),
          AppIconButton(
            keyValue: deleteKey,
            tooltip: AppText.strings.commonDelete,
            size: AppIconButtonSize.dense,
            icon: Icon(
              Icons.delete_outline,
              color: AppColors.deleteGlyph(enabled: lit != null),
            ),
            onPressed: lit == null
                ? null
                : () => onPresetsChanged([
                    for (final preset in presets)
                      if (preset != lit) preset,
                  ]),
          ),
        ],
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final preset in presets)
            _SizeCell(
              key: ValueKey<String>('tool-size-preset-${label(preset)}'),
              value: preset,
              selected: preset == lit,
              onTap: () => onSizeSelected(preset),
            ),
        ],
      ),
    );
  }
}

/// One rack cell: the size DRAWN, with its number under it.
///
/// 🚨The dot is what makes this a rack rather than a list of numbers — the
/// screenshot picks a size by how big the blob looks, and the digits are
/// there to confirm it. A cell that printed only the number would be the
/// size field with extra steps.
class _SizeCell extends StatelessWidget {
  const _SizeCell({
    super.key,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final double value;
  final bool selected;
  final VoidCallback onTap;

  static const double _cell = 38;

  /// The widest the dot may draw. Every size at or above it fills the cell,
  /// which is what the reference does too — past a point the number is the
  /// only thing still telling them apart, and that is honest: they no
  /// longer differ by anything a 38px cell can show.
  static const double _maxDot = 26;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // ⛔COLOUR ONLY (CLAUDE.md: 「선택 표시는 색상만」). This cell used to
    // paint `primaryContainer` BEHIND the selected chip — a filled chip,
    // which is the exact thing the rule forbids, and the scanner that
    // guards it was looking for `backgroundColor:` and never saw a
    // `Material(color: selected ? …)`.
    final ink = selected ? AppColors.accent : colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: ControlPressClaim(
        onPressed: onTap,
        child: FaceInkWell(
          edge: AppShapes.control(AppShapes.controlSmall),
          onTap: silentPress(onTap),
          // ⛔WIDTH ONLY. Pinning the height too made the column overflow by
          // whatever the label's line height happened to be — a number that
          // moves with the app's typeface, so it would have come back the
          // day the font changed. The dot's box is fixed; the label takes
          // what it takes.
          child: SizedBox(
            width: _cell,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: _cell,
                  child: Center(
                    child: Container(
                      width: math.min(value, _maxDot),
                      height: math.min(value, _maxDot),
                      decoration: BoxDecoration(
                        color: ink,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                Text(
                  ToolSizePresetPanel.label(value),
                  style: TextStyle(fontSize: 10, color: ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
