import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/canvas_shape_kind.dart';
import '../shortcuts/editor_action_registry.dart';
import '../shortcuts/editor_shortcut_scope.dart';
import 'brush_tool_state.dart';
import 'tool_press.dart';
import 'transform_tool_options.dart';
import '../widgets/content_scrollbar.dart';
import '../widgets/empty_state_text.dart';
import '../text/app_strings.dart';

/// The sub-tool tiles the tool library lists for a rail [group], in order,
/// each with its glyph. Empty for the tools that have none.
///
/// ★THE TILES ARE PRESSES: each is the [SubToolPress] its shortcut action
/// carries, so a tile, its name and its key come from one row (I-19, 유저
/// 2026-09-13: 「툴 내부의 세부툴도 설정가능하게」) — and a tile added here
/// without an action fails `every_tool_and_tile_is_an_action_test`.
List<({SubToolPress press, IconData icon})> subToolTilesOf(CanvasTool group) =>
    switch (group) {
      CanvasTool.select => _shapeTiles(CanvasTool.select),
      // The CUT tool's tiles: every shape, then the stamp. Same grammar as
      // the selection tool above — and the stamp tile does more than tidy
      // the rail: with grabbing and stamping separated, a drag means
      // exactly one thing inside each, so the tool needs no modifier key
      // and works on a tablet. That is why the stamp stays a TOOL while
      // rectangle and lasso became shapes: it is a different verb, not a
      // different outline.
      CanvasTool.cut || CanvasTool.cutStamp => [
        ..._shapeTiles(CanvasTool.cut),
        (
          press: const ToolTilePress(CanvasTool.cutStamp),
          icon: Icons.approval_outlined,
        ),
      ],
      // The FILL tool's tiles: the bucket, then every shape. Same grammar
      // again — and the bucket stays a TOOL for the same reason the stamp
      // does. It is a different verb (flood from a tap, respecting the
      // line art) rather than a different outline, so a tap means exactly
      // one thing inside each tile and no modifier is needed.
      CanvasTool.fill || CanvasTool.fillShape => [
        (
          press: const ToolTilePress(CanvasTool.fill),
          icon: Icons.format_color_fill,
        ),
        ..._shapeTiles(CanvasTool.fillShape),
      ],
      // The transform tool's three tiles, in TVPaint's order with 일반 as
      // the default. They are not three tools — the mode is a setting, so
      // that switching one mid-session widens or narrows the OPEN box
      // instead of confirming it and starting again.
      CanvasTool.move => const [
        (press: TransformModePress(TransformMode.normal), icon: Icons.crop_free),
        (
          press: TransformModePress(TransformMode.perspective),
          icon: Icons.transform,
        ),
        (press: TransformModePress(TransformMode.mesh), icon: Icons.grid_4x4),
      ],
      CanvasTool.brush ||
      CanvasTool.eraser ||
      CanvasTool.eyedropper ||
      CanvasTool.guide => const [],
    };

/// One shape tile per [CanvasShapeKind], in rail order, for [verb].
///
/// ONE list feeds every drag-out verb, so a new [CanvasShapeKind] shows up
/// under select, cut and fill from a single entry here rather than from one
/// hand-written tile per verb.
List<({SubToolPress press, IconData icon})> _shapeTiles(CanvasTool verb) => [
  for (final shape in CanvasShapeKind.values)
    (
      press: ShapeTilePress(verb, shape),
      icon: switch (shape) {
        CanvasShapeKind.rect => Icons.crop_square,
        CanvasShapeKind.ellipse => Icons.circle_outlined,
        CanvasShapeKind.lasso => Icons.gesture,
        CanvasShapeKind.polygon => Icons.polyline_outlined,
      },
    ),
];

/// The TOOL LIBRARY panel (R11-④, CSP's sub-tool palette): its content
/// follows the active tool. The brush and the eraser show the brush
/// preset library (each remembers its own selection —
/// PaintToolStateNotifier), the drag-out tools list the SHAPES they can
/// trace, and the single-action tools show a short usage note. Detailed
/// knobs live in the TOOL SETTINGS panel.
class ToolLibraryPanel extends StatelessWidget {
  const ToolLibraryPanel({
    super.key,
    required this.tool,
    required this.brushLibrary,
    this.onPress,
    this.shapeKind = CanvasShapeKind.rect,
    this.guideLibrary,
    this.transformOptions,
  });

  final CanvasTool tool;

  /// A tile's press, applied by the host through [pressTool] — the press the
  /// tile's shortcut makes too. A shape tile is also how its verb is
  /// entered: tapping "Rectangle Cut" while the stamp is armed means both,
  /// which is why the press carries the verb. Null leaves the tiles inert
  /// (hosts with no tool state behind them).
  final ValueChanged<ToolPress>? onPress;

  /// The shape the ACTIVE verb is set to trace — which tile reads as
  /// selected. Meaningless for tools that trace nothing.
  final CanvasShapeKind shapeKind;

  /// The transform tool's settings; its three MODES are the tiles this
  /// panel lists for [CanvasTool.move].
  ///
  /// A listenable rather than a value because the host rebuilds this panel
  /// only when the TOOL or its preset changes — picking a mode is neither,
  /// so the tiles subscribe for themselves and nothing else in the library
  /// pays for it.
  final ValueListenable<TransformToolOptions>? transformOptions;

  /// The brush preset library content (built by the workspace, which owns
  /// the preset state) — shown for the painting tools.
  final Widget brushLibrary;

  /// The active cut's guide list, built by the workspace (which owns the
  /// cut). Null in hosts with no cut behind them; the tool then explains
  /// itself instead.
  final Widget? guideLibrary;

  /// A tile list with its bar beside it — every list this panel shows is
  /// one (H35: 「툴 라이브러리 패널 … 내용물에 공통적으로 스크롤바 넣자」).
  Widget _tileList(String keyValue, List<Widget> tiles) => ContentScrollbar(
    builder: (context, controller) => ListView(
      key: ValueKey<String>(keyValue),
      controller: controller,
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: tiles,
    ),
  );

  /// [group]'s tiles; [options] says which transform mode is current.
  List<Widget> _tiles(CanvasTool group, {TransformToolOptions? options}) => [
    for (final tile in subToolTilesOf(group))
      _SubToolTile(
        press: tile.press,
        icon: tile.icon,
        selected: switch (tile.press) {
          // A shape tile reads as current only while ITS verb is the
          // active one — with the stamp armed no outline is being traced,
          // so none of the cut shapes is selected.
          ShapeTilePress(:final verb, :final shape) =>
            tool == verb && shapeKind == shape,
          ToolTilePress(tool: final armed) => tool == armed,
          TransformModePress(:final mode) => options?.mode == mode,
        },
        onPress: onPress,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    switch (tool) {
      case CanvasTool.brush:
      case CanvasTool.eraser:
        return brushLibrary;
      case CanvasTool.select:
        return _tileList('tool-library-selection', _tiles(CanvasTool.select));
      case CanvasTool.cut:
      case CanvasTool.cutStamp:
        return _tileList('tool-library-cut', _tiles(CanvasTool.cut));
      case CanvasTool.fill:
      case CanvasTool.fillShape:
        return _tileList('tool-library-fill', _tiles(CanvasTool.fill));
      case CanvasTool.move:
        return ValueListenableBuilder<TransformToolOptions>(
          valueListenable: transformOptions ?? _fallbackTransformOptions,
          builder: (context, options, _) => _tileList(
            'tool-library-transform',
            _tiles(CanvasTool.move, options: options),
          ),
        );
      case CanvasTool.eyedropper:
        return const _ToolNote(keyValue: 'tool-library-eyedropper');
      case CanvasTool.guide:
        // The cut's own guides, grouped by kind — the same shape the brush
        // library has (group, then entries), with one difference worth
        // knowing: the brush library is app-wide and permanent, while this
        // list belongs to the CUT and changes when you move to another one.
        return guideLibrary ??
            const _ToolNote(keyValue: 'tool-library-guide');
    }
  }
}

/// The stand-in for hosts that do not own the transform settings (focused
/// tests). Nothing ever writes it, so one instance for the process is
/// correct and it is never disposed.
final ValueNotifier<TransformToolOptions> _fallbackTransformOptions =
    ValueNotifier(TransformToolOptions.defaults);

/// One sub-tool: its action's entrance. The action's name, its live key at
/// the row's end — the way a menu row prints one (I-19-menu-keys) — and its
/// press.
class _SubToolTile extends StatelessWidget {
  const _SubToolTile({
    required this.press,
    required this.icon,
    required this.selected,
    required this.onPress,
  });

  final SubToolPress press;
  final IconData icon;
  final bool selected;

  /// Null disables the tile (ListTile greys itself out) — the host does
  /// not own this setting, or has no tool state to write it back to.
  final ValueChanged<ToolPress>? onPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final actionId = toolActionIdFor(press);
    final pressed = onPress;
    // Own Material: the dock body paints a background color, and ListTile
    // ink/selection tints render on the nearest Material ancestor.
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        // The action id IS the tile's address: 'sub-tool-select-lasso'.
        key: ValueKey<String>('sub-$actionId'),
        dense: true,
        leading: Icon(
          icon,
          size: 18,
          color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
        title: Text(editorActionLabel(actionId)),
        trailing: ShortcutKeysText(
          actionIds: [actionId],
          enabled: pressed != null,
        ),
        // Selection reads from the color alone (no check glyph — the strip
        // must not jump, per the selection-style rule).
        selected: selected,
        selectedTileColor: colorScheme.surfaceContainerHigh,
        onTap: pressed == null ? null : () => pressed(press),
      ),
    );
  }
}

/// A tool with no library of its own — the eyedropper, and the guide tool
/// when its host hands it none — says so in the one short line.
///
/// ↩️It carried usage sentences (how Alt picks while painting, what a guide
/// steers). 유저 2026-09-15 (empty-state-law-Q1) chose 「공용 위젯 하나 +
/// 짧은 한 줄」, and the sentences went with 「설명 문구 금지」.
class _ToolNote extends StatelessWidget {
  const _ToolNote({required this.keyValue});

  final String keyValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey<String>(keyValue),
      padding: const EdgeInsets.all(12),
      child: EmptyStateText(
        AppText.strings.toolLibraryEmpty,
        place: EmptyStatePlace.list,
      ),
    );
  }
}
