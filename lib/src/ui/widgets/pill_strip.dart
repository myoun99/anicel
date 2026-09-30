import 'package:flutter/material.dart';

import '../input/control_press_claim.dart';
import '../theme/app_theme.dart';
import 'app_tooltip.dart';

const _pillPadding = EdgeInsets.symmetric(horizontal: 7, vertical: 2);

/// One segment of a [PillStrip].
class PillItem {
  const PillItem({
    required this.keyValue,
    required this.label,
    required this.selected,
    this.onTap,
    this.tooltip,
    this.otherLabel,
  });

  /// Tests reach for `ValueKey<String>(keyValue)`, so the key is part of
  /// the row's contract.
  final String keyValue;
  final String label;
  final bool selected;

  /// Null = offered but refused: the pill keeps its place and loses its
  /// tap (「없다가 생기는 UI 금지」).
  final VoidCallback? onTap;
  final String? tooltip;

  /// What the pill says in its other state, when a press changes its word
  /// ([TogglePill]).
  final String? otherLabel;
}

/// 🚨THE ONE GROUPED-CHOICE CONTROL (유저 2026-09-09: 「여러개중 하나
/// 선택한다거나 … 복수선택한다거나 그룹으로 묶여있는 선택은 이 ui 사용하도록
/// 공용화. 출력쪽말고 다른쪽도 마찬가지로」): joined pills in one outline, the
/// chosen ones tinted accent. Whether the group is single- or multi-select
/// is the CALLER's rule — the strip only shows which are on — so 선택(하나)
/// and 이름 지정(여럿) wear one look. Selection is colour alone.
///
/// The export window had it first (I-12); every grouped choice in the app
/// wears it now (board `pill-group-everywhere`) — ⛔no `SegmentedButton`,
/// no chip row of its own (`test/architecture/grouped_choices_are_one_pill_strip_test.dart`).
///
/// ⚠️Laid along [axis]. Across, it needs a BOUNDED width: its pills are
/// [Flexible] so the strip shrinks instead of overflowing a narrow column
/// — as a child of a `Row`, wrap it in `Flexible` yourself; under `Align`,
/// `Wrap` or a `Column` it is fine. Down, the pills stand one per line at
/// the strip's full width, for answers too long to sit side by side in a
/// panel's width.
class PillStrip extends StatelessWidget {
  const PillStrip({
    super.key,
    required this.items,
    this.axis = Axis.horizontal,
  });

  final List<PillItem> items;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final across = axis == Axis.horizontal;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        shape: AppShapes.container(
          AppShapes.wellRadius,
          side: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Flex(
        direction: axis,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: across
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i += 1)
            _pill(items[i], first: i == 0, across: across),
        ],
      ),
    );
  }

  Widget _pill(PillItem item, {required bool first, required bool across}) {
    final Widget pill = Pill(
      key: ValueKey<String>(item.keyValue),
      label: item.label,
      otherLabel: item.otherLabel,
      selected: item.selected,
      onTap: item.onTap,
      leadingHairline: !first,
      axis: axis,
    );
    final tooltip = item.tooltip;
    final shown = tooltip == null
        ? pill
        : AppTooltip(message: tooltip, child: pill);
    // Loose, across: a pill takes its own width while the strip fits, and
    // gives width up (its label ellipsising) when the column is narrower
    // than the strip — a strip never overflows its row. Down, each pill
    // is one line tall.
    return across ? Flexible(child: shown) : shown;
  }
}

/// One drawn segment of a [PillStrip] — the widget a test reaches through
/// the item's key to read `selected`, `label` and `onTap`.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.leadingHairline,
    this.axis = Axis.horizontal,
    this.otherLabel,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Every segment but the first draws the hairline that separates it
  /// from the one before — on its left across, on its top down.
  final bool leadingHairline;
  final Axis axis;

  /// The word of the pill's other state, held invisible under [label]: the
  /// pill keeps ONE width whichever word it says, so a press that flips it
  /// does not pull its edge out from under the pointer and the next press
  /// lands where this one did (「자리는 항상 예약하고 내용만 바꾼다」).
  final String? otherLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    Text word(String text, {bool shown = true}) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        // A selected pill reads selected even when it takes no tap —
        // 「커스텀」 is a state the delta puts the row in, not a button.
        color: !shown
            ? Colors.transparent
            : selected
            ? accent
            : onTap == null
            ? theme.disabledColor
            : theme.colorScheme.onSurface,
      ),
    );
    final other = otherLabel;
    final hairline = BorderSide(color: theme.dividerColor);
    return ControlPressClaim(
      onPressed: onTap,
      child: InkWell(
        onTap: silentPress(onTap),
        child: Container(
          padding: _pillPadding,
          // Down, a pill spans the strip, and its word sits in the middle
          // as it does in a pill that is only as wide as its word.
          alignment: axis == Axis.vertical ? Alignment.center : null,
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.14) : null,
            border: !leadingHairline
                ? null
                : axis == Axis.horizontal
                ? Border(left: hairline)
                : Border(top: hairline),
          ),
          child: other == null
              ? word(label)
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    // Held for its width only: set in no colour and never
                    // read out. ⛔Not an `Opacity` or a `Visibility`: the
                    // one is a compositing boundary a panel cannot bake
                    // across, the other takes the slot away.
                    ExcludeSemantics(child: word(other, shown: false)),
                    word(label),
                  ],
                ),
        ),
      ),
    );
  }
}

/// 🚨A YES/NO IS ONE PILL (유저 2026-09-25: 「SE 빈칸 이런 불리언값 있잖아.
/// 이런거 누르면 강조색/칠함, 다시누르면 일반색/비움 이렇게 텍스트도
/// 바뀌게하면 알기쉬울거같은데. 공용ui로서 해도 될듯?」): lit with its ON
/// word while on, plain with its OFF word while off, so the word says the
/// state as plainly as the colour does. It is a strip of one, so it wears
/// the grouped choices' outline.
///
/// ⚠️Where it stands and where the ring ([BooleanDot]) stands — every
/// other yes/no row, by the user's 2026-09-23 「진짜 불리언값 모든곳에
/// 적용」 — is board decision `pill-group-booleans-Q1`.
class TogglePill extends StatelessWidget {
  const TogglePill({
    super.key,
    required this.keyValue,
    required this.on,
    required this.words,
    required this.onChanged,
  });

  /// The pill is keyed `ValueKey<String>(keyValue)`, as a strip's pill is.
  final String keyValue;
  final bool on;

  /// What the pill says in each state.
  final ({String on, String off}) words;

  /// Null = refused: the pill keeps its place and its word, and loses its
  /// tap.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return PillStrip(
      items: [
        PillItem(
          keyValue: keyValue,
          label: on ? words.on : words.off,
          otherLabel: on ? words.off : words.on,
          selected: on,
          onTap: onChanged == null ? null : () => onChanged(!on),
        ),
      ],
    );
  }
}
