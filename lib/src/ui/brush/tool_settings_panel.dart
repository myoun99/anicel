import 'package:flutter/material.dart';

import '../../models/app_language.dart';
import '../../models/brush_tip_entry.dart';
import '../../services/canvas_color_sampler.dart' show CanvasColorSampleSource;
import '../../services/canvas_flood_fill.dart';
import '../../services/canvas_selection.dart';
import '../../services/canvas_selection_region.dart';
import '../../services/resample/resample_kernel.dart';
import '../widgets/drag_value_label.dart';
import '../widgets/field_slider.dart';
import 'brush_settings_panel.dart';
import 'brush_tool_state.dart';
import 'canvas_selection_commands.dart';
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
    this.transformResampleMode = ResampleMode.blend,
    this.onTransformResampleModeChanged,
    this.selectionCommands,
    this.language = AppLanguage.en,
    this.eyedropperSource = CanvasColorSampleSource.display,
    this.onEyedropperSourceChanged,
    this.tips = const <BrushTipEntry>[],
    this.onTipImportRequested,
  });

  /// The shared tip library, forwarded to the brush settings' tip pickers.
  final List<BrushTipEntry> tips;

  /// Opens the add-a-tip-from-an-image flow.
  final VoidCallback? onTipImportRequested;

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

  /// P3a: the Move tool's resampler choice — the tent that smooths, or the
  /// coverage argmax that keeps a two-value drawing two-valued.
  final ResampleMode transformResampleMode;
  final ValueChanged<ResampleMode>? onTransformResampleModeChanged;

  /// The mounted selection layer's imperative channel — the Move tool's
  /// numeric inputs read and write the live transform through it.
  final CanvasSelectionCommands? selectionCommands;

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
          language: language,
          tips: tips,
          onTipImportRequested: onTipImportRequested,
        ),
        CanvasTool.fill => _FillSettings(
          options: fillOptions,
          onChanged: onFillOptionsChanged,
        ),
        // R28 #6: the eyedropper has a REFERENCE SOURCE setting now.
        CanvasTool.eyedropper => _EyedropperSettings(
          source: eyedropperSource,
          onChanged: onEyedropperSourceChanged,
        ),
        CanvasTool.selectRect || CanvasTool.lasso => _SelectionSettings(
          state: state,
          onChanged: onChanged,
          maskOptions: selectionMaskOptions,
          onMaskOptionsChanged: onSelectionMaskOptionsChanged,
          selectionCommands: selectionCommands,
          language: language,
        ),
        CanvasTool.move => _MoveSettings(
          selectionCommands: selectionCommands,
          resampleMode: transformResampleMode,
          onResampleModeChanged: onTransformResampleModeChanged,
        ),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
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
    required this.resampleMode,
    required this.onResampleModeChanged,
  });

  final CanvasSelectionCommands? selectionCommands;

  /// P3a: which resampler a transform commit runs through. A null handler
  /// shows the switch disabled — the same convention the eyedropper's
  /// source picker uses for hosts that do not own the setting.
  final ResampleMode resampleMode;
  final ValueChanged<ResampleMode>? onResampleModeChanged;

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
        DragValueLabel(
          keyValue: keyValue,
          text: text,
          tooltip: AppText.strings.viewDragDoubleTap,
          width: 72,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSelection = widget.selectionCommands?.hasSelection ?? false;
    return ListView(
      key: const ValueKey<String>('tool-settings-move'),
      padding: const EdgeInsets.all(12),
      children: [
        Text(AppText.strings.toolMove, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          hasSelection
              ? 'Values apply to the selection\'s transform box '
                    '(Enter confirms, Esc reverts).'
              : 'No selection: the box opens on the WHOLE picture '
                    '(Enter confirms, Esc reverts).',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
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
        const SizedBox(height: 12),
        // ⚠️ The "Preserve exact colours" switch belongs here and is
        // deliberately NOT built yet.
        //
        // Everything behind it works — the mode threads from this panel to
        // all three warp paths and the preview, and its contracts are
        // tested. What is not ready is the KERNEL's coverage argmax, which
        // erases the artwork the mode exists for. Measured on 1px line art
        // through the shipping kernel: a 50% reduction keeps 3 ink pixels
        // of 381, and an isolated 1px diagonal rotated 37° or 45° comes
        // back with none at all.
        //
        // The cause is that Pick's contract is stated in terms of COVERED
        // AREA but the accumulator weighs taps with a TENT — a
        // reconstruction filter, not a coverage measure. At 45° that puts
        // ink at 1.172 against ground's 1.343 around every ink pixel, so
        // every one of them loses. Replacing the tent with the actual
        // overlap length of a source pixel and the destination pixel's
        // preimage takes that 50% reduction from 3 ink pixels to 127 and
        // the 37° rotation from 0 to 26, and is better or equal on 16 of
        // 18 measured fixture rows. Exactly 45° stays at 0 under both,
        // because there the feature covers exactly half of every
        // destination pixel and no argmax can break that tie.
        //
        // That is a change to the shared kernel and its C mirror, with its
        // own parity pass and its own tuning question (what replaces the
        // radius floor once the weight means coverage), so it is its own
        // round rather than a rider on this one. Shipping the switch first
        // would hand the user a control that does the opposite of its
        // label on exactly the artwork it advertises.
        // R20-D3 mesh warp: opens the control grid on the selection —
        // or, with none, on the whole picture (R26 #13). Enter commits
        // the triangulated warp; Esc reverts. Perspective rides the
        // Ctrl+corner gesture on the box itself (R20-D2).
        OutlinedButton.icon(
          key: const ValueKey<String>('move-mesh-warp-button'),
          onPressed: () => widget.selectionCommands?.beginMeshTransform(),
          icon: const Icon(Icons.grid_4x4, size: 16),
          label: Text(AppText.strings.brMeshWarp),
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
