import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/material.dart';

import '../../core/set_toggle.dart';
import '../../models/brush_anti_alias.dart';
import '../../models/brush_correction.dart';
import '../../models/brush_mixing_method.dart';
import '../../models/brush_pressure_curve.dart';
import '../../models/brush_settings_group.dart';
import '../../models/brush_settings_row.dart';
import '../../models/brush_shape.dart' show BrushMaskSlot, BrushShape;
import '../../models/brush_tip_entry.dart';
import '../../models/brush_tip_order.dart';
import '../../models/brush_texture_mode.dart';
import '../../models/separable_blend_mode.dart';
import '../panels/editor_panel_frame.dart';
import '../timeline/layer_label_controls.dart'
    show LayerVisibilityToggleButton;
import '../widgets/app_icon_button.dart';
import '../widgets/app_window.dart';
import '../widgets/content_scrollbar.dart';
import '../widgets/floating_app_window.dart';
import '../widgets/group_tab.dart';
import '../widgets/settings_rows.dart';
import '../widgets/field_slider.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/pressure_curve_popup.dart';
import '../widgets/setting_source_button.dart';
import '../widgets/tip_direction_popup.dart';
import 'brush_tip_picker.dart';
import 'brush_tool_state.dart';
import 'tool_setting_rows.dart'
    show
        ToolSettingChoiceRow,
        ToolSettingColumns,
        ToolSettingRow,
        ToolSettingSurface;
import 'tool_settings_section.dart';
import '../text/app_strings.dart';
import '../text/model_vocabulary.dart';
import '../widgets/pill_strip.dart';

/// Editable brush tool properties — the brush's own settings, each row
/// one of [BrushSettingsRow]. The BRUSH BLEND, size and opacity live in the
/// top strip; the color swatches and the tip shape segment are GONE (R26
/// #11): color belongs to the color wheel panel, the tip belongs to brush
/// presets.
///
/// 🗣️I-141 (유저 2026-10-29): the panel shows only the rows the brush
/// SHOWS ([BrushToolState.shown]), in the panel's own order, with no group
/// heads (Q2 「패널 본래 순서 그대로」; 「클튜처럼 보이도록 고정한 항목은
/// 항목헤더같은거 표시안함. 멤버만 심플하게 하나씩 보여주는느낌」), and the
/// wrench under them opens the brush detail window, where every row stands
/// under its group with an eye that shows it here or not (Q1 ⓐ 「클튜식 —
/// 상세 창에서 고른다」). ↩️Every row stood here under six folding group
/// heads (BB-2 candidate B, 07-22; F-418-Q10).
///
/// 🚨THE WINDOW IS THE USER'S EXCEPTION to 「툴 설정은 툴 설정 패널에 —
/// 그 툴 전용 패널을 새로 만들지 않는다」: Q1's answer chose a window, and
/// Q3 (「떠 있는 창(클튜처럼)」) one that floats, so the canvas takes
/// strokes while it is open. Its rows are THIS panel's rows, built by the
/// one [_BrushSettingsPanelState._rowOf] — the window is where they are
/// chosen, not a second panel.
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
    this.detailAt,
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

  /// Where the brush detail window stands ([FloatingAppWindow.at]) — the
  /// workspace's, so it opens where it was left after a restart (Q3 「창은
  /// 끌어서 옮기고 자리를 기억한다」). Null keeps it for as long as the panel
  /// lives.
  final ValueNotifier<Offset?>? detailAt;

  // The `language` parameter left with the blend row: it existed only for
  // the blend labels (ja = CSP terms), and the rest of the panel reads its
  // wording from `AppText.strings`.

  @override
  State<BrushSettingsPanel> createState() => _BrushSettingsPanelState();
}

/// The rows one place showed last, by the row each is ([BrushSettingsRow]).
///
/// 🔬H40 (유저 2026-09-11): 「고르는 프레임에서 끝나더라도 지금 안그래도 고를때
/// 렉있어서 그부분도 효율적으로 가볍게 하고싶어」. With this panel open, a
/// pick's frame was measured at half a second, and nearly all of it was
/// here: every slider, its stepper, its pressure button and their tooltips
/// were built again for every brush — the rows two brushes share included.
///
/// ⇒ A row that SHOWS what it showed before is handed back as the very
/// instance it was ([keep]), which the framework skips whole. What a row
/// shows is its label, its number, its range and unit, whether it is alive,
/// and its pressure curves ([_BrushSettingsPanelState._sameRow]).
///
/// A row is found by the row it is, not by its place: what a brush shows
/// (I-141) and a switch's rows standing only while it is on (F-478-Q2) both
/// move the rows under them. Each row is keyed by it as well, or the
/// framework would hand a kept row the element of whichever row stood at
/// its place before. ↩️Rows were found by their place, which held while
/// every row stood in the panel whatever the brush.
///
/// One per place a row stands — the panel, and the detail window's group.
class _KeptRows {
  Map<BrushSettingsRow, Widget> _kept = const {};

  /// [fresh], with every row that shows what the kept row of its name
  /// showed replaced by that kept instance.
  List<(BrushSettingsRow, Widget)> keep(
    List<(BrushSettingsRow, Widget)> fresh,
  ) {
    final kept = _kept;
    final rows = [
      for (final (row, built) in fresh)
        switch (kept[row]) {
          final old? when _BrushSettingsPanelState._sameRow(old, built) => (
            row,
            old,
          ),
          _ => (row, built),
        },
    ];
    _kept = {for (final (row, built) in rows) row: built};
    return rows;
  }
}

/// ⚠️A kept row's callbacks must write the brush in hand NOW, not the one it
/// was built with — so the configuration is read through the getters below
/// at CALL time, and the rows keep closing over those names as they always
/// did. ⛔A row that holds the state ITSELF as a field cannot be kept at all
/// (the tip order, the dual blend): it would write that snapshot back.
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

  final _panelRows = _KeptRows();
  final _detailRows = _KeptRows();

  /// The brush detail window, and the group its rail is on.
  final _detail = OverlayPortalController();
  BrushSettingsGroup _detailGroup = BrushSettingsGroup.ink;

  /// Where the window stands when no workspace keeps it ([widget.detailAt]).
  ValueNotifier<Offset?>? _ownDetailAt;
  ValueNotifier<Offset?> get _detailAt =>
      widget.detailAt ?? (_ownDetailAt ??= ValueNotifier<Offset?>(null));

  /// The window's size: the rail, and the rows at the panel's own width
  /// with an eye before each — the texture group's eleven without a scroll.
  static const Size _detailSize = Size(480, 400);

  @override
  void dispose() {
    _ownDetailAt?.dispose();
    super.dispose();
  }

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
        // What it shows is the setting it holds; its callback reads the
        // brush in hand at call time, as every kept row's does.
        (final TipDirectionButton a, final TipDirectionButton b) =>
          a.direction == b.direction,
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

  /// The rows of [rows] that stand in the brush in hand ([_stands]), each
  /// built, in the panel's order — the panel's and the window's alike.
  List<(BrushSettingsRow, Widget)> _built(
    bool Function(BrushSettingsRow row) rows,
  ) => [
    for (final row in BrushSettingsRow.values)
      if (rows(row) && _stands(row)) (row, _rowOf(row)),
  ];

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
          children: [
            // 유저 확정 (rail-and-strip): SIZE, OPACITY and BLEND — each with
            // its pressure curve or lock — left this panel for the TOP STRIP.
            // They are the settings a hand changes mid-stroke, against a test
            // mark on the canvas, and this panel scrolls; the strip is always
            // where it was. Keeping a second copy here would be two places
            // showing one number.
            for (final (row, built) in _panelRows.keep(
              _built(state.shown.contains),
            ))
              KeyedSubtree(key: ValueKey<BrushSettingsRow>(row), child: built),
            KeyedSubtree(
              key: const ValueKey<String>('brush-detail-bar'),
              child: _detailBar(context),
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
          ],
        ),
      ),
    );
  }

  /// The wrench under the rows, at the panel's end, over a hairline — what
  /// opens the brush detail window and closes it again.
  Widget _detailBar(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(
          height: 1,
          thickness: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        const SizedBox(height: ToolSettingsSection.rowGap),
        Align(
          alignment: Alignment.centerRight,
          child: FloatingAppWindow(
            controller: _detail,
            at: _detailAt,
            size: _detailSize,
            window: _detailWindow,
            child: AppIconButton(
              keyValue: 'brush-detail-button',
              tooltip: AppText.strings.brDetailTitle,
              icon: const Icon(Icons.build_outlined),
              outlined: true,
              isSelected: _detail.isShowing,
              onPressed: () => setState(_detail.toggle),
            ),
          ),
        ),
      ],
    ),
  );

  /// The brush detail window: the groups down its left side, as the brush
  /// library's are (I-141-Q4 「클튜처럼 왼쪽에 두자. 브러시그룹/브러시목록이랑
  /// 비슷한느낌으로」 — ↩️a tab strip across its top, as drawn first), and the
  /// rail's group's rows, each with its eye.
  Widget _detailWindow(
    BuildContext context,
    Size size,
    GestureDragUpdateCallback onTitleDrag,
  ) => AppWindow(
    windowKey: const ValueKey<String>('brush-detail-window'),
    title: AppText.strings.brDetailTitle,
    onClose: () => setState(_detail.hide),
    onTitleDrag: onTitleDrag,
    width: size.width,
    height: size.height,
    scrollBody: false,
    bodyPadding: EdgeInsets.zero,
    body: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _detailRail(),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        Expanded(
          child: ToolSettingSurface(
            end: _PanelSlider.endReach,
            child: ContentScrollbar(
              builder: (context, controller) => ListView(
                key: const ValueKey<String>('brush-detail-rows'),
                controller: controller,
                padding: ToolSettingsSection.inset,
                children: [
                  for (final (row, built) in _detailRows.keep(
                    _built((row) => row.group == _detailGroup),
                  ))
                    _EyedRow(
                      key: ValueKey<BrushSettingsRow>(row),
                      row: row,
                      shown: state.shown.contains(row),
                      onToggle: () => onChanged(
                        state.copyWith(shown: toggledSet(state.shown, row)),
                      ),
                      child: built,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  /// The window's rail: one [GroupTab] a group, the brush library's tab.
  Widget _detailRail() => SizedBox(
    width: GroupTab.namedWidth,
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final group in BrushSettingsGroup.values)
            GroupTab(
              keyValue: 'brush-detail-group-${group.name}',
              label: _groupLabel(group),
              selected: group == _detailGroup,
              onTap: () => setState(() => _detailGroup = group),
            ),
        ],
      ),
    ),
  );

  static String _groupLabel(BrushSettingsGroup group) => switch (group) {
    BrushSettingsGroup.ink => AppText.strings.brGroupInk,
    BrushSettingsGroup.tip => AppText.strings.brGroupTip,
    BrushSettingsGroup.mixing => AppText.strings.brGroupMixing,
    BrushSettingsGroup.scattering => AppText.strings.brGroupScattering,
    BrushSettingsGroup.texture => AppText.strings.brGroupTexture,
    BrushSettingsGroup.correction => AppText.strings.brGroupCorrection,
  };

  /// Whether [row] stands in the brush in hand at all.
  ///
  /// 🗣️F-478-Q2 (유저 2026-10-27): 「없앤다 — 패널 안 스위치도 같은 법」 — the
  /// rows under a switch are there only while it is on, and the rows under
  /// them moving is the cost the answer took. ↩️They were mounted only while
  /// the switch was on, then went DEAD instead (유저, 반복: 「없다가 생기는 UI
  /// 금지. 자리는 항상 예약하고 내용만 바꾼다」 — the panel jumped under the
  /// finger), until this answer. A row the brush shows stands by this law in
  /// the panel, and the window's rows by it too (I-141).
  bool _stands(BrushSettingsRow row) => switch (row) {
    // How the dabs take the tips (F-176-Q3) — with tips to take: the round
    // tip has none. One tip keeps it: the two laps still draw that tip once.
    BrushSettingsRow.tipOrder => state.tips.isNotEmpty,
    // How many of the tips each turn holds (F-456-Q4) — with two tips to
    // throw between. ↩️It stood DEAD below two.
    BrushSettingsRow.tipsPerTurn => state.tips.length >= 2,
    BrushSettingsRow.mixingMethod => state.mixesGroundColor,
    // The reservoir's three are the mix's alone: a blur picks no colour up
    // (I-75), so by the same answer they are there only under a mix.
    BrushSettingsRow.paintAmount ||
    BrushSettingsRow.paintDensity ||
    BrushSettingsRow.colorStretch => state.shape.picksUpGround,
    // The dual tip's knobs, with a dual tip. ↩️They stood DEAD without one.
    BrushSettingsRow.dualScale ||
    BrushSettingsRow.dualDensity ||
    BrushSettingsRow.dualBlend ||
    BrushSettingsRow.dualRoundness ||
    BrushSettingsRow.dualAngle ||
    BrushSettingsRow.dualSpacing ||
    BrushSettingsRow.dualScatter ||
    BrushSettingsRow.dualScatterCount ||
    BrushSettingsRow.dualScatterBothAxes => state.dualMask != null,
    // The texture's knobs, with a texture. ↩️They stood DEAD without one.
    BrushSettingsRow.textureScale ||
    BrushSettingsRow.textureDensity ||
    BrushSettingsRow.textureMode ||
    BrushSettingsRow.textureInvert ||
    BrushSettingsRow.textureBrightness ||
    BrushSettingsRow.textureContrast => state.textureMaskSource != null,
    // What sits under the 手ブレ補正 (유저 2026-10-20 「적용해제면
    // 손떨림보정쪽 다른 버튼 규칙처럼 비활성화」 — the other buttons' rule,
    // which F-478-Q2 made 「없앤다」). ↩️It stood DIM when off.
    BrushSettingsRow.stabilizer ||
    BrushSettingsRow.steadyingBySpeed => state.correction.steadies,
    // What bends the 後補正, where it corrects. ↩️They stood DEAD at no
    // strength.
    BrushSettingsRow.postBySpeed ||
    BrushSettingsRow.postByViewScale ||
    BrushSettingsRow.postBezier => state.correction.postStrength > 0,
    _ => true,
  };

  /// [row] of the brush in hand.
  Widget _rowOf(BrushSettingsRow row) => switch (row) {
    // ---- インク ----
    BrushSettingsRow.flow => _PanelSlider(
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
    // ---- ブラシ先端 ----
    BrushSettingsRow.tip => BrushTipPickerRow(
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
    BrushSettingsRow.tipOrder => _TipOrderRow(
      state: state,
      onChanged: onChanged,
    ),
    BrushSettingsRow.tipsPerTurn => _PanelSlider(
      label: AppText.strings.brTipsPerTurn,
      value: state.tipsPerTurn.clamp(1, state.tips.length).toDouble(),
      min: 1,
      max: state.tips.length.toDouble(),
      divisions: state.tips.length - 1,
      keyValue: 'brush-tool-tips-per-turn-slider',
      onChanged: (value) =>
          onChanged(state.copyWith(tipsPerTurn: value.round())),
    ),
    BrushSettingsRow.hardness => _PanelSlider(
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
    BrushSettingsRow.antiAlias => _AntiAliasRow(
      value: state.antiAlias,
      onChanged: (step) => onChanged(state.copyWith(antiAlias: step)),
    ),
    BrushSettingsRow.roundness => _PanelSlider(
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
    BrushSettingsRow.angle => _PanelSlider(
      label: AppText.strings.brAngle,
      unit: '°',
      value: BrushToolState.clampAngleDegrees(state.angleDegrees),
      min: BrushToolState.minAngleDegrees,
      max: BrushToolState.maxAngleDegrees,
      keyValue: 'brush-tool-angle-slider',
      onChanged: (value) => onChanged(state.copyWith(angleDegrees: value)),
      // 向き is ONE setting — the angle, the base it turns from and its
      // random turn (F-176-Q1 「클튜처럼 — 「방향」 하나: 기준 + 랜덤」) —
      // and the base and the random turn are behind the button beside it
      // (F-176-Q6 「클튜처럼 — 각도 옆 버튼 하나」). ↩️They were two rows of
      // their own under the angle.
      trailing: TipDirectionButton(
        direction: (
          base: state.rotationMode,
          random: BrushToolState.clampZeroToOne(state.angleJitter),
        ),
        onChanged: (direction) => onChanged(
          state.copyWith(
            rotationMode: direction.base,
            angleJitter: direction.random,
          ),
        ),
      ),
    ),
    BrushSettingsRow.spacing => _PanelSlider(
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
    // ---- 色の混ぜ方 ----
    BrushSettingsRow.mixing => SettingsSwitchRow(
      tileKey: const ValueKey<String>('brush-tool-mixing-toggle'),
      label: AppText.strings.brMixing,
      value: state.mixesGroundColor,
      onChanged: (value) => onChanged(state.copyWith(mixesGroundColor: value)),
    ),
    BrushSettingsRow.mixingMethod => _MixingMethodRow(
      state: state,
      onChanged: onChanged,
    ),
    BrushSettingsRow.paintAmount => _PanelSlider(
      label: AppText.strings.brPaintAmount,
      unit: '%',
      displayScale: 100,
      value: BrushToolState.clampZeroToOne(state.paintAmount),
      min: 0,
      max: 1,
      keyValue: 'brush-tool-paint-amount-slider',
      onChanged: (value) => onChanged(state.copyWith(paintAmount: value)),
      trailing: _pressureButton(BrushPressureTarget.paintAmount),
    ),
    BrushSettingsRow.paintDensity => _PanelSlider(
      label: AppText.strings.brPaintDensity,
      unit: '%',
      displayScale: 100,
      value: BrushToolState.clampZeroToOne(state.paintDensity),
      min: 0,
      max: 1,
      keyValue: 'brush-tool-paint-density-slider',
      onChanged: (value) => onChanged(state.copyWith(paintDensity: value)),
      trailing: _pressureButton(BrushPressureTarget.paintDensity),
    ),
    BrushSettingsRow.colorStretch => _PanelSlider(
      label: AppText.strings.brColorStretch,
      unit: '%',
      displayScale: 100,
      value: BrushToolState.clampZeroToOne(state.colorStretch),
      min: 0,
      max: 1,
      keyValue: 'brush-tool-color-stretch-slider',
      onChanged: (value) => onChanged(state.copyWith(colorStretch: value)),
    ),
    // ---- 散布効果 ----
    BrushSettingsRow.scatter => _PanelSlider(
      // A ratio of the brush size, so scatter keeps its character as
      // the brush grows.
      label: AppText.strings.brScatter,
      unit: '%',
      displayScale: 100,
      value: BrushToolState.clampScatterRadius(state.scatterRadiusRatio),
      min: 0,
      max: 4,
      keyValue: 'brush-tool-scatter-slider',
      onChanged: (value) =>
          onChanged(state.copyWith(scatterRadiusRatio: value)),
    ),
    BrushSettingsRow.scatterCount => _PanelSlider(
      label: AppText.strings.brScatterCount,
      value: BrushToolState.clampScatterCount(state.scatterCount).toDouble(),
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
    BrushSettingsRow.scatterBothAxes => SettingsSwitchRow(
      tileKey: const ValueKey<String>('brush-tool-scatter-both-axes-toggle'),
      label: AppText.strings.brScatterBothAxes,
      value: state.scatterBothAxes,
      onChanged: (value) => onChanged(state.copyWith(scatterBothAxes: value)),
    ),
    // ---- テクスチャ ----
    BrushSettingsRow.dualTip => BrushTipPickerRow(
      label: AppText.strings.brDualTip,
      role: BrushTipRole.dual,
      selected: [?state.dualMask],
      tips: tips,
      onImportRequested: _importTip,
      onRenameTip: _renameTip,
      onDeleteTip: _deleteTip,
      onPicked: (masks) =>
          onChanged(state.withMask(BrushMaskSlot.dual, masks.firstOrNull)),
    ),
    BrushSettingsRow.dualScale => _PanelSlider(
      label: AppText.strings.brScale,
      unit: '%',
      displayScale: 100,
      value: BrushToolState.clampDualMaskScale(state.dualMaskScale),
      min: 0.05,
      max: 10,
      scale: FieldSliderScale.exponential,
      keyValue: 'brush-tool-dual-scale-slider',
      onChanged: (value) => onChanged(state.copyWith(dualMaskScale: value)),
    ),
    // The dual mask's own density, beside its scale — the same pair
    // the texture mask below has had all along. The dual mask used to
    // be an unconditional multiply, which made it the one mask you
    // could only have at full strength.
    BrushSettingsRow.dualDensity => _PanelSlider(
      label: AppText.strings.brTextureDensity,
      unit: '%',
      displayScale: 100,
      value: BrushToolState.clampZeroToOne(state.dualDensity),
      min: 0,
      max: 1,
      keyValue: 'brush-tool-dual-density-slider',
      onChanged: (value) => onChanged(state.copyWith(dualDensity: value)),
    ),
    BrushSettingsRow.dualBlend => _DualBlendRow(
      state: state,
      onChanged: onChanged,
    ),
    // The second tip's way along the path: the first tip's rows of the
    // same names, the same ranges and controls ([BrushShape.secondTip]).
    BrushSettingsRow.dualRoundness => _PanelSlider(
      label: AppText.strings.brRoundness,
      unit: '%',
      displayScale: 100,
      value: BrushToolState.clampRoundness(state.dualRoundness),
      min: BrushToolState.minRoundness,
      max: 1,
      keyValue: 'brush-tool-dual-roundness-slider',
      onChanged: (value) => onChanged(state.copyWith(dualRoundness: value)),
    ),
    BrushSettingsRow.dualAngle => _PanelSlider(
      label: AppText.strings.brAngle,
      unit: '°',
      value: BrushToolState.clampAngleDegrees(state.dualAngleDegrees),
      min: BrushToolState.minAngleDegrees,
      max: BrushToolState.maxAngleDegrees,
      keyValue: 'brush-tool-dual-angle-slider',
      onChanged: (value) => onChanged(state.copyWith(dualAngleDegrees: value)),
      trailing: TipDirectionButton(
        direction: (
          base: state.dualRotationMode,
          random: BrushToolState.clampZeroToOne(state.dualAngleJitter),
        ),
        onChanged: (direction) => onChanged(
          state.copyWith(
            dualRotationMode: direction.base,
            dualAngleJitter: direction.random,
          ),
        ),
      ),
    ),
    BrushSettingsRow.dualSpacing => _PanelSlider(
      label: AppText.strings.brSpacing,
      unit: '%',
      displayScale: 100,
      value: BrushToolState.clampSpacing(state.dualSpacing),
      min: BrushShape.minSpacing,
      max: BrushShape.maxSpacing,
      scale: FieldSliderScale.exponential,
      keyValue: 'brush-tool-dual-spacing-slider',
      onChanged: (value) => onChanged(state.copyWith(dualSpacing: value)),
    ),
    BrushSettingsRow.dualScatter => _PanelSlider(
      label: AppText.strings.brScatter,
      unit: '%',
      displayScale: 100,
      value: BrushToolState.clampScatterRadius(state.dualScatterRadiusRatio),
      min: 0,
      max: 4,
      keyValue: 'brush-tool-dual-scatter-slider',
      onChanged: (value) =>
          onChanged(state.copyWith(dualScatterRadiusRatio: value)),
    ),
    BrushSettingsRow.dualScatterCount => _PanelSlider(
      label: AppText.strings.brScatterCount,
      value: BrushToolState.clampScatterCount(
        state.dualScatterCount,
      ).toDouble(),
      min: 1,
      max: 16,
      divisions: 15,
      keyValue: 'brush-tool-dual-scatter-count-slider',
      onChanged: (value) =>
          onChanged(state.copyWith(dualScatterCount: value.round())),
    ),
    BrushSettingsRow.dualScatterBothAxes => SettingsSwitchRow(
      tileKey: const ValueKey<String>(
        'brush-tool-dual-scatter-both-axes-toggle',
      ),
      label: AppText.strings.brScatterBothAxes,
      value: state.dualScatterBothAxes,
      onChanged: (value) =>
          onChanged(state.copyWith(dualScatterBothAxes: value)),
    ),
    BrushSettingsRow.texture => BrushTipPickerRow(
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
    BrushSettingsRow.textureScale => _PanelSlider(
      label: AppText.strings.brScale,
      unit: '%',
      displayScale: 100,
      value: BrushToolState.clampDualMaskScale(state.textureScale),
      min: 0.05,
      max: 10,
      scale: FieldSliderScale.exponential,
      keyValue: 'brush-tool-texture-scale-slider',
      onChanged: (value) => onChanged(state.copyWith(textureScale: value)),
    ),
    BrushSettingsRow.textureDensity => _PanelSlider(
      label: AppText.strings.brTextureDensity,
      unit: '%',
      displayScale: 100,
      value: BrushToolState.clampZeroToOne(state.textureDensity),
      min: 0,
      max: 1,
      keyValue: 'brush-tool-texture-density-slider',
      onChanged: (value) => onChanged(state.copyWith(textureDensity: value)),
      trailing: _pressureButton(BrushPressureTarget.textureDensity),
    ),
    BrushSettingsRow.textureMode => _TextureModeRow(
      state: state,
      onChanged: onChanged,
    ),
    // The three LEVELS both source formats carry and neither could
    // reach: the importers baked them into the mask, which left no
    // original to re-bake from. Clip Studio calls them 濃度反転 /
    // 明るさ / コントラスト and Photoshop InvT / Brightness / Contrast.
    BrushSettingsRow.textureInvert => SettingsSwitchRow(
      tileKey: const ValueKey<String>('brush-tool-texture-invert-toggle'),
      label: AppText.strings.brTextureInvert,
      value: state.textureInvert,
      onChanged: (value) => onChanged(state.copyWith(textureInvert: value)),
    ),
    BrushSettingsRow.textureBrightness => _PanelSlider(
      label: AppText.strings.brTextureBrightness,
      unit: '%',
      displayScale: 100,
      value: BrushToolState.clampSignedUnit(state.textureBrightness),
      min: -1,
      max: 1,
      keyValue: 'brush-tool-texture-brightness-slider',
      onChanged: (value) =>
          onChanged(state.copyWith(textureBrightness: value)),
    ),
    BrushSettingsRow.textureContrast => _PanelSlider(
      label: AppText.strings.brTextureContrast,
      unit: '%',
      displayScale: 100,
      value: BrushToolState.clampSignedUnit(state.textureContrast),
      min: -1,
      max: 1,
      keyValue: 'brush-tool-texture-contrast-slider',
      onChanged: (value) => onChanged(state.copyWith(textureContrast: value)),
    ),
    // ---- 補正 ----
    // 角をとがらせる, first as in Clip Studio's group: the steadied line and
    // the 後補正 both keep the corners the pen turned (F-418-Q11).
    BrushSettingsRow.sharpenCorners => SettingsSwitchRow(
      tileKey: const ValueKey<String>('brush-tool-sharpen-corners'),
      label: AppText.strings.brSharpenCorners,
      value: state.correction.sharpenCorners,
      onChanged: (on) =>
          _correct(state.correction.copyWith(sharpenCorners: on)),
    ),
    BrushSettingsRow.stabilizerOn => SettingsSwitchRow(
      tileKey: const ValueKey<String>('brush-tool-stabilizer-on'),
      label: AppText.strings.brStabilizerOn,
      value: state.correction.steadies,
      onChanged: (on) => _correct(state.correction.copyWith(steadies: on)),
    ),
    // The brush's own, kept in its preset as Clip Studio keeps it
    // (F-418-Q6). ↩️It was the pull string's rope, a hand-feel setting kept
    // out of presets (P7).
    BrushSettingsRow.stabilizer => _PanelSlider(
      label: AppText.strings.brStabilizer,
      value: BrushToolState.clampCorrection(
        state.correction.stabilization,
        BrushCorrection.maxStabilization,
      ),
      min: 0,
      max: BrushCorrection.maxStabilization,
      // Whole numbers, as Clip Studio sets it (유저 2026-10-21, F-435:
      // 「클튜에선 소수점자리가 없음. 거기까지 조절안함. 우리도 정수로만」).
      divisions: BrushCorrection.maxStabilization.toInt(),
      keyValue: 'brush-tool-stabilizer-slider',
      onChanged: (value) =>
          _correct(state.correction.copyWith(stabilization: value)),
    ),
    // Clip Studio's switch and 補正タイプ under it, as one row.
    // ↩️It dimmed where the line is not steadied, as Clip Studio greys
    // what sits under a switch that is off (F-418).
    BrushSettingsRow.steadyingBySpeed => _SteadyingBySpeedRow(
      value: state.correction.steadyingBySpeed,
      onPick: (value) =>
          _correct(state.correction.copyWith(steadyingBySpeed: value)),
    ),
    BrushSettingsRow.postCorrection => _PanelSlider(
      label: AppText.strings.brPostCorrection,
      value: BrushToolState.clampCorrection(
        state.correction.postStrength,
        BrushCorrection.maxPostStrength,
      ),
      min: 0,
      max: BrushCorrection.maxPostStrength,
      // Whole numbers too: Clip Studio's 後補正 is the same whole 0..100
      // (F-435, by F-34's 「데이터적으로 소수점이 필요없는것들 정수화」).
      divisions: BrushCorrection.maxPostStrength.toInt(),
      keyValue: 'brush-tool-post-correction-slider',
      onChanged: (value) =>
          _correct(state.correction.copyWith(postStrength: value)),
    ),
    BrushSettingsRow.postBySpeed => _postSwitch(
      'brush-tool-post-by-speed-toggle',
      AppText.strings.brPostBySpeed,
      state.correction.postBySpeed,
      (on) => state.correction.copyWith(postBySpeed: on),
    ),
    BrushSettingsRow.postByViewScale => _postSwitch(
      'brush-tool-post-by-view-scale-toggle',
      AppText.strings.brPostByViewScale,
      state.correction.postByViewScale,
      (on) => state.correction.copyWith(postByViewScale: on),
    ),
    BrushSettingsRow.postBezier => _postSwitch(
      'brush-tool-post-bezier-toggle',
      AppText.strings.brPostBezier,
      state.correction.postBezier,
      (on) => state.correction.copyWith(postBezier: on),
    ),
  };

  /// One of the three switches that bend the 後補正.
  Widget _postSwitch(
    String key,
    String label,
    bool value,
    BrushCorrection Function(bool on) change,
  ) => SettingsSwitchRow(
    tileKey: ValueKey<String>(key),
    label: label,
    value: value,
    onChanged: (on) => _correct(change(on)),
  );
}

/// A row of the brush detail window: the eye that shows it in the panel or
/// not, and the row itself — the panel's own, live here as there (Clip
/// Studio's サブツール詳細 edits as its palette does).
///
/// ⛔NOT a hand-rolled eye: the app's one ([LayerVisibilityToggleButton],
/// F-58 「비지블버튼은 다른곳에서도 쓰니까 공용화/통일화」), its off colour
/// with it.
class _EyedRow extends StatelessWidget {
  const _EyedRow({
    super.key,
    required this.row,
    required this.shown,
    required this.onToggle,
    required this.child,
  });

  final BrushSettingsRow row;
  final bool shown;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    // At the row's top, level with its control: the gap under a row is
    // the row's own.
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LayerVisibilityToggleButton(
        name: 'brush-detail-eye-${row.name}',
        isVisible: shown,
        tooltip: shown
            ? AppText.strings.brHideFromPanel
            : AppText.strings.brShowInPanel,
        onToggle: onToggle,
      ),
      const SizedBox(width: ToolSettingColumns.gap),
      Expanded(child: child),
    ],
  );
}

/// Which tip each dab takes — Clip Studio's 繰り返し方法, all six (F-176-Q3
/// 「클튜 여섯 전부 + 끌어서 순서」), in the order Clip Studio lists them.
///
/// 🗣️F-478-Q2 (유저 2026-10-27): 「없앤다 — 패널 안 스위치도 같은 법」 —
/// there only with tips to take turns: the round tip has none. One tip
/// keeps it: the two laps still draw that tip once. ↩️It stood DEAD for the
/// round tip (「없다가 생기는 UI 금지」).
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
    BrushTipOrder.lean => AppText.strings.brTipOrderLean,
  };

  @override
  Widget build(BuildContext context) => ToolSettingRow(
    label: AppText.strings.brTipOrder,
    child: PanelFlyoutButton(
      key: const ValueKey<String>('brush-tool-tip-order-menu-button'),
      label: _labelFor(state.tipOrder),
      expand: true,
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

/// テクスチャの合成モード — the paper multiplied into the coverage, or its
/// HEIGHT cutting the silhouette ([BrushTextureMode], F-451). There only
/// with a texture to meet, as the texture's sliders above it (F-478-Q2).
class _TextureModeRow extends StatelessWidget {
  const _TextureModeRow({required this.state, required this.onChanged});

  final BrushToolState state;
  final ValueChanged<BrushToolState> onChanged;

  String _labelFor(BrushTextureMode mode) => switch (mode) {
    BrushTextureMode.multiply => SeparableBlendMode.multiply.labelFor(
      AppText.language,
    ),
    BrushTextureMode.height => AppText.strings.brTextureModeHeight,
  };

  @override
  Widget build(BuildContext context) => ToolSettingChoiceRow<BrushTextureMode>(
    tool: 'brush-tool',
    name: 'texture-mode',
    label: AppText.strings.brTextureMode,
    current: state.textureMode,
    answers: [
      for (final mode in BrushTextureMode.values)
        (value: mode, key: mode.name, label: _labelFor(mode)),
    ],
    onPick: (mode) => () => onChanged(state.copyWith(textureMode: mode)),
  );
}

/// 混色の方式 — the reservoir's 下地混色, or a blur (I-75,
/// [BrushMixingMethod]) — there only while mixing is on (F-478-Q2).
class _MixingMethodRow extends StatelessWidget {
  const _MixingMethodRow({required this.state, required this.onChanged});

  final BrushToolState state;
  final ValueChanged<BrushToolState> onChanged;

  String _labelFor(BrushMixingMethod method) => switch (method) {
    BrushMixingMethod.mix => AppText.strings.brMixingMix,
    BrushMixingMethod.blur => AppText.strings.brMixingBlur,
  };

  @override
  Widget build(BuildContext context) =>
      ToolSettingChoiceRow<BrushMixingMethod>(
        tool: 'brush-tool',
        name: 'mixing-method',
        label: AppText.strings.brMixingMethod,
        current: state.mixingMethod,
        answers: [
          for (final method in BrushMixingMethod.values)
            (value: method, key: method.name, label: _labelFor(method)),
        ],
        onPick: (method) =>
            () => onChanged(state.copyWith(mixingMethod: method)),
      );
}

/// 速度による手ブレ補正 — none, or which way the pen's speed bends the
/// steadying ([BrushSteadyingBySpeed]).
class _SteadyingBySpeedRow extends StatelessWidget {
  const _SteadyingBySpeedRow({required this.value, required this.onPick});

  final BrushSteadyingBySpeed value;
  final ValueChanged<BrushSteadyingBySpeed> onPick;

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
        onPick: (type) => () => onPick(type),
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

  /// ↩️It was nullable to make a row DEAD rather than absent, for the rows a
  /// switch above leaves with nothing to say — which are absent now
  /// (F-478-Q2, 유저 2026-10-27 「없앤다 — 패널 안 스위치도 같은 법」).
  final ValueChanged<double> onChanged;
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
      FieldSlider.handsReach + _trailingGap + SettingSourceButton.slotWidth;

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
/// ⛔A `PanelFlyoutButton` row, the shape this panel already uses for the tip
/// order. Twelve entries is what a flyout is for; the segmented button
/// above is for the four-way edge step, and a third control shape would be
/// a new convention for no reason.
class _DualBlendRow extends StatelessWidget {
  const _DualBlendRow({required this.state, required this.onChanged});

  final BrushToolState state;
  final ValueChanged<BrushToolState> onChanged;

  @override
  Widget build(BuildContext context) {
    final language = AppText.language;
    // There only with a dual tip, as the two sliders above it (F-478-Q2).
    // ↩️It stood DEAD without one (「없다가 생기는 UI 금지」 — the mask rows
    // had mounted only once a mask was picked, which shoved four rows under
    // the finger that had just come back from the popup), until the answer
    // took that cost.
    // A row of the grid like the rotation's ([ToolSettingRow]). ↩️It wrote
    // its own: the name, and the button as wide as its word at the end.
    return ToolSettingRow(
      label: AppText.strings.brDualBlend,
      child: PanelFlyoutButton(
        key: const ValueKey<String>('brush-tool-dual-blend-menu-button'),
        label: state.dualCompositeMode.labelFor(language),
        expand: true,
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
