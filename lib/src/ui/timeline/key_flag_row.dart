import 'package:flutter/material.dart';

import '../widgets/app_window.dart' show AppWindowField;
import '../widgets/pill_strip.dart' show PillItem, PillStrip;

/// One of a [KeyFlagRow]'s two pills: its [word], and the [id] it is found
/// by.
typedef KeyFlagChoice = ({String id, String word});

/// A KEY WINDOW ROW THAT SAYS ONE YES OR NO OF THE KEYS IT COVERS, in two
/// pills — [off] and [on]: whether the path a position walks bends through
/// them (I-89 ④-Q4 — 직선, a corner, or 곡선, smooth through them as their
/// neighbours lay it), whether their time roves (④-Q5).
///
/// It shows what the keys say TOGETHER with [picked] on them, as the sides'
/// rows do: a choice is lit where all of them are it. Where no covered key
/// can say it, the row is offered and refused (「없다가 생기는 UI 금지」).
class KeyFlagRow extends StatelessWidget {
  const KeyFlagRow({
    super.key,
    required this.label,
    required this.off,
    required this.on,
    required this.flags,
    required this.picked,
    required this.onPicked,
  });

  final String label;
  final KeyFlagChoice off;
  final KeyFlagChoice on;

  /// What each covered key that can say it says.
  final List<bool> flags;

  /// What the user picked, or nothing yet — only a pick is ever written.
  final bool? picked;

  final ValueChanged<bool> onPicked;

  @override
  Widget build(BuildContext context) {
    final said = {for (final flag in flags) picked ?? flag};
    final agreed = said.length == 1 ? said.single : null;
    PillItem choice(KeyFlagChoice choice, {required bool value}) => PillItem(
      keyValue: choice.id,
      label: choice.word,
      selected: agreed == value,
      onTap: flags.isEmpty ? null : () => onPicked(value),
    );
    return AppWindowField(
      label: label,
      child: Align(
        alignment: Alignment.centerLeft,
        child: PillStrip(
          items: [choice(off, value: false), choice(on, value: true)],
        ),
      ),
    );
  }
}
