import 'package:flutter/material.dart';

import '../../models/app_language.dart';
import '../../models/brush_tip_entry.dart';
import '../../models/canvas_shape_kind.dart';
import '../../models/drawing_guide.dart';
import '../../services/canvas_color_sampler.dart' show CanvasColorSampleSource;
import '../../services/canvas_flood_fill.dart';
import '../../services/canvas_selection.dart';
import '../../services/canvas_selection_region.dart';
import '../../services/resample/resample_kernel.dart';
import '../widgets/drag_value_label.dart';
import '../widgets/field_slider.dart';
import 'brush_settings_panel.dart';
import 'brush_tool_state.dart';
import 'guide_panels.dart';
import 'canvas_selection_commands.dart';
import 'transform_tool_options.dart';
import '../../models/cut_piece.dart';
import '../../services/cut_piece_slot.dart';
import 'cut_piece_preview.dart';
import '../theme/app_theme.dart';
import '../text/app_strings.dart';

/// The TOOL SETTINGS panel (R11-④, CSP's tool property palette): detailed
/// knobs for the ACTIVE tool. Painting tools show the brush settings, the
/// fill shows its flood options, the selection tool picks its variant
/// (rectangle/lasso — R17-U: one toolbar tool), and Move shows the live
/// transform's numeric inputs.
class ToolSettingsPanel extends StatelessWidget {
  const ToolSettingsPanel({
    super.key,
    required this.state,
    required this.onChanged,
    required this.fillOptions,
    required this.onFillOptionsChanged,
    this.selectionMaskOptions = SelectionMaskOptions.none,
    this.onSelectionMaskOptionsChanged,
    this.transformOptions = TransformToolOptions.defaults,
    this.onTransformOptionsChanged,
    this.selectionCommands,
    this.language = AppLanguage.en,
    this.eyedropperSource = CanvasColorSampleSource.display,
    this.onEyedropperSourceChanged,
    this.tips = const <BrushTipEntry>[],
    this.onTipImportRequested,
    this.onRenameTip,
    this.onDeleteTip,
    this.guides,
    this.selectedGuideId,
    this.onGuidesCommitted,
    this.cutPieceSlot,
    this.onCutPasteAbove,
    this.onCutPasteBelow,
    this.onRegisterCutPieceAsTip,
  });

  /// The active cut's guides, and which one the tool is editing. Null
  /// handler = the panel shows but cannot change them (hosts with no cut).
  final CutGuides? guides;
  final GuideId? selectedGuideId;
  final ValueChanged<CutGuides>? onGuidesCommitted;

  /// The shared tip library, forwarded to the brush settings' tip pickers.
  final List<BrushTipEntry> tips;

  /// Opens the add-a-tip-from-an-image flow.
  final VoidCallback? onTipImportRequested;

  /// Manage a tip from inside the library popup. The pair of them is why
  /// picking no longer dismisses that popup.
  final void Function(BrushTipEntry tip)? onRenameTip;
  final void Function(BrushTipEntry tip)? onDeleteTip;

  /// The program language (BB-2): the brush blend labels localize
  /// (ja = CSP terms); everything else keeps incremental coverage.
  final AppLanguage language;

  final BrushToolState state;
  final ValueChanged<BrushToolState> onChanged;
  final FloodFillOptions fillOptions;
  final ValueChanged<FloodFillOptions> onFillOptionsChanged;

  /// R26 (C2): the Select tool's lift-time mask knobs (grow/shrink,
  /// inward feather, edge AA).
  final SelectionMaskOptions selectionMaskOptions;
  final ValueChanged<SelectionMaskOptions>? onSelectionMaskOptionsChanged;

  /// The transform tool's knobs: mode, scale anchor, AA, mesh grid. A null
  /// handler shows them disabled — the convention the eyedropper's source
  /// picker uses for hosts that do not own the setting.
  final TransformToolOptions transformOptions;
  final ValueChanged<TransformToolOptions>? onTransformOptionsChanged;

  /// The mounted selection layer's imperative channel — the Move tool's
  /// numeric inputs read and write the live transform through it.
  final CanvasSelectionCommands? selectionCommands;

  /// The piece the cut tool is holding — the stamp tile's knobs pose it.
  final CutPieceSlot? cutPieceSlot;

  /// Drop the held piece back at the coordinates it was cut from, over or
  /// behind what is already there. Null = the host cannot paste (no cel).
  final VoidCallback? onCutPasteAbove;
  final VoidCallback? onCutPasteBelow;

  /// Promote the held piece into the brush tip library. Explicit on
  /// purpose: cutting must never grow the library by itself.
  final VoidCallback? onRegisterCutPieceAsTip;

  /// R28 #6: where the eyedropper reads from (PS/CSP's 참조원). Null
  /// handler = the picker shows but cannot be changed (hosts that do not
  /// own the setting).
  final CanvasColorSampleSource eyedropperSource;
  final ValueChanged<CanvasColorSampleSource>? onEyedropperSourceChanged;

  @override
  Widget build(BuildContext context) {
    // Own Material (the tool LIBRARY panel's rule, same reason): the dock
    // body paints a background color, and the Switch/ListTile ink and
    // selection tints render on the nearest Material ancestor — without
    // one Flutter asserts that those effects would be invisible. R26 #31
    // surfaced it by docking this panel open by default, so every tool's
    // settings now build for real instead of only when its tab is picked.
    return Material(
      type: MaterialType.transparency,
      child: switch (state.tool) {
        CanvasTool.brush || CanvasTool.eraser => BrushSettingsPanel(
          state: state,
          onChanged: onChanged,
          tips: tips,
          onTipImportRequested: onTipImportRequested,
          onRenameTip: onRenameTip,
          onDeleteTip: onDeleteTip,
        ),
        CanvasTool.fill => _FillSettings(
          options: fillOptions,
          onChanged: onFillOptionsChanged,
        ),
        // 유저 확정 ⑥: a panel PER TILE, showing what actually applies.
        // The bucket's knobs above are about reading the picture — where
        // the flood may go — and a drawn outline never asks that question,
        // so tolerance, gap close and pasteboard-fill are simply not here.
        // Only the edge is shared, because only the edge is shared.
        CanvasTool.fillShape => _ShapeFillSettings(
          options: fillOptions,
          onChanged: onFillOptionsChanged,
          shapeKind: state.activeShapeKind,
          selectionCommands: selectionCommands,
        ),
        // R28 #6: the eyedropper has a REFERENCE SOURCE setting now.
        CanvasTool.eyedropper => _EyedropperSettings(
          source: eyedropperSource,
          onChanged: onEyedropperSourceChanged,
        ),
        CanvasTool.select => _SelectionSettings(
          state: state,
          onChanged: onChanged,
          maskOptions: selectionMaskOptions,
          onMaskOptionsChanged: onSelectionMaskOptionsChanged,
          selectionCommands: selectionCommands,
          language: language,
        ),
        // The CUT grab: nothing to set whatever shape it is wearing (the
        // grab is hard-edged by law — 2치 보존 — and it makes no selection,
        // so there is no combine mode either) — except the polygon's
        // confirm, which every drag-out verb needs while a trace is open.
        CanvasTool.cut => _CutGrabSettings(
          shapeKind: state.activeShapeKind,
          selectionCommands: selectionCommands,
        ),
        CanvasTool.cutStamp => _CutStampSettings(
          slot: cutPieceSlot,
          onPasteAbove: onCutPasteAbove,
          onPasteBelow: onCutPasteBelow,
          onRegisterAsTip: onRegisterCutPieceAsTip,
        ),
        CanvasTool.move => _MoveSettings(
          selectionCommands: selectionCommands,
          options: transformOptions,
          onOptionsChanged: onTransformOptionsChanged,
        ),
        // Guides get their knobs HERE, like every other tool. There is no
        // guide panel of its own.
        CanvasTool.guide => GuideSettings(
          guides: guides ?? CutGuides.empty,
          selectedGuideId: selectedGuideId,
          onGuidesCommitted: onGuidesCommitted ?? (_) {},
        ),
      },
    );
  }
}

/// The two GRAB tiles have nothing to set.
///
/// Not an oversight: the grab makes no selection, so there is no combine
/// mode to offer, and its mask is hard-edged by law (2치 보존) rather than
/// by a default someone could nudge. The soft-edge knobs that would
/// otherwise belong here already live on the Select tool.
/// The SHAPE FILL tile's knobs.
///
/// Short on purpose. A drawn outline is filled whatever is inside it (유저
/// 확정: 올가미 채우기는 A), so nothing here reads the picture — the
/// bucket's tolerance, gap close and pasteboard boundary have no question
/// to answer. What remains is the edge, which both tiles share because
/// both end in a coverage mask.
class _ShapeFillSettings extends StatelessWidget {
  const _ShapeFillSettings({
    required this.options,
    required this.onChanged,
    required this.shapeKind,
    required this.selectionCommands,
  });

  final FloodFillOptions options;
  final ValueChanged<FloodFillOptions> onChanged;
  final CanvasShapeKind? shapeKind;
  final CanvasSelectionCommands? selectionCommands;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const ValueKey<String>('tool-settings-fill-shape'),
      padding: const EdgeInsets.all(12),
      children: [
        Text('Shape Fill', style: theme.textTheme.titleSmall),
        _ClosePolygonButton(
          shapeKind: shapeKind,
          selectionCommands: selectionCommands,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const ValueKey<String>('fill-shape-anti-alias-switch'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(AppText.strings.brAntiAlias),
          value: options.antiAlias,
          onChanged: (value) => onChanged(options.copyWith(antiAlias: value)),
        ),
      ],
    );
  }
}

class _CutGrabSettings extends StatelessWidget {
  const _CutGrabSettings({
    required this.shapeKind,
    required this.selectionCommands,
  });

  final CanvasShapeKind? shapeKind;
  final CanvasSelectionCommands? selectionCommands;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey<String>('tool-settings-cut-grab'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Text(
              'Cut copies the pixels under the drag — the original stays.\n'
              'Pick Stamp to place the piece you are holding.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          _ClosePolygonButton(
            shapeKind: shapeKind,
            selectionCommands: selectionCommands,
          ),
        ],
      ),
    );
  }
}

/// The polygon's confirm, for hands with no Enter key.
///
/// Shows only while the polygon shape is armed, and only bites once three
/// vertices are down — a button offering to close nothing would be lying
/// about what a tap does. Nothing at all is rendered otherwise, so the
/// panel does not grow a permanent dead row for the other shapes.
class _ClosePolygonButton extends StatelessWidget {
  const _ClosePolygonButton({
    required this.shapeKind,
    required this.selectionCommands,
  });

  final CanvasShapeKind? shapeKind;
  final CanvasSelectionCommands? selectionCommands;

  @override
  Widget build(BuildContext context) {
    final commands = selectionCommands;
    if (shapeKind != CanvasShapeKind.polygon || commands == null) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: commands,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: FilledButton.tonal(
          key: const ValueKey<String>('selection-close-polygon-button'),
          onPressed: commands.canClosePolygon ? commands.closePolygon : null,
          child: Text(AppText.strings.selectionClosePolygon),
        ),
      ),
    );
  }
}

/// The STAMP tile's knobs.
///
/// Deliberately short: spacing, jitter and the rest of the brush
/// parameters are NOT here (유저 확정 — "스페이싱 같은 거 없애고 … 그건 그냥
/// 팁으로 등록해서 뭐 할 때만 띄우는 게 낫겠다"). The law that falls out is
/// **a held piece stays simple, brush parameters belong to a registered
/// tip** — the same split Photoshop draws between a clipboard piece and a
/// Define Brush Preset.
class _CutStampSettings extends StatelessWidget {
  const _CutStampSettings({
    required this.slot,
    required this.onPasteAbove,
    required this.onPasteBelow,
    required this.onRegisterAsTip,
  });

  final CutPieceSlot? slot;
  final VoidCallback? onPasteAbove;
  final VoidCallback? onPasteBelow;
  final VoidCallback? onRegisterAsTip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final holder = slot;
    if (holder == null) {
      return const SizedBox.shrink(
        key: ValueKey<String>('tool-settings-cut-stamp'),
      );
    }
    return ListenableBuilder(
      listenable: holder,
      builder: (context, _) {
        final piece = holder.piece;
        if (piece == null) {
          return Padding(
            key: const ValueKey<String>('tool-settings-cut-stamp'),
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                'Nothing held yet.\n'
                'Cut a piece with the rectangle or lasso tile first.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }
        return ListView(
          key: const ValueKey<String>('tool-settings-cut-stamp'),
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              'Holding ${piece.image.width}×${piece.image.height} px',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            // What you are holding, so finding out does not require
            // stamping it somewhere and undoing.
            SizedBox(
              height: 88,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: CutPiecePreview(piece: piece),
              ),
            ),
            const SizedBox(height: 12),
            Text('Paste at original position', style: theme.textTheme.labelSmall),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey<String>('cut-paste-above-button'),
                    onPressed: onPasteAbove,
                    child: const Text('Above'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey<String>('cut-paste-below-button'),
                    onPressed: onPasteBelow,
                    child: const Text('Below'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Flip is a flag applied at stamp time, never baked into the
            // held bytes: baking would destroy the original, and flipping
            // is a byte re-order that keeps the 1:1 contract intact.
            SwitchListTile(
              key: const ValueKey<String>('cut-flip-horizontal-switch'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Flip horizontal'),
              value: piece.flipHorizontal,
              onChanged: (value) =>
                  holder.updatePose(flipHorizontal: value),
            ),
            SwitchListTile(
              key: const ValueKey<String>('cut-flip-vertical-switch'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Flip vertical'),
              value: piece.flipVertical,
              onChanged: (value) => holder.updatePose(flipVertical: value),
            ),
            const SizedBox(height: 8),
            // Percent, not pixels: with pixels "original" is 300 for one
            // piece and 40 for the next, so the number would have to be
            // remembered. And NOT the top strip's brush size — sharing it
            // would multiply the piece by whatever pen width was last
            // used, the same failure the locked 100% opacity avoids.
            Text(
              'Size ${piece.scalePercent}%',
              style: theme.textTheme.labelSmall,
            ),
            Slider(
              key: const ValueKey<String>('cut-scale-slider'),
              min: CutPiece.minScalePercent.toDouble(),
              max: 400,
              value: piece.scalePercent.clamp(1, 400).toDouble(),
              onChanged: (value) =>
                  holder.updatePose(scalePercent: value.round()),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                // Reset clears size AND both flips, which is why there is
                // no separate "original size" button: those two knobs are
                // everything this panel poses.
                OutlinedButton(
                  key: const ValueKey<String>('cut-reset-button'),
                  onPressed: piece.isPosed ? holder.resetPose : null,
                  child: const Text('Reset'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey<String>('cut-register-tip-button'),
                    onPressed: onRegisterAsTip,
                    child: const Text('Register as Tip…'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// R17-U: the selection VARIANT is a setting of the single Select tool.
/// R26 (C2): plus the lift-time mask knobs — grow/shrink, inward
/// feather, edge AA. Defaults keep the lift byte-preserving.
class _SelectionSettings extends StatelessWidget {
  const _SelectionSettings({
    required this.state,
    required this.onChanged,
    required this.maskOptions,
    required this.onMaskOptionsChanged,
    required this.selectionCommands,
    required this.language,
  });

  final BrushToolState state;
  final ValueChanged<BrushToolState> onChanged;
  final SelectionMaskOptions maskOptions;
  final ValueChanged<SelectionMaskOptions>? onMaskOptionsChanged;
  final CanvasSelectionCommands? selectionCommands;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onMask = onMaskOptionsChanged;
    final commands = selectionCommands;
    return ListView(
      key: const ValueKey<String>('tool-settings-selection'),
      padding: const EdgeInsets.all(12),
      children: [
        // R26 #12: the rectangle/lasso CHOICE lives in the tool library
        // (two tools there), so the settings panel no longer duplicates
        // it — only the mask knobs remain.
        Text(AppText.strings.toolSelect, style: theme.textTheme.titleSmall),
        _ClosePolygonButton(
          shapeKind: state.activeShapeKind,
          selectionCommands: commands,
        ),
        // R26 #16: 갱신 / 추가 / 삭제 / 선택중 — how the next drag folds
        // into the region already selected. Default 추가 (유저 원문).
        if (commands != null) ...[
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: commands,
            builder: (context, _) => _SelectionModeRow(
              mode: commands.combineMode,
              language: language,
              onChanged: (mode) => commands.combineMode = mode,
            ),
          ),
        ],
        if (onMask != null) ...[
          const SizedBox(height: 8),
          FieldSlider(
            key: const ValueKey<String>('selection-grow-slider'),
            min: -20,
            max: 20,
            divisions: 40,
            value: maskOptions.growPx.toDouble().clamp(-20, 20),
            label: AppText.strings.brGrowShrink,
            valueText: maskOptions.growPx == 0
                ? 'off'
                : '${maskOptions.growPx > 0 ? '+' : ''}${maskOptions.growPx} px',
            onChanged: (value) =>
                onMask(maskOptions.copyWith(growPx: value.round())),
          ),
          const SizedBox(height: 8),
          FieldSlider(
            key: const ValueKey<String>('selection-feather-slider'),
            min: 0,
            max: 50,
            divisions: 50,
            value: maskOptions.featherPx.clamp(0, 50),
            label: AppText.strings.brFeather,
            valueText: maskOptions.featherPx <= 0
                ? 'off'
                : '${maskOptions.featherPx.round()} px',
            onChanged: (value) =>
                onMask(maskOptions.copyWith(featherPx: value.roundToDouble())),
          ),
          SwitchListTile(
            key: const ValueKey<String>('selection-anti-alias-switch'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(AppText.strings.brAntiAliasEdge),
            value: maskOptions.antiAlias,
            onChanged: (value) =>
                onMask(maskOptions.copyWith(antiAlias: value)),
          ),
        ],
      ],
    );
  }
}

/// R26 #16: the four selection modes as one segmented row — the same
/// "selection shows in COLOR only" rule the rest of the app follows
/// ([[ui-selection-style]]: no check marks).
class _SelectionModeRow extends StatelessWidget {
  const _SelectionModeRow({
    required this.mode,
    required this.language,
    required this.onChanged,
  });

  final SelectionCombineMode mode;
  final AppLanguage language;
  final ValueChanged<SelectionCombineMode> onChanged;

  static const Map<SelectionCombineMode, IconData> _icons = {
    SelectionCombineMode.replace: Icons.crop_square,
    SelectionCombineMode.add: Icons.add_box_outlined,
    SelectionCombineMode.subtract: Icons.indeterminate_check_box_outlined,
    SelectionCombineMode.intersect: Icons.join_inner,
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      key: const ValueKey<String>('selection-mode-row'),
      children: [
        for (final candidate in SelectionCombineMode.values)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              key: ValueKey<String>('selection-mode-${candidate.name}'),
              tooltip: candidate.labelFor(language),
              onPressed: () => onChanged(candidate),
              icon: Icon(_icons[candidate]),
              iconSize: 20,
              isSelected: candidate == mode,
              style: IconButton.styleFrom(
                foregroundColor: candidate == mode
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                backgroundColor: candidate == mode
                    ? colorScheme.surfaceContainerHigh
                    : Colors.transparent,
                shape: AppShapes.control(AppShapes.controlSmall),
              ),
            ),
          ),
      ],
    );
  }
}

/// The Move/Transform tool's numeric inputs (R17-U 유저 채택 설계:
/// 좌표/각도 수치 입력): X/Y offset, angle and scale of the LIVE
/// transform box, applied on submit through the selection channel. The
/// channel notifies on session changes so the fields track handle drags.
class _MoveSettings extends StatefulWidget {
  const _MoveSettings({
    required this.selectionCommands,
    required this.options,
    required this.onOptionsChanged,
  });

  final CanvasSelectionCommands? selectionCommands;

  /// The transform tool's knobs. A null handler shows them disabled — the
  /// convention the eyedropper's source picker uses for hosts that do not
  /// own the setting.
  final TransformToolOptions options;
  final ValueChanged<TransformToolOptions>? onOptionsChanged;

  @override
  State<_MoveSettings> createState() => _MoveSettingsState();
}

class _MoveSettingsState extends State<_MoveSettings> {
  // The live channel values, synced from the session at rest and owned
  // locally during a label drag (R26 #14: the deferred session ping must
  // not eat drag steps).
  double _tx = 0;
  double _ty = 0;
  double _angleDeg = 0;
  double _scalePct = 100;

  @override
  void initState() {
    super.initState();
    widget.selectionCommands?.addListener(_syncFromSession);
    _syncFromSession();
  }

  @override
  void didUpdateWidget(covariant _MoveSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.selectionCommands, widget.selectionCommands)) {
      oldWidget.selectionCommands?.removeListener(_syncFromSession);
      widget.selectionCommands?.addListener(_syncFromSession);
      _syncFromSession();
    }
  }

  @override
  void dispose() {
    widget.selectionCommands?.removeListener(_syncFromSession);
    super.dispose();
  }

  String _trim(double value) {
    final rounded = double.parse(value.toStringAsFixed(2));
    return rounded == rounded.roundToDouble()
        ? rounded.round().toString()
        : rounded.toString();
  }

  void _syncFromSession() {
    if (!mounted) {
      return;
    }
    final values = widget.selectionCommands?.transformValues;
    setState(() {
      _tx = values?.tx ?? 0;
      _ty = values?.ty ?? 0;
      _angleDeg = values?.rotationDegrees ?? 0;
      _scalePct = (values?.scale ?? 1) * 100;
    });
  }

  /// Writes the four channels through the selection channel — with no
  /// session open this OPENS one (Ctrl+T semantics; R26 #13: with no
  /// selection the box opens on the whole picture).
  void _apply() {
    widget.selectionCommands?.setTransformValues(
      tx: _tx,
      ty: _ty,
      rotationDegrees: _angleDeg,
      scale: _scalePct.clamp(1.0, 3200.0) / 100,
    );
  }

  /// One transform channel as the shared DRAG VALUE READOUT (R26 #14 —
  /// the canvas bar's zoom/angle vocabulary: drag = a unit per pixel,
  /// double-tap = type).
  Widget _channel({
    required String keyValue,
    required String label,
    required String text,
    required void Function(double units) onDrag,
    required void Function(double parsed) onSubmit,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        // 유저 08-13: 수치값은 오른쪽 정렬. Scoped to this panel — the
        // readout is shared with the canvas bar, the conte page field and
        // the timesheet, and those are a UI-session decision, not this
        // round's.
        DragValueLabel(
          keyValue: keyValue,
          text: text,
          tooltip: AppText.strings.viewDragDoubleTap,
          width: 72,
          textAlign: TextAlign.right,
          textStyle: const TextStyle(fontSize: 12),
          onDragDelta: onDrag,
          onEditSubmit: (raw) {
            final parsed = double.tryParse(
              raw.replaceAll('%', '').replaceAll('°', '').trim(),
            );
            if (parsed != null) {
              onSubmit(parsed);
            }
          },
        ),
      ],
    );
  }

  /// The mesh grid's cell count on one axis.
  Widget _gridChannel({
    required String keyValue,
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    final handler = widget.onOptionsChanged;
    return _channel(
      keyValue: keyValue,
      label: label,
      text: '$value',
      onDrag: handler == null
          ? (_) {}
          : (units) => onChanged(
              TransformToolOptions.clampMeshCells(value + units.round()),
            ),
      onSubmit: handler == null
          ? (_) {}
          : (parsed) =>
                onChanged(TransformToolOptions.clampMeshCells(parsed.round())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The one gate for the whole panel. Choosing the tool is always
    // allowed now; it is the EDIT that is refused, and it is refused
    // quietly — flat controls rather than a notice per press (유저 08-13).
    final canEdit = widget.selectionCommands?.canEditTransform ?? false;
    final options = widget.options;
    final onOptions = canEdit ? widget.onOptionsChanged : null;
    return ListView(
      key: const ValueKey<String>('tool-settings-move'),
      padding: const EdgeInsets.all(12),
      children: [
        Text(AppText.strings.toolMove, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _channel(
          keyValue: 'move-x-field',
          label: 'X',
          text: _trim(_tx),
          onDrag: (units) {
            setState(() => _tx += units);
            _apply();
          },
          onSubmit: (value) {
            setState(() => _tx = value);
            _apply();
          },
        ),
        const SizedBox(height: 4),
        _channel(
          keyValue: 'move-y-field',
          label: 'Y',
          text: _trim(_ty),
          onDrag: (units) {
            setState(() => _ty += units);
            _apply();
          },
          onSubmit: (value) {
            setState(() => _ty = value);
            _apply();
          },
        ),
        const SizedBox(height: 4),
        _channel(
          keyValue: 'move-angle-field',
          label: AppText.strings.brAngle,
          text: '${_trim(_angleDeg)}°',
          onDrag: (units) {
            setState(() => _angleDeg += units);
            _apply();
          },
          onSubmit: (value) {
            setState(() => _angleDeg = value);
            _apply();
          },
        ),
        const SizedBox(height: 4),
        _channel(
          keyValue: 'move-scale-field',
          label: AppText.strings.brScale,
          text: '${_trim(_scalePct)}%',
          onDrag: (units) {
            setState(() => _scalePct = (_scalePct + units).clamp(1.0, 3200.0));
            _apply();
          },
          onSubmit: (value) {
            setState(() => _scalePct = value.clamp(1.0, 3200.0));
            _apply();
          },
        ),
        // The mesh's density, shown as numbers because that is what it is
        // (유저 08-13: "수치도 조절가능하게 값으로 드러내고"). Only in 메쉬
        // — a grid size means nothing to the other two modes.
        if (options.mode == TransformMode.mesh) ...[
          const SizedBox(height: 4),
          _gridChannel(
            keyValue: 'move-mesh-columns-field',
            label: AppText.strings.trMeshColumns,
            value: options.meshColumns,
            onChanged: (cells) => widget.onOptionsChanged?.call(
              options.copyWith(meshColumns: cells),
            ),
          ),
          const SizedBox(height: 4),
          _gridChannel(
            keyValue: 'move-mesh-rows-field',
            label: AppText.strings.trMeshRows,
            value: options.meshRows,
            onChanged: (cells) => widget.onOptionsChanged?.call(
              options.copyWith(meshRows: cells),
            ),
          ),
        ],
        const SizedBox(height: 12),
        // 유저 08-13, in this order: 좌우반전 · 상하반전 · 리셋 · 적용.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              key: const ValueKey<String>('move-flip-horizontal-button'),
              onPressed: canEdit
                  ? () => widget.selectionCommands?.flipTransform(
                      horizontal: true,
                    )
                  : null,
              child: Text(AppText.strings.trFlipHorizontal),
            ),
            OutlinedButton(
              key: const ValueKey<String>('move-flip-vertical-button'),
              onPressed: canEdit
                  ? () => widget.selectionCommands?.flipTransform(
                      horizontal: false,
                    )
                  : null,
              child: Text(AppText.strings.trFlipVertical),
            ),
            OutlinedButton(
              key: const ValueKey<String>('move-reset-button'),
              onPressed: canEdit
                  ? () => widget.selectionCommands?.resetTransform()
                  : null,
              child: Text(AppText.strings.commonReset),
            ),
            FilledButton(
              key: const ValueKey<String>('move-apply-button'),
              onPressed: canEdit
                  ? () => widget.selectionCommands?.applyTransform()
                  : null,
              child: Text(AppText.strings.commonApply),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // The scale anchor, as a persistent choice rather than a held key
        // — a hold cannot be reached on a tablet while the pen is on the
        // handle. Alt still inverts it for one drag.
        Text(
          AppText.strings.trAnchor,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        SegmentedButton<TransformAnchor>(
          key: const ValueKey<String>('move-anchor-segments'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment<TransformAnchor>(
              value: TransformAnchor.oppositeCorner,
              label: Text(AppText.strings.trAnchorOpposite),
            ),
            ButtonSegment<TransformAnchor>(
              value: TransformAnchor.center,
              label: Text(AppText.strings.trAnchorCenter),
            ),
          ],
          selected: {options.anchor},
          onSelectionChanged: onOptions == null
              ? null
              : (selection) =>
                    onOptions(options.copyWith(anchor: selection.first)),
        ),
        const SizedBox(height: 12),
        // AA, and nothing else.
        //
        // It was "Preserve original colours" over a paragraph about
        // in-between shades, which is the same switch described from the
        // far side: the argmax preserves the source words BECAUSE it
        // refuses to blend, and the blend anti-aliases BECAUSE it does.
        // 유저 08-13 asked for the two letters and the polarity that goes
        // with them — AA on is the smoothing default, AA off is the
        // two-value copy.
        SwitchListTile(
          key: const ValueKey<String>('move-antialias-switch'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('AA'),
          value: options.resampleMode == ResampleMode.blend,
          onChanged: onOptions == null
              ? null
              : (value) => onOptions(
                  options.copyWith(
                    resampleMode: value
                        ? ResampleMode.blend
                        : ResampleMode.pick,
                  ),
                ),
        ),
      ],
    );
  }
}

/// R28 #6: the eyedropper's REFERENCE SOURCE — Photoshop's "current
/// layer / all layers", Clip Studio's 참조원. The tool itself works in
/// every section and on every layer kind; this only decides which pixels
/// it reads. A row with nothing drawable (an SE row) simply reads the
/// canvas color, which is what the user described.
class _EyedropperSettings extends StatelessWidget {
  const _EyedropperSettings({required this.source, required this.onChanged});

  final CanvasColorSampleSource source;
  final ValueChanged<CanvasColorSampleSource>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final handler = onChanged;
    return ListView(
      key: const ValueKey<String>('tool-settings-eyedropper'),
      padding: const EdgeInsets.all(12),
      children: [
        Text(AppText.strings.toolEyedropper, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(
          'Reference',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        // Selection shows through COLOR only — no check glyphs (the
        // program's selection style).
        SegmentedButton<CanvasColorSampleSource>(
          key: const ValueKey<String>('eyedropper-source-segments'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment<CanvasColorSampleSource>(
              value: CanvasColorSampleSource.display,
              label: Text(AppText.strings.brDisplay),
            ),
            ButtonSegment<CanvasColorSampleSource>(
              value: CanvasColorSampleSource.layer,
              label: Text(AppText.strings.tlLayer),
            ),
          ],
          selected: {source},
          onSelectionChanged: handler == null
              ? null
              : (selection) => handler(selection.first),
        ),
        const SizedBox(height: 8),
        Text(
          source == CanvasColorSampleSource.display
              ? 'Picks the color you SEE — every visible layer, blended.'
              : 'Picks the ACTIVE layer\'s own pixels; empty areas read the '
                    'canvas color.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _FillSettings extends StatelessWidget {
  const _FillSettings({required this.options, required this.onChanged});

  final FloodFillOptions options;
  final ValueChanged<FloodFillOptions> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const ValueKey<String>('tool-settings-fill'),
      padding: const EdgeInsets.all(12),
      children: [
        Text('Fill', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        FieldSlider(
          key: const ValueKey<String>('fill-tolerance-slider'),
          min: 0,
          max: 128,
          divisions: 128,
          value: options.tolerance.toDouble().clamp(0, 128),
          label: AppText.strings.brTolerance,
          valueText: '${options.tolerance}',
          onChanged: (value) =>
              onChanged(options.copyWith(tolerance: value.round())),
        ),
        const SizedBox(height: 8),
        FieldSlider(
          key: const ValueKey<String>('fill-expand-slider'),
          min: 0,
          max: 4,
          divisions: 4,
          value: options.expandPx.toDouble().clamp(0, 4),
          label: AppText.strings.brExpand,
          valueText: '${options.expandPx} px',
          onChanged: (value) =>
              onChanged(options.copyWith(expandPx: value.round())),
        ),
        const SizedBox(height: 8),
        FieldSlider(
          key: const ValueKey<String>('fill-gap-close-slider'),
          min: 0,
          max: 8,
          divisions: 8,
          value: options.gapClosePx.toDouble().clamp(0, 8),
          label: AppText.strings.brGapClose,
          valueText: options.gapClosePx == 0
              ? 'off'
              : '${options.gapClosePx} px',
          onChanged: (value) =>
              onChanged(options.copyWith(gapClosePx: value.round())),
        ),
        SwitchListTile(
          key: const ValueKey<String>('fill-anti-alias-switch'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(AppText.strings.brAntiAlias),
          value: options.antiAlias,
          onChanged: (value) => onChanged(options.copyWith(antiAlias: value)),
        ),
        SwitchListTile(
          key: const ValueKey<String>('fill-extend-beyond-canvas-switch'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(AppText.strings.brFillBeyondCanvas),
          subtitle: Text(AppText.strings.brOpenRegionsRefuse),
          value: options.extendBeyondCanvas,
          onChanged: (value) =>
              onChanged(options.copyWith(extendBeyondCanvas: value)),
        ),
      ],
    );
  }
}
