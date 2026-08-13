import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_icon_button.dart';
import 'grip_band.dart';
import 'panel_flyout.dart';

/// THE grammar of the frame panels' command bar (유저 확정, 2026-08-10):
///
/// > **알약 = `[ 명사 ] [ 그 명사의 고빈도 동사들 ]`**
///
/// One border per NOUN. The first cell is that noun's NAME — and pressing it
/// opens that noun's menu, so the label is the button and there is no `▾`
/// beside it. Everything after the first cell is a verb aimed at the same
/// noun, with [PillDivider] between groups of them.
///
/// The rule pays for itself twice. A pill with NO verbs is not an exception —
/// it is the same shape with the list empty (the FX and settings pills) — and
/// the border itself carries information: **a pill is a noun and its verbs; a
/// bare row of icons is a state machine** (the playback transport, which is
/// deliberately not wrapped in one).
///
/// ⛔The `▾` is gone from the whole bar, with ONE exception: a verb that
/// offers VARIANTS carries a slim caret beside it ([StrapIconButton]).
///
/// That exception was itself the retired rule for a while — the variants sat
/// on a band along the button's top edge, bought with the argument that 「a
/// caret costs 16px of the scarce axis, and the top edge costs none」. It
/// cost something the width never would: nobody could find it. The `＋`
/// makes only an animation layer, so the band was the sole route to every
/// other KIND, and a first-time user simply could not reach them (유저
/// 2026-08-14: 「옛날처럼 +버튼 오른쪽에 펼치기아이콘으로 버튼 했었잖아.
/// 그거 그대로하자.」). Discoverability was feature availability, and the bar
/// scrolls anyway.
class CommandPill extends StatelessWidget {
  const CommandPill({
    super.key,
    this.head,
    this.children = const <Widget>[],
    this.enabled = true,
  });

  /// The noun's name cell — see [PillNameCell]. First, and the menu.
  ///
  /// NULL for the SHARED pill (유저 2026-08-12: 「프레임알약 옆에 공용버튼
  /// 들어가는 알약만들고 거기」). Its verbs — delete, copy, paste — belong to
  /// no noun: they act on whatever is selected, and the selection is not a
  /// thing with a menu. Inventing a name cell for it would have been a
  /// border drawn around a gap, which is the mistake push/pull avoided by
  /// waiting for the frame pill rather than growing a "rows" noun.
  final Widget? head;

  /// The verbs, in order. Put a [PillDivider] between groups.
  final List<Widget> children;

  /// Whether this whole noun applies right now. A pill that does not apply
  /// DIMS — it never disappears and never resizes, because the bar's law is
  /// 「자리는 못 박고 색만 죽인다」 (유저 확정).
  final bool enabled;

  /// The pill's outer height. [AppIconButtonSize.bar] plus 2px of breath on
  /// each side, which is what makes a pill sit inside a 36px command bar
  /// with the [GripBand.hitExtent] of its `＋` reaching into the margin.
  static const double height = 28;

  /// The breath after the LAST verb, so the pill is not open on one side.
  ///
  /// It matches the smaller of the head's two paddings (4 for an icon name
  /// cell, 6 for a text one) rather than picking the larger: the verbs
  /// already carry a little of their own inside their 24px boxes, and the
  /// complaint was a border touching a glyph, not a cramped row.
  static const double _tailBreath = 4;

  @override
  Widget build(BuildContext context) {
    final pill = DecoratedBox(
      decoration: ShapeDecoration(
        // The app's control shape at this height — never a hand-typed
        // radius: `app_shapes_coverage_test` polices exactly that, and the
        // corner ratio is a token so a future control-shape change lands
        // here too.
        shape: AppShapes.control(
          height,
          side: const BorderSide(color: AppColors.hairline),
        ),
      ),
      child: SizedBox(
        height: height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A headless pill still owes its first verb the same breath the
            // name cell would have carried.
            if (head case final head?) head else const SizedBox(width: 2),
            ...children,
            // ② 유저 2026-08-12: 「N 옆에 공간이 잘린거마냥 공간부족해서
            // 이상해보임」.
            //
            // The head carries its own leading breath and the tail carried
            // none, so the last verb sat flat against the border — which on
            // the frame pill is `N`, a glyph with no bearing of its own
            // (`_commaButton` is 24px wide with zero padding). The pill owes
            // its contents the same margin on both ends, so it pays it here
            // rather than in each bar: a trailing `SizedBox` in the frame
            // pill alone would have fixed the complaint and left cut, layer
            // and fx still lopsided.
            const SizedBox(width: _tailBreath),
          ],
        ),
      ),
    );
    // Opacity and NOT a per-child enablement sweep: the law is about the
    // WHOLE noun standing down, and a disabled child already dims itself.
    // Wrapping keeps the geometry identical to the enabled pill by
    // construction, which is the part a per-child version keeps getting
    // wrong.
    if (enabled) {
      return pill;
    }
    return Opacity(
      opacity: 0.38,
      child: IgnorePointer(child: pill),
    );
  }
}

/// The thin rule between two groups of verbs INSIDE one pill.
class PillDivider extends StatelessWidget {
  const PillDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 15,
    margin: const EdgeInsets.symmetric(horizontal: 3),
    color: AppColors.hairline,
  );
}

/// A pill's FIRST cell: the noun's name, and the noun's menu.
///
/// [label] writes the name out (컷 · 레이어 · 프레임 — 유저 확정: 아이콘 말고
/// 텍스트); [icon] is for the two nouns whose name is already a symbol
/// everywhere (FX, settings). Exactly one of them.
class PillNameCell extends StatelessWidget {
  const PillNameCell({
    super.key,
    required this.keyValue,
    required this.entriesBuilder,
    this.label,
    this.icon,
    this.tooltip,
  }) : assert(
         (label == null) != (icon == null),
         'a name cell is a word or a glyph, not both',
       );

  final String keyValue;
  final List<PanelFlyoutEntry> Function() entriesBuilder;
  final String? label;
  final IconData? icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    final Widget content = label == null
        ? Icon(icon, size: 16, color: AppColors.textDim)
        : Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(fontSize: 11.5, color: AppColors.text),
          );
    final cell = Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey<String>(keyValue),
        // `customBorder`, not a hand-typed `borderRadius`: the splash has to
        // wear the app's control shape like everything else, and a literal
        // radius here is what `app_shapes_coverage_test` exists to catch.
        customBorder: AppShapes.control(CommandPill.height - 4),
        // 🚨A NAME CELL WITH NOTHING TO SHOW OPENS NOTHING. `showMenu`
        // asserts on an empty list, so a pill whose last menu item is
        // retired used to crash on the press rather than simply having no
        // menu — which is a hard failure for a soft situation, and it is
        // the noun's own name the user pressed.
        //
        // The entries are built to ask rather than assumed empty: several of
        // them are gated per state, so "empty right now" is a live answer.
        onTap: () {
          final entries = entriesBuilder();
          if (entries.isEmpty) {
            return;
          }
          showPanelFlyout(context, entries: entries);
        },
        child: Container(
          height: CommandPill.height - 4,
          constraints: const BoxConstraints(minWidth: 24),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: label == null ? 4 : 6),
          child: content,
        ),
      ),
    );
    final tooltip = this.tooltip;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: tooltip == null ? cell : Tooltip(message: tooltip, child: cell),
    );
  }
}

/// A verb whose top edge opens its VARIANTS.
///
/// The body is the primary action; a [GripBand] runs along the button's top
/// edge and opens [entriesBuilder]. Null [entriesBuilder] draws no band at
/// all — and that absence is itself the signal: **a band means there is
/// something to choose.** The frame pill's `＋` makes one thing in the place
/// you are standing, so it wears none.
///
/// Both halves keep their own key strings, so a test that pressed the retired
/// `SplitIconButton`'s body or its `▾` zone still finds them.
class StrapIconButton extends StatefulWidget {
  const StrapIconButton({
    super.key,
    required this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.menuKey,
    this.entriesBuilder,
    this.accent = false,
  }) : assert(
         (menuKey == null) == (entriesBuilder == null),
         'a band needs both a key and a list',
       );

  final String buttonKey;
  final String? menuKey;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final List<PanelFlyoutEntry> Function()? entriesBuilder;

  /// The ADD affordance, and the ONLY place the accent is allowed on this
  /// bar (유저 확정): the GLYPH goes accent — never the border, never the
  /// band.
  final bool accent;

  @override
  State<StrapIconButton> createState() => _StrapIconButtonState();
}

class _StrapIconButtonState extends State<StrapIconButton> {
  bool _bandHovered = false;
  bool _bandPressed = false;

  bool get _hasBand => widget.entriesBuilder != null;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final button = AppIconButton(
      keyValue: widget.buttonKey,
      tooltip: widget.tooltip,
      onPressed: widget.onPressed,
      icon: Icon(
        widget.icon,
        color: widget.accent ? AppColors.addGlyph(enabled: enabled) : null,
      ),
    );
    if (!_hasBand) {
      return button;
    }
    // 🚨★ 유저 확정 2026-08-14, ⛔재론 금지: 「**옛날처럼 +버튼 오른쪽에
    // 펼치기아이콘으로 버튼** 했었잖아. 그거 그대로하자.」
    //
    // The variants used to live on an 8px band laid over the button's top
    // edge, and the note defending that weighed one cost only: 「a caret
    // costs 16px of the scarce axis, and the top edge costs none」. It bought
    // the width by making the affordance invisible.
    //
    // ⚠️Here that is not a cosmetic loss. The `＋` makes an ANIMATION layer
    // and nothing else; the band was the ONLY route to a storyboard, image or
    // text layer. Someone new to the app could not find it (유저: 「그 띠가
    // 너무 알기어렵다고해」), so discoverability WAS feature availability —
    // and 16px is not the expensive side of that trade. The bar scrolls
    // (유저: 「스크롤있으니까 상관없는데」).
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        _ExpandButton(
          menuKey: widget.menuKey!,
          enabled: enabled,
          hovered: _bandHovered,
          pressed: _bandPressed,
          onHoverChanged: (value) => setState(() => _bandHovered = value),
          onPressedChanged: (value) => setState(() => _bandPressed = value),
          onOpen: (context) =>
              showPanelFlyout(context, entries: widget.entriesBuilder!()),
        ),
      ],
    );
  }
}

/// The slim caret beside a [StrapIconButton] that opens its variants.
///
/// Narrow on purpose: it is a second door onto the button next to it, not a
/// verb of its own, and a full-width target would read as two buttons.
///
/// ⛔The accent never lands here. [StrapIconButton.accent] puts it on the
/// `＋` GLYPH and only there (유저 확정) — an accented caret would claim the
/// menu is the thing that adds. The ink climbs [GripBand]'s ladder instead,
/// which is the same one the retired band used, so the hover and press
/// shades are unchanged.
class _ExpandButton extends StatelessWidget {
  const _ExpandButton({
    required this.menuKey,
    required this.enabled,
    required this.hovered,
    required this.pressed,
    required this.onHoverChanged,
    required this.onPressedChanged,
    required this.onOpen,
  });

  final String menuKey;
  final bool enabled;
  final bool hovered;
  final bool pressed;
  final ValueChanged<bool> onHoverChanged;
  final ValueChanged<bool> onPressedChanged;
  final void Function(BuildContext context) onOpen;

  /// Wide enough to aim at, narrow enough to read as part of its neighbour.
  static const double width = 16;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: GestureDetector(
        key: ValueKey<String>(menuKey),
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => onPressedChanged(true) : null,
        onTapCancel: () => onPressedChanged(false),
        onTap: enabled
            ? () {
                onPressedChanged(false);
                onOpen(context);
              }
            : null,
        child: SizedBox(
          width: width,
          height: CommandPill.height,
          child: Center(
            child: Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: GripBand.ink(
                nearby: enabled,
                hovered: hovered,
                active: pressed,
                idle: AppColors.hairlineStrong,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
