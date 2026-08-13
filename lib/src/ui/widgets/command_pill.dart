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
/// ⛔The `▾` is gone from the whole bar. Where a verb needs to offer VARIANTS
/// it grows a [GripBand] along its top edge instead ([StrapIconButton]) — a
/// caret costs 16px of the scarce axis, and the top edge costs none.
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
    return SizedBox(
      width: AppIconButtonSize.bar.maxWidth,
      height: CommandPill.height,
      child: Stack(
        children: [
          // ★The body keeps its FULL size and sits against the bottom; the
          // band's target is laid OVER its top edge rather than beside it.
          //
          // It was written the other way first — body pushed down below the
          // 8px, `Align`ed inside what was left — and that is 24px of button
          // in a 20px box: a silent 4px overflow, because a `Stack` neither
          // clips nor complains. The pill is exactly the bar's content height
          // (36 − 8 of padding = 28), so there is no margin above it to
          // borrow; the zone has to come out of the button's own top.
          //
          // What the body loses is 8px of TARGET, not of glyph — the icon is
          // 18px centred in a 24px box, so it still clears the band.
          Align(alignment: Alignment.bottomCenter, child: button),
          Positioned(
            left: 3,
            right: 3,
            top: 1,
            height: GripBand.reach,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // ★Thickness never moves (유저 확정: 호버하면 굵어지는 것은
                  // 폐기, 처음부터 굵은 상태). Only the colour climbs, and it
                  // climbs the app's one ladder.
                  color: GripBand.ink(
                    nearby: enabled,
                    hovered: _bandHovered,
                    active: _bandPressed,
                    idle: AppColors.hairlineStrong,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          // LAST in the stack, so its 8px wins the hit test over the body.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: GripBand.hitExtent,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _bandHovered = true),
              onExit: (_) => setState(() => _bandHovered = false),
              child: GestureDetector(
                key: ValueKey<String>(widget.menuKey!),
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => setState(() => _bandPressed = true),
                onTapCancel: () => setState(() => _bandPressed = false),
                onTap: () {
                  setState(() => _bandPressed = false);
                  showPanelFlyout(
                    context,
                    entries: widget.entriesBuilder!(),
                    // The list belongs to the BUTTON, not to the 8px sliver
                    // that opened it — anchoring on the sliver would hang the
                    // menu off the bar's top edge instead of under the button.
                    anchorRect: Offset.zero &
                        Size(
                          AppIconButtonSize.bar.maxWidth,
                          CommandPill.height,
                        ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
