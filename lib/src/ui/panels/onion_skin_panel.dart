import '../widgets/app_tooltip.dart';
import 'package:flutter/material.dart';

import '../../models/onion_skin_settings.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart';
import '../input/control_press_claim.dart';
import '../widgets/color_swatch_button.dart';
import '../widgets/field_slider.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/static_raster.dart';
import '../layout/device_grid.dart';

/// The onion-skin dock panel: the light-table graph every 2D package
/// speaks (TVPaint's light table, Krita's onion docker) — ONE strip
/// centred on the current drawing with EVERY peg on screen at once, before
/// pegs left, after pegs right, each peg's bar height being its opacity
/// and the peg's index under it.
///
/// Drag a bar — the app's one slider, stood up — to set that peg's
/// opacity; press the peg's number under it to silence it (press again to
/// bring back the value it had). Zero is a legal value and the only "off"
/// there is — a peg can't be on and invisible at once.
///
/// Above the graph: what a peg step counts (drawing blocks or raw frames),
/// the Colors/Images mode, where the ghosts lie (on top or in place), and
/// each side's tint on the shared color-wheel swatch.
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
    OnionSkinStep.blocks => AppText.strings.onionStepBlocks,
    OnionSkinStep.frames => AppText.strings.onionStepFrames,
  };

  static String _modeLabel(OnionSkinMode mode) => switch (mode) {
    OnionSkinMode.colors => AppText.strings.onionModeColors,
    OnionSkinMode.images => AppText.strings.onionModeImages,
  };

  static String _placementLabel(OnionSkinPlacement placement) =>
      switch (placement) {
        OnionSkinPlacement.onTop => AppText.strings.onionPlacementOnTop,
        OnionSkinPlacement.inPlace => AppText.strings.onionPlacementInPlace,
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
                        OnionSkinStep.blocks =>
                          AppText.strings.onionStepBlocksDrawings,
                        OnionSkinStep.frames => AppText.strings.onionStepFrames,
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
                const SizedBox(width: 6),
                Flexible(
                  child: PanelFlyoutButton(
                    key: const ValueKey<String>('onion-placement-button'),
                    label: _placementLabel(settings.placement),
                    tooltip: AppText.strings.onionPlacementHelp,
                    expand: true,
                    entriesBuilder: () =>
                        OnionSkinPlacement.values.asFlyoutChoices(
                          current: settings.placement,
                          keyPrefix: 'onion-placement-',
                          labelOf: _placementLabel,
                          onPicked: (placement) => onChanged(
                            settings.copyWith(placement: placement),
                          ),
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
/// them — each peg a bar standing up, its height its opacity, and its
/// number under it.
class _OnionFalloffStrip extends StatefulWidget {
  const _OnionFalloffStrip({required this.settings, required this.onChanged});

  final OnionSkinSettings settings;
  final ValueChanged<OnionSkinSettings> onChanged;

  @override
  State<_OnionFalloffStrip> createState() => _OnionFalloffStripState();
}

class _OnionFalloffStripState extends State<_OnionFalloffStrip> {
  static const double _stripHeight = 72;

  /// The order row's — the switches' — height.
  static const double _numberHeight = 16;

  /// What a press on a number restores when the peg has no remembered
  /// value.
  static const double _restoreOpacity = 0.3;

  /// Between two bars.
  static const double _gap = 1;

  static int get _slots => OnionSkinSettings.maxPegs;
  static int get _columns => _slots * 2 + 1;

  /// What each peg was worth before its number silenced it, so the second
  /// press brings the same falloff back instead of a guess.
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

  /// (before, peg index) for a column; null for the current-drawing column.
  (bool, int)? _pegForColumn(int column) {
    if (column == _slots) {
      return null;
    }
    return column < _slots
        ? (true, _slots - 1 - column)
        : (false, column - _slots - 1);
  }

  /// The [_columns] columns, [_gap] apart, each [cell] built for its
  /// column at the width it gets — the bars' row and the numbers' row are
  /// laid out by this one walk, so a number sits under its own bar.
  Widget _row(Widget Function(int column, double width) cell) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var column = 0; column < _columns; column += 1) ...[
        if (column > 0) const SizedBox(width: _gap),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => cell(column, box.maxWidth),
          ),
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: _stripHeight, child: _row(_buildBar)),
        const SizedBox(height: 2),
        SizedBox(height: _numberHeight, child: _row(_buildNumber)),
      ],
    );
  }

  /// 🚨★★★**THE BAR IS THE APP'S ONE SLIDER** (F-461, 유저 2026-10-23:
  /// 「우선 슬라이더를 지금 쓰는 공용화된 슬라이더 사용」 — ↩️F-150 ②, 유저
  /// 2026-09-16: 「공용슬라이더 사용해서 통일화」, had it only ride
  /// [FieldSlider]'s drag in a strip of its own). Stood up, its number
  /// standing down it a glyph to a cell ([FieldSlider.upright]), in the
  /// side's tint at rest and while dragged ([FieldSlider.color], F-474) —
  /// the bar tap, drag, wheel and claim of every other bar in the app.
  Widget _buildBar(int column, double width) {
    final settings = widget.settings;
    final target = _pegForColumn(column);
    if (target == null) {
      // The current drawing: no peg, nothing to set — the full bar.
      return AppTooltip(
        key: const ValueKey<String>('onion-peg-current'),
        message: AppText.strings.onionCurrentDrawing,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: AppColors.accent,
            shape: AppShapes.container(FieldSlider.radiusFor(width)),
          ),
        ),
      );
    }
    final (before, index) = target;
    final peg = _pegAt(_pegsOf(before), index);
    final side = before ? 'before' : 'after';
    final name = before
        ? AppText.strings.onionPegBefore(index + 1)
        : AppText.strings.onionPegAfter(index + 1);
    // The per cent is the bar's own to write (F-34) — the tooltip names the
    // peg, and says `off` where the bar has nothing to show.
    return AppTooltip(
      key: ValueKey<String>('onion-peg-$side-${index + 1}'),
      message: peg.shows ? name : '$name · ${AppText.strings.commonOff}',
      child: FieldSlider.opacity(
        key: ValueKey<String>('onion-peg-bar-$side-${index + 1}'),
        value: peg.opacity,
        height: width,
        axis: Axis.vertical,
        upright: true,
        color: Color(before ? settings.tintBefore : settings.tintAfter),
        onChanged: (opacity) =>
            _write(before, _writePeg(_pegsOf(before), index, opacity)),
      ),
    );
  }

  /// 🚨★★★**THE NUMBER UNDER THE BAR IS THE SWITCH** (F-461, 유저
  /// 2026-10-23: 「1번 2번 등 슬라이더 아래의 순서 숫자를 버튼으로서 누르면
  /// on/off」 — ↩️F-150 ③, 유저 2026-09-16: 「숫자 써있는곳 버튼으로만들어서」,
  /// had been read as the percentage at the bar's floor). Zero is the only
  /// off; a second press brings back the value the peg had.
  ///
  /// ⛔[ControlPressClaim], like every other button in the app: a press that
  /// lands here must not become the panel's scroll, and 「released inside」
  /// is what makes it a click.
  Widget _buildNumber(int column, double width) {
    final target = _pegForColumn(column);
    if (target == null) {
      return Center(
        child: Text(
          '●',
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(fontSize: 10, color: AppColors.accent),
        ),
      );
    }
    final (before, index) = target;
    final shows = _pegAt(_pegsOf(before), index).shows;
    void press() => _toggle(before: before, index: index);
    return Material(
      color: Colors.transparent,
      child: ControlPressClaim(
        onPressed: press,
        child: InkWell(
          mouseCursor: AppCursors.press,
          key: ValueKey<String>(
            'onion-peg-switch-${before ? 'before' : 'after'}-${index + 1}',
          ),
          customBorder: AppShapes.container(FieldSlider.radiusFor(width)),
          onTap: silentPress(press),
          child: Center(
            child: Text(
              '${index + 1}',
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: 10,
                color: shows ? AppColors.text : AppColors.textDim,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
