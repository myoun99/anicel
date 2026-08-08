import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_scrollbar_lane.dart';

/// The lane vocabulary lives next door so calculation-only files can name
/// a width without importing a widget; everyone who has the scrollbar has
/// the vocabulary too.
export 'app_scrollbar_lane.dart';

/// How a press on the lane (outside the thumb) behaves.
enum AppScrollbarLanePress {
  /// Press/tap centers the thumb at the pointer, then drags relatively
  /// (timeline rails, panel scrollables).
  jumpToPointer,

  /// The whole lane is a relative drag surface: the thumb moves 1:1 with
  /// the pointer no matter where the press lands (canvas panbars).
  relativeDrag,
}

/// Pure scrollbar geometry shared by every scrollbar in the app.
///
/// When there is nothing to scroll the thumb fills the whole lane — both
/// the canvas panbars and the timeline rails pin that behavior.
class AppScrollbarGeometry {
  AppScrollbarGeometry({
    required double trackExtent,
    required double viewportExtent,
    required double contentExtent,
    required double offset,
    required this.minThumbExtent,
  }) : trackExtent = _finiteNonNegative(trackExtent),
       viewportExtent = _finiteNonNegative(viewportExtent),
       contentExtent = _finiteNonNegative(contentExtent) {
    maxScroll = (this.contentExtent - this.viewportExtent)
        .clamp(0.0, double.infinity)
        .toDouble();
    canScroll = maxScroll > 0 && this.trackExtent > 0;
    if (!canScroll) {
      thumbExtent = this.trackExtent;
      thumbTravel = 0;
      thumbStart = 0;
      this.offset = 0;
      return;
    }
    final proportionalExtent =
        this.viewportExtent / this.contentExtent * this.trackExtent;
    final safeMinimum = minThumbExtent.clamp(0.0, this.trackExtent).toDouble();
    thumbExtent = proportionalExtent
        .clamp(safeMinimum, this.trackExtent)
        .toDouble();
    thumbTravel = (this.trackExtent - thumbExtent)
        .clamp(0.0, double.infinity)
        .toDouble();
    this.offset = offset.clamp(0.0, maxScroll).toDouble();
    thumbStart = thumbTravel == 0 ? 0 : this.offset / maxScroll * thumbTravel;
  }

  final double trackExtent;
  final double viewportExtent;
  final double contentExtent;
  final double minThumbExtent;
  late final double offset;
  late final double maxScroll;
  late final bool canScroll;
  late final double thumbExtent;
  late final double thumbTravel;
  late final double thumbStart;

  double offsetForThumbStart(double thumbStart) {
    if (!canScroll || thumbTravel <= 0) {
      return 0;
    }
    final clamped = thumbStart.clamp(0.0, thumbTravel).toDouble();
    return clamped / thumbTravel * maxScroll;
  }

  bool containsThumb(double axisPosition) =>
      axisPosition >= thumbStart && axisPosition <= thumbStart + thumbExtent;

  static double _finiteNonNegative(double value) {
    if (!value.isFinite || value <= 0) {
      return 0;
    }
    return value;
  }
}

/// The app-wide scrollbar visual: no track, a thin grey thumb whose ONLY
/// state signal is colour — grey at rest, white under the pointer, accent
/// while pressed. The thickness never changes (유저 지시: 어떤 레일이든
/// 눌렀다고 크기가 바뀌지 않는다), so a press cannot nudge the layout of
/// whatever sits beside the lane. Parents supply the hit lane
/// ([AppScrollbarLane]) — the thumb stays visually thin inside it.
///
/// The pressed colour lights on pointer-DOWN and is deliberately
/// independent of whether there is anything to scroll: a full-lane thumb
/// (the nothing-to-scroll state below) is still a control the user
/// pressed, and staying grey read as a dead widget.
///
/// Fully controlled: position comes from [offset] against
/// [viewportExtent]/[contentExtent]; interactions emit absolute offsets
/// through [onOffsetChanged]. [onChangeEnd] fires once per drag on both
/// end and cancel (the canvas panbar sync contract).
class AppScrollbar extends StatefulWidget {
  const AppScrollbar({
    super.key,
    required this.axis,
    required this.offset,
    required this.viewportExtent,
    required this.contentExtent,
    required this.onOffsetChanged,
    this.onChangeEnd,
    this.lanePress = AppScrollbarLanePress.jumpToPointer,
    this.minThumbExtent = 28,
    this.thumbKey,
    this.laneKey,
  });

  final Axis axis;
  final double offset;
  final double viewportExtent;
  final double contentExtent;
  final ValueChanged<double> onOffsetChanged;
  final VoidCallback? onChangeEnd;
  final AppScrollbarLanePress lanePress;
  final double minThumbExtent;
  final Key? thumbKey;
  final Key? laneKey;

  @override
  State<AppScrollbar> createState() => _AppScrollbarState();
}

class _AppScrollbarState extends State<AppScrollbar> {
  /// One thickness for every state — see the class doc.
  static const double _thickness = 4;
  static const Duration _stateAnimation = Duration(milliseconds: 100);

  bool _hovered = false;

  /// Whether a pointer is down on the lane. Tracked by a [Listener] rather
  /// than the drag recognisers because a plain TAP must light it too, and
  /// because the drag callbacks bail out early when there is nothing to
  /// scroll — that pair of gaps is why the timeline rails never turned
  /// accent no matter how hard they were clicked.
  bool _pressed = false;
  double? _dragThumbStart;
  double? _dragPointerStart;

  AppScrollbarGeometry _geometry(double trackExtent) => AppScrollbarGeometry(
    trackExtent: trackExtent,
    viewportExtent: widget.viewportExtent,
    contentExtent: widget.contentExtent,
    offset: widget.offset,
    minThumbExtent: widget.minThumbExtent,
  );

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackExtent = horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final geometry = _geometry(trackExtent);
        // Colour is the whole state machine (see the class doc). White
        // rather than a palette grey because a 4px thumb has to win
        // against the lane behind it to read as "the pointer is here".
        final color = _pressed
            ? AppColors.accent
            : _hovered
            ? Colors.white
            : AppColors.hairlineStrong;
        return Listener(
          // Outside the recognisers on purpose: a tap and a press on a
          // full-lane thumb both have to light the accent, and neither
          // reaches the drag callbacks.
          onPointerDown: (_) => _setPressed(true),
          onPointerUp: (_) => _setPressed(false),
          onPointerCancel: (_) => _setPressed(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: widget.lanePress == AppScrollbarLanePress.jumpToPointer
                ? (details) => _lanePressed(
                    _axisPosition(details.localPosition),
                    geometry,
                  )
                : null,
            onHorizontalDragStart: horizontal
                ? (details) =>
                      _dragStart(_axisPosition(details.localPosition), geometry)
                : null,
            onVerticalDragStart: horizontal
                ? null
                : (details) => _dragStart(
                    _axisPosition(details.localPosition),
                    geometry,
                  ),
            onHorizontalDragUpdate: horizontal
                ? (details) => _dragUpdate(
                    _axisPosition(details.localPosition),
                    geometry,
                  )
                : null,
            onVerticalDragUpdate: horizontal
                ? null
                : (details) => _dragUpdate(
                    _axisPosition(details.localPosition),
                    geometry,
                  ),
            onHorizontalDragEnd: horizontal ? (_) => _dragEnd() : null,
            onVerticalDragEnd: horizontal ? null : (_) => _dragEnd(),
            onHorizontalDragCancel: horizontal ? _dragEnd : null,
            onVerticalDragCancel: horizontal ? null : _dragEnd,
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(child: SizedBox.expand(key: widget.laneKey)),
                  Positioned(
                    left: horizontal ? geometry.thumbStart : 0,
                    right: horizontal ? null : 0,
                    top: horizontal ? 0 : geometry.thumbStart,
                    bottom: horizontal ? 0 : null,
                    width: horizontal ? geometry.thumbExtent : null,
                    height: horizontal ? null : geometry.thumbExtent,
                    child: Center(
                      child: AnimatedContainer(
                        key: widget.thumbKey,
                        duration: _stateAnimation,
                        curve: Curves.easeOut,
                        width: horizontal ? double.infinity : _thickness,
                        height: horizontal ? _thickness : double.infinity,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(_thickness / 2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _setPressed(bool value) {
    if (_pressed != value) {
      setState(() => _pressed = value);
    }
  }

  double _axisPosition(Offset localPosition) =>
      widget.axis == Axis.horizontal ? localPosition.dx : localPosition.dy;

  void _lanePressed(double position, AppScrollbarGeometry geometry) {
    if (!geometry.canScroll || geometry.containsThumb(position)) {
      return;
    }
    widget.onOffsetChanged(
      geometry.offsetForThumbStart(position - geometry.thumbExtent / 2),
    );
  }

  void _dragStart(double position, AppScrollbarGeometry geometry) {
    if (!geometry.canScroll) {
      return;
    }
    var thumbStart = geometry.thumbStart;
    if (widget.lanePress == AppScrollbarLanePress.jumpToPointer &&
        !geometry.containsThumb(position)) {
      thumbStart = (position - geometry.thumbExtent / 2)
          .clamp(0.0, geometry.thumbTravel)
          .toDouble();
      widget.onOffsetChanged(geometry.offsetForThumbStart(thumbStart));
    }
    _dragThumbStart = thumbStart;
    _dragPointerStart = position;
  }

  void _dragUpdate(double position, AppScrollbarGeometry geometry) {
    final dragThumbStart = _dragThumbStart;
    final dragPointerStart = _dragPointerStart;
    if (dragThumbStart == null || dragPointerStart == null) {
      return;
    }
    if (!geometry.canScroll) {
      return;
    }
    final nextThumbStart = (dragThumbStart + (position - dragPointerStart))
        .clamp(0.0, geometry.thumbTravel)
        .toDouble();
    widget.onOffsetChanged(geometry.offsetForThumbStart(nextThumbStart));
  }

  void _dragEnd() {
    final wasDragging = _dragThumbStart != null;
    _dragThumbStart = null;
    _dragPointerStart = null;
    // The pressed colour is the Listener's to clear — a drag that ends
    // with the pointer still down (a cancel from an arena loss) must stay
    // lit until the finger actually lifts.
    if (wasDragging) {
      widget.onChangeEnd?.call();
    }
  }
}

/// [AppScrollbar] driven by a [ScrollController].
///
/// Extents come from the attached position; before attachment (or while
/// dimensions are unknown) the fallback extents keep the thumb meaningful —
/// the timeline rails pass their layout-derived sizes there.
class AppControllerScrollbar extends StatefulWidget {
  const AppControllerScrollbar({
    super.key,
    required this.controller,
    required this.axis,
    this.lanePress = AppScrollbarLanePress.jumpToPointer,
    this.minThumbExtent = 28,
    this.fallbackViewportExtent,
    this.fallbackContentExtent,
    this.thumbKey,
    this.laneKey,
  });

  final ScrollController controller;
  final Axis axis;
  final AppScrollbarLanePress lanePress;
  final double minThumbExtent;
  final double? fallbackViewportExtent;
  final double? fallbackContentExtent;
  final Key? thumbKey;
  final Key? laneKey;

  @override
  State<AppControllerScrollbar> createState() => _AppControllerScrollbarState();
}

class _AppControllerScrollbarState extends State<AppControllerScrollbar> {
  bool _attachRetryUsed = false;

  /// The controller's position, or null when it is attached to anything
  /// other than exactly one view.
  ///
  /// 🚨`ScrollController.position` ASSERTS on both zero and TWO — and
  /// `hasClients` only rules out zero. Two scroll views sharing one
  /// controller (synchronised panes) would have thrown, which stopped
  /// mattering the moment this bar became something the app hands out
  /// automatically rather than something a caller chose.
  ScrollPosition? get _position {
    final positions = widget.controller.positions;
    return positions.length == 1 ? positions.first : null;
  }

  bool get _hasDimensions => _position?.hasContentDimensions ?? false;

  @override
  Widget build(BuildContext context) {
    // A ScrollController does not notify on attach, so the first build can
    // race the scrollable's layout. Retry once on the next frame; further
    // updates arrive through offset notifications or host rebuilds.
    if (!_hasDimensions && !_attachRetryUsed) {
      _attachRetryUsed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    } else if (_hasDimensions) {
      _attachRetryUsed = false;
    }
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        var viewportExtent = widget.fallbackViewportExtent ?? 0.0;
        var contentExtent = widget.fallbackContentExtent ?? 0.0;
        var offset = 0.0;
        final position = _position;
        if (_hasDimensions && position != null) {
          viewportExtent = position.viewportDimension;
          contentExtent = position.viewportDimension + position.maxScrollExtent;
          offset = position.pixels;
        }
        return AppScrollbar(
          axis: widget.axis,
          offset: offset,
          viewportExtent: viewportExtent,
          contentExtent: contentExtent,
          lanePress: widget.lanePress,
          minThumbExtent: widget.minThumbExtent,
          thumbKey: widget.thumbKey,
          laneKey: widget.laneKey,
          onOffsetChanged: _jumpTo,
        );
      },
    );
  }

  void _jumpTo(double offset) {
    final position = _position;
    if (position == null || !_hasDimensions) {
      return;
    }
    widget.controller.jumpTo(
      offset.clamp(0.0, position.maxScrollExtent).toDouble(),
    );
  }
}
