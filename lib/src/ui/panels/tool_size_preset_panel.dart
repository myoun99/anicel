import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../input/control_press_claim.dart';
import '../theme/app_theme.dart';

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
/// ⚠️Setting a size here writes it straight onto the tool, so a preset that
/// is not a snap still lands exactly — the caller does not re-snap.
class ToolSizePresetPanel extends StatelessWidget {
  const ToolSizePresetPanel({
    super.key,
    required this.size,
    required this.onSizeSelected,
  });

  /// The tool's size right now — the cell matching it reads as selected.
  final double size;
  final ValueChanged<double> onSizeSelected;

  /// The rack, as the screenshot on I-2 draws it: dense at the low end,
  /// where a pen actually lives, and coarse above it.
  ///
  /// ⛔A LIST, NOT A FORMULA. It is read off the reference the user gave
  /// (「무조건 스샷 참고」) rather than generated from a ratio, because the
  /// steps are not one ratio — 0.7→1→1.5 is finer than 1200→1500→1700, and
  /// a curve fitted to both would miss every value at one end.
  static const List<double> presets = <double>[
    0.7,
    1,
    1.5,
    2,
    2.5,
    3,
    4,
    5,
    6,
    7,
    8,
    10,
    12,
    15,
    17,
    20,
    25,
    30,
    40,
    50,
    60,
    70,
    80,
    100,
    120,
    150,
    170,
    200,
    250,
    300,
    400,
    500,
    600,
    700,
    800,
    1000,
    1200,
    1500,
    1700,
    2000,
  ];

  /// How close a size has to be to a preset to read as that preset. The
  /// list is exact and a press writes it verbatim, so this only absorbs
  /// float error.
  static const double _match = 0.01;

  static String label(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final preset in presets)
            _SizeCell(
              key: ValueKey<String>('tool-size-preset-${label(preset)}'),
              value: preset,
              selected: (preset - size).abs() < _match,
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
    return ControlPressClaim(
      child: Material(
        color: Colors.transparent,
        shape: AppShapes.control(AppShapes.controlSmall),
        clipBehavior: Clip.antiAlias,
        child: ControlPressClaim(
          onPressed: onTap,
          child: InkWell(
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
      ),
    );
  }
}
