import 'package:flutter/material.dart';

import '../../models/brush_pressure_curve.dart';
import '../../models/brush_shape.dart' show BrushMaskSlot;
import '../../models/brush_tip_entry.dart';
import '../../models/brush_tip_rotation_mode.dart';
import '../panels/editor_panel_frame.dart';
import '../widgets/field_slider.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/pressure_curve_popup.dart';
import 'brush_tip_picker.dart';
import 'brush_tool_state.dart';
import '../text/app_strings.dart';

/// Editable brush tool properties — the CSP-style GROUPED layout (BB-2,
/// user-picked candidate B, 07-22): 브러시 크기 / 잉크 / 브러시 끝 /
/// 보정, with the BRUSH BLEND dropdown living in the ink group exactly
/// where Clip Studio keeps its 합성 모드. The color swatches and the tip
/// shape segment are GONE (R26 #11): color belongs to the color wheel
/// panel, the tip belongs to brush presets.
///
/// The brush library lives in the separate [BrushPresetPanel]; this panel
/// only mutates the live [BrushToolState].
class BrushSettingsPanel extends StatelessWidget {
  const BrushSettingsPanel({
    super.key,
    required this.state,
    required this.onChanged,
    this.tips = const <BrushTipEntry>[],
    this.onTipImportRequested,
    this.onRenameTip,
    this.onDeleteTip,
  });

  final BrushToolState state;
  final ValueChanged<BrushToolState> onChanged;

  /// The shared tip library, for the tip / dual / texture pickers. Empty
  /// keeps the pickers hidden, which is what a bare panel test wants.
  final List<BrushTipEntry> tips;

  /// Opens the add-a-tip-from-an-image flow.
  final VoidCallback? onTipImportRequested;

  /// Manage the tip picked inside the library popup. Null leaves the
  /// buttons out — the same shape [onTipImportRequested] already has.
  final void Function(BrushTipEntry tip)? onRenameTip;
  final void Function(BrushTipEntry tip)? onDeleteTip;

  // The `language` parameter left with the blend row: it existed only for
  // the blend labels (ja = CSP terms), and the rest of the panel reads its
  // wording from `AppText.strings`.

  /// The CSP-style per-setting pressure button (BB-3): sits at the right
  /// of each pressure-capable slider row and opens the shared curve popup.
  Widget _pressureButton(BrushPressureTarget target, String title) {
    return PressureCurveButton(
      keyValue: 'brush-tool-pressure-${target.name}',
      title: title,
      curve: state.pressureCurveFor(target),
      onChanged: (curve) => onChanged(state.withPressureCurve(target, curve)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final spacingLabel = '${(state.spacing * 100).round()}%';
    final hardnessLabel = '${(state.hardness * 100).round()}%';
    final flowLabel = '${(state.flow * 100).round()}%';
    final roundnessLabel = '${(state.roundness * 100).round()}%';
    final angleLabel = '${state.angleDegrees.round()}°';
    return EditorPanelFrame(
      title: 'Brush Settings',
      child: Column(
        key: const ValueKey<String>('brush-settings-panel'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 유저 확정 (rail-and-strip): SIZE, OPACITY and BLEND — each with
          // its pressure curve or lock — left this panel for the TOP STRIP.
          // They are the settings a hand changes mid-stroke, against a test
          // mark on the canvas, and this panel scrolls; the strip is always
          // where it was. Keeping a second copy here would be two places
          // showing one number.
          _GroupHeader('Ink', first: true),
          _PanelSlider(
            label: AppText.strings.brFlow,
            valueLabel: flowLabel,
            value: BrushToolState.clampUnit(state.flow),
            min: 0,
            max: 1,
            keyValue: 'brush-tool-flow-slider',
            onChanged: (value) => onChanged(state.copyWith(flow: value)),
            trailing: _pressureButton(
              BrushPressureTarget.flow,
              AppText.strings.brFlow,
            ),
          ),
          _GroupHeader('Brush tip'),
          if (tips.isNotEmpty)
            BrushTipPickerRow(
              label: AppText.strings.brBrushTip,
              role: BrushTipRole.tip,
              selected: state.tipMask,
              tips: tips,
              onImportRequested: onTipImportRequested,
              onRenameTip: onRenameTip,
              onDeleteTip: onDeleteTip,
              // The sampled tip REPLACES hardness and tip shape, so clearing
              // it is how a brush gets its parametric footprint back — which
              // is why this goes through withTipMask rather than copyWith.
              onPicked: (mask) =>
                  onChanged(state.withMask(BrushMaskSlot.tip, mask)),
            ),
          _PanelSlider(
            label: AppText.strings.brHardness,
            valueLabel: hardnessLabel,
            value: BrushToolState.clampUnit(state.hardness),
            min: 0,
            max: 1,
            keyValue: 'brush-tool-hardness-slider',
            onChanged: (value) => onChanged(state.copyWith(hardness: value)),
            trailing: _pressureButton(
              BrushPressureTarget.hardness,
              AppText.strings.brHardness,
            ),
          ),
          _PanelSlider(
            label: AppText.strings.brRoundness,
            valueLabel: roundnessLabel,
            value: BrushToolState.clampRoundness(state.roundness),
            min: BrushToolState.minRoundness,
            max: 1,
            keyValue: 'brush-tool-roundness-slider',
            onChanged: (value) => onChanged(state.copyWith(roundness: value)),
          ),
          _PanelSlider(
            label: AppText.strings.brAngle,
            valueLabel: angleLabel,
            value: BrushToolState.clampAngleDegrees(state.angleDegrees),
            min: BrushToolState.minAngleDegrees,
            max: BrushToolState.maxAngleDegrees,
            keyValue: 'brush-tool-angle-slider',
            onChanged: (value) =>
                onChanged(state.copyWith(angleDegrees: value)),
          ),
          _PanelSlider(
            label: AppText.strings.brSpacing,
            valueLabel: spacingLabel,
            value: BrushToolState.clampSpacing(state.spacing),
            min: BrushToolState.minSpacing,
            max: BrushToolState.maxSpacing,
            scale: FieldSliderScale.exponential,
            keyValue: 'brush-tool-spacing-slider',
            onChanged: (value) => onChanged(state.copyWith(spacing: value)),
          ),
          _RotationModeRow(state: state, onChanged: onChanged),
          // P20 shipped placement dynamics into the engine and left them
          // unreachable: only a preset or an import could set them. These
          // are those knobs.
          _GroupHeader('Randomness'),
          _PanelSlider(
            label: AppText.strings.brSizeJitter,
            valueLabel: '${(state.sizeJitter * 100).round()}%',
            value: BrushToolState.clampZeroToOne(state.sizeJitter),
            min: 0,
            max: 1,
            keyValue: 'brush-tool-size-jitter-slider',
            onChanged: (value) => onChanged(state.copyWith(sizeJitter: value)),
          ),
          _PanelSlider(
            label: AppText.strings.brOpacityJitter,
            valueLabel: '${(state.opacityJitter * 100).round()}%',
            value: BrushToolState.clampZeroToOne(state.opacityJitter),
            min: 0,
            max: 1,
            keyValue: 'brush-tool-opacity-jitter-slider',
            onChanged: (value) =>
                onChanged(state.copyWith(opacityJitter: value)),
          ),
          _PanelSlider(
            label: AppText.strings.brAngleJitter,
            valueLabel: '${(state.angleJitter * 100).round()}%',
            value: BrushToolState.clampZeroToOne(state.angleJitter),
            min: 0,
            max: 1,
            keyValue: 'brush-tool-angle-jitter-slider',
            onChanged: (value) => onChanged(state.copyWith(angleJitter: value)),
          ),
          _PanelSlider(
            label: AppText.strings.brRoundnessJitter,
            valueLabel: '${(state.roundnessJitter * 100).round()}%',
            value: BrushToolState.clampZeroToOne(state.roundnessJitter),
            min: 0,
            max: 1,
            keyValue: 'brush-tool-roundness-jitter-slider',
            onChanged: (value) =>
                onChanged(state.copyWith(roundnessJitter: value)),
          ),
          _PanelSlider(
            label: AppText.strings.brSpacingJitter,
            valueLabel: '${(state.spacingJitter * 100).round()}%',
            value: BrushToolState.clampZeroToOne(state.spacingJitter),
            min: 0,
            max: 1,
            keyValue: 'brush-tool-spacing-jitter-slider',
            onChanged: (value) =>
                onChanged(state.copyWith(spacingJitter: value)),
          ),
          _GroupHeader('Mixing'),
          _PanelSwitch(
            label: AppText.strings.brMixing,
            value: state.mixesGroundColor,
            keyValue: 'brush-tool-mixing-toggle',
            onChanged: (value) =>
                onChanged(state.copyWith(mixesGroundColor: value)),
          ),
          if (state.mixesGroundColor) ...[
            _PanelSlider(
              label: AppText.strings.brPaintAmount,
              valueLabel: '${(state.paintAmount * 100).round()}%',
              value: BrushToolState.clampZeroToOne(state.paintAmount),
              min: 0,
              max: 1,
              keyValue: 'brush-tool-paint-amount-slider',
              onChanged: (value) =>
                  onChanged(state.copyWith(paintAmount: value)),
            ),
            _PanelSlider(
              label: AppText.strings.brPaintDensity,
              valueLabel: '${(state.paintDensity * 100).round()}%',
              value: BrushToolState.clampZeroToOne(state.paintDensity),
              min: 0,
              max: 1,
              keyValue: 'brush-tool-paint-density-slider',
              onChanged: (value) =>
                  onChanged(state.copyWith(paintDensity: value)),
            ),
            _PanelSlider(
              label: AppText.strings.brColorStretch,
              valueLabel: '${(state.colorStretch * 100).round()}%',
              value: BrushToolState.clampZeroToOne(state.colorStretch),
              min: 0,
              max: 1,
              keyValue: 'brush-tool-color-stretch-slider',
              onChanged: (value) =>
                  onChanged(state.copyWith(colorStretch: value)),
            ),
          ],
          _GroupHeader('Scattering'),
          _PanelSlider(
            // A ratio of the brush size, so scatter keeps its character as
            // the brush grows.
            label: AppText.strings.brScatter,
            valueLabel: '${(state.scatterRadiusRatio * 100).round()}%',
            value: BrushToolState.clampScatterRadius(state.scatterRadiusRatio),
            min: 0,
            max: 4,
            keyValue: 'brush-tool-scatter-slider',
            onChanged: (value) =>
                onChanged(state.copyWith(scatterRadiusRatio: value)),
          ),
          _PanelSlider(
            label: AppText.strings.brScatterCount,
            valueLabel: '${state.scatterCount}',
            value: BrushToolState.clampScatterCount(
              state.scatterCount,
            ).toDouble(),
            min: 1,
            max: 16,
            keyValue: 'brush-tool-scatter-count-slider',
            onChanged: (value) =>
                onChanged(state.copyWith(scatterCount: value.round())),
          ),
          _PanelSwitch(
            label: AppText.strings.brScatterBothAxes,
            value: state.scatterBothAxes,
            keyValue: 'brush-tool-scatter-both-axes-toggle',
            onChanged: (value) =>
                onChanged(state.copyWith(scatterBothAxes: value)),
          ),
          if (tips.isNotEmpty) ...[
            _GroupHeader('Texture'),
            BrushTipPickerRow(
              label: AppText.strings.brDualTip,
              role: BrushTipRole.dual,
              selected: state.dualMask,
              tips: tips,
              onImportRequested: onTipImportRequested,
              onRenameTip: onRenameTip,
              onDeleteTip: onDeleteTip,
              onPicked: (mask) =>
                  onChanged(state.withMask(BrushMaskSlot.dual, mask)),
            ),
            if (state.dualMask != null)
              _PanelSlider(
                label: AppText.strings.brScale,
                valueLabel: '${(state.dualMaskScale * 100).round()}%',
                value: BrushToolState.clampDualMaskScale(state.dualMaskScale),
                min: 0.05,
                max: 10,
                scale: FieldSliderScale.exponential,
                keyValue: 'brush-tool-dual-scale-slider',
                onChanged: (value) =>
                    onChanged(state.copyWith(dualMaskScale: value)),
              ),
            BrushTipPickerRow(
              label: AppText.strings.brTexture,
              role: BrushTipRole.texture,
              selected: state.textureMask,
              tips: tips,
              onImportRequested: onTipImportRequested,
              onRenameTip: onRenameTip,
              onDeleteTip: onDeleteTip,
              onPicked: (mask) =>
                  onChanged(state.withMask(BrushMaskSlot.texture, mask)),
            ),
            if (state.textureMask != null) ...[
              _PanelSlider(
                label: AppText.strings.brScale,
                valueLabel: '${(state.textureScale * 100).round()}%',
                value: BrushToolState.clampDualMaskScale(state.textureScale),
                min: 0.05,
                max: 10,
                scale: FieldSliderScale.exponential,
                keyValue: 'brush-tool-texture-scale-slider',
                onChanged: (value) =>
                    onChanged(state.copyWith(textureScale: value)),
              ),
              _PanelSlider(
                label: AppText.strings.brTextureDensity,
                valueLabel: '${(state.textureDensity * 100).round()}%',
                value: BrushToolState.clampZeroToOne(state.textureDensity),
                min: 0,
                max: 1,
                keyValue: 'brush-tool-texture-density-slider',
                onChanged: (value) =>
                    onChanged(state.copyWith(textureDensity: value)),
              ),
            ],
          ],
          _GroupHeader('Correction'),
          // Pull-string stabilization (P7): a hand-feel setting, kept OUT
          // of brush presets on purpose.
          _PanelSlider(
            label: AppText.strings.brStabilizer,
            valueLabel: '${state.stabilizerStrength.round()}',
            value: BrushToolState.clampStabilizerStrength(
              state.stabilizerStrength,
            ),
            min: 0,
            max: 100,
            keyValue: 'brush-tool-stabilizer-slider',
            onChanged: (value) =>
                onChanged(state.copyWith(stabilizerStrength: value)),
          ),
        ],
      ),
    );
  }
}

/// The CSP category rule: a small header over each settings group, a
/// hairline separating it from the group above.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label, {this.first = false});

  final String label;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!first)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Divider(
                height: 1,
                thickness: 1,
                color: theme.colorScheme.outlineVariant,
              ),
            ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// How a dab picks its angle: the fixed [BrushToolState.angleDegrees], or
/// the stroke's own direction with that angle as an offset.
///
/// A flat tip is the whole reason this exists — a calligraphy nib held at a
/// fixed angle draws thick and thin as the stroke turns, while a bristle
/// brush wants to rake ALONG the stroke however it curves.
class _RotationModeRow extends StatelessWidget {
  const _RotationModeRow({required this.state, required this.onChanged});

  final BrushToolState state;
  final ValueChanged<BrushToolState> onChanged;

  String _labelFor(BrushTipRotationMode mode) => switch (mode) {
    BrushTipRotationMode.fixed => AppText.strings.brRotationFixed,
    BrushTipRotationMode.direction => AppText.strings.brRotationDirection,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              AppText.strings.brTipRotation,
              style: theme.textTheme.labelSmall,
            ),
          ),
          PanelFlyoutButton(
            key: const ValueKey<String>('brush-tool-rotation-menu-button'),
            label: _labelFor(state.rotationMode),
            tooltip: AppText.strings.brTipRotation,
            entriesBuilder: () => [
              for (final candidate in BrushTipRotationMode.values)
                PanelFlyoutItem(
                  keyValue: 'brush-tool-rotation-${candidate.name}',
                  label: _labelFor(candidate),
                  checked: candidate == state.rotationMode,
                  onSelected: () =>
                      onChanged(state.copyWith(rotationMode: candidate)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A labelled on/off row, matching the slider rows' label-left layout.
class _PanelSwitch extends StatelessWidget {
  const _PanelSwitch({
    required this.label,
    required this.value,
    required this.keyValue,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final String keyValue;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.labelSmall)),
          Switch(
            key: ValueKey<String>(keyValue),
            value: value,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// The BRUSH BLEND row moved to the TOP STRIP with size and opacity (유저
// 확정). It is the same button and the same lock, transplanted rather than
// rebuilt — see `_BlendModeControl` in editor_top_strip.dart.

class _PanelSlider extends StatelessWidget {
  const _PanelSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.keyValue,
    required this.onChanged,
    this.scale = FieldSliderScale.linear,
    this.trailing,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final String keyValue;
  final ValueChanged<double> onChanged;
  final FieldSliderScale scale;

  /// Optional right-edge control (BB-3: the pressure-curve button).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final slider = FieldSlider(
      key: ValueKey<String>(keyValue),
      value: value,
      min: min,
      max: max,
      label: label,
      valueText: valueLabel,
      scale: scale,
      onChanged: onChanged,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: trailing == null
          ? slider
          : Row(
              children: [
                Expanded(child: slider),
                const SizedBox(width: 4),
                trailing!,
              ],
            ),
    );
  }
}
