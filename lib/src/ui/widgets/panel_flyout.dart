import 'package:flutter/material.dart';

import '../text/vertical_writing_text.dart';
import '../theme/app_theme.dart';
import '../input/control_press_claim.dart';

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
    this.submenuBuilder,
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

  /// A SECOND level, anchored to this row and opened by hovering it.
  ///
  /// 🚨★★★유저 설계(I-4): 「위에서부터 콘티,레이아웃,러프원화,원화,동화,시아게
  /// 가 있고, 거기 **호버하면 추가로 앵커팝오버로 수정라벨이 뜨도록**. 즉 축으로
  /// 서 2가지가 존재하도록」 — the second axis exists so that it is NOT all on
  /// screen at once. Flattening the two into one list defeats the reason
  /// there are two.
  ///
  /// ⚠️A row that has one takes no tap of its own: choosing happens in the
  /// child. Built lazily, like the top-level list.
  final List<PanelFlyoutEntry> Function()? submenuBuilder;

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

  // 🚨★★★THE SUBMENU IS AN OVERLAY THE HOVER MOVES, NOT A STACK OF ROUTES.
  //
  // ⛔The first attempt opened each child with `showMenu` again. A menu is a
  // ROUTE: hovering the next stage pushed another one on top instead of
  // replacing it, hovering a row with no child left the last one standing,
  // and every route positions itself from scratch so they overlapped rather
  // than sitting flush. 유저 2026-08-27: 「**전혀 갱신안되고있음.** 추가팝오버도
  // 기존 팝오버에 딱 붙어서 열리는게아니라 뭔가 **겹쳐있음**」.
  //
  // One notifier says which row is pointed at and one entry draws beside it,
  // so pointing somewhere else REPLACES the child and pointing at a plain
  // row clears it — which is the behaviour a submenu has everywhere.
  final open = ValueNotifier<_OpenSubmenu?>(null);
  final overlayState = Navigator.of(anchorContext).overlay!;
  PanelFlyoutItem? pickedInSubmenu;
  final submenuEntry = OverlayEntry(
    builder: (context) => ValueListenableBuilder<_OpenSubmenu?>(
      valueListenable: open,
      builder: (context, request, _) => request == null
          ? const SizedBox.shrink()
          : _SubmenuLayer(
              request: request,
              onPicked: (item) {
                pickedInSubmenu = item;
                open.value = null;
                // The parent list goes with it: the level you answered is
                // not a level you want to be left staring at.
                Navigator.of(anchorContext).maybePop();
              },
            ),
    ),
  );

  final menuFuture = showMenu<PanelFlyoutItem>(
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
            // 🚨★★★A ROW WITH A SUBMENU TAKES NO SELECTION — its tap OPENS
            // the child, exactly as hovering does.
            //
            // 유저 2026-08-27 talked themselves through both shapes: first
            // 「레이아웃 › 버튼 클릭하면 레이아웃 아가리로서 작동하도록」, then
            // 「**아니다 그러면 호버없는 터치에서 불가능하니까 하지말자.**
            // 추가팝오버 있는거 클릭하면 **그냥 호버랑 같은기능** 되도록」 —
            // a finger has no hover, so if the tap picked 소재 the child
            // would be unreachable on a tablet. 소재 lives inside the child,
            // where a finger can get to it.
            enabled: entry.enabled && entry.submenuBuilder == null,
            height: flyoutRowHeight,
            // ⛔The row pads itself, from the INSIDE. `PopupMenuItem`'s own
            // padding would sit outside the ink, so a lit row would stop
            // short of the menu's edge — and on a submenu row, where the ink
            // is this widget's rather than Material's, the hit area would
            // stop there too (유저 2026-08-29: 「버튼이 작은거같은데」).
            padding: EdgeInsets.zero,
            // EVERY row reports where the pointer is, including the ones
            // with no child: entering a plain row is what CLOSES an open
            // submenu, which is the half that was missing.
            child: _HoverReporter(
              entry: entry,
              open: open,
              child: flyoutRowSurface(
                _itemBody(entry, hasSubmenu: entry.submenuBuilder != null),
              ),
            ),
          ),
        },
    ],
  );

  // ⚠️INSERTED AFTER THE MENU IS UP, and that ordering is the whole reason
  // this is not one line. An overlay entry goes ABOVE the entries that exist
  // when it is inserted — insert it before `showMenu` and the menu route
  // covers the child. One frame is enough for the route to be there.
  var closed = false;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!closed) {
      overlayState.insert(submenuEntry);
    }
  });
  final selected = await menuFuture;
  closed = true;
  if (submenuEntry.mounted) {
    submenuEntry.remove();
  }
  open.dispose();
  // The child's pick wins: it is the more specific answer, and reaching it
  // popped the parent route with no value of its own.
  (pickedInSubmenu ?? selected)?.onSelected?.call();
}

/// 🚨★★★ONE ROW'S METRICS, AND BOTH LEVELS READ THEM.
///
/// The parent list and the submenu draw the same row, so a height typed
/// into one and not the other is a drift waiting to happen — 32 was written
/// twice already, once as `PopupMenuItem.height` and once as the overlay's
/// own constant.
///
/// ⚠️The padding lives HERE rather than on `PopupMenuItem` because the row's
/// INK has to reach the menu's edge: a row that pads itself from the outside
/// lights only the part inside the padding, which is exactly what 유저
/// 2026-08-29 reported — 「호버색이 다른 용지처럼 전면 흰색되는게 아니라
/// 작게 글자만큼만 흰 배경 생기고 버튼 취급? 인식도 그 안에서만 되」.
const double flyoutRowHeight = 32;
const EdgeInsets flyoutRowPadding = EdgeInsets.symmetric(horizontal: 16);

/// A row laid out so its ink and its hit area are the WHOLE row.
Widget flyoutRowSurface(Widget body) => SizedBox(
  height: flyoutRowHeight,
  child: Padding(padding: flyoutRowPadding, child: body),
);

/// What the pointer is currently on, and where that row is on screen.
class _OpenSubmenu {
  const _OpenSubmenu({
    required this.owner,
    required this.anchor,
    required this.entries,
  });

  /// WHICH row opened it. The parent stays lit while its child is up (유저
  /// 2026-08-29: 「겹으로 들어가면 들어간 위치. 즉 **부모 버튼도 흰색인채로
  /// 유지**하도록」), and hover alone cannot say that — the pointer has left
  /// the parent by then.
  final String owner;

  /// The parent ROW's rect in overlay coordinates. The child is drawn flush
  /// against its right edge — 유저: 「기존 팝오버에 **딱 붙어서** 열리는게
  /// 아니라 뭔가 겹쳐있음」.
  final Rect anchor;

  final List<PanelFlyoutEntry> entries;
}

/// 🚨★★★EVERY ROW REPORTS THE POINTER, INCLUDING THE PLAIN ONES.
///
/// 유저 2026-08-27: 「**호버한것마다 팝오버 갱신**하고 없으면 팝오버 열게
/// 없는곳에 호버하면 **사라지고** 해야하는데 **전혀 갱신안되고있음**」.
///
/// ⛔That is why a plain row sets the notifier to null rather than ignoring
/// the pointer: closing the child is not the child's job, it is the job of
/// whatever you pointed at next. A row that stayed silent left the last
/// submenu standing over a stage nobody was looking at.
class _HoverReporter extends StatelessWidget {
  const _HoverReporter({
    required this.entry,
    required this.open,
    required this.child,
  });

  final PanelFlyoutItem entry;
  final ValueNotifier<_OpenSubmenu?> open;
  final Widget child;

  void _report(BuildContext context) {
    final builder = entry.submenuBuilder;
    if (builder == null) {
      open.value = null;
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) {
      return;
    }
    // 🚨THE MENU'S OUTER EDGE, NOT THIS ROW'S CONTENT EDGE. A row sits
    // inside the menu's horizontal padding, so anchoring to the row put the
    // child a dozen pixels INSIDE the parent — measured, and it is exactly
    // 「기존 팝오버에 딱 붙어서 열리는게아니라 뭔가 겹쳐있음」.
    //
    // The nearest [Material] IS the menu surface, so its right edge is what
    // «beside the parent» means.
    RenderBox? surface;
    context.visitAncestorElements((element) {
      if (element.widget is Material) {
        surface = element.renderObject as RenderBox?;
        return false;
      }
      return true;
    });
    final rowTop = box.localToGlobal(Offset.zero, ancestor: overlay);
    final rowBottom = box.localToGlobal(
      box.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final menu = surface;
    final right = menu == null
        ? rowBottom.dx
        : menu
              .localToGlobal(
                menu.size.bottomRight(Offset.zero),
                ancestor: overlay,
              )
              .dx;
    final left = menu == null
        ? rowTop.dx
        : menu.localToGlobal(Offset.zero, ancestor: overlay).dx;
    open.value = _OpenSubmenu(
      owner: entry.keyValue,
      anchor: Rect.fromLTRB(left, rowTop.dy, right, rowBottom.dy),
      entries: builder(),
    );
  }


  @override
  Widget build(BuildContext context) {
    // A plain row is left alone: Material's own InkWell already lights it,
    // and this only has to report the pointer.
    if (entry.submenuBuilder == null) {
      return MouseRegion(onEnter: (_) => _report(context), child: child);
    }
    // 🚨★★★THE SAME LIT ROW THE OTHERS GET. 유저 2026-08-28: 「콘티나 미술
    // 이런 겹이 있는곳에 호버해도 **동일하게 바탕 흰색으로 하는거** 있잖아.
    // **통일**해서 적용하고」.
    //
    // ⛔A submenu row is `enabled: false` — it must not pop the menu, or a
    // finger tapping a stage would close the list instead of opening the
    // child. Disabling drops Material's InkWell with it, which is why these
    // rows sat dead under the pointer. Putting the InkWell back INSIDE the
    // row restores the highlight without restoring the pop: a disabled
    // PopupMenuItem still hit-tests its child first (the note further up
    // this file says so, for the knob rows).
    //
    // ⚠️[child] is already the WHOLE row ([flyoutRowSurface]) — the ink and
    // the hit area are the row, not the text inside it.
    return MouseRegion(
      onEnter: (_) => _report(context),
      // A finger has no hover, so a tap does the same thing. ⛔Not a second
      // behaviour — the same call, reached the only way a finger can.
      child: ControlPressClaim(onPressed: () => _report(context), child: InkWell(
        onTap: silentPress(() => _report(context)),
        // 🚨And it STAYS lit while its child is up. Hover cannot say this:
        // by the time the submenu is open the pointer has moved off the
        // parent, so Material's highlight has already faded (유저
        // 2026-08-29: 「부모 버튼도 흰색인채로 유지하도록」).
        child: ValueListenableBuilder<_OpenSubmenu?>(
          valueListenable: open,
          builder: (context, request, row) => ColoredBox(
            color: request?.owner == entry.keyValue
                // The same wash Material's own hover lays down, so the two
                // states are one appearance rather than two that resemble
                // each other.
                ? Theme.of(context).hoverColor
                : const Color(0x00000000),
            child: row,
          ),
          child: child,
        ),
      )),
    );
  }
}

/// The child popover — ONE overlay the hover moves, not a route per stage.
class _SubmenuLayer extends StatelessWidget {
  const _SubmenuLayer({required this.request, required this.onPicked});

  final _OpenSubmenu request;
  final ValueChanged<PanelFlyoutItem> onPicked;

  static const double _width = 200;

  @override
  Widget build(BuildContext context) {
    final overlaySize = MediaQuery.sizeOf(context);
    final items = request.entries.whereType<PanelFlyoutItem>().toList();
    final height = items.length * flyoutRowHeight + 16;
    // Flush against the parent's right edge, its first row level with the
    // row that opened it — and folded back to the parent's LEFT when there
    // is no room, which is what every submenu does at a screen edge.
    final left = request.anchor.right + _width <= overlaySize.width
        ? request.anchor.right
        : request.anchor.left - _width;
    final top = (request.anchor.top - 8).clamp(
      0.0,
      (overlaySize.height - height).clamp(0.0, double.infinity),
    );
    return Positioned(
      left: left,
      top: top,
      width: _width,
      child: Material(
        // ⛔THE SHARED popup surface, not a colour of its own. Naming
        // `AppColors.surface` here is exactly what let the child and its
        // parent drift apart — 유저: 「겹이랑 팝오버랑 색이 다르거든?」.
        color: AppPopupSurface.color,
        elevation: AppPopupSurface.elevation,
        shape: AppPopupSurface.shape,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in items)
                ControlPressClaim(onPressed: item.enabled ? () => onPicked(item) : null, child: InkWell(
                  key: ValueKey<String>(item.keyValue),
                  onTap: silentPress(item.enabled ? () => onPicked(item) : null),
                  // ⛔The SAME row surface and the SAME body the parent list
                  // draws — a submenu that laid itself out would drift from
                  // the list it belongs to.
                  child: flyoutRowSurface(_itemBody(item)),
                )),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _itemBody(PanelFlyoutItem entry, {bool hasSubmenu = false}) => Row(
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
    if (entry.checked ?? false) ...[
      const SizedBox(width: 8),
      Icon(Icons.check, size: 14, color: AppColors.accent),
    ],
    // The one glyph a submenu row wears: it says there is another level,
    // which the row cannot say with colour the way «selected» does.
    if (hasSubmenu) ...[
      const SizedBox(width: 4),
      Icon(Icons.chevron_right, size: 14, color: _inkFor(entry)),
    ],
  ],
);

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
      child: ControlPressClaim(onPressed: () => showPanelFlyout(context, entries: entriesBuilder()), child: InkWell(
        // `customBorder` and not `borderRadius`: the splash is a corner like
        // any other and takes the app's superellipse, so this widget adds
        // nothing to the circular-corner debt (`app_shapes_coverage_test`,
        // which only ever ratchets down). [PanelFlyoutButton] beside it still
        // hand-types a `circular(4)` on both its border and its splash.
        customBorder: AppShapes.container(AppShapes.wellRadius),
        onTap: silentPress(() => showPanelFlyout(context, entries: entriesBuilder())),
        child: Padding(padding: padding, child: child),
      )),
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
      child: ControlPressClaim(onPressed: enabled
            ? () => showPanelFlyout(context, entries: entriesBuilder())
            : null, child: InkWell(
        customBorder: AppShapes.container(AppShapes.wellRadius),
        // Null, not a no-op: an `InkWell` with a null callback stops
        // splashing and stops taking hover, so the button reads shut to the
        // hand as well as to the eye.
        onTap: silentPress(enabled
            ? () => showPanelFlyout(context, entries: entriesBuilder())
            : null),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: AppShapes.container(
              AppShapes.wellRadius,
              side: BorderSide(
                color: enabled
                    ? AppColors.hairline
                    : AppColors.hairline.withValues(alpha: 0.5),
              ),
            ),
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
      )),
    );
    if (tooltip == null) {
      return chip;
    }
    return Tooltip(message: tooltip, child: chip);
  }
}
