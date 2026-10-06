import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
    this.tone,
  });

  /// Tests reach for `ValueKey<String>(keyValue)`, so the key is part of
  /// the row's contract.
  final String keyValue;
  final String label;
  final bool selected;

  /// What a chosen pill is tinted with, where that is not the app's accent:
  /// a choice that puts a mark of its own colour somewhere else wears that
  /// colour, so the two read as one (the export window's laid direction and
  /// the 「D」 on the drawing). Null — every other pill — is the accent.
  final Color? tone;

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
/// ⚠️Laid along [axis]. Across, it needs a BOUNDED width to give width up
/// in ([_PillRow]): it shrinks instead of overflowing a narrow column — as
/// a child of a `Row`, wrap it in `Flexible` yourself; under `Align`,
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
    final pills = [
      for (var i = 0; i < items.length; i += 1) _pill(items[i], first: i == 0),
    ];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        shape: AppShapes.container(
          AppShapes.wellRadius,
          side: BorderSide(color: theme.dividerColor),
        ),
      ),
      // Down, each pill is one line tall at the strip's full width.
      child: axis == Axis.horizontal
          ? _PillRow(children: pills)
          : Column(mainAxisSize: MainAxisSize.min, children: pills),
    );
  }

  Widget _pill(PillItem item, {required bool first}) {
    final Widget pill = Pill(
      key: ValueKey<String>(item.keyValue),
      label: item.label,
      otherLabel: item.otherLabel,
      selected: item.selected,
      onTap: item.onTap,
      leadingHairline: !first,
      axis: axis,
      tone: item.tone,
    );
    final tooltip = item.tooltip;
    return tooltip == null ? pill : AppTooltip(message: tooltip, child: pill);
  }
}

/// Pills side by side: each its OWN width while the strip fits the room it
/// is given — and where it does not, the widest give width up first (their
/// words ellipsising), down to one cap they share, so a short word is never
/// cut for a long one. A strip never overflows its row.
///
/// ↩️A `Flex` of loose `Flexible`s stood here. It capped every pill at an
/// EQUAL share of the room whether or not the strip fit, so in a strip of
/// one long word and three short ones the long one was cut while room stood
/// empty beside it (found fitting 「디렉션」 beside 「셀」 into the export
/// window's rules column, 2026-10-06).
class _PillRow extends MultiChildRenderObjectWidget {
  const _PillRow({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPillRow();
}

class _PillRowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderPillRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PillRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PillRowParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PillRowParentData) {
      child.parentData = _PillRowParentData();
    }
  }

  /// What each pill of [natural] widths is given of [room]: its own while
  /// they all fit — else the narrowest keep theirs and the rest share what
  /// is left evenly.
  static List<double> _sharesOf(List<double> natural, double room) {
    // A strip that fits to the hair is a strip that fits: a pill short of
    // its own width by a rounding would wear an ellipsis for it.
    if (natural.fold(0.0, (sum, width) => sum + width) <= room + 0.01) {
      return natural;
    }
    final narrowestFirst = [for (var i = 0; i < natural.length; i += 1) i]
      ..sort((a, b) => natural[a].compareTo(natural[b]));
    final shares = [...natural];
    var left = room;
    for (var kept = 0; kept < narrowestFirst.length; kept += 1) {
      final cap = left / (narrowestFirst.length - kept);
      if (natural[narrowestFirst[kept]] > cap + _hair) {
        for (final index in narrowestFirst.skip(kept)) {
          shares[index] = cap;
        }
        break;
      }
      left -= natural[narrowestFirst[kept]];
    }
    return shares;
  }

  /// How far past its share a pill may stand and still be kept whole. An
  /// ellipsis costs a word its last glyph and more: taking it from a pill a
  /// third of a pixel over would save the others a third of a pixel (「美術」
  /// read 「美…」 beside two words that were being cut anyway).
  static const double _hair = 1;

  List<double> _sharesIn(BoxConstraints constraints) => _sharesOf([
    for (var child = firstChild; child != null; child = childAfter(child))
      child.getMaxIntrinsicWidth(double.infinity),
  ], constraints.maxWidth);

  /// The strip's size for [constraints], each pill measured by [layOut] at
  /// the width it is given.
  Size _sizeFor(
    BoxConstraints constraints,
    Size Function(RenderBox child, BoxConstraints constraints) layOut,
  ) {
    final shares = _sharesIn(constraints);
    var width = 0.0;
    var height = 0.0;
    var index = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final size = layOut(
        child,
        BoxConstraints(
          minWidth: shares[index],
          maxWidth: shares[index],
          maxHeight: constraints.maxHeight,
        ),
      );
      width += size.width;
      height = height > size.height ? height : size.height;
      index += 1;
    }
    return constraints.constrain(Size(width, height));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _sizeFor(constraints, (child, given) => child.getDryLayout(given));

  @override
  void performLayout() {
    size = _sizeFor(constraints, (child, given) {
      child.layout(given, parentUsesSize: true);
      return child.size;
    });
    var left = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      // In the middle of the strip's height, as a row sets its children.
      (child.parentData! as _PillRowParentData).offset = Offset(
        left,
        (size.height - child.size.height) / 2,
      );
      left += child.size.width;
    }
  }

  double _across(double Function(RenderBox child) widthOf) {
    var sum = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      sum += widthOf(child);
    }
    return sum;
  }

  double _tallest(double Function(RenderBox child) heightOf) {
    var most = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final height = heightOf(child);
      most = most > height ? most : height;
    }
    return most;
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _across((child) => child.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _across((child) => child.getMaxIntrinsicWidth(height));

  @override
  double computeMinIntrinsicHeight(double width) =>
      _tallest((child) => child.getMinIntrinsicHeight(double.infinity));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _tallest((child) => child.getMaxIntrinsicHeight(double.infinity));

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToHighestActualBaseline(baseline);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
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
    this.tone,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// The tint of the pill while it is chosen ([PillItem.tone]); null is the
  /// app's accent.
  final Color? tone;

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
    final accent = tone ?? theme.colorScheme.primary;
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
          // Down, a pill takes the whole width the strip is given and sets
          // its word in the middle, as it sits in a pill only as wide as
          // its word — one alignment does both.
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
