import 'dart:async';
import 'package:flutter/material.dart';

import '../input/control_press_claim.dart';
import '../text/text_measure.dart';
import '../theme/app_theme.dart';
import 'app_icon_button.dart';
import 'grip_band.dart';
import 'keyboard_press.dart';
import 'panel_flyout.dart';
import 'rail_glyph_button.dart';
import 'static_raster.dart';

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
  ///
  /// At 1× — see [heightIn] for the pill where it is shown.
  static const double height = 28;

  /// The largest words a pill holds: the comma buttons' digits. The name
  /// cell's 11.5 sits inside a line of this.
  static const double verbFontSize = 12.5;

  /// What a pill adds to [height] where it is shown: one line of its largest
  /// words, grown under the OS text size.
  ///
  /// 🚨text-scale-fixed-height-bars (유저 2026-09-18, 「막대가 글자 크기를
  /// 따라 자란다」). 🔬In the app's face at 1.5× the name cells' words stood
  /// 25 tall in their 24.
  static double growthIn(BuildContext context) => TextMeasure(
    context,
    DefaultTextStyle.of(context).style.copyWith(fontSize: verbFontSize),
  ).lineGrowthOf(TextMeasure.everyScript);

  /// The pill where it is shown — every cell inside it is this less 4.
  static double heightIn(BuildContext context) => height + growthIn(context);

  /// The breath after the LAST verb — THE SAME one the head pays on its
  /// leading edge.
  ///
  /// 🚨유저 #7 (2026-08-14): 「**1,2,3,4,N 에서 n버튼 오른쪽만 미묘하게 짧다**
  /// 던가, **fx버튼의 오른쪽이 미묘하게 공간 있다**던가. 이런 미묘한 이상한
  /// 패딩 싹 삭제」.
  ///
  /// ⛔A flat 4 was 「the smaller of the head's two paddings」, picked back
  /// when the complaint was a border touching a glyph. But a name cell pays
  /// `1 + (4 | 6)` on its leading edge, so a TEXT-headed pill measured 7 in
  /// and 4 out — and `N`, a glyph with no bearing of its own, is exactly
  /// where those three pixels went missing.
  ///
  /// ★So the tail READS the head rather than guessing at it. 「The pill owes
  /// its contents the same margin on both ends」 is what the old note
  /// already said; the constant just could not say it.
  ///
  /// ⛔And it never guesses. Anything else answered an icon's 5, which is
  /// what the frame pill paid after its word's 7 the day its name went into
  /// a gated group the pill could not see into — and what the headless
  /// pill paid after its 2 from the first day (frame-pill-tail-breath-
  /// regressed, 2026-10-27).
  static double _tailBreathFor(Widget? head) => switch (head) {
    // A head baked in a zone of its own is still its cell.
    CommandGroupZone(:final child) => _tailBreathFor(child),
    PillNameCell(label: _?) => PillNameCell.textBreath,
    PillNameCell() => PillNameCell.iconBreath,
    null => _headlessBreath,
    _ => throw StateError('a pill reads its head, and this one hides it'),
  };

  /// What a headless pill pays its first verb, where the name cell would
  /// have stood.
  static const double _headlessBreath = 2;

  @override
  Widget build(BuildContext context) {
    final pill = DecoratedBox(
      decoration: ShapeDecoration(
        // The app's control shape at this height — never a hand-typed
        // radius: `app_shapes_coverage_test` polices exactly that, and the
        // corner ratio is a token so a future control-shape change lands
        // here too.
        shape: AppShapes.control(
          heightIn(context),
          side: BorderSide(color: AppColors.hairline),
        ),
      ),
      child: SizedBox(
        height: heightIn(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A headless pill still owes its first verb the same breath the
            // name cell would have carried.
            if (head case final head?)
              head
            else
              const SizedBox(width: _headlessBreath),
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
            // ⛔None when there are no verbs. A head-only pill (fx) already
            // pays its own trailing padding, and adding the tail on top of
            // it is the 「fx버튼의 오른쪽이 미묘하게 공간 있다」 gap.
            if (children.isNotEmpty) SizedBox(width: _tailBreathFor(head)),
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
    return Opacity(opacity: 0.38, child: IgnorePointer(child: pill));
  }
}

/// One BAKE of the command bar ([StaticRaster]): a group's pill, or a piece
/// of one, that changes only with what the group shows.
///
/// Siblings, never nesting — a bake inside a bake is the one thing that
/// freezes, and a tick layer inside one keeps it from baking at all. So a
/// pill with bakes of its own in it (the frame pill's groups), or with
/// something that ticks in it (the cut's name did, F-463 ④ to F-491), is
/// zoned round them, a zone on either side.
class CommandGroupZone extends StatelessWidget {
  const CommandGroupZone({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      StaticRaster(debugLabel: 'command-group', child: child);
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
///
/// 🪶ONE FACE (card frame-panels-build-in-one-frame, 2026-10-25): the cell
/// was a claim, a [Material], an [InkWell] and a tooltip — ~30 elements, and
/// a tab wears four, built again whenever it is shown. It is a plate now
/// ([RailPlateButton]): one render object that is the claim, the hover, the
/// tooltip, the cursor and the node, with the keyboard's focus above it
/// ([KeyboardPress]). ⛔Nothing on the screen changes — the hover and the
/// focus are the [InkWell]'s colours in its shape, the word sits in the
/// [Material]'s text style (`a_name_cell_is_one_face_test`).
///
/// 🔧Enter and Space OPEN the menu now, and so does a screen reader's
/// press. The [InkWell] took the focus and answered both with a tap that
/// did nothing — the menu was the claim's, which hears only a pointer —
/// while every icon button beside it answers them (board `F-450-Q1`:
/// 「통일 — 아이콘 버튼도 Enter · Space 로 눌린다」).
class PillNameCell extends StatefulWidget {
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

  /// 🚨유저 #7 — the head's TOTAL leading breath, named so the pill's tail
  /// can pay the same one instead of guessing at it.
  ///
  /// ⛔They are totals, not the inner padding: the cell also sits inside
  /// [_outerInset], and it was that split that let a "4 vs 6" comparison
  /// look symmetric while the pill measured 7 in and 4 out.
  static const double iconBreath = 5;
  static const double textBreath = 7;

  /// The gap OUTSIDE the tappable cell, so two adjacent name cells never
  /// touch. Part of the breath above, which is why it is subtracted from
  /// the inner padding rather than added to it.
  static const double _outerInset = 1;

  @override
  State<PillNameCell> createState() => _PillNameCellState();
}

class _PillNameCellState extends State<PillNameCell> with KeyboardPress {
  @override
  VoidCallback get keyboardPress => _open;

  // 🚨A NAME CELL WITH NOTHING TO SHOW OPENS NOTHING. `showMenu` asserts on
  // an empty list, so a pill whose last menu item is retired used to crash
  // on the press rather than simply having no menu — which is a hard
  // failure for a soft situation, and it is the noun's own name the user
  // pressed.
  //
  // The entries are built to ask rather than assumed empty: several of them
  // are gated per state, so "empty right now" is a live answer.
  void _open() {
    final entries = widget.entriesBuilder();
    if (entries.isEmpty) {
      return;
    }
    unawaited(showPanelFlyout(context, entries: entries));
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final height = CommandPill.heightIn(context) - 4;
    final Widget content = label == null
        ? Icon(widget.icon, size: 16, color: AppColors.textDim)
        : Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(fontSize: 11.5, color: AppColors.text),
          );
    // 🚨A name cell is a control: a press that lands here is its own,
    // scroll included — the plate IS its claim ([PressClaim]).
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PillNameCell._outerInset,
      ),
      child: keyboardReaches(
        RailPlateButton(
          key: ValueKey<String>(widget.keyValue),
          name: widget.keyValue,
          tooltip: widget.tooltip ?? '',
          onPressed: _open,
          focus: keyboardFocus,
          // The app's control shape, as the [InkWell]'s `customBorder` wore
          // it — never a hand-typed radius (`app_shapes_coverage_test`).
          hoverShape: AppShapes.control(height),
          // The [Material] the cell stood on SET the words' style — the
          // theme's body text — rather than leaving the bar's.
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyMedium!,
            child: Container(
              height: height,
              constraints: const BoxConstraints(minWidth: 24),
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(
                horizontal:
                    (label == null
                        ? PillNameCell.iconBreath
                        : PillNameCell.textBreath) -
                    PillNameCell._outerInset,
              ),
              child: content,
            ),
          ),
        ),
      ),
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
    this.shortcuts = const [],
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

  /// The actions the BODY presses — its tooltip shows their live keys
  /// (I-19), as an [AppIconButton]'s does.
  final List<String> shortcuts;

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
      shortcuts: widget.shortcuts,
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
    // and nothing else; the band was the ONLY route to a storyboard or image
    // layer. Someone new to the app could not find it (유저: 「그 띠가
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
      cursor: AppCursors.pressWhen(live: enabled),
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      // 🚨The caret is a control like the button beside it — the pill bar
      // scrolls, and a press that lands here must not become that scroll.
      //
      // 🚨★F-120 (유저 2026-09-13): 「펜으로 레이어나 컷이나 +버튼 옆의 생성할
      // 레이어 여는 버튼같은게 작동안함. 마우스로는 작동함 … 그런 커서
      // 위치따라 판정하는거 없도록. 애초에 공용버튼아닌가?」. The claim was
      // mounted here and said nothing: the menu opened from the
      // `GestureDetector`'s TAP, and the claim takes the arena on the first
      // movement — which rejects that very tap. A pen always moves a little
      // while it is down, so the menu opened for a still mouse and never for
      // a pen. ⇒ The claim fires the caret, exactly as it fires
      // [AppIconButton]; the tap is silent and stays only to hold the arena.
      child: ControlPressClaim(
        onPressed: enabled ? () => onOpen(context) : null,
        child: GestureDetector(
          key: ValueKey<String>(menuKey),
          behavior: HitTestBehavior.opaque,
          onTap: silentPress(enabled ? () => onOpen(context) : null),
          // The pressed shade rides the POINTER for the same reason: a tap's
          // down/cancel pair went back to looking unpressed on the first
          // wobble. Every light face (`PressFace`) draws its own layer so.
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: enabled ? (_) => onPressedChanged(true) : null,
            onPointerUp: (_) => onPressedChanged(false),
            onPointerCancel: (_) => onPressedChanged(false),
            child: SizedBox(
              width: width,
              height: CommandPill.heightIn(context),
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
        ),
      ),
    );
  }
}
