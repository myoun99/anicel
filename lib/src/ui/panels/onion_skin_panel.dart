import 'package:flutter/material.dart';

import '../../models/onion_skin_settings.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/color_swatch_button.dart';
import '../widgets/panel_flyout.dart';

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
  });

  final OnionSkinSettings settings;
  final ValueChanged<OnionSkinSettings> onChanged;

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
      padding: const EdgeInsets.all(8),
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
                  entriesBuilder: () => [
                    for (final step in OnionSkinStep.values)
                      PanelFlyoutItem(
                        keyValue: 'onion-step-${step.name}',
                        label: switch (step) {
                          OnionSkinStep.blocks => 'Blocks (drawings)',
                          OnionSkinStep.frames => 'Frames',
                        },
                        checked: settings.step == step,
                        onSelected: () =>
                            onChanged(settings.copyWith(step: step)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: PanelFlyoutButton(
                  key: const ValueKey<String>('onion-mode-button'),
                  label: _modeLabel(settings.mode),
                  tooltip: AppText.strings.onionGhostColorHelp,
                  expand: true,
                  entriesBuilder: () => [
                    for (final mode in OnionSkinMode.values)
                      PanelFlyoutItem(
                        keyValue: 'onion-mode-${mode.name}',
                        label: _modeLabel(mode),
                        checked: settings.mode == mode,
                        onSelected: () =>
                            onChanged(settings.copyWith(mode: mode)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ColorSwatchButton(
                keyValue: 'onion-tint-before',
                title: AppText.strings.onionBefore,
                tooltip: AppText.strings.onionBeforeTint,
                color: settings.tintBefore,
                onChanged: (color) =>
                    onChanged(settings.copyWith(tintBefore: color)),
              ),
              const SizedBox(width: 6),
              ColorSwatchButton(
                keyValue: 'onion-tint-after',
                title: AppText.strings.onionAfter,
                tooltip: AppText.strings.onionAfterTint,
                color: settings.tintAfter,
                onChanged: (color) =>
                    onChanged(settings.copyWith(tintAfter: color)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _OnionFalloffStrip(settings: settings, onChanged: onChanged),
        ],
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final showPercent = width / _columns >= _minWidthForPercent;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              // The strip owns the vertical drag; each column owns its tap.
              onVerticalDragStart: (details) =>
                  _handleDragStart(details, width),
              onVerticalDragUpdate: (details) =>
                  _handleDragTo(details.localPosition.dy),
              onVerticalDragEnd: (_) => _endDrag(),
              onVerticalDragCancel: _endDrag,
              child: MouseRegion(
                onExit: (_) => setState(() => _hoverColumn = null),
                child: Container(
                  height: _stripHeight,
                  decoration: BoxDecoration(
                    color: AppColors.backdrop,
                    border: Border.all(color: AppColors.hairline),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Row(
                      // Stretch, or the Row's loose cross-axis constraints
                      // let each column shrink to its own bar: the bars
                      // would float mid-strip and only the bar itself would
                      // be tappable.
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var column = 0; column < _columns; column += 1)
                          _buildColumn(column, showPercent: showPercent),
                      ],
                    ),
                  ),
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

  Widget _buildColumn(int column, {required bool showPercent}) {
    final settings = widget.settings;
    final target = _pegForColumn(column);
    if (target == null) {
      return Expanded(
        child: Tooltip(
          key: const ValueKey<String>('onion-peg-current'),
          message: 'Current drawing',
          child: _graphColumn(
            opacity: 1,
            color: AppColors.accent,
            sideWash: null,
            hovered: false,
            label: null,
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
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hoverColumn = column),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _toggle(before: before, index: index),
            child: _graphColumn(
              opacity: peg.opacity,
              color: tint,
              sideWash: tint.withValues(alpha: 0.05),
              hovered: _hoverColumn == column,
              label: showPercent ? '$percent' : null,
            ),
          ),
        ),
      ),
    );
  }

  /// One graph column: the side wash that shows an empty slot is still a
  /// slot, the bar, and the value pinned to the floor — the readout keeps
  /// one baseline instead of riding up and down with the bar.
  Widget _graphColumn({
    required double opacity,
    required Color color,
    required Color? sideWash,
    required bool hovered,
    required String? label,
  }) {
    final barHeight = (opacity.clamp(0.0, 1.0) * _graphHeight);
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
          if (label != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 1,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.1,
                    color: opacity > 0
                        ? AppColors.text
                        : AppColors.hairlineStrong,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
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
