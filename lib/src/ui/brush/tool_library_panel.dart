import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import 'brush_tool_state.dart';
import 'transform_tool_options.dart';

/// The TOOL LIBRARY panel (R11-④, CSP's sub-tool palette): its content
/// follows the active tool. The brush and the eraser show the brush
/// preset library (each remembers its own selection —
/// PaintToolStateNotifier), the selection tools list their variants
/// (rectangle / lasso), and the single-action tools show a short usage
/// note. Detailed knobs live in the TOOL SETTINGS panel.
class ToolLibraryPanel extends StatelessWidget {
  const ToolLibraryPanel({
    super.key,
    required this.tool,
    required this.onToolChanged,
    required this.brushLibrary,
    this.guideLibrary,
    this.transformOptions,
    this.onTransformOptionsChanged,
  });

  final CanvasTool tool;
  final ValueChanged<CanvasTool> onToolChanged;

  /// The transform tool's settings; its three MODES are the tiles this
  /// panel lists for [CanvasTool.move]. A null handler shows them
  /// disabled, the convention every other host-owned setting uses here.
  ///
  /// A listenable rather than a value because the host rebuilds this panel
  /// only when the TOOL or its preset changes — picking a mode is neither,
  /// so the tiles subscribe for themselves and nothing else in the library
  /// pays for it.
  final ValueListenable<TransformToolOptions>? transformOptions;
  final ValueChanged<TransformToolOptions>? onTransformOptionsChanged;

  /// The brush preset library content (built by the workspace, which owns
  /// the preset state) — shown for the painting tools.
  final Widget brushLibrary;

  /// The active cut's guide list, built by the workspace (which owns the
  /// cut). Null in hosts with no cut behind them; the tool then explains
  /// itself instead.
  final Widget? guideLibrary;

  @override
  Widget build(BuildContext context) {
    switch (tool) {
      case CanvasTool.brush:
      case CanvasTool.eraser:
        return brushLibrary;
      case CanvasTool.selectRect:
      case CanvasTool.lasso:
        return ListView(
          key: const ValueKey<String>('tool-library-selection'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            _SubToolTile(
              keyValue: 'sub-tool-select-rect',
              icon: Icons.highlight_alt_outlined,
              label: 'Rectangle Select',
              selected: tool == CanvasTool.selectRect,
              onTap: () => onToolChanged(CanvasTool.selectRect),
            ),
            _SubToolTile(
              keyValue: 'sub-tool-lasso',
              icon: Icons.gesture,
              label: 'Lasso Select',
              selected: tool == CanvasTool.lasso,
              onTap: () => onToolChanged(CanvasTool.lasso),
            ),
          ],
        );
      // The CUT tool's three tiles. Same grammar as the selection tool
      // above (one rail button, variants as tiles) — and here it does more
      // than tidy the rail: with grabbing and stamping on separate tiles, a
      // drag means exactly one thing inside each, so the tool needs no
      // modifier key and works on a tablet.
      case CanvasTool.cutRect:
      case CanvasTool.cutLasso:
      case CanvasTool.cutStamp:
        return ListView(
          key: const ValueKey<String>('tool-library-cut'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            _SubToolTile(
              keyValue: 'sub-tool-cut-rect',
              icon: Icons.crop_square,
              label: 'Rectangle Cut',
              selected: tool == CanvasTool.cutRect,
              onTap: () => onToolChanged(CanvasTool.cutRect),
            ),
            _SubToolTile(
              keyValue: 'sub-tool-cut-lasso',
              icon: Icons.gesture,
              label: 'Lasso Cut',
              selected: tool == CanvasTool.cutLasso,
              onTap: () => onToolChanged(CanvasTool.cutLasso),
            ),
            _SubToolTile(
              keyValue: 'sub-tool-cut-stamp',
              icon: Icons.approval_outlined,
              label: 'Stamp',
              selected: tool == CanvasTool.cutStamp,
              onTap: () => onToolChanged(CanvasTool.cutStamp),
            ),
          ],
        );
      // The transform tool's three tiles, in TVPaint's order with 일반 as
      // the default. They are not three tools — the mode is a setting, so
      // that switching one mid-session widens or narrows the OPEN box
      // instead of confirming it and starting again.
      case CanvasTool.move:
        final onOptions = onTransformOptionsChanged;
        return ValueListenableBuilder<TransformToolOptions>(
          valueListenable: transformOptions ?? _fallbackTransformOptions,
          builder: (context, options, _) => ListView(
            key: const ValueKey<String>('tool-library-transform'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              _SubToolTile(
                keyValue: 'sub-tool-transform-normal',
                icon: Icons.crop_free,
                label: AppText.strings.trModeNormal,
                selected: options.mode == TransformMode.normal,
                onTap: onOptions == null
                    ? null
                    : () => onOptions(
                        options.copyWith(mode: TransformMode.normal),
                      ),
              ),
              _SubToolTile(
                keyValue: 'sub-tool-transform-perspective',
                icon: Icons.transform,
                label: AppText.strings.trModePerspective,
                selected: options.mode == TransformMode.perspective,
                onTap: onOptions == null
                    ? null
                    : () => onOptions(
                        options.copyWith(mode: TransformMode.perspective),
                      ),
              ),
              _SubToolTile(
                keyValue: 'sub-tool-transform-mesh',
                icon: Icons.grid_4x4,
                label: AppText.strings.brMeshWarp,
                selected: options.mode == TransformMode.mesh,
                onTap: onOptions == null
                    ? null
                    : () =>
                          onOptions(options.copyWith(mode: TransformMode.mesh)),
              ),
            ],
          ),
        );
      case CanvasTool.eyedropper:
        return const _ToolNote(
          keyValue: 'tool-library-eyedropper',
          note:
              'Eyedropper picks the visible color under the pointer.\n'
              'Hold Alt to pick temporarily while painting.',
        );
      case CanvasTool.fill:
        return const _ToolNote(
          keyValue: 'tool-library-fill',
          note:
              'Fill floods the tapped region with the current color.\n'
              'Tolerance, expand and anti-alias live in Tool Settings.',
        );
      case CanvasTool.guide:
        // The cut's own guides, grouped by kind — the same shape the brush
        // library has (group, then entries), with one difference worth
        // knowing: the brush library is app-wide and permanent, while this
        // list belongs to the CUT and changes when you move to another one.
        return guideLibrary ??
            const _ToolNote(
              keyValue: 'tool-library-guide',
              note:
                  'Guides steer the other tools: symmetry copies a stroke, '
                  'perspective holds it to a vanishing point.\n'
                  'They belong to the cut, and 겸용 cuts share one set.',
            );
    }
  }
}

/// The stand-in for hosts that do not own the transform settings (focused
/// tests). Nothing ever writes it, so one instance for the process is
/// correct and it is never disposed.
final ValueNotifier<TransformToolOptions> _fallbackTransformOptions =
    ValueNotifier(TransformToolOptions.defaults);

class _SubToolTile extends StatelessWidget {
  const _SubToolTile({
    required this.keyValue,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String keyValue;
  final IconData icon;
  final String label;
  final bool selected;

  /// Null disables the tile — the host does not own this setting.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Own Material: the dock body paints a background color, and ListTile
    // ink/selection tints render on the nearest Material ancestor.
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        key: ValueKey<String>(keyValue),
        dense: true,
        leading: Icon(
          icon,
          size: 18,
          color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
        title: Text(label),
        // Selection reads from the color alone (no trailing check glyph —
        // the strip must not jump, per the selection-style rule).
        selected: selected,
        selectedTileColor: colorScheme.surfaceContainerHigh,
        onTap: onTap,
      ),
    );
  }
}

class _ToolNote extends StatelessWidget {
  const _ToolNote({required this.keyValue, required this.note});

  final String keyValue;
  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: ValueKey<String>(keyValue),
      padding: const EdgeInsets.all(12),
      child: Align(
        alignment: Alignment.topLeft,
        child: Text(
          note,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
