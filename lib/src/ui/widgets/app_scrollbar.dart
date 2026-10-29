import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/text_on_ground.dart' show textOnColor;
import '../timeline/axis_turn.dart'
    show extentAcross, extentAlong, partAlong, stripAlong;
import 'app_scrollbar_lane.dart';
import 'owning_axis_grip.dart';
import 'tick_layer.dart';

/// The lane vocabulary lives next door so calculation-only files can name
/// a width without importing a widget; everyone who has the scrollbar has
/// the vocabulary too.
export 'app_scrollbar_lane.dart';

/// The lane the bars under it are given where they are not given one —
/// the bar laid over an overflowing scrollable, the content column's, the
/// canvas panel's panbars — [AppScrollbarLane.thin] outside any scope.
///
/// The PANEL says it, once, for everything laid in it: F-440 (유저
/// 2026-10-23) 「뒷 배경에 깔리는 패널만 두꺼운 스크롤바 사용. 나중에
/// 콘티용지패널을 뒤에 깔수있게 할거기 때문에 입구를 그런식으로 설계」 — a
/// panel that finds itself on the workspace's floor (`CanvasFloorInsets`)
/// says thick, and the same panel docked passes on the lane its seat gives.
/// ↩️The preferences window said thick here from F-409 (10-20) to F-440.
class AppScrollbarLaneScope extends InheritedWidget {
  const AppScrollbarLaneScope({
    super.key,
    required this.lane,
    required super.child,
  });

  final double lane;

  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AppScrollbarLaneScope>()
          ?.lane ??
      AppScrollbarLane.thin;

  @override
  bool updateShouldNotify(AppScrollbarLaneScope oldWidget) =>
      lane != oldWidget.lane;
}

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
  }) : trackExtent = finiteNonNegativeExtent(trackExtent),
       viewportExtent = finiteNonNegativeExtent(viewportExtent),
       contentExtent = finiteNonNegativeExtent(contentExtent) {
    maxScroll = scrollRangeFor(
      contentExtent: this.contentExtent,
      viewportExtent: this.viewportExtent,
    );
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
}

/// The app-wide scrollbar visual: no track, a grey thumb whose ONLY state
/// signal is colour — grey at rest, white under the pointer, accent while
/// pressed. The thickness never changes (유저 지시: 어떤 레일이든 눌렀다고
/// 크기가 바뀌지 않는다), so a press cannot nudge the layout of whatever sits
/// beside the lane. Parents supply the lane ([AppScrollbarLane]), and the
/// thumb fills it across — F-409: 「조작 가능한 만큼 위젯의 모양새가
/// 위치하도록」. ↩️It was 4px wherever the lane was, so most of what took the
/// pointer was air.
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
    this.minThumbExtent = AppScrollbarThumb.minimum,
    this.thumbKey,
    this.laneKey,
    this.enabled = true,
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

  /// False takes no press, no drag and no hover colour: the thumb stays at
  /// rest where the view is, because the extents are still the truth.
  final bool enabled;

  @override
  State<AppScrollbar> createState() => _AppScrollbarState();
}

class _AppScrollbarState extends State<AppScrollbar> {
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackExtent = extentAlong(widget.axis, constraints.biggest);
        final geometry = _geometry(trackExtent);
        // Colour is the whole state machine (see the class doc). The ink the
        // chrome takes (white on the dark palette, black on the light, I-143)
        // rather than a palette grey because a thumb has to win
        // against the lane behind it to read as "the pointer is here".
        final color = !widget.enabled
            ? AppColors.hairlineStrong
            : _pressed
            ? AppColors.accent
            : _hovered
            ? textOnColor(AppColors.surface)
            : AppColors.hairlineStrong;
        // 🚨F-202 (유저 2026-09-27): 「안에서 동작하는 스크롤이나 드래그는 절대
        // 밖으로 안새게」. A thumb's drag is the bar's VERB, so the bar wears
        // the grip every drag verb on a control wears — the claim, and a
        // drag that takes the arena on its FIRST movement. ↩️It waited for
        // the slop, and a pull whose first step went across the bar's axis
        // (a horizontal panbar inside the vertical strip of panels) gave
        // the strip the drag instead: the strip scrolled, the thumb did not.
        final lane = OwningAxisGrip(
          axis: widget.axis,
          configure: (recognizer) {
            recognizer.onStart = (details) =>
                _dragStart(_axisPosition(details.localPosition), geometry);
            recognizer.onUpdate = (details) =>
                _dragUpdate(_axisPosition(details.localPosition), geometry);
            recognizer.onEnd = (_) => _dragEnd();
            recognizer.onCancel = _dragEnd;
          },
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(child: SizedBox.expand(key: widget.laneKey)),
                stripAlong(
                  widget.axis,
                  along: geometry.thumbStart,
                  alongExtent: geometry.thumbExtent,
                  child: AnimatedContainer(
                    key: widget.thumbKey,
                    duration: _stateAnimation,
                    curve: Curves.easeOut,
                    decoration: ShapeDecoration(
                      color: color,
                      shape: AppShapes.control(
                        extentAcross(widget.axis, constraints.biggest),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        return Listener(
          // Outside the recognisers on purpose: a tap and a press on a
          // full-lane thumb both have to light the accent, and neither
          // reaches the drag callbacks.
          onPointerDown: (_) => _setPressed(true),
          onPointerUp: (_) => _setPressed(false),
          onPointerCancel: (_) => _setPressed(false),
          child: widget.lanePress == AppScrollbarLanePress.jumpToPointer
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => _lanePressed(
                    _axisPosition(details.localPosition),
                    geometry,
                  ),
                  child: lane,
                )
              : lane,
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
      partAlong(widget.axis, localPosition);

  void _lanePressed(double position, AppScrollbarGeometry geometry) {
    if (!widget.enabled ||
        !geometry.canScroll ||
        geometry.containsThumb(position)) {
      return;
    }
    widget.onOffsetChanged(
      geometry.offsetForThumbStart(position - geometry.thumbExtent / 2),
    );
  }

  void _dragStart(double position, AppScrollbarGeometry geometry) {
    // A drag that does not start leaves `_dragThumbStart` null, which is
    // what stops `_dragUpdate` too.
    if (!widget.enabled || !geometry.canScroll) {
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
    this.minThumbExtent = AppScrollbarThumb.minimum,
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
  /// The metrics the last build DREW, so the post-frame check can tell a
  /// stale thumb from a settled one.
  ///
  /// 🚨T7 — a [ScrollController] notifies when the OFFSET moves and at no
  /// other time. Content growing or shrinking under a stationary offset —
  /// adding layers, expanding a lane group, switching to a cut with a
  /// different number of rows — changes what the thumb should be and rings
  /// no bell at all. The bar then keeps the size it had, which is exactly
  /// the report: 「컷1에서 레이어 많이 만들고, 컷2 가면 스크롤바가 작은 채로」.
  ///
  /// A host rebuild used to be the accidental cure, and where one did not
  /// arrive the bar simply lied. It is worse than a missed notify: the
  /// scrollable LAYS OUT after this widget builds, so even in the frame
  /// where everything changes, the numbers read here are the previous
  /// frame's. Something has to look again once the frame is done.
  ///
  /// ★So the existing one-shot attach retry is generalised rather than
  /// joined by a second mechanism: the same "look again after the frame"
  /// answers both, and one of them was already the trusted idiom here.
  ({double viewport, double content, double offset})? _drawn;

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

  /// The metrics as they stand RIGHT NOW, falling back while unattached.
  ({double viewport, double content, double offset}) get _metrics {
    final position = _position;
    if (!_hasDimensions || position == null) {
      return (
        viewport: widget.fallbackViewportExtent ?? 0.0,
        content: widget.fallbackContentExtent ?? 0.0,
        offset: 0.0,
      );
    }
    return (
      viewport: position.viewportDimension,
      content: position.viewportDimension + position.maxScrollExtent,
      offset: position.pixels,
    );
  }

  /// Looks once more after the frame has laid out, and rebuilds only if what
  /// was drawn is no longer true. Costs one callback and three comparisons
  /// per build; a settled bar stops there.
  void _scheduleSettledCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _metrics == _drawn) {
        return;
      }
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    // A ScrollController does not notify on attach, so the first build can
    // race the scrollable's layout — and (T7) it never notifies for a content
    // extent that changed under a still offset either. One post-frame look
    // covers both, which is why the one-shot attach retry that used to sit
    // here is GONE rather than kept beside it: it was this check with a
    // narrower question ([[duplication-program]] — the last step is deleting
    // the predecessor).
    _scheduleSettledCheck();
    // 🚨A SCROLL REDRAWS THE BAR AND NOTHING BESIDE IT
    // (playback-page-turn-repaints-the-whole-timeline, 10-11). The bar is
    // built again at every pixel of scroll, and a widget built again is laid
    // out by the nearest [LayoutBuilder] above it — Flutter runs a
    // LayoutBuilder's subtree's rebuilds in its own layout. So the bar
    // brings its own: given the lane it fills as TIGHT constraints, it is a
    // relayout boundary, and the layer above it keeps the repaint there.
    // ↩️The rebuild was laid out by the panel's LayoutBuilder around the
    // bar, whose relayout climbed to the panel, and that panel's layer was
    // painted again whole: 🔬393 of the timeline's render objects for a
    // one-pixel scroll of its frame axis — at every page turn of a run.
    // (The bar's [Stack] expands to its lane already, so tightening it
    // changes no size.)
    // ↩️It brought the paint and the layout halves of a [TickLayer] by hand
    // and not the third: a scroll's relayout climbed to the semantics
    // boundary above it, and a page turn of a run re-walked 351 render
    // objects of the workspace for a moved thumb (2026-10-11). It is a tick
    // of the scroll, so it is one.
    return SizedBox.expand(child: TickLayer(child: _bar()));
  }

  Widget _bar() => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final metrics = _metrics;
      final viewportExtent = metrics.viewport;
      final contentExtent = metrics.content;
      final offset = metrics.offset;
      // Recorded from INSIDE the AnimatedBuilder: an offset notification
      // rebuilds only this closure, and the check must compare against
      // what was actually painted rather than the outer build's snapshot.
      _drawn = metrics;
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
