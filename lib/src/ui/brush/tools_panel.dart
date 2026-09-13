import '../widgets/app_icon_button.dart';
import 'package:flutter/material.dart';

import 'brush_tool_state.dart';
import 'tool_press.dart';
import '../shortcuts/editor_action_registry.dart';
import '../shortcuts/editor_shortcut_scope.dart';
import '../widgets/static_raster.dart';
import '../layout/device_grid.dart';

/// The Photoshop/Clip-Studio style tool switcher (brush ⇄ eraser): a
/// dockable PANEL whose home is a slim vertical edge dock, so it lives on
/// the left OR right workspace edge (left-handed choice) — or in any wider
/// dock, where its tab shows the panel name. Content only: the hosting
/// dock draws the chrome. Both tools share the brush options (size,
/// hardness, tip) — the eraser only flips the dabs into destination-out.
class ToolsPanel extends StatelessWidget {
  const ToolsPanel({
    super.key,
    required this.tool,
    required this.onPress,
    this.historyControls,
  });

  final CanvasTool tool;

  /// A rail button's press, applied by the host through [pressTool]. Which
  /// tile a group re-enters on is the tool notifier's memory
  /// (`PaintToolStateNotifier.railEntry` — 유저 2026-08-15 「모드 선택한게
  /// 초기화됨」; CSP and Photoshop restore the last sub-tool the same way),
  /// asked at press time, so the button never has to be told.
  final ValueChanged<ToolPress> onPress;

  /// Undo / redo / onion — the things a hand reaches for BETWEEN strokes,
  /// which is what the rail is for. They sit above the tools, separated by a
  /// rule.
  ///
  /// A slot rather than built here so the panel stays session-free: the
  /// host owns the history manager these listen to. Null keeps the rail
  /// tools-only (passive hosts and the panel's own tests).
  final Widget? historyControls;

  /// The edge dock width this panel is designed for.
  ///
  /// R9 #17: 72 → 48, a third of the rail's width back to the canvas. The
  /// tool BUTTONS are what the old number was padding out; the compact
  /// tab strip scrolls, so its close/lock glyphs cost the rail nothing.
  /// 48 was chosen to HOLD a 42px stylus target rather than shrink the
  /// target to fit (the user's rule); the rail-and-strip round then handed
  /// the colour swatch to the top strip, and 42 is still the cell.
  static const double dockWidth = 48;

  /// The rail's button box: a stylus-sized square that fits [dockWidth]
  /// with the panel's own padding.
  static const double buttonExtent = 42;

  /// The rule a strip puts between two clusters of buttons.
  ///
  /// Public because the strip has THREE clusters, not two: history, the
  /// tools, and — below this panel entirely — the buttons that open panel
  /// groups. The seam the workspace draws under the tools has to be the
  /// same line as the one drawn under history, or the strip reads as one
  /// divided list plus something else stuck on the end (유저, R3 #15).
  static Widget groupDivider(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Divider(
      height: 1,
      thickness: 1,
      indent: 2,
      endIndent: 2,
      color: Theme.of(context).colorScheme.outlineVariant,
    ),
  );

  /// A rail button: the entrance of its group's action, pressing what that
  /// action presses.
  ///
  /// 🗣️I-19: 「툴버튼도 … 툴팁으로 숏컷 키 보여주도록」. A button that IS one
  /// action's entrance takes that action's registry name — the shortcut list
  /// and the tooltip say one word — and names the action, so its key comes
  /// from the live bindings.
  Widget _toolButton({
    required String keyValue,
    required CanvasTool group,
    required IconData icon,
    required bool selected,
  }) {
    final press = RailToolPress(group);
    final actionId = toolActionIdFor(press);
    return RailButton(
      keyValue: keyValue,
      tooltip: editorActionLabel(actionId),
      shortcuts: [actionId],
      icon: icon,
      selected: selected,
      onPressed: () => onPress(press),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Left-aligned like a PS tool column: docked into a wide dock the
    // buttons must hug the panel's left edge, not float centered.
    // R26 #31: the library now shares the left wide dock with the tool
    // settings below it, so its column can be shorter than the buttons —
    // it scrolls instead of overflowing.
    return SingleChildScrollView(
      // ⚠️Quantized because this panel scrolls — see the onion-skin
      // panel for why. 3 and 6 are both off the grid at 1.35.
      padding: EdgeInsets.only(
        left: DeviceGrid.of(context).position(3),
        top: DeviceGrid.of(context).position(6),
        bottom: DeviceGrid.of(context).position(6),
      ),
      // Baked inside the scroller, because a viewport is itself a repaint
      // boundary and the edge dock outside it can never reach past one.
      // This column is in the FLOOR — it is on screen with every panel
      // closed, and it was being re-executed on the GPU for a pointer
      // that never came near it.
      child: StaticRaster(
        debugLabel: 'tool-column',
        child: Column(
          key: const ValueKey<String>('tools-panel'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (historyControls != null) ...[
              historyControls!,
              groupDivider(context),
            ],
            _toolButton(
              keyValue: 'tool-brush-button',
              group: CanvasTool.brush,
              icon: Icons.brush_outlined,
              selected: tool == CanvasTool.brush,
            ),
            const SizedBox(height: 4),
            _toolButton(
              keyValue: 'tool-eraser-button',
              group: CanvasTool.eraser,
              // No dedicated eraser glyph in this icon set; the "magic
              // eraser" wand reads closest.
              icon: Icons.auto_fix_normal,
              selected: tool == CanvasTool.eraser,
            ),
            const SizedBox(height: 4),
            _toolButton(
              keyValue: 'tool-eyedropper-button',
              group: CanvasTool.eyedropper,
              icon: Icons.colorize_outlined,
              selected: tool == CanvasTool.eyedropper,
            ),
            const SizedBox(height: 4),
            // ONE Fill button for both tiles — the bucket and the shapes.
            // It re-enters on the tile the fill was last left on, which is
            // the rule every multi-tile button now shares (see [onPress]).
            _toolButton(
              keyValue: 'tool-fill-button',
              group: CanvasTool.fill,
              icon: Icons.format_color_fill_outlined,
              selected: canvasToolFills(tool),
            ),
            const SizedBox(height: 4),
            _toolButton(
              keyValue: 'tool-guide-button',
              group: CanvasTool.guide,
              // A drafting square: the tool sets up the guides, and the
              // guides steer the brush.
              icon: Icons.architecture_outlined,
              selected: tool == CanvasTool.guide,
            ),
            const SizedBox(height: 4),
            // R17-U: ONE selection tool — the rectangle/lasso variant is a
            // tool SETTING, not a separate toolbar entry (유저 채택 설계).
            //
            // The button no longer has to be told which variant to restore:
            // the shape lives beside the tool now, so "select" already
            // means "select, with the outline I last used".
            _toolButton(
              keyValue: 'tool-select-button',
              group: CanvasTool.select,
              icon: Icons.highlight_alt_outlined,
              selected: tool == CanvasTool.select,
            ),
            const SizedBox(height: 4),
            _toolButton(
              keyValue: 'tool-move-button',
              group: CanvasTool.move,
              icon: Icons.open_with,
              selected: tool == CanvasTool.move,
            ),
            const SizedBox(height: 4),
            // The CUT tool, one button for three tiles — same shape as the
            // Select button above it. It grabs a COPY of the pixels under
            // the drag and stamps them back elsewhere; the source is never
            // removed.
            //
            // Pressing it while the stamp is armed leaves the stamp alone;
            // coming back from another tool lands on the GRAB, because the
            // stamp is not one of the tiles the memory keeps (유저 확정 —
            // 찍기는 성질이 다르다). The grab wears whatever outline it last
            // wore either way, because that memory is the shape's, not this
            // button's.
            _toolButton(
              keyValue: 'tool-cut-button',
              group: CanvasTool.cut,
              // Scissors: the user's own word for this tool is 잘라내기, and
              // the glyph should say that even though the source survives.
              icon: Icons.content_cut,
              selected: canvasToolUsesCutPiece(tool),
            ),
            // 유저 확정 (rail-and-strip): 「컬러 스와치는 레일에서 빠진다」 —
            // the top strip's colour button IS the swatch, so keeping one here
            // would be two places to read the same colour. The rail is
            // history + onion + the tools, and that is all.
          ],
        ),
      ),
    );
  }
}

/// One button on the tool rail: a stylus-sized square that says its state
/// with colour, not size.
///
/// Public because the rail is no longer only tools — undo, redo and the
/// onion toggle are handed in by the host and have to be the SAME button,
/// or the column stops reading as one grid.
/// ⛔A strip button has NO grip (유저 정정, R2 #5). It grew one in R1 on the
/// reading that every button on a strip should be liftable; the panel it
/// opens already has a draggable tab, so the second handle was a promise
/// with nothing behind it — it painted, it took the cursor, and dragging it
/// moved nothing. Opening the group and dragging its tab is the one way.
class RailButton extends StatelessWidget {
  const RailButton({
    super.key,
    required this.keyValue,
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
    this.shortcuts = const [],
  });

  final String keyValue;
  final String tooltip;
  final IconData icon;
  final bool selected;

  /// Null disables the button — a tool is always available, but undo and
  /// redo are not, and they wear this same square.
  final VoidCallback? onPressed;

  /// The actions this square presses — [AppIconButton.shortcuts].
  final List<String> shortcuts;

  @override
  Widget build(BuildContext context) {
    // 🚨★★★THE SELECTED CHIP IS GONE, and that is the app's own law arriving
    // here at last. 「선택 표시는 색상만」 — an accent FOREGROUND, never a
    // filled chip and never a check mark ([[ui-selection-style]]). This
    // square wore `surfaceContainerHigh` behind the glyph while the comment
    // right above it said 「앱에 버튼은 한 종류 (유저 확정)」; it was the one
    // kind in shape and a second kind in state. 유저 2026-08-28 chose the
    // tokens over collapsing the sizes, which is what let this join without
    // the 42px stylus target (R9 #17) changing.
    return AppIconButton(
      keyValue: keyValue,
      tooltip: tooltip,
      isSelected: selected,
      size: AppIconButtonSize.tool,
      icon: Icon(icon),
      onPressed: onPressed,
      shortcuts: shortcuts,
    );
  }
}
