import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/brush_blend_mode.dart';
import '../../models/brush_pressure_curve.dart';
import '../../models/brush_shape.dart';
import '../canvas/canvas_capsule.dart';
import '../panels/tool_size_preset_panel.dart';
import '../shortcuts/editor_action_registry.dart' show blendModeActionId;
import '../sliced_value_listenable_builder.dart';
import '../text/app_strings.dart';
import '../text/model_vocabulary.dart';
import '../timeline/axis_turn.dart' show alongBox, sizedAlong;
import '../widgets/field_slider.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/pressure_curve_popup.dart';
import '../widgets/setting_source_button.dart';
import '../widgets/strip_group_rule.dart';
import '../widgets/value_hands.dart' show ValuePencil;
import 'brush_tool_state.dart';

/// How long the size bar and the opacity bar each stand — their width
/// lying, their height stood.
typedef BrushBarWidths = ({double size, double opacity});

/// The size bar and the opacity bar, as one place lays them.
typedef BrushBars = ({FieldSlider size, FieldSlider opacity});

/// The pill's links from each bar to the bubble its number stands in
/// ([FieldSliderBubble]).
typedef BrushBarBubbles = ({FieldSliderBubble size, FieldSliderBubble opacity});

/// How a bar stands where it is laid: the place's [BrushValuesLayout], its
/// thickness there, and its bubble where its number stands beside it.
typedef _BarStand = ({
  BrushValuesLayout layout,
  double thickness,
  FieldSliderBubble? bubble,
});

/// What the bars show of the state ([BrushValueBars.build]).
typedef _BarsSlice = (bool, bool, bool, double, double, BrushShape);

/// Where the brush's values stand, and so how they are laid.
enum BrushValuesLayout {
  /// The top strip: the two bars side by side, lying, each with its curve
  /// after it.
  strip,

  /// The strip's group button's popover: one bar over the other, lying.
  popover,

  /// The canvas's brush pill (I-34): one column, each bar stood up with its
  /// number alone — beside it, in a bubble (I-135) — and its ± and its
  /// curve under it.
  pill;

  /// Whether the bars stand.
  bool get stood => this == pill;

  /// The way the bars run.
  Axis get axis => stood ? Axis.vertical : Axis.horizontal;

  /// What the bars' keys begin with — the strip's own for the two places
  /// that are the strip's.
  String get _keyPrefix => stood ? 'brush-pill' : 'top-strip';
}

/// Size and opacity, each followed by its pressure curve button.
///
/// Bars rather than value buttons: these are set WHILE drawing, against a
/// test mark on the canvas, and an anchored popover closes on the first
/// pointer-down outside it (R27 #5) — a button would force open-adjust-
/// close-draw every time. [FieldSlider] already puts the name and the
/// number inside the track, so one 140px run says everything.
///
/// The pressure buttons came WITH them from the tool settings panel (유저
/// 확정): a curve belongs beside the value it shapes, and splitting them
/// across two surfaces would mean setting a size here and asking how the
/// pen affects it over there.
///
/// Its own listener: a size drag must not rebuild the popover buttons or
/// re-read the project name beside them.
///
/// ↩️It was the top strip's own until the canvas's pill took the same
/// bars (I-34, 2026-10-18): ONE group of bars for every place they stand,
/// laid as the place asks ([layout]).
class BrushValueBars extends StatelessWidget {
  const BrushValueBars({
    super.key,
    required this.brushTool,
    required this.widths,
    this.layout = BrushValuesLayout.strip,
    this.bubbles,
  }) : assert(
         (bubbles != null) == (layout == BrushValuesLayout.pill),
         'the pill\'s bars, and only they, write their numbers in bubbles',
       );

  final ValueNotifier<BrushToolState> brushTool;

  /// How long the two bars stand — [full] where the strip has room; the
  /// pill's one length for both ([pillTrackIn] and the ± under it).
  final BrushBarWidths widths;

  /// Side by side in the strip; one over the other in the group's popover;
  /// stood, one over the other, in the canvas's pill.
  final BrushValuesLayout layout;

  /// The pill's links to the bubbles its bars' numbers stand in
  /// ([BrushValuesPill]); null in the strip and its popover, whose bars
  /// write their own.
  final BrushBarBubbles? bubbles;

  /// A bar at its full width — its track as it was at 140 and its pencil
  /// after it ([ValuePencil.reach]), so a bar that took its pencil writes
  /// in the room it always had (at twice the OS text its widest number
  /// ran past its track without it).
  static const double fullBar = 140 + ValuePencil.reach;
  static const BrushBarWidths full = (size: fullBar, opacity: fullBar);

  /// A lying bar's thickness — the strip's and its popover's.
  static const double barHeight = 42;
  static const double gap = 4;

  /// Between two lines laid one over the other — the popover's.
  static const double lineGap = 6;

  /// Everything beside the two bars when they stand side by side: a
  /// pressure button after each, and the gaps.
  static const double fixedWidth =
      gap +
      SettingSourceButton.slotWidth +
      gap +
      gap +
      SettingSourceButton.slotWidth;

  /// A stood bar's thickness at 1× — the pill's, and every other part of
  /// the pill is as wide.
  ///
  /// 🗣️유저 2026-10-18 (I-34): 「크기나 압력이나 다른 버튼이나 알약에
  /// 맞출수있어? 슬라이더는 특히 표준 버튼정도가 슬림하고 적당한거같은데」 —
  /// as slim as the x-sheet's blend chip stood up (its 「표준」), which is 20.
  static const double _stoodThickness = 20;

  /// [_stoodThickness] as it is shown: grown with the OS text, as a bar's
  /// one line is ([FieldSlider.growthIn]).
  static double stoodThicknessIn(BuildContext context) =>
      _stoodThickness + FieldSlider.growthIn(context);

  /// The size bar as [stand] lays it — the one a place shows, and the one
  /// its measures read.
  static FieldSlider _sizeBar(
    _BarStand stand, {
    required double value,
    required ValueChanged<double>? onChanged,
  }) => FieldSlider(
    key: ValueKey<String>('${stand.layout._keyPrefix}-size-bar'),
    label: AppText.strings.brSize,
    value: value,
    min: BrushToolState.minSize,
    max: BrushToolState.maxSize,
    // Equal travel multiplies the value, so the left half covers the small
    // sizes where a pixel matters.
    scale: FieldSliderScale.exponential,
    // F-325 (유저 2026-10-09): the +/− and the wheel step through the tool
    // size panel's rack, as it is.
    stops: ToolSizePresetPanel.presets,
    // 🗣️I-125-Q1 (유저 2026-10-23): in the pill, 「px는 필요없어보임」 — and
    // its bubble writes 「<20.0」 (I-135).
    unit: stand.layout.stood ? '' : ' px',
    height: stand.thickness,
    axis: stand.layout.axis,
    // 🗣️I-34 (유저 2026-10-18): 「숫자만으로 하자」 — the pill's bars.
    nameInside: !stand.layout.stood,
    bubble: stand.bubble,
    onChanged: onChanged,
  );

  /// The opacity bar as [stand] lays it — as [_sizeBar]. In the pill its
  /// number stands alone, no % (F-460, 유저 2026-10-23: 「불투명도는 %
  /// 없앰」 — ↩️I-125-Q1 had kept it, 「%는 괜찮은데」).
  static FieldSlider _opacityBar(
    _BarStand stand, {
    required double value,
    required ValueChanged<double>? onChanged,
  }) => FieldSlider.opacity(
    key: ValueKey<String>('${stand.layout._keyPrefix}-opacity-bar'),
    label: AppText.strings.brOpacity,
    value: value,
    height: stand.thickness,
    axis: stand.layout.axis,
    nameInside: !stand.layout.stood,
    bubble: stand.bubble,
    onChanged: onChanged,
  );

  /// The two bars as [layout] writes them, at the ends of their ranges —
  /// what the measures below read.
  static BrushBars _measured(BrushValuesLayout layout, double thickness) {
    final stand = (layout: layout, thickness: thickness, bubble: null);
    return (
      size: _sizeBar(stand, value: BrushToolState.maxSize, onChanged: null),
      opacity: _opacityBar(stand, value: 1, onChanged: null),
    );
  }

  /// The narrowest each bar goes: where it still writes its name and its
  /// widest number whole ([FieldSlider.narrowestIn]).
  ///
  /// Each its OWN: the answer's words are 「이름과 숫자가 막대 안에 들어가는
  /// 최소 폭」, and the two bars do not write the same words.
  ///
  /// Never past [fullBar]: where the writing asks for more than the full
  /// bar (a long name under a large OS text size) there is nothing to
  /// narrow, and the bar cuts its name short at 140 as it always has.
  static BrushBarWidths narrowestIn(BuildContext context) {
    double of(FieldSlider bar) =>
        math.min(fullBar, bar.narrowestIn(context));
    final bars = _measured(BrushValuesLayout.strip, barHeight);
    return (size: of(bars.size), opacity: of(bars.opacity));
  }

  /// The pill's bars' one TRACK: as long as the longer of the two's widest
  /// number would stand in it, a glyph to a cell
  /// ([FieldSlider.standingRunIn]) — so the two stand alike. Their ± stand
  /// under it ([FieldSlider.bubbleHandsReach]).
  ///
  /// 🗣️I-34 (유저 2026-10-18): 「크기랑 불투명도 막대길이 다른거
  /// 신경쓰이니 길이는 통일하는방향. 그리고 가로길이 좀 더 슬림하게
  /// 할수있나? 최대한 슬림했으면」.
  ///
  /// ↩️The numbers stood IN the tracks (I-125 → F-460) until they stepped
  /// out beside them, into their bubbles (I-135); the tracks kept the
  /// length the numbers had given them. ⚠️Keeping it was my call — the
  /// card asked nothing of the length.
  static double pillTrackIn(BuildContext context) {
    final bars = _measured(BrushValuesLayout.pill, stoodThicknessIn(context));
    return math
        .max(
          bars.size.standingRunIn(context),
          bars.opacity.standingRunIn(context),
        )
        .ceilToDouble();
  }

  /// The pill's bubbles' one width: the widest number either bar says,
  /// whole ([FieldSliderValueBubble.widthIn]) — 「불투명도도 그 고정크기로
  /// 통일」 (I-135).
  static double bubbleWidthIn(BuildContext context) {
    final bars = _measured(BrushValuesLayout.pill, stoodThicknessIn(context));
    return FieldSliderValueBubble.widthIn(context, [bars.size, bars.opacity]);
  }

  /// What the bars show of [state] — a drag elsewhere, or a colour, moves
  /// none of them ([build]).
  static _BarsSlice _sliceOf(BrushToolState state) => (
    state.supports(ToolParameter.size),
    state.supports(ToolParameter.opacity),
    state.supports(ToolParameter.pressure),
    BrushToolState.clampSize(state.activeSize),
    BrushToolState.clampOpacity(state.activeOpacity),
    state.shape.copyWith(color: 0),
  );

  /// The two bars as this place lays them from [state] — the ones it
  /// shows, and the ones the pill's bubbles read their numbers off.
  ///
  /// ⛔Every write reads the notifier when it happens, never [state] — a
  /// field outside the slice may have moved since it was built.
  BrushBars _barsFor(BuildContext context, BrushToolState state) {
    final thickness = layout.stood ? stoodThicknessIn(context) : barHeight;
    return (
      size: _sizeBar(
        (layout: layout, thickness: thickness, bubble: bubbles?.size),
        // The ACTIVE tool's size, as the bar beside it is the active
        // tool's opacity: the shape tool's plain line keeps its own.
        value: BrushToolState.clampSize(state.activeSize),
        onChanged: state.supports(ToolParameter.size)
            ? (value) =>
                  brushTool.value = brushTool.value.withActiveSize(value)
            : null,
      ),
      opacity: _opacityBar(
        (layout: layout, thickness: thickness, bubble: bubbles?.opacity),
        // TP1: the ACTIVE tool's opacity — the fill and the stamp keep
        // their own, so this bar stops being the brush's alone (유저: 툴마다
        // 기억하게해서 필 툴도 불투명도 설정하면 그걸로 채워지게).
        value: BrushToolState.clampOpacity(state.activeOpacity),
        onChanged: state.supports(ToolParameter.opacity)
            ? (value) =>
                  brushTool.value = brushTool.value.withActiveOpacity(value)
            : null,
      ),
    );
  }

  /// The two bars' widths where [room] is what they may take between them:
  /// [full] where there is room; where there is not, each gives up the same
  /// share of what it can spare, so both reach their [narrowest] together;
  /// and null where even those do not fit.
  ///
  /// In whole pixels, rounded down — a bar's edge stays on the grid, and
  /// the two never take more than [room]. (The pixel that rounding can take
  /// from a bar at its narrowest comes out of the breath between its name
  /// and its number, never out of either.)
  static BrushBarWidths? widthsIn(double room, BrushBarWidths narrowest) {
    final short = fullBar * 2 - room;
    if (short <= 0) {
      return full;
    }
    final spare = fullBar * 2 - narrowest.size - narrowest.opacity;
    if (short > spare) {
      return null;
    }
    final share = short / spare;
    double narrowed(double least) =>
        (fullBar - (fullBar - least) * share).floorToDouble();
    return (
      size: narrowed(narrowest.size),
      opacity: narrowed(narrowest.opacity),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 🚨Sliced to what the bars SHOW (2026-09-26): the whole state moved them
    // on every colour-wheel frame and every other bar's drag, two bars and
    // two curve buttons rebuilt for news none of them draws. The curves are
    // the shape's, so the shape stands for them — with its COLOUR set aside,
    // because the colour lives in the shape too and is the one field that
    // moves every frame of a colour-wheel drag.
    // ⛔Every write reads the notifier when it happens, never the builder's
    // state — a field outside the slice may have moved since it was built.
    return SlicedValueListenableBuilder<BrushToolState, _BarsSlice>(
      valueListenable: brushTool,
      slice: _sliceOf,
      builder: (context, state) {
        // TP2: one group, and each member is DIMMED rather than hidden when
        // the armed tool has no use for it (유저: 뭐가 적용되고 뭐가
        // 적용안되는지 몰라할거같으니까 … 적용안되는툴이나 모드면
        // 비활성화시키도록). The table lives on the state — see
        // [BrushToolState.supports] — so the strip cannot disagree with the
        // commit about what a tool reads.
        //
        // Dimmed, never removed: a control that comes and goes is one you
        // have to look for, and the layout would jump every tool switch.
        final pressureOn = state.supports(ToolParameter.pressure);
        Widget pressure(BrushPressureTarget target) {
          return PressureCurveButton(
            keyValue: 'brush-tool-pressure-${target.name}',
            target: target,
            curves: state.targetCurves(target),
            enabled: pressureOn,
            onChanged: (curves) => brushTool.value = brushTool.value
                .withTargetCurves(target, curves),
          );
        }

        Widget placed(double length, FieldSlider bar) => sizedAlong(
          layout.axis,
          along: length,
          across: bar.height,
          child: bar,
        );
        final bars = _barsFor(context, state);
        // Along the line: a bar, then its curve — after it lying, under it
        // stood.
        final step = alongBox(layout.axis, gap);
        final sizeLine = [
          placed(widths.size, bars.size),
          step,
          pressure(BrushPressureTarget.size),
        ];
        final opacityLine = [
          placed(widths.opacity, bars.opacity),
          step,
          pressure(BrushPressureTarget.opacity),
        ];
        return switch (layout) {
          BrushValuesLayout.strip => Row(
            mainAxisSize: MainAxisSize.min,
            children: [...sizeLine, step, ...opacityLine],
          ),
          BrushValuesLayout.popover => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: sizeLine),
              const SizedBox(height: lineGap),
              Row(mainAxisSize: MainAxisSize.min, children: opacityLine),
            ],
          ),
          // Every part centred across the pill (유저 2026-10-18: 「넘치더라도
          // 알약에서 가로로 중앙정렬이도록」).
          BrushValuesLayout.pill => Column(
            mainAxisSize: MainAxisSize.min,
            children: [...sizeLine, step, ...opacityLine],
          ),
        };
      },
    );
  }
}

/// The blend mode and its lock — at the strip's left-most right-group
/// slot, and at the head of the canvas's pill.
///
/// The BRUSH BLEND dropdown (BB-2) moved here whole from the tool settings
/// panel (유저 확정) — the PS/CSP vocabulary where the LABEL is the current
/// mode, plus the pin that keeps a brush on one blend. A named button beats
/// the icon popover the strip briefly wore: a blend you cannot read without
/// opening it is a blend you check by opening it.
///
/// It is one of the three settings a preset deliberately never carries
/// (R26 #10), which is what makes it belong out here with the hand's other
/// standing choices rather than inside a preset.
///
/// The width is FIXED (유저 확정): the label is the mode name, and letting
/// the button breathe with the text meant every blend change shoved the
/// bars beside it sideways. Long names ellipsize instead.
class BrushBlendModeControl extends StatelessWidget {
  const BrushBlendModeControl({
    super.key,
    required this.brushTool,
    this.axis = Axis.horizontal,
    this.length = buttonWidth,
    this.thickness,
  });

  final ValueNotifier<BrushToolState> brushTool;

  /// Which way it reads: lying in the strip; stood in the pill, its word
  /// down the vertical-writing table as the x-sheet's blend chip writes
  /// its own (I-34).
  final Axis axis;

  /// Its FIXED extent along [axis] — [buttonWidth] in the strip; the pill's
  /// bars' track there, so the chip is as long as what it heads.
  final double length;

  /// Its extent across, stood — the pill's parts' thickness. Null lying:
  /// the button's own height.
  final double? thickness;

  /// Wider than the label needs on average, so the common modes read whole
  /// and only the long ones are cut.
  static const double buttonWidth = 116;

  @override
  Widget build(BuildContext context) {
    final stood = axis == Axis.vertical;
    Widget fixed(Widget child) => SizedBox(
      width: stood ? thickness : length,
      height: stood ? length : null,
      child: child,
    );
    // Sliced to what the button SHOWS, like the bars beside it — and its
    // pick reads the notifier when it happens, never the builder's state.
    return SlicedValueListenableBuilder<
      BrushToolState,
      (bool, BrushBlendMode)
    >(
      valueListenable: brushTool,
      slice: (state) => (state.blendIsAChoice, state.activeBlendMode),
      builder: (context, state) {
        final language = AppText.settings.value.programLanguage;
        // TP2: tools that composite nothing get the control DIMMED, not an
        // empty gap. It used to be shown for every one of them (a dropdown
        // answering a question nobody downstream asked), then reserved as
        // blank space — and blank space says nothing about why. Dim says
        // "this exists and does not apply here", which is the question the
        // user actually had: 뭐가 적용되고 뭐가 적용안되는지. The eraser's
        // stands dimmed on its one mode ([BrushToolState.blendIsAChoice]).
        final blendOn = state.blendIsAChoice;
        final mode = state.activeBlendMode;
        return fixed(
          PanelFlyoutButton(
            key: const ValueKey<String>('brush-tool-blend-menu-button'),
            label: mode.labelFor(language),
            tooltip: AppText.strings.brBlendMode,
            enabled: blendOn,
            axis: axis,
            // Stood, the x-sheet's blend chip's room around its word — the
            // chip the pill is as slim as.
            padding: stood
                ? const EdgeInsets.symmetric(horizontal: 2, vertical: 3)
                : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            // `expand` is what makes the fixed box hold: the label
            // becomes Flexible inside it, so it ellipsizes rather than
            // overflowing the width the strip budgeted.
            expand: true,
            // ONE list for every tool that composites — TS8 유저 법:
            // 「블렌드모드가 존재한다면 다 공통이야. 지우개만 이레이저만
            // 남기는거고. 나머지는 이레이저 포함 다 있어.」 The stamp
            // joining `toolHasBlendMode` is all it took: the eraser's
            // one mode is the button dimmed on it, so this list needs no
            // per-tool filter to obey that law.
            entriesBuilder: () => BrushBlendMode.values.asFlyoutValueChoices(
              current: mode,
              // 🗣️I-31 made every mode an action (F1–F12); the row it is
              // picked from says so, as every button does (I-40).
              choiceOf: (candidate) => PanelFlyoutChoice(
                key: 'brush-tool-blend-${candidate.name}',
                label: candidate.labelFor(language),
                shortcuts: [blendModeActionId(candidate)],
              ),
              // Writes to whichever drawer the armed tool owns — the
              // BRUSH's is its own shape, so the mode picked here is
              // the mode that brush keeps and exports. The button
              // never names a tool (유저 확정: 블렌드모드 선택도 툴에
              // 산다).
              onPicked: (candidate) =>
                  brushTool.value =
                      brushTool.value.withActiveBlendMode(candidate),
            ),
          ),
        );
      },
    );
  }
}

/// The brush's values on the canvas — its blend, its size and its opacity,
/// one slim column at the canvas's left edge, centred on the room there.
///
/// 🗣️I-34 (유저 2026-10-18): the place the brush's values stand by
/// default — 「그리고 기본값은 알약으로 두는걸 기본값으로」 — drawn and
/// taken as https://claude.ai/artifact/UKKCxHqAwhRAXgpK9b6twP. The top
/// strip holds them instead where the workspace says so
/// ([BrushValuesLayout.strip]). A capsule as the view pill is, ringed and
/// opaque, so what it covers is cover to the canvas's framing.
///
/// Its bars' numbers stand BESIDE them, each in a bubble at its value
/// (I-135, [FieldSliderValueBubble]), in a lane to the capsule's right.
class BrushValuesPill extends StatefulWidget {
  const BrushValuesPill({super.key, required this.brushTool});

  final ValueNotifier<BrushToolState> brushTool;

  /// How wide the pill stands: its parts' thickness, and the ring's room
  /// inside it on each side — the view pill's ([CanvasCapsule.barPillEnd]).
  ///
  /// The capsule's width, and so the framing's band
  /// ([CanvasEdgePill.width]): the bubbles beside it stand outside the
  /// band. ⚠️My call — they are two numbers over the drawing, and a band as
  /// wide as them would frame all of the drawing a bubble's width further
  /// in for them.
  static double widthIn(BuildContext context) =>
      BrushValueBars.stoodThicknessIn(context) + CanvasCapsule.barPillEnd * 2;

  /// From the capsule's edge to a bubble's point.
  static const double _bubbleBreath = 2;

  @override
  State<BrushValuesPill> createState() => _BrushValuesPillState();
}

class _BrushValuesPillState extends State<BrushValuesPill> {
  /// Each bar's link to its bubble, kept while the pill stands.
  final BrushBarBubbles _bubbles = (
    size: FieldSliderBubble(),
    opacity: FieldSliderBubble(),
  );

  @override
  Widget build(BuildContext context) {
    final track = BrushValueBars.pillTrackIn(context);
    final length = track + FieldSlider.bubbleHandsReach;
    final bars = BrushValueBars(
      brushTool: widget.brushTool,
      widths: (size: length, opacity: length),
      layout: BrushValuesLayout.pill,
      bubbles: _bubbles,
    );
    final bubbleWidth = BrushValueBars.bubbleWidthIn(context);
    final lane =
        BrushValuesPill._bubbleBreath +
        FieldSliderValueBubble.point +
        bubbleWidth;
    // The lane stands as tall as the pill, so a bubble at either end of its
    // bar is still inside a box that takes a press — and holds nothing but
    // the bubbles, so the drawing under the rest of it still takes the pen.
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(right: lane),
          child: _capsule(context, track: track, bars: bars),
        ),
        Positioned(
          top: 0,
          right: 0,
          bottom: 0,
          width: lane,
          child: _BrushValueBubbles(
            bars: bars,
            width: bubbleWidth,
            // The track's edge is the ring's room in from the capsule's.
            reach: CanvasCapsule.barPillEnd + BrushValuesPill._bubbleBreath,
          ),
        ),
      ],
    );
  }

  /// The capsule: the blend over the [bars], as long as their [track].
  Widget _capsule(
    BuildContext context, {
    required double track,
    required BrushValueBars bars,
  }) => CanvasCapsule(
    keyValue: 'canvas-brush-pill',
    width: BrushValuesPill.widthIn(context),
    child: Padding(
      padding: const EdgeInsets.all(CanvasCapsule.barPillEnd),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // As long as the bars' TRACK — their ± are under it.
          BrushBlendModeControl(
            brushTool: widget.brushTool,
            axis: Axis.vertical,
            length: track,
            thickness: BrushValueBars.stoodThicknessIn(context),
          ),
          const SizedBox(height: StripGroupRule.margin),
          const StripGroupRule(run: Axis.vertical),
          const SizedBox(height: StripGroupRule.margin),
          bars,
        ],
      ),
    ),
  );
}

/// The pill's bars' numbers, each in its bubble beside its bar
/// ([FieldSliderValueBubble]): read off the bars as [bars] lays them, from
/// the same slice of the state, so a bubble and its bar say one number.
class _BrushValueBubbles extends StatelessWidget {
  const _BrushValueBubbles({
    required this.bars,
    required this.width,
    required this.reach,
  });

  /// The pill's bars, with their bubbles.
  final BrushValueBars bars;
  final double width;
  final double reach;

  @override
  Widget build(BuildContext context) =>
      SlicedValueListenableBuilder<BrushToolState, _BarsSlice>(
        valueListenable: bars.brushTool,
        slice: BrushValueBars._sliceOf,
        builder: (context, state) {
          final laid = bars._barsFor(context, state);
          final prefix = bars.layout._keyPrefix;
          return Stack(
            children: [
              FieldSliderValueBubble(
                keyValue: '$prefix-size-bubble',
                bar: laid.size,
                width: width,
                reach: reach,
              ),
              FieldSliderValueBubble(
                keyValue: '$prefix-opacity-bubble',
                bar: laid.opacity,
                width: width,
                reach: reach,
              ),
            ],
          );
        },
      );
}
