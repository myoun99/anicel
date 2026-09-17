import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/onion_skin_settings.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart';
import '../input/control_press_claim.dart';
import '../widgets/axis_bar_gesture.dart';
import '../widgets/color_swatch_button.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/static_raster.dart';
import '../layout/device_grid.dart';
import '../widgets/superellipse_clip.dart';

/// The onion-skin dock panel: the light-table graph every 2D package
/// speaks (TVPaint's light table, Krita's onion docker) — ONE strip
/// centred on the current drawing with EVERY peg on screen at once, before
/// pegs left, after pegs right, each peg's bar height being its opacity,
/// the percentage printed along the strip's floor and the peg's index
/// under it.
///
/// Tap a bar to silence it (tap again to bring back the value it had),
/// drag it up/down to set that peg's opacity. Zero is a legal value and
/// the only "off" there is — a peg can't be on and invisible at once.
///
/// Above the graph: what a peg step counts (drawing blocks or raw frames),
/// the Colors/Images mode, and each side's tint on the shared color-wheel
/// swatch.
///
/// There is NO master switch (UI-R17 #5): onion applies PER LAYER via the
/// timeline rows' toggles — this panel only shapes the ghosts.
class OnionSkinPanel extends StatelessWidget {
  const OnionSkinPanel({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.currentColorOf,
  });

  final OnionSkinSettings settings;
  final ValueChanged<OnionSkinSettings> onChanged;

  /// The tool's colour, for the picker's 「현재 색 반영」 — see
  /// [ColorSwatchButton.currentColorOf] for why it is a callback.
  final int Function() currentColorOf;

  static String _stepLabel(OnionSkinStep step) => switch (step) {
    OnionSkinStep.blocks => 'Blocks',
    OnionSkinStep.frames => 'Frames',
  };

  static String _modeLabel(OnionSkinMode mode) => switch (mode) {
    OnionSkinMode.colors => 'Colors',
    OnionSkinMode.images => 'Images',
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      // ⚠️Quantized because this panel scrolls: the scroll body
      // cancels the OFFSET fraction and nothing else, so an
      // unquantized padding keeps its own. 8 × 1.35 = 10.8.
      padding: EdgeInsets.all(DeviceGrid.of(context).position(8)),
      // This panel is baked like every other, and its history is worth a
      // line because it was the one that would not: the parity test found
      // a band inside the strip that was present painting through and
      // transparent when baked, so the bake was switched off here rather
      // than shipped unexplained.
      //
      // The cause was not in this file. `StaticRaster` was blitting its
      // capture at whatever fractional device rectangle layout gave it,
      // which nearest-neighbour resampling then snapped — and this panel,
      // being 117 logical pixels tall, is a fractional number of device
      // pixels at every display scaling except 100% and 200%. It just
      // happened to be the panel that showed it. See the measurements in
      // `static_raster_parity_test.dart`.
      child: StaticRaster(
        debugLabel: 'body:onion',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Flexible(
                  child: PanelFlyoutButton(
                    key: const ValueKey<String>('onion-step-button'),
                    label: _stepLabel(settings.step),
                    tooltip: AppText.strings.onionPegCountHelp,
                    expand: true,
                    entriesBuilder: () => OnionSkinStep.values.asFlyoutChoices(
                      current: settings.step,
                      keyPrefix: 'onion-step-',
                      labelOf: (step) => switch (step) {
                        OnionSkinStep.blocks => 'Blocks (drawings)',
                        OnionSkinStep.frames => 'Frames',
                      },
                      onPicked: (step) =>
                          onChanged(settings.copyWith(step: step)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: PanelFlyoutButton(
                    key: const ValueKey<String>('onion-mode-button'),
                    label: _modeLabel(settings.mode),
                    tooltip: AppText.strings.onionGhostColorHelp,
                    expand: true,
                    entriesBuilder: () => OnionSkinMode.values.asFlyoutChoices(
                      current: settings.mode,
                      keyPrefix: 'onion-mode-',
                      labelOf: _modeLabel,
                      onPicked: (mode) =>
                          onChanged(settings.copyWith(mode: mode)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ColorSwatchButton(
                  keyValue: 'onion-tint-before',
                  tooltip: AppText.strings.onionBeforeTint,
                  color: settings.tintBefore,
                  currentColorOf: currentColorOf,
                  onChanged: (color) =>
                      onChanged(settings.copyWith(tintBefore: color)),
                ),
                const SizedBox(width: 6),
                ColorSwatchButton(
                  keyValue: 'onion-tint-after',
                  tooltip: AppText.strings.onionAfterTint,
                  color: settings.tintAfter,
                  currentColorOf: currentColorOf,
                  onChanged: (color) =>
                      onChanged(settings.copyWith(tintAfter: color)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _OnionFalloffStrip(settings: settings, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// The peg at [index] — slots past a short list read as silent, so the
/// strip can always offer all [OnionSkinSettings.maxPegs] of them.
OnionPeg _pegAt(List<OnionPeg> pegs, int index) =>
    index < pegs.length ? pegs[index] : const OnionPeg(opacity: 0);

/// Writes one peg's opacity, growing the list to reach [index] with silent
/// pegs (peg k stays "the k-th step" whatever the list length).
List<OnionPeg> _writePeg(List<OnionPeg> pegs, int index, double opacity) {
  final next = List<OnionPeg>.of(pegs);
  while (next.length <= index) {
    next.add(const OnionPeg(opacity: 0));
  }
  next[index] = next[index].copyWith(opacity: opacity);
  return next;
}

/// The light table itself: `[before 8..1] ● [after 1..8]`, always all of
/// them, bar height = opacity.
class _OnionFalloffStrip extends StatefulWidget {
  const _OnionFalloffStrip({required this.settings, required this.onChanged});

  final OnionSkinSettings settings;
  final ValueChanged<OnionSkinSettings> onChanged;

  @override
  State<_OnionFalloffStrip> createState() => _OnionFalloffStripState();
}

class _OnionFalloffStripState extends State<_OnionFalloffStrip> {
  static const double _stripHeight = 72;

  /// The strip's drawable interior (the box height less its hairline).
  static const double _graphHeight = _stripHeight - 2;

  /// What a tap restores when the peg has no remembered value.
  static const double _restoreOpacity = 0.3;

  /// Below this a column can't hold two digits; the percentages step
  /// aside and the index row (one digit) carries the reading.
  static const double _minWidthForPercent = 11;

  static int get _slots => OnionSkinSettings.maxPegs;
  static int get _columns => _slots * 2 + 1;

  /// Column the pointer hovers (null = none) — pure affordance.
  int? _hoverColumn;

  /// The drag edits the peg it STARTED on: a wobble across the column edge
  /// must not switch which drawing is being sculpted.
  bool? _dragBefore;
  int? _dragIndex;

  /// What each peg was worth before a tap silenced it, so the second tap
  /// brings the same falloff back instead of a guess.
  final Map<String, double> _silenced = <String, double>{};

  List<OnionPeg> _pegsOf(bool before) =>
      before ? widget.settings.beforePegs : widget.settings.afterPegs;

  void _write(bool before, List<OnionPeg> pegs) {
    widget.onChanged(
      before
          ? widget.settings.copyWith(beforePegs: pegs)
          : widget.settings.copyWith(afterPegs: pegs),
    );
  }

  void _toggle({required bool before, required int index}) {
    final pegs = _pegsOf(before);
    final current = _pegAt(pegs, index).opacity;
    final memo = '${before ? 'before' : 'after'}-$index';
    final double next;
    if (current > 0) {
      _silenced[memo] = current;
      next = 0;
    } else {
      next = _silenced[memo] ?? _restoreOpacity;
    }
    _write(before, _writePeg(pegs, index, next));
  }

  void _setOpacity({
    required bool before,
    required int index,
    required double opacity,
  }) {
    _write(before, _writePeg(_pegsOf(before), index, opacity));
  }

  /// (before, peg index) for a column; null for the current-drawing column.
  (bool, int)? _pegForColumn(int column) {
    if (column == _slots) {
      return null;
    }
    return column < _slots
        ? (true, _slots - 1 - column)
        : (false, column - _slots - 1);
  }

  void _handleDragStart(DragStartDetails details, double width) {
    final columnWidth = width / _columns;
    if (columnWidth <= 0) {
      return;
    }
    final column = (details.localPosition.dx / columnWidth).floor();
    final target = column < 0 || column >= _columns
        ? null
        : _pegForColumn(column);
    if (target == null) {
      return;
    }
    _dragBefore = target.$1;
    _dragIndex = target.$2;
    _handleDragTo(details.localPosition.dy);
  }

  void _handleDragTo(double dy) {
    final before = _dragBefore;
    final index = _dragIndex;
    if (before == null || index == null) {
      return;
    }
    // Zero is a legal landing: dragging a bar to the floor turns that peg
    // off, which is how most of the strip is meant to sit.
    final opacity = (1 - dy / _stripHeight).clamp(0.0, 1.0);
    _setOpacity(before: before, index: index, opacity: opacity);
  }

  void _endDrag() {
    _dragBefore = null;
    _dragIndex = null;
  }

  /// The strip's drag, wired the way [FieldSlider] wires its own.
  ///
  /// ⚠️`DragStartBehavior.down` for the same reason the slider gives: the bar
  /// answers the PRESS, and with acceptance on the first movement there is no
  /// slop left to discard anyway.
  void _configureDrag(DragGestureRecognizer recognizer, double width) {
    // ⚠️BLOCK bodies, not arrows: a `..` on the line after an arrow binds to
    // the arrow's own expression, so a cascade of arrow assignments reads as
    // cascading on a `void` — which is what the analyzer said, three times.
    recognizer
      ..dragStartBehavior = DragStartBehavior.down
      ..onStart = (DragStartDetails details) {
        _handleDragStart(details, width);
      }
      ..onUpdate = (DragUpdateDetails details) {
        _handleDragTo(details.localPosition.dy);
      }
      ..onEnd = (DragEndDetails details) {
        _endDrag();
      }
      ..onCancel = _endDrag;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final showPercent = width / _columns >= _minWidthForPercent;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: _stripHeight,
              decoration: ShapeDecoration(
                color: AppColors.backdrop,
                shape: AppShapes.container(
                  AppShapes.wellRadius,
                  side: const BorderSide(color: AppColors.hairline),
                ),
              ),
              child: SuperellipseClip(
                shape: AppShapes.container(3),
                // 🚨★★★**THE BARS AND THE NUMBERS ARE TWO LAYERS, AND THAT
                // IS NOT A LOOK — IT IS WHO OWNS THE POINTER** (F-150 ②③).
                //
                // A slider takes the STRONG claim: [DragVerbClaim] says 「a
                // drag from here is my verb」 and every press claim inside it
                // stands down (`valueControlOwnsPointer`). 🧪Measured: with
                // the number drawn INSIDE the strip's claim its press could
                // never fire — the toggle test stayed at 0.4.
                //
                // ⇒ The numbers are a SIBLING layer on top, outside the
                // claim. Nothing moves: they sit at the same floor they
                // always did, and a press that lands on one is hit-tested
                // into it before the drag layer below is offered anything.
                child: Stack(
                  children: [
                    Positioned.fill(
                      // 🚨**THE BAR IS A SLIDER, SO IT RIDES THE SLIDER'S
                      // LAW** (유저 2026-09-16: 「그래프? 바 쪽 지금 클릭하면
                      // on off인데 **그런거 없애고, 공용슬라이더 사용해서
                      // 통일화**」).
                      //
                      // ↩️It was a plain `GestureDetector(onVerticalDrag…)`,
                      // which waits for the device's slop — so a drag begun
                      // on these bars could be taken by the panel's own
                      // scroller before the strip ever heard of it, and
                      // nothing claimed the press for a value control at
                      // all. [FieldSlider] answered both long ago and this
                      // strip simply never asked.
                      //
                      // ⛔The recogniser is on the STRIP, not each column:
                      // the drag edits the peg it STARTED on, so a wobble
                      // across a column edge must not switch which drawing
                      // is being sculpted.
                      child: DragVerbClaim(
                        child: RawGestureDetector(
                          behavior: HitTestBehavior.opaque,
                          gestures: <Type, GestureRecognizerFactory>{
                            OwningVerticalDragGestureRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                  OwningVerticalDragGestureRecognizer
                                >(
                                  () => OwningVerticalDragGestureRecognizer(
                                    debugOwner: this,
                                  ),
                                  (recognizer) =>
                                      _configureDrag(recognizer, width),
                                ),
                          },
                          child: MouseRegion(
                            onExit: (_) =>
                                setState(() => _hoverColumn = null),
                            child: Row(
                              // Stretch, or the Row's loose cross-axis
                              // constraints let each column shrink to its
                              // own bar: the bars would float mid-strip.
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (
                                  var column = 0;
                                  column < _columns;
                                  column += 1
                                )
                                  _buildColumn(column),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (showPercent)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 1,
                        child: Row(
                          // ⛔THE READOUT KEEPS ONE BASELINE. A `FittedBox`
                          // scales a two-digit number down and a one-digit
                          // one not at all, so centred they sit at two
                          // heights — which is the very thing the old
                          // per-column `Positioned(bottom: 1)` prevented.
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (
                              var column = 0;
                              column < _columns;
                              column += 1
                            )
                              _buildPercentSwitch(column),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
            // The strip's hairline insets its columns by 1px; the index
            // row matches it so a digit sits under its own bar.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Row(
                children: [
                  for (var column = 0; column < _columns; column += 1)
                    _buildIndexLabel(column),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildColumn(int column) {
    final settings = widget.settings;
    final target = _pegForColumn(column);
    if (target == null) {
      return Expanded(
        child: Tooltip(
          key: const ValueKey<String>('onion-peg-current'),
          message: AppText.strings.onionCurrentDrawing,
          child: _graphColumn(
            opacity: 1,
            color: AppColors.accent,
            sideWash: null,
            hovered: false,
          ),
        ),
      );
    }
    final (before, index) = target;
    final peg = _pegAt(
      before ? settings.beforePegs : settings.afterPegs,
      index,
    );
    final tint = Color(before ? settings.tintBefore : settings.tintAfter);
    final percent = (peg.opacity * 100).round();
    return Expanded(
      child: Tooltip(
        key: ValueKey<String>(
          'onion-peg-${before ? 'before' : 'after'}-${index + 1}',
        ),
        message:
            '${index + 1} ${before ? 'back' : 'ahead'} · '
            '${peg.shows ? '$percent%' : 'off'}',
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          onEnter: (_) => setState(() => _hoverColumn = column),
          // ↩️**A TAP HERE USED TO TOGGLE THE PEG OFF AND ON** — 유저
          // 2026-09-16: 「바 쪽 지금 클릭하면 on off인데 **그런거 없애고**」.
          // The bar is a slider and a slider is dragged; the switch moved to
          // the NUMBER, where the user put it.
          child: KeyedSubtree(
            key: ValueKey<String>(
              'onion-peg-column-${before ? 'before' : 'after'}-${index + 1}',
            ),
            child: _graphColumn(
              opacity: peg.opacity,
              color: tint,
              sideWash: tint.withValues(alpha: 0.05),
              hovered: _hoverColumn == column,
            ),
          ),
        ),
      ),
    );
  }

  /// 🚨★★★**THE NUMBER IS THE SWITCH** (F-150 ③, 유저 2026-09-16: 「버튼
  /// on off는 **숫자 써있는곳 버튼으로만들어서 그거 누르면 on off 전환**
  /// 되도록」). It is the one part of the column that is not the bar, which
  /// is what lets the bar be nothing but a slider.
  ///
  /// ⛔[ControlPressClaim], like every other button in the app: a press that
  /// lands here must not become the strip's drag or the panel's scroll, and
  /// 「released inside」 is what makes it a click.
  Widget _buildPercentSwitch(int column) {
    final target = _pegForColumn(column);
    if (target == null) {
      // The current drawing has no peg to silence.
      return const Expanded(child: SizedBox.shrink());
    }
    final (before, index) = target;
    final settings = widget.settings;
    final peg = _pegAt(
      before ? settings.beforePegs : settings.afterPegs,
      index,
    );
    return Expanded(
      child: ControlPressClaim(
        key: ValueKey<String>(
          'onion-peg-switch-${before ? 'before' : 'after'}-${index + 1}',
        ),
        onPressed: () => _toggle(before: before, index: index),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${(peg.opacity * 100).round()}',
            maxLines: 1,
            style: TextStyle(
              fontSize: 10,
              height: 1.1,
              color: peg.shows ? AppColors.text : AppColors.hairlineStrong,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }

  /// One graph column: the side wash that shows an empty slot is still a
  /// slot, and the bar. ↩️The value used to be drawn here too, pinned to the
  /// floor; it is its own layer now (see [build]) because it became a
  /// button and a button cannot live inside a slider's claim.
  Widget _graphColumn({
    required double opacity,
    required Color color,
    required Color? sideWash,
    required bool hovered,
  }) {
    final barHeight = opacity.clamp(0.0, 1.0) * _graphHeight;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hovered ? AppColors.surfaceHigh : sideWash,
        border: const Border(
          right: BorderSide(color: AppColors.hairline, width: 0.5),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (barHeight > 0)
            Positioned(
              left: 1,
              right: 1,
              bottom: 0,
              height: barHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.34),
                  border: Border(top: BorderSide(color: color, width: 2)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIndexLabel(int column) {
    final target = _pegForColumn(column);
    final String text;
    final Color color;
    if (target == null) {
      text = '●';
      color = AppColors.accent;
    } else {
      final (before, index) = target;
      final pegs = before
          ? widget.settings.beforePegs
          : widget.settings.afterPegs;
      text = '${index + 1}';
      color = _pegAt(pegs, index).shows ? AppColors.text : AppColors.textDim;
    }
    return Expanded(
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }
}
