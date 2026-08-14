import 'package:flutter/material.dart';

import 'brush_tool_state.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/static_raster.dart';

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
    required this.onToolChanged,
    this.groupEntry,
    this.historyControls,
  });

  final CanvasTool tool;
  final ValueChanged<CanvasTool> onToolChanged;

  /// Which TILE a rail button re-enters its group on — asked with the
  /// group's default tile and answered with the one that group was last
  /// left on.
  ///
  /// 유저 2026-08-15: *"필 툴은 아직도 다른 툴 이동하면 모드 선택한게
  /// 초기화됨. 도대체 왜 다른거랑 공통로직안할까?"* — and the answer was
  /// that it had no common logic to share. A group with more than one tile
  /// had only "stay if you are already inside", so leaving the group at all
  /// threw the choice away and a shape fill came back as the bucket. This
  /// is the memory that was missing, and it is one rule for every button
  /// rather than a per-button `if`. CSP and Photoshop both restore the last
  /// sub-tool the same way.
  ///
  /// Null falls back to that old rule, which is what a host with no tool
  /// memory behind it (focused tests) can honestly answer.
  final CanvasTool Function(CanvasTool group)? groupEntry;

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

  /// The tool the button for [group] should switch to.
  CanvasTool _entryFor(CanvasTool group) {
    final resolve = groupEntry;
    if (resolve != null) {
      return resolve(group);
    }
    return canvasToolRailGroup(tool) == group ? tool : group;
  }

  @override
  Widget build(BuildContext context) {
    // Left-aligned like a PS tool column: docked into a wide dock the
    // buttons must hug the panel's left edge, not float centered.
    // R26 #31: the library now shares the left wide dock with the tool
    // settings below it, so its column can be shorter than the buttons —
    // it scrolls instead of overflowing.
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 3, top: 6, bottom: 6),
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
            RailButton(
              keyValue: 'tool-brush-button',
              tooltip: AppText.strings.toolBrushTip,
              icon: Icons.brush_outlined,
              selected: tool == CanvasTool.brush,
              onPressed: () => onToolChanged(CanvasTool.brush),
            ),
            const SizedBox(height: 4),
            RailButton(
              keyValue: 'tool-eraser-button',
              tooltip: AppText.strings.toolEraserTip,
              // No dedicated eraser glyph in this icon set; the "magic
              // eraser" wand reads closest.
              icon: Icons.auto_fix_normal,
              selected: tool == CanvasTool.eraser,
              onPressed: () => onToolChanged(CanvasTool.eraser),
            ),
            const SizedBox(height: 4),
            RailButton(
              keyValue: 'tool-eyedropper-button',
              tooltip: AppText.strings.toolEyedropperTip,
              icon: Icons.colorize_outlined,
              selected: tool == CanvasTool.eyedropper,
              onPressed: () => onToolChanged(CanvasTool.eyedropper),
            ),
            const SizedBox(height: 4),
            // ONE Fill button for both tiles — the bucket and the shapes.
            // It re-enters on the tile the fill was last left on, which is
            // the rule every multi-tile button now shares (see
            // [groupEntry]).
            RailButton(
              keyValue: 'tool-fill-button',
              tooltip: AppText.strings.toolFillTip,
              icon: Icons.format_color_fill_outlined,
              selected: canvasToolFills(tool),
              onPressed: () => onToolChanged(_entryFor(CanvasTool.fill)),
            ),
            const SizedBox(height: 4),
            RailButton(
              keyValue: 'tool-guide-button',
              tooltip: AppText.strings.toolGuide,
              // A drafting square: the tool sets up the guides, and the
              // guides steer the brush.
              icon: Icons.architecture_outlined,
              selected: tool == CanvasTool.guide,
              onPressed: () => onToolChanged(CanvasTool.guide),
            ),
            const SizedBox(height: 4),
            // R17-U: ONE selection tool — the rectangle/lasso variant is a
            // tool SETTING, not a separate toolbar entry (유저 채택 설계).
            //
            // The button no longer has to be told which variant to restore:
            // the shape lives beside the tool now, so "select" already
            // means "select, with the outline I last used".
            RailButton(
              keyValue: 'tool-select-button',
              tooltip: AppText.strings.toolSelectTip,
              icon: Icons.highlight_alt_outlined,
              selected: tool == CanvasTool.select,
              onPressed: () => onToolChanged(CanvasTool.select),
            ),
            const SizedBox(height: 4),
            RailButton(
              keyValue: 'tool-move-button',
              tooltip: AppText.strings.toolMoveTip,
              icon: Icons.open_with,
              selected: tool == CanvasTool.move,
              onPressed: () => onToolChanged(CanvasTool.move),
            ),
            const SizedBox(height: 4),
            // The CUT tool, one button for three tiles — same shape as the
            // Select button above it. It grabs a COPY of the pixels under
            // the drag and stamps them back elsewhere; the source is never
            // removed.
            RailButton(
              keyValue: 'tool-cut-button',
              tooltip: AppText.strings.toolCutTip,
              // Scissors: the user's own word for this tool is 잘라내기, and
              // the glyph should say that even though the source survives.
              icon: Icons.content_cut,
              selected: canvasToolUsesCutPiece(tool),
              // Re-enters on the tile the cut was last left on — the stamp
              // is not knocked back to the grab by going away and coming
              // back, any more than by pressing the button while it is
              // already armed. The grab wears whatever outline it last wore
              // either way, because that memory is the shape's, not this
              // button's.
              onPressed: () => onToolChanged(_entryFor(CanvasTool.cut)),
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
  });

  final String keyValue;
  final String tooltip;
  final IconData icon;
  final bool selected;

  /// Null disables the button — a tool is always available, but undo and
  /// redo are not, and they wear this same square.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      key: ValueKey<String>(keyValue),
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      iconSize: 20,
      isSelected: selected,
      padding: EdgeInsets.zero,
      // R9 #17: a tight box, so the slim rail holds the button instead of
      // the button dictating a 72px rail. Still 42 across — the stylus
      // target the rail was narrowed AROUND, not below.
      constraints: const BoxConstraints.tightFor(
        width: ToolsPanel.buttonExtent,
        height: ToolsPanel.buttonExtent,
      ),
      style: IconButton.styleFrom(
        foregroundColor: selected
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant,
        backgroundColor: selected
            ? colorScheme.surfaceContainerHigh
            : Colors.transparent,
        // 앱에 버튼은 한 종류 (유저 확정): this square is it, so it wears the
        // app's one corner rather than a radius of its own.
        shape: AppShapes.control(ToolsPanel.buttonExtent),
        // The 42px box IS the tap target (R9 #17) — M3's automatic 48px
        // inflation is what made the rail need 72.
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size.square(ToolsPanel.buttonExtent),
        fixedSize: const Size.square(ToolsPanel.buttonExtent),
      ),
    );
  }
}
