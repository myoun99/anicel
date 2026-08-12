import 'package:flutter/material.dart';

import '../text/vertical_writing_text.dart';
import '../theme/app_theme.dart';

/// One entry of a [showPanelFlyout] list.
///
/// The app's shared popup-list vocabulary (the FieldSlider of menus): every
/// toolbar menu, legend bulk flyout and split-button dropdown builds from
/// these entries so they all read alike.
sealed class PanelFlyoutEntry {
  const PanelFlyoutEntry();
}

/// Non-interactive section caption.
class PanelFlyoutHeader extends PanelFlyoutEntry {
  const PanelFlyoutHeader(this.label);

  final String label;
}

/// Thin separator between groups.
class PanelFlyoutDivider extends PanelFlyoutEntry {
  const PanelFlyoutDivider();
}

/// A row of CONTROLS rather than a command — the knobs a panel keeps out
/// of its pill (rotate, flip, the surface colours).
///
/// It is deliberately part of THIS vocabulary rather than a popover of its
/// own: R6 spent a round pulling every hand-rolled popup back into this
/// one shell, and a panel that grew its own settings surface would undo
/// that on the day it was written.
///
/// A row is never selectable, so turning a knob does not close the flyout
/// — choosing a command is what closes it, and a knob is not a choice.
class PanelFlyoutRow extends PanelFlyoutEntry {
  const PanelFlyoutRow({
    required this.keyValue,
    required this.builder,
    this.listenable,
    this.label,
    this.height = 32,
  });

  final String keyValue;

  /// Optional caption to the left of the controls, for a knob whose own
  /// glyph does not say what it is.
  final String? label;

  /// Built LAZILY and rebuilt on [listenable], which is the whole reason
  /// this is a builder and not a widget.
  ///
  /// 🚨 A flyout is an overlay route: its entries are built once, when it
  /// opens, and nothing in the host's own rebuilds reaches them. That is
  /// fine for a command — a command has no state to show — but a knob
  /// that cannot show its own state is a knob nobody can read. Rotate the
  /// view from inside the list and the accent would still sit on the
  /// button it was on when the list opened.
  final WidgetBuilder builder;

  /// What the controls in this row are ABOUT. Null for a row whose
  /// contents cannot change while the list is open.
  final Listenable? listenable;

  final double height;
}

/// A selectable command.
class PanelFlyoutItem extends PanelFlyoutEntry {
  const PanelFlyoutItem({
    required this.keyValue,
    required this.label,
    this.icon,
    this.iconFlipY = false,
    this.swatch,
    this.checked,
    this.selected = false,
    this.danger = false,
    this.enabled = true,
    this.onSelected,
  }) : assert(
         icon == null || swatch == null,
         'a row has ONE leading mark: a glyph or a colour, not both',
       );

  /// Widget key string — menu items that replaced toolbar buttons reuse the
  /// retired button's key string so tests only gain a menu-open tap.
  final String keyValue;

  final String label;
  final IconData? icon;

  /// Mirrors [icon] vertically.
  ///
  /// For the ONE case the rail already solved this way: an attach arrow
  /// points down-right natively, and the above-placement one is that same
  /// glyph flipped ([LayerAttachArrowCell]). A separate up-arrow glyph would
  /// be a second vocabulary for a distinction the rail makes by flipping.
  final bool iconFlipY;

  /// A filled circle in the leading slot, in ITS OWN colour — for rows whose
  /// subject IS a colour (the layer mark picker).
  ///
  /// It cannot be expressed as [icon]: a glyph is inked by [_inkFor], which
  /// is how a flyout says enabled / destructive / current, and a swatch that
  /// obeyed that would stop being the colour it is naming. So the leading
  /// slot takes either a glyph the list may tint or a colour it may not.
  final Color? swatch;

  /// Trailing check when true; null means the item is not a toggle.
  ///
  /// ⛔A TOGGLE, not a selection. Which of several things is CURRENT is
  /// [selected] — see there for why the two may not share a glyph.
  final bool? checked;

  /// This row is the one currently in force — the open panel in an overflow
  /// list, the bound gesture in a picker.
  ///
  /// ★It reads as COLOUR and nothing else, and it may not grow the row.
  /// 유저 (R11-①): 「어차피 선택하면 ui적으로 색 바뀌니까 그거로 충분해」 —
  /// the standing rule that selection is never a check glyph, because a mark
  /// that appears on selection changes the row's width and makes the list
  /// twitch as you move through it.
  final bool selected;

  /// Destructive styling (delete commands).
  final bool danger;

  final bool enabled;

  /// Runs AFTER the flyout closes.
  final VoidCallback? onSelected;
}

/// Shows the shared flyout anchored under [anchorContext]'s widget and runs
/// the picked item's [PanelFlyoutItem.onSelected] after the menu closes.
///
/// [anchorRect] narrows the anchor to a rect INSIDE that widget, in its
/// local coordinates. PAINTED affordances (the timeline's run-edge property
/// tags) have no box of their own to anchor on, and this keeps them on the
/// one shared popup shell instead of growing a surface-local copy.
///
/// When the space below the anchor can't fit the list, the flyout opens
/// UPWARD instead (its bottom hugging the anchor's top) — the item order
/// never changes (UI-R6 #1); Material's default merely clamped the menu,
/// which read as the list growing bottom-up.
Future<void> showPanelFlyout(
  BuildContext anchorContext, {
  required List<PanelFlyoutEntry> entries,
  Rect? anchorRect,
}) async {
  final button = anchorContext.findRenderObject()! as RenderBox;
  final anchor = anchorRect ?? (Offset.zero & button.size);
  final overlay =
      Navigator.of(anchorContext).overlay!.context.findRenderObject()!
          as RenderBox;
  // The entry heights are fixed (32/24/6 + the menu's 8+8 padding), so the
  // flyout's height is known before layout.
  var estimatedHeight = 16.0;
  for (final entry in entries) {
    estimatedHeight += switch (entry) {
      PanelFlyoutHeader() => 24.0,
      PanelFlyoutDivider() => 6.0,
      PanelFlyoutRow(:final height) => height,
      PanelFlyoutItem() => 32.0,
    };
  }
  final anchorTopLeft = button.localToGlobal(anchor.topLeft, ancestor: overlay);
  final anchorBottomLeft = button.localToGlobal(
    anchor.bottomLeft,
    ancestor: overlay,
  );
  final spaceBelow = overlay.size.height - anchorBottomLeft.dy;
  final openUpward =
      estimatedHeight > spaceBelow && anchorTopLeft.dy > spaceBelow;
  final menuAnchorRect = openUpward
      ? Rect.fromLTWH(
          anchorTopLeft.dx,
          anchorTopLeft.dy - estimatedHeight,
          anchor.width,
          estimatedHeight,
        )
      : Rect.fromPoints(
          anchorBottomLeft,
          button.localToGlobal(anchor.bottomRight, ancestor: overlay),
        );
  final position = RelativeRect.fromRect(
    menuAnchorRect,
    Offset.zero & overlay.size,
  );

  final selected = await showMenu<PanelFlyoutItem>(
    context: anchorContext,
    position: position,
    // Instant open/close (R4 #2): the whole list appears in one frame.
    popUpAnimationStyle: instantMenuAnimation,
    items: [
      for (final entry in entries)
        switch (entry) {
          PanelFlyoutHeader(:final label) => PopupMenuItem<PanelFlyoutItem>(
            enabled: false,
            height: 24,
            child: Text(
              label,
              style: const TextStyle(fontSize: 10, color: AppColors.textDim),
            ),
          ),
          PanelFlyoutDivider() =>
            const PopupMenuDivider(height: 6)
                as PopupMenuEntry<PanelFlyoutItem>,
          // `enabled: false` is what keeps a knob from doubling as a
          // command: the row itself takes no tap and never closes the
          // list. The CHILD still gets the pointer — a disabled
          // PopupMenuItem only drops its own handler, and its
          // GestureDetector hit-tests children before itself.
          PanelFlyoutRow(
            :final label,
            :final builder,
            :final listenable,
            :final height,
          ) =>
            PopupMenuItem<PanelFlyoutItem>(
              key: ValueKey<String>(entry.keyValue),
              enabled: false,
              height: height,
              child: Row(
                children: [
                  if (label != null) ...[
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textDim,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: listenable == null
                        ? Builder(builder: builder)
                        : ListenableBuilder(
                            listenable: listenable,
                            builder: (context, _) => builder(context),
                          ),
                  ),
                ],
              ),
            ),
          PanelFlyoutItem() => PopupMenuItem<PanelFlyoutItem>(
            key: ValueKey<String>(entry.keyValue),
            value: entry,
            enabled: entry.enabled,
            height: 32,
            child: Row(
              children: [
                if (entry.swatch case final swatch?) ...[
                  // 14 rather than the glyph's 16: the same circle the rail
                  // draws for the same mark, so the list and the row it was
                  // opened from show one size of dot.
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: swatch,
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else if (entry.icon != null) ...[
                  Transform.flip(
                    flipY: entry.iconFlipY,
                    child: Icon(entry.icon, size: 16, color: _inkFor(entry)),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    entry.label,
                    style: TextStyle(fontSize: 12, color: _inkFor(entry)),
                  ),
                ),
                if (entry.checked == true) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check, size: 14, color: AppColors.accent),
                ],
              ],
            ),
          ),
        },
    ],
  );
  selected?.onSelected?.call();
}

/// One row's ink. Disabled dims, destructive reddens, CURRENT accents —
/// and the last of those is the whole way a flyout says "this one", because
/// selection is colour and never a glyph (see [PanelFlyoutItem.selected]).
Color _inkFor(PanelFlyoutItem entry) {
  if (!entry.enabled) {
    return AppColors.textDim.withValues(alpha: 0.5);
  }
  if (entry.danger) {
    return AppColors.danger;
  }
  return entry.selected ? AppColors.accent : AppColors.text;
}

/// A flyout trigger that is NOT a chip: a `⋮`, a glyph, a composed label —
/// whatever the host already draws — with the tap, the ink, the tooltip and
/// the hit area supplied from here.
///
/// 🐛유저, R6 #4: 「규격들이 다 제각각임. 텍스트사이즈도 다 다르고 이상함.」
/// [PanelFlyoutButton] only ever fitted the hosts that wanted a bordered
/// word, so every host that wanted an icon reached past it for a raw
/// `PopupMenuButton` — and inherited Material's row height instead of the
/// app's. Four of them did, and they landed on three different heights (48,
/// 34, and a hand-rolled 32). The shared list was never the hard part; the
/// missing piece was a way to OPEN it without a label.
///
/// It carries no border and no padding of its own beyond [padding], because
/// the things it wraps already look like themselves.
///
/// ⛔And for the same reason there is deliberately no `enabled`.
/// [PanelFlyoutButton] has one because it draws its own label and border and
/// can therefore DIM itself; this widget draws nothing, so all it could do
/// is swallow the tap while the host's child went on looking live — a
/// control that is shut without saying so, which is the exact thing 유저
/// R4 #12 rejected (잠궜는데 바꿀 수 있으면 잠금이 아니잖아). A host that
/// needs a shut state owns the appearance of one.
class PanelFlyoutTrigger extends StatelessWidget {
  const PanelFlyoutTrigger({
    super.key,
    required this.child,
    required this.entriesBuilder,
    this.tooltip,
    this.padding = const EdgeInsets.all(8),
  });

  /// What the host draws — an `Icon`, a `Row`, a `Chip`.
  final Widget child;

  final List<PanelFlyoutEntry> Function() entriesBuilder;

  final String? tooltip;

  /// Grows the HIT AREA around [child]. A 16px glyph is not a target.
  ///
  /// The default is `PopupMenuButton`'s own, which is what all four hosts
  /// were getting before they moved here — 8 around a 16px glyph is the
  /// 32px target the panel headers are built on. A host that already sizes
  /// its own child (the tab overflow's fixed-width slot) passes zero.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final Widget button = Material(
      color: Colors.transparent,
      child: InkWell(
        // `customBorder` and not `borderRadius`: the splash is a corner like
        // any other and takes the app's superellipse, so this widget adds
        // nothing to the circular-corner debt (`app_shapes_coverage_test`,
        // which only ever ratchets down). [PanelFlyoutButton] beside it still
        // hand-types a `circular(4)` on both its border and its splash.
        customBorder: AppShapes.container(AppShapes.wellRadius),
        onTap: () => showPanelFlyout(context, entries: entriesBuilder()),
        child: Padding(padding: padding, child: child),
      ),
    );
    final message = tooltip;
    if (message == null) {
      return button;
    }
    return Tooltip(message: message, child: button);
  }
}

/// A labeled flyout trigger ('Layer ▾', 'Frame ▾', 'Cut ▾'): compact
/// bordered chip that opens [showPanelFlyout] with lazily built entries.
class PanelFlyoutButton extends StatelessWidget {
  const PanelFlyoutButton({
    super.key,
    required this.label,
    required this.entriesBuilder,
    this.tooltip,
    this.showCaret = true,
    this.fontSize = 12,
    this.labelColor,
    this.fontWeight,
    this.padding = const EdgeInsets.fromLTRB(8, 4, 5, 4),
    this.expand = false,
    this.axis = Axis.horizontal,
    this.enabled = true,
  });

  /// False = the button says what it holds and refuses to open.
  ///
  /// 유저, R4 #12: 잠궜는데 바꿀 수 있으면 잠금이 아니잖아. A control behind a
  /// lock has to LOOK shut, not merely be labelled shut — so the ink and the
  /// caret dim together and the tap stops resolving.
  final bool enabled;

  /// Which way the button READS. Vertical writes its label down the
  /// button through the shared vertical-writing table — the x-sheet's
  /// 28px columns have no other way to carry a word.
  final Axis axis;

  final String label;
  final List<PanelFlyoutEntry> Function() entriesBuilder;
  final String? tooltip;

  /// R28 #2: the caret is optional. Slot-width rails (the layer rail's
  /// blend column) drop it and keep the text alone — the border still
  /// says "button", which is the whole point of sharing this widget.
  final bool showCaret;

  final double fontSize;

  /// Null = the standard button ink; callers pass a color to carry state
  /// (the layer rail accents a non-normal mode).
  final Color? labelColor;
  final FontWeight? fontWeight;
  final EdgeInsetsGeometry padding;

  /// Fill the parent's width and CENTER the label instead of hugging it —
  /// how a fixed-width rail column keeps its button centered in the slot.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final vertical = axis == Axis.vertical;
    final ink = labelColor ?? AppColors.text;
    final labelStyle = TextStyle(
      fontSize: fontSize,
      color: enabled ? ink : ink.withValues(alpha: 0.4),
      fontWeight: fontWeight,
    );
    final Widget text = vertical
        ? VerticalWritingText(text: label, style: labelStyle)
        : Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textAlign: expand ? TextAlign.center : TextAlign.start,
            style: labelStyle,
          );
    final chip = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        // Null, not a no-op: an `InkWell` with a null callback stops
        // splashing and stops taking hover, so the button reads shut to the
        // hand as well as to the eye.
        onTap: enabled
            ? () => showPanelFlyout(context, entries: entriesBuilder())
            : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: enabled
                  ? AppColors.hairline
                  : AppColors.hairline.withValues(alpha: 0.5),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: padding,
            child: Flex(
              direction: axis,
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (expand) Flexible(child: text) else text,
                if (showCaret) ...[
                  SizedBox(
                    width: vertical ? null : 2,
                    height: vertical ? 2 : null,
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 16,
                    color: enabled
                        ? AppColors.textDim
                        : AppColors.textDim.withValues(alpha: 0.4),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (tooltip == null) {
      return chip;
    }
    return Tooltip(message: tooltip!, child: chip);
  }
}
