import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/material.dart';

import '../../models/brush_anti_alias.dart';
import '../../models/brush_correction.dart';
import '../../models/brush_pressure_curve.dart';
import '../../models/brush_shape.dart' show BrushMaskSlot, BrushShape;
import '../../models/brush_tip_entry.dart';
import '../../models/brush_tip_order.dart';
import '../../models/brush_tip_rotation_mode.dart';
import '../../models/separable_blend_mode.dart';
import '../panels/editor_panel_frame.dart';
import '../widgets/settings_rows.dart';
import '../widgets/field_slider.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/pressure_curve_popup.dart';
import 'brush_tip_picker.dart';
import 'brush_tool_state.dart';
import 'tool_setting_rows.dart'
    show ToolSettingChoiceRow, ToolSettingRow, ToolSettingSurface;
import 'tool_settings_section.dart';
import '../text/app_strings.dart';
import '../text/model_vocabulary.dart';
import '../widgets/pill_strip.dart';

/// Editable brush tool properties — the CSP-style GROUPED layout (BB-2,
/// user-picked candidate B, 07-22): 브러시 크기 / 잉크 / 브러시 끝 /
/// 보정, with the BRUSH BLEND dropdown living in the ink group exactly
/// where Clip Studio keeps its 합성 모드. The color swatches and the tip
/// shape segment are GONE (R26 #11): color belongs to the color wheel
/// panel, the tip belongs to brush presets.
///
/// The brush library lives in the separate [BrushPresetPanel]; this panel
/// only mutates the live [BrushToolState].
class BrushSettingsPanel extends StatefulWidget {
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

  /// The shared tip library, for the tip / dual / texture pickers.
  ///
  /// ⛔An empty library used to take the three picker rows and the whole
  /// Texture group OFF the panel. That was product shape decided by a bare
  /// panel test — the app always ships built-in tips, so the branch could
  /// only ever fire in a test, and what it removed was a group HEADER as
  /// well. The rows are always here now; an empty library just opens an
  /// empty grid.
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

  @override
  State<BrushSettingsPanel> createState() => _BrushSettingsPanelState();
}

/// 🔬H40 (유저 2026-09-11): 「고르는 프레임에서 끝나더라도 지금 안그래도 고를때
/// 렉있어서 그부분도 효율적으로 가볍게 하고싶어」. With this panel open, a
/// pick's frame was measured at half a second, and nearly all of it was
/// here: every slider, its stepper, its pressure button and their tooltips
/// were built again for every brush — the rows two brushes share included.
///
/// ⇒ A row that SHOWS what it showed before is handed back as the very
/// instance it was ([_keepRows]), which the framework skips whole. What a
/// row shows is its label, its number, its range and unit, whether it is
/// alive, and its pressure curves ([_sameRow]).
///
/// ⚠️A kept row's callbacks must write the brush in hand NOW, not the one it
/// was built with — so the configuration is read through the getters below
/// at CALL time, and the rows keep closing over those names as they always
/// did. ⛔A row that holds the state ITSELF as a field cannot be kept at all
/// (tip rotation, the dual blend): it would write that snapshot back.
///
/// ⛔Not a repaint boundary per row (tried 2026-09-24, H40): on the real
/// Windows app at the user's screen size it bought nothing — a pick's worst
/// frame 29.1 ms against 21.3 without, opening the panel 68 against 38.5 —
/// and the boundary itself moved one pixel of a segmented control's outline
/// by 1/255. A kept row is skipped at build; the column paints as one.
class _BrushSettingsPanelState extends State<BrushSettingsPanel> {
  BrushToolState get state => widget.state;
  ValueChanged<BrushToolState> get onChanged => widget.onChanged;
  List<BrushTipEntry> get tips => widget.tips;
  VoidCallback? get onTipImportRequested => widget.onTipImportRequested;
  void Function(BrushTipEntry tip)? get onRenameTip => widget.onRenameTip;
  void Function(BrushTipEntry tip)? get onDeleteTip => widget.onDeleteTip;

  List<Widget> _kept = const [];

  // The library's tip callbacks, handed to the rows as this state's own
  // methods, which read the current callback at call time. The workspace
  // builds new closures on every rebuild, so the rows could never be kept
  // while they carried those; a method's tear-off compares EQUAL from one
  // build to the next, which is what [_sameRow] asks.
  void _importTipNow() => widget.onTipImportRequested?.call();
  void _renameTipNow(BrushTipEntry tip) => widget.onRenameTip?.call(tip);
  void _deleteTipNow(BrushTipEntry tip) => widget.onDeleteTip?.call(tip);
  VoidCallback? get _importTip =>
      widget.onTipImportRequested == null ? null : _importTipNow;
  void Function(BrushTipEntry tip)? get _renameTip =>
      widget.onRenameTip == null ? null : _renameTipNow;
  void Function(BrushTipEntry tip)? get _deleteTip =>
      widget.onDeleteTip == null ? null : _deleteTipNow;

  /// [fresh], with every row that shows what the kept row at its place
  /// showed replaced by that kept instance.
  List<Widget> _keepRows(List<Widget> fresh) {
    final kept = _kept;
    if (kept.length == fresh.length) {
      for (var i = 0; i < fresh.length; i += 1) {
        if (_sameRow(kept[i], fresh[i])) {
          fresh[i] = kept[i];
        }
      }
    }
    _kept = fresh;
    return fresh;
  }

  /// Whether [kept] and [fresh] show the same thing. Callbacks are not
  /// compared: theirs read the configuration at call time (see the class).
  static bool _sameRow(Widget kept, Widget fresh) => switch ((kept, fresh)) {
    (final _PanelSlider a, final _PanelSlider b) =>
      a.label == b.label &&
          a.value == b.value &&
          a.min == b.min &&
          a.max == b.max &&
          a.unit == b.unit &&
          a.displayScale == b.displayScale &&
          a.divisions == b.divisions &&
          a.scale == b.scale &&
          a.keyValue == b.keyValue &&
          (a.onChanged == null) == (b.onChanged == null) &&
          _sameTrailing(a.trailing, b.trailing),
    (final SettingsSwitchRow a, final SettingsSwitchRow b) =>
      a.label == b.label &&
          a.value == b.value &&
          a.tileKey == b.tileKey &&
          a.help == b.help &&
          a.inPickOneGroup == b.inPickOneGroup &&
          (a.onChanged == null) == (b.onChanged == null),
    (final _AntiAliasRow a, final _AntiAliasRow b) => a.value == b.value,
    // The library's callbacks ARE compared: the rows carry the panel's own
    // forwarders ([_importTip] and its two siblings) — tear-offs of one
    // method on one state, equal across builds, reading the library's
    // callback at call time.
    // ⚠️The masks ELEMENT BY ELEMENT: a one-mask slot hands its mask over
    // in a list made for the row, which is never the list it had before.
    (final BrushTipPickerRow a, final BrushTipPickerRow b) =>
      a.label == b.label &&
          a.role == b.role &&
          listEquals(a.selected, b.selected) &&
          identical(a.tips, b.tips) &&
          a.onImportRequested == b.onImportRequested &&
          a.onRenameTip == b.onRenameTip &&
          a.onDeleteTip == b.onDeleteTip,
    _ => false,
  };

  static bool _sameTrailing(Widget? kept, Widget? fresh) =>
      switch ((kept, fresh)) {
        (null, null) => true,
        (final PressureCurveButton a, final PressureCurveButton b) =>
          a.keyValue == b.keyValue &&
              a.target == b.target &&
              a.enabled == b.enabled &&
              mapEquals(a.curves, b.curves),
        _ => false,
      };

  /// The brush in hand, correcting its line as [correction] says (F-418).
  void _correct(BrushCorrection correction) =>
      onChanged(state.copyWith(correction: correction));

  /// The CSP-style per-setting pressure button (BB-3): sits at the right
  /// of each pressure-capable slider row and opens the shared curve popup.
  Widget _pressureButton(BrushPressureTarget target) {
    return PressureCurveButton(
      keyValue: 'brush-tool-pressure-${target.name}',
      target: target,
      curves: state.targetCurves(target),
      onChanged: (curves) => onChanged(state.withTargetCurves(target, curves)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return EditorPanelFrame(
      title: AppText.strings.brushSettingsTitle,
      // H35: the tool settings panel's content keeps its bar in view.
      bodyLane: true,
      // The grid's end column holds the curve buttons after the ±.
      child: ToolSettingSurface(
        end: _PanelSlider.endReach,
        child: Column(
          key: const ValueKey<String>('brush-settings-panel'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: _keepRows([
            // 유저 확정 (rail-and-strip): SIZE, OPACITY and BLEND — each with
            // its pressure curve or lock — left this panel for the TOP STRIP.
            // They are the settings a hand changes mid-stroke, against a test
            // mark on the canvas, and this panel scrolls; the strip is always
            // where it was. Keeping a second copy here would be two places
            // showing one number.
            ToolSettingsGroupHeader(AppText.strings.brGroupInk, first: true),
            _PanelSlider(
              label: AppText.strings.brFlow,
              unit: '%',
              displayScale: 100,
              value: BrushToolState.clampUnit(state.flow),
              min: 0,
              max: 1,
              keyValue: 'brush-tool-flow-slider',
              onChanged: (value) => onChanged(state.copyWith(flow: value)),
              trailing: _pressureButton(BrushPressureTarget.flow),
            ),
            ToolSettingsGroupHeader(AppText.strings.brGroupTip),
            BrushTipPickerRow(
              label: AppText.strings.brBrushTip,
              role: BrushTipRole.tip,
              selected: state.tips,
              tips: tips,
              onImportRequested: _importTip,
              onRenameTip: _renameTip,
              onDeleteTip: _deleteTip,
              // The sampled tips REPLACE hardness and tip shape, so clearing
              // them is how a brush gets its parametric footprint back — and
              // an empty list says so outright, which `copyWith` keeps for a
              // tip it is not given. ↩️One tip went through `withMask`.
              onPicked: (masks) => onChanged(state.copyWith(tips: masks)),
            ),
            // How the dabs take the tips above (F-176-Q3).
            _TipOrderRow(state: state, onChanged: onChanged),
            _PanelSlider(
              label: AppText.strings.brHardness,
              unit: '%',
              displayScale: 100,
              value: BrushToolState.clampUnit(state.hardness),
              min: 0,
              max: 1,
              keyValue: 'brush-tool-hardness-slider',
              onChanged: (value) => onChanged(state.copyWith(hardness: value)),
              trailing: _pressureButton(BrushPressureTarget.hardness),
            ),
            // Beside hardness on purpose: hardness sets how WIDE the coverage
            // ramp is, this sets how hard its edge cuts. Two halves of one
            // footprint, so they read together.
            _AntiAliasRow(
              value: state.antiAlias,
              onChanged: (step) => onChanged(state.copyWith(antiAlias: step)),
            ),
            _PanelSlider(
              label: AppText.strings.brRoundness,
              unit: '%',
              displayScale: 100,
              value: BrushToolState.clampRoundness(state.roundness),
              min: BrushToolState.minRoundness,
              max: 1,
              keyValue: 'brush-tool-roundness-slider',
              onChanged: (value) => onChanged(state.copyWith(roundness: value)),
              trailing: _pressureButton(BrushPressureTarget.roundness),
            ),
            _PanelSlider(
              label: AppText.strings.brAngle,
              unit: '°',
              value: BrushToolState.clampAngleDegrees(state.angleDegrees),
              min: BrushToolState.minAngleDegrees,
              max: BrushToolState.maxAngleDegrees,
              keyValue: 'brush-tool-angle-slider',
              onChanged: (value) =>
                  onChanged(state.copyWith(angleDegrees: value)),
            ),
            // 向き is ONE setting — the angle above, the base it turns from
            // and its random turn (F-176-Q1 「클튜처럼 — 「방향」 하나: 기준 +
            // 랜덤」) — so the three sit together. ↩️The random turn was the
            // 「무작위」 group's angle slider, the base a row of its own below
            // spacing.
            _RotationModeRow(state: state, onChanged: onChanged),
            _PanelSlider(
              label: AppText.strings.curveSourceRandom,
              unit: '%',
              displayScale: 100,
              value: BrushToolState.clampZeroToOne(state.angleJitter),
              min: 0,
              max: 1,
              keyValue: 'brush-tool-angle-jitter-slider',
              onChanged: (value) =>
                  onChanged(state.copyWith(angleJitter: value)),
            ),
            _PanelSlider(
              label: AppText.strings.brSpacing,
              unit: '%',
              displayScale: 100,
              value: BrushToolState.clampSpacing(state.spacing),
              min: BrushShape.minSpacing,
              max: BrushShape.maxSpacing,
              scale: FieldSliderScale.exponential,
              keyValue: 'brush-tool-spacing-slider',
              onChanged: (value) => onChanged(state.copyWith(spacing: value)),
              trailing: _pressureButton(BrushPressureTarget.spacing),
            ),
            ToolSettingsGroupHeader(AppText.strings.brGroupMixing),
            SettingsSwitchRow(
              tileKey: const ValueKey<String>('brush-tool-mixing-toggle'),
              label: AppText.strings.brMixing,
              value: state.mixesGroundColor,
              onChanged: (value) =>
                  onChanged(state.copyWith(mixesGroundColor: value)),
            ),
            // ⛔THE ROWS DO NOT APPEAR AND DISAPPEAR — they go DEAD (유저, 반복:
            // 「없다가 생기는 UI 금지. 자리는 항상 예약하고 내용만 바꾼다」).
            // The three below used to be mounted only while mixing was on, so
            // turning the switch made the panel jump and everything under it
            // moved out from under the finger.
            _PanelSlider(
              label: AppText.strings.brPaintAmount,
              unit: '%',
              displayScale: 100,
              value: BrushToolState.clampZeroToOne(state.paintAmount),
              min: 0,
              max: 1,
              keyValue: 'brush-tool-paint-amount-slider',
              onChanged: state.mixesGroundColor
                  ? (value) => onChanged(state.copyWith(paintAmount: value))
                  : null,
            ),
            _PanelSlider(
              label: AppText.strings.brPaintDensity,
              unit: '%',
              displayScale: 100,
              value: BrushToolState.clampZeroToOne(state.paintDensity),
              min: 0,
              max: 1,
              keyValue: 'brush-tool-paint-density-slider',
              onChanged: state.mixesGroundColor
                  ? (value) => onChanged(state.copyWith(paintDensity: value))
                  : null,
            ),
            _PanelSlider(
              label: AppText.strings.brColorStretch,
              unit: '%',
              displayScale: 100,
              value: BrushToolState.clampZeroToOne(state.colorStretch),
              min: 0,
              max: 1,
              keyValue: 'brush-tool-color-stretch-slider',
              onChanged: state.mixesGroundColor
                  ? (value) => onChanged(state.copyWith(colorStretch: value))
                  : null,
            ),
            ToolSettingsGroupHeader(AppText.strings.brGroupScattering),
            _PanelSlider(
              // A ratio of the brush size, so scatter keeps its character as
              // the brush grows.
              label: AppText.strings.brScatter,
              unit: '%',
              displayScale: 100,
              value: BrushToolState.clampScatterRadius(
                state.scatterRadiusRatio,
              ),
              min: 0,
              max: 4,
              keyValue: 'brush-tool-scatter-slider',
              onChanged: (value) =>
                  onChanged(state.copyWith(scatterRadiusRatio: value)),
            ),
            _PanelSlider(
              label: AppText.strings.brScatterCount,
              value: BrushToolState.clampScatterCount(
                state.scatterCount,
              ).toDouble(),
              min: 1,
              max: 16,
              // A COUNT of dabs, so the bar stops between them — F-34's own
              // sentence (「데이터적으로 소수점이 필요없는것들 정수화 … 조절시
              // 자연수이도록」) and the same fix the RGB channel and the
              // opacity bars already carry. Without it the bar hands 8.4 to an
              // int and its own readout has to write `8.0`.
              divisions: 15,
              keyValue: 'brush-tool-scatter-count-slider',
              onChanged: (value) =>
                  onChanged(state.copyWith(scatterCount: value.round())),
            ),
            SettingsSwitchRow(
              tileKey: const ValueKey<String>(
                'brush-tool-scatter-both-axes-toggle',
              ),
              label: AppText.strings.brScatterBothAxes,
              value: state.scatterBothAxes,
              onChanged: (value) =>
                  onChanged(state.copyWith(scatterBothAxes: value)),
            ),
            ToolSettingsGroupHeader(AppText.strings.brGroupTexture),
            BrushTipPickerRow(
              label: AppText.strings.brDualTip,
              role: BrushTipRole.dual,
              selected: [?state.dualMask],
              tips: tips,
              onImportRequested: _importTip,
              onRenameTip: _renameTip,
              onDeleteTip: _deleteTip,
              onPicked: (masks) => onChanged(
                state.withMask(BrushMaskSlot.dual, masks.firstOrNull),
              ),
            ),
            _PanelSlider(
              label: AppText.strings.brScale,
              unit: '%',
              displayScale: 100,
              value: BrushToolState.clampDualMaskScale(state.dualMaskScale),
              min: 0.05,
              max: 10,
              scale: FieldSliderScale.exponential,
              keyValue: 'brush-tool-dual-scale-slider',
              onChanged: state.dualMask == null
                  ? null
                  : (value) => onChanged(state.copyWith(dualMaskScale: value)),
            ),
            // The dual mask's own density, beside its scale — the same pair
            // the texture mask below has had all along. The dual mask used to
            // be an unconditional multiply, which made it the one mask you
            // could only have at full strength.
            _PanelSlider(
              label: AppText.strings.brTextureDensity,
              unit: '%',
              displayScale: 100,
              value: BrushToolState.clampZeroToOne(state.dualDensity),
              min: 0,
              max: 1,
              keyValue: 'brush-tool-dual-density-slider',
              onChanged: state.dualMask == null
                  ? null
                  : (value) => onChanged(state.copyWith(dualDensity: value)),
            ),
            _DualBlendRow(state: state, onChanged: onChanged),
            BrushTipPickerRow(
              label: AppText.strings.brTexture,
              role: BrushTipRole.texture,
              // ⚠️The SOURCE, not the painted mask: the swatch answers "which
              // texture did I pick", and a levelled bake is a different object
              // that would never match a library entry.
              selected: [?state.textureMaskSource],
              tips: tips,
              onImportRequested: _importTip,
              onRenameTip: _renameTip,
              onDeleteTip: _deleteTip,
              onPicked: (masks) => onChanged(
                state.withMask(BrushMaskSlot.texture, masks.firstOrNull),
              ),
            ),
            _PanelSlider(
              label: AppText.strings.brScale,
              unit: '%',
              displayScale: 100,
              value: BrushToolState.clampDualMaskScale(state.textureScale),
              min: 0.05,
              max: 10,
              scale: FieldSliderScale.exponential,
              keyValue: 'brush-tool-texture-scale-slider',
              onChanged: state.textureMaskSource == null
                  ? null
                  : (value) => onChanged(state.copyWith(textureScale: value)),
            ),
            _PanelSlider(
              label: AppText.strings.brTextureDensity,
              unit: '%',
              displayScale: 100,
              value: BrushToolState.clampZeroToOne(state.textureDensity),
              min: 0,
              max: 1,
              keyValue: 'brush-tool-texture-density-slider',
              onChanged: state.textureMaskSource == null
                  ? null
                  : (value) => onChanged(state.copyWith(textureDensity: value)),
            ),
            // The three LEVELS both source formats carry and neither could
            // reach: the importers baked them into the mask, which left no
            // original to re-bake from. Clip Studio calls them 濃度反転 /
            // 明るさ / コントラスト and Photoshop InvT / Brightness / Contrast.
            SettingsSwitchRow(
              tileKey: const ValueKey<String>(
                'brush-tool-texture-invert-toggle',
              ),
              label: AppText.strings.brTextureInvert,
              value: state.textureInvert,
              onChanged: state.textureMaskSource == null
                  ? null
                  : (value) => onChanged(state.copyWith(textureInvert: value)),
            ),
            _PanelSlider(
              label: AppText.strings.brTextureBrightness,
              unit: '%',
              displayScale: 100,
              value: BrushToolState.clampSignedUnit(state.textureBrightness),
              min: -1,
              max: 1,
              keyValue: 'brush-tool-texture-brightness-slider',
              onChanged: state.textureMaskSource == null
                  ? null
                  : (value) =>
                        onChanged(state.copyWith(textureBrightness: value)),
            ),
            _PanelSlider(
              label: AppText.strings.brTextureContrast,
              unit: '%',
              displayScale: 100,
              value: BrushToolState.clampSignedUnit(state.textureContrast),
              min: -1,
              max: 1,
              keyValue: 'brush-tool-texture-contrast-slider',
              onChanged: state.textureMaskSource == null
                  ? null
                  : (value) =>
                        onChanged(state.copyWith(textureContrast: value)),
            ),
            ToolSettingsGroupHeader(AppText.strings.brGroupCorrection),
            // The brush's own, kept in its preset as Clip Studio keeps it
            // (F-418-Q6). ↩️It was the pull string's rope, a hand-feel
            // setting kept out of presets (P7).
            _PanelSlider(
              label: AppText.strings.brStabilizer,
              value: BrushToolState.clampCorrection(
                state.correction.stabilization,
                BrushCorrection.maxStabilization,
              ),
              min: 0,
              max: BrushCorrection.maxStabilization,
              keyValue: 'brush-tool-stabilizer-slider',
              onChanged: (value) =>
                  _correct(state.correction.copyWith(stabilization: value)),
            ),
            // Clip Studio's switch and 補正タイプ under it, as one row — and
            // dim where the line is not steadied, as Clip Studio greys what
            // sits under a switch that is off (F-418).
            _SteadyingBySpeedRow(
              value: state.correction.steadyingBySpeed,
              onPick: state.correction.steadies
                  ? (value) => _correct(
                      state.correction.copyWith(steadyingBySpeed: value),
                    )
                  : null,
            ),
            _PanelSlider(
              label: AppText.strings.brPostCorrection,
              value: BrushToolState.clampCorrection(
                state.correction.postStrength,
                BrushCorrection.maxPostStrength,
              ),
              min: 0,
              max: BrushCorrection.maxPostStrength,
              keyValue: 'brush-tool-post-correction-slider',
              onChanged: (value) =>
                  _correct(state.correction.copyWith(postStrength: value)),
            ),
            for (final (key, label, value, change) in [
              (
                'brush-tool-post-by-speed-toggle',
                AppText.strings.brPostBySpeed,
                state.correction.postBySpeed,
                (bool on) => state.correction.copyWith(postBySpeed: on),
              ),
              (
                'brush-tool-post-by-view-scale-toggle',
                AppText.strings.brPostByViewScale,
                state.correction.postByViewScale,
                (bool on) => state.correction.copyWith(postByViewScale: on),
              ),
              (
                'brush-tool-post-bezier-toggle',
                AppText.strings.brPostBezier,
                state.correction.postBezier,
                (bool on) => state.correction.copyWith(postBezier: on),
              ),
            ])
              SettingsSwitchRow(
                tileKey: ValueKey<String>(key),
                label: label,
                value: value,
                onChanged: state.correction.postStrength > 0
                    ? (on) => _correct(change(on))
                    : null,
              ),
            // ⛔THE AUTO-FRAME TOGGLE IS NOT HERE ANY MORE (F-61, 유저:
            // 「프레임 자동생성 버튼 툴 설정에 있는데, **왜 이딴식으로
            // 결정한거지? 내가 분명 타임라인 헤더쪽에 두라하지않았나?** 프레임
            // 알약 안, 중간나누기 버튼 오른쪽에 두도록. 기존 잔재는 삭제」).
            //
            // ⚠️Kept as a note rather than deleted silently: the earlier
            // quote I built it from (「**프레임 자동생성 on버튼** 만들게
            // 햇던거같은데」) says nothing about WHERE, and I read the tool
            // settings convention into the gap. It lives in the frame pill —
            // beside the other verbs that make and unmake a block, which is
            // the group it belongs to.
          ]),
        ),
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
    BrushTipRotationMode.penTilt => AppText.strings.brRotationPenTilt,
  };

  @override
  Widget build(BuildContext context) => ToolSettingRow(
    label: AppText.strings.brTipRotation,
    child: PanelFlyoutButton(
      key: const ValueKey<String>('brush-tool-rotation-menu-button'),
      label: _labelFor(state.rotationMode),
      expand: true,
      entriesBuilder: () => BrushTipRotationMode.values.asFlyoutChoices(
        current: state.rotationMode,
        keyPrefix: 'brush-tool-rotation-',
        labelOf: _labelFor,
        onPicked: (mode) => onChanged(state.copyWith(rotationMode: mode)),
      ),
    ),
  );
}

/// Which tip each dab takes — Clip Studio's 繰り返し方法, all six (F-176-Q3
/// 「클튜 여섯 전부 + 끌어서 순서」), in the order Clip Studio lists them.
///
/// ⛔ALWAYS HERE, and DEAD for the round tip, which has no tips to take
/// turns — 「없다가 생기는 UI 금지」, the shape [_DualBlendRow] takes. One
/// tip keeps it live: the two laps still draw that tip once.
class _TipOrderRow extends StatelessWidget {
  const _TipOrderRow({required this.state, required this.onChanged});

  final BrushToolState state;
  final ValueChanged<BrushToolState> onChanged;

  String _labelFor(BrushTipOrder order) => switch (order) {
    BrushTipOrder.repeat => AppText.strings.brTipOrderRepeat,
    BrushTipOrder.pingPong => AppText.strings.brTipOrderPingPong,
    BrushTipOrder.holdLast => AppText.strings.brTipOrderHoldLast,
    BrushTipOrder.random => AppText.strings.brTipOrderRandom,
    BrushTipOrder.oneLap => AppText.strings.brTipOrderOneLap,
    BrushTipOrder.shuffledLap => AppText.strings.brTipOrderShuffledLap,
  };

  @override
  Widget build(BuildContext context) => ToolSettingRow(
    label: AppText.strings.brTipOrder,
    child: PanelFlyoutButton(
      key: const ValueKey<String>('brush-tool-tip-order-menu-button'),
      label: _labelFor(state.tipOrder),
      expand: true,
      enabled: state.tips.isNotEmpty,
      entriesBuilder: () => BrushTipOrder.values.asFlyoutChoices(
        current: state.tipOrder,
        keyPrefix: 'brush-tool-tip-order-',
        labelOf: _labelFor,
        onPicked: (order) => onChanged(state.copyWith(tipOrder: order)),
      ),
    ),
  );
}

// The BRUSH BLEND row moved to the TOP STRIP with size and opacity (유저
// 확정). It is the same button and the same lock, transplanted rather than
// rebuilt — see `_BlendModeControl` in editor_top_strip.dart.

/// The brush EDGE row — 없음 / 1 / 2 / 3 (유저 확정, 클튜 4단) — named
/// 「안티앨리어스」 as every tool's is. ↩️It was 「가장자리」 (🗣️유저
/// 2026-10-10: 「안티앨리어스로 이름 다 통일」).
///
/// A [PillStrip], the app's one grouped choice (유저 2026-09-09, board
/// `pill-group-everywhere`) — the four answers have plain names, so no icon
/// has to be invented for them, and the chosen one is told by colour alone.
/// 🪦It was a Material `SegmentedButton`, as the eyedropper's source was.
class _AntiAliasRow extends StatelessWidget {
  const _AntiAliasRow({required this.value, required this.onChanged});

  final BrushAntiAlias value;
  final ValueChanged<BrushAntiAlias> onChanged;

  /// 1·2·3 are DIGITS, not words — they read the same in every language
  /// this program speaks, so only 없음 goes through [AppText].
  String _labelFor(BrushAntiAlias step) => switch (step) {
    BrushAntiAlias.none => AppText.strings.brEdgeNone,
    BrushAntiAlias.low => '1',
    BrushAntiAlias.medium => '2',
    BrushAntiAlias.high => '3',
  };

  /// Every tool's choice row ([ToolSettingChoiceRow] — its name in the
  /// name column, the answers sharing the control column; tool-settings-
  /// panel-tidy, 유저 2026-10-10 「고르기는 한 모양」). ↩️It wrote its own: a
  /// dimmer name with the strip right after it, and then the curve slot's
  /// reservation by hand — the grid keeps the end column now.
  @override
  Widget build(BuildContext context) => ToolSettingChoiceRow<BrushAntiAlias>(
    tool: 'brush-tool',
    name: 'edge',
    label: AppText.strings.brAntiAlias,
    current: value,
    answers: [
      for (final step in BrushAntiAlias.values)
        (value: step, key: step.name, label: _labelFor(step)),
    ],
    onPick: (step) => () => onChanged(step),
  );
}

/// 速度による手ブレ補正 — none, or which way the pen's speed bends the
/// steadying ([BrushSteadyingBySpeed]). Null [onPick] dims it: a brush that
/// steadies nothing has nothing for the speed to bend.
class _SteadyingBySpeedRow extends StatelessWidget {
  const _SteadyingBySpeedRow({required this.value, required this.onPick});

  final BrushSteadyingBySpeed value;
  final ValueChanged<BrushSteadyingBySpeed>? onPick;

  String _labelFor(BrushSteadyingBySpeed type) => switch (type) {
    BrushSteadyingBySpeed.off => AppText.strings.commonNone,
    BrushSteadyingBySpeed.slow => AppText.strings.brBySpeedSlow,
    BrushSteadyingBySpeed.fast => AppText.strings.brBySpeedFast,
  };

  @override
  Widget build(BuildContext context) =>
      ToolSettingChoiceRow<BrushSteadyingBySpeed>(
        tool: 'brush-tool',
        name: 'steadying-by-speed',
        label: AppText.strings.brStabilizerBySpeed,
        current: value,
        answers: [
          for (final type in BrushSteadyingBySpeed.values)
            (value: type, key: type.name, label: _labelFor(type)),
        ],
        onPick: (type) {
          final pick = onPick;
          return pick == null ? null : () => pick(type);
        },
      );
}

class _PanelSlider extends StatelessWidget {
  const _PanelSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.keyValue,
    required this.onChanged,
    this.unit = '',
    this.displayScale = 1,
    this.divisions,
    this.scale = FieldSliderScale.linear,
    this.trailing,
  });

  final String label;

  /// ⛔THE ROW PASSES A UNIT, NEVER A NUMBER (F-34). Seventeen of these rows
  /// wrote `'${(x * 100).round()}%'` by hand — a rounding the bar had not
  /// done, so a spacing holding 12.4% read `12%`, and the digit count came
  /// and went with the value.
  final String unit;
  final double displayScale;
  final int? divisions;
  final double value;
  final double min;
  final double max;
  final String keyValue;

  /// Null makes the row DEAD, not absent: it keeps its place, its label and
  /// its number, and stops taking the gesture. That is the whole reason this
  /// is nullable — see the mixing and mask rows, which used to be mounted
  /// conditionally and made the panel jump under the finger.
  final ValueChanged<double>? onChanged;
  final FieldSliderScale scale;

  /// Optional right-edge control (BB-3: the pressure-curve button).
  ///
  /// ⚠️Optional in CONTENT, never in SPACE — see [build].
  final Widget? trailing;

  /// The gap between the ± and the trailing slot.
  static const double _trailingGap = 4;

  /// The END column of this panel's grid ([ToolSettingSurface.end]): a
  /// bar's ±, and the curve button's slot after them.
  static const double endReach =
      FieldSlider.handsReach + _trailingGap + PressureCurveButton.slotWidth;

  @override
  Widget build(BuildContext context) {
    final slider = FieldSlider.cell(
      key: ValueKey<String>(keyValue),
      value: value,
      min: min,
      max: max,
      label: label,
      unit: unit,
      displayScale: displayScale,
      divisions: divisions,
      scale: scale,
      onChanged: onChanged,
    );
    // 🚨THE SLOT IS ALWAYS THERE, whether or not a button sits in it (유저
    // 09-08: 「슬라이더 크기는 항상 고정되도록. 압력버튼없으면 그냥
    // 빈공간으로」). ⛔The branch this replaced gave the eighteen sliders
    // WITHOUT a curve button the button's width as well, so one panel drew
    // its slider at two different lengths — 「자리는 항상 예약하고 내용만
    // 바꾼다」 with the reservation missing. It is the grid's END column
    // now, after the ± ([endReach]), which every row of the panel keeps.
    return ToolSettingRow.bar(label: label, bar: slider, trailing: trailing);
  }
}

/// How the DUAL mask COMBINES with the coverage under it.
///
/// 🚨A brush could ARRIVE with a mode and never be edited to one (v33). Both
/// source formats carry it — Clip Studio's `DualBrushCompositeMode`, whose
/// 加算 shows up in the user's own files, and Photoshop's `dualBrush.BlnM`,
/// eight codes across 765 brushes — the engine reads them now, and the dual
/// mask's other knobs have had rows here all along.
///
/// ⛔A `PanelFlyoutButton` row, the shape this panel already uses for tip
/// rotation. Twelve entries is what a flyout is for; the segmented button
/// above is for the four-way edge step, and a third control shape would be
/// a new convention for no reason.
class _DualBlendRow extends StatelessWidget {
  const _DualBlendRow({required this.state, required this.onChanged});

  final BrushToolState state;
  final ValueChanged<BrushToolState> onChanged;

  @override
  Widget build(BuildContext context) {
    final language = AppText.language;
    // ⛔The row is ALWAYS here and goes DEAD without a dual tip — the same
    // shape the two sliders above it take, and 「없다가 생기는 UI 금지」: the
    // mask rows used to mount only once a mask was picked, which shoved
    // four rows under the finger that had just come back from the popup.
    final enabled = state.dualMask != null;
    // A row of the grid like the rotation's ([ToolSettingRow]). ↩️It wrote
    // its own: the name, and the button as wide as its word at the end.
    return ToolSettingRow(
      label: AppText.strings.brDualBlend,
      child: PanelFlyoutButton(
        key: const ValueKey<String>('brush-tool-dual-blend-menu-button'),
        label: state.dualCompositeMode.labelFor(language),
        expand: true,
        // ⛔`enabled`, NOT an empty list. `showMenu` asserts on one, and a
        // button that opens nothing is 「잠궜는데 바꿀 수 있으면 잠금이
        // 아니잖아」 — the flyout's own doc says a host that needs a shut
        // state owns the appearance of one, and this button can dim itself.
        enabled: enabled,
        entriesBuilder: () => SeparableBlendMode.values.asFlyoutChoices(
          current: state.dualCompositeMode,
          keyPrefix: 'brush-tool-dual-blend-',
          labelOf: (mode) => mode.labelFor(language),
          onPicked: (mode) =>
              onChanged(state.copyWith(dualCompositeMode: mode)),
        ),
      ),
    );
  }
}
