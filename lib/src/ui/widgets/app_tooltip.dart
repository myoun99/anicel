// Adapted from Flutter's `widgets/raw_tooltip.dart` and
// `material/tooltip.dart` (Flutter 3.47.4):
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// THE APP'S TOOLTIP — Flutter's [Tooltip], with ONE change: the global
/// pointer route is held only while the tooltip is showing or about to.
///
/// 🚨WHY IT EXISTS (09-25, measured on the real app, the user's layout):
/// 288 tooltips are mounted, and Flutter's `RawTooltipState.initState`
/// registers a global pointer route for EVERY one of them. `PointerRouter`
/// copies the whole route map and calls every route on every pointer event —
/// each pen sample (250 Hz), each hover move — so a stroke spent about a
/// fifth of the UI thread's time in `PointerRouter.route`, mostly in routes
/// that answer "not mine" and return. The route has one job: dismiss the
/// tooltip when a pointer goes down somewhere else, and its handler returns
/// at once unless the tooltip is pending or showing. Holding it only then
/// changes nothing but the cost.
///
/// ⛔Everything else is Flutter's, line for line — the hover rules, the
/// exclusive mouse region, the long-press and tap triggers, the fade, the
/// position and the Material look from [TooltipTheme]. Changing any of it
/// here is changing the app's tooltip, not fixing a cost.
///
/// It IS a [Tooltip] (a subclass with its own state), so `find.byTooltip`
/// and `tester.widget<Tooltip>` keep reading it.
class AppTooltip extends Tooltip {
  const AppTooltip({
    super.key,
    super.message,
    super.richMessage,
    super.constraints,
    super.padding,
    super.margin,
    super.verticalOffset,
    super.preferBelow,
    super.excludeFromSemantics,
    super.decoration,
    super.textStyle,
    super.textAlign,
    super.waitDuration,
    super.showDuration,
    super.exitDuration,
    super.enableTapToDismiss,
    super.triggerMode,
    super.enableFeedback,
    super.onTriggered,
    super.mouseCursor,
    super.ignorePointer,
    super.positionDelegate,
    super.child,
  });

  /// Dismisses every tooltip on screen — these, the summoned window
  /// ([SummonedTooltip]) and any of Flutter's own.
  static bool dismissAllToolTips() {
    final ours = _HoldingRawTooltip.dismissAll();
    final summoned = SummonedTooltip.dismiss();
    final theirs = Tooltip.dismissAllToolTips();
    return ours || summoned || theirs;
  }

  /// How many of these tooltips hold a global pointer route right now.
  @visibleForTesting
  static int get debugRoutesHeld => _HoldingRawTooltipState._routesHeld;

  @override
  State<Tooltip> createState() => AppTooltipState();
}

/// HOW THE APP'S TOOLTIPS LOOK AND TIME — [TooltipState]'s resolution,
/// lifted out of the widget: the tooltip's own field, then the theme's
/// ([TooltipTheme]), then Material's default.
///
/// ONE resolution for every tooltip the app shows: [AppTooltip], which
/// wraps its child, and the summoned window the rail's glyphs share
/// ([SummonedTooltip]) — so the two cannot come to look or time apart.
final class AppTooltipLook {
  AppTooltipLook._({
    required this.box,
    required this.verticalOffset,
    required this.preferBelow,
    required this.hoverDelay,
    required this.touchDelay,
    required this.dismissDelay,
    required this.triggerMode,
    required this.enableFeedback,
    required this.excludeFromSemantics,
  });

  /// The look in [context], with [tooltip]'s own fields first where it has
  /// any — a summoned window has none and takes the theme's.
  factory AppTooltipLook.of(BuildContext context, {Tooltip? tooltip}) {
    final theme = Theme.of(context);
    final tooltipTheme = TooltipTheme.of(context);
    final platform = theme.platform;
    final (
      TextStyle defaultTextStyle,
      BoxDecoration defaultDecoration,
    ) = switch (theme) {
      ThemeData(brightness: Brightness.dark, :final TextTheme textTheme) => (
        textTheme.bodyMedium!.copyWith(
          color: Colors.black,
          fontSize: _defaultFontSize(platform),
        ),
        BoxDecoration(
          // Flutter's withOpacity(0.9): alpha (255 × 0.9).round().
          color: Colors.white.withAlpha(230),
          borderRadius: const BorderRadius.all(Radius.circular(4)),
        ),
      ),
      ThemeData(brightness: Brightness.light, :final TextTheme textTheme) => (
        textTheme.bodyMedium!.copyWith(
          color: Colors.white,
          fontSize: _defaultFontSize(platform),
        ),
        BoxDecoration(
          color: Colors.grey[700]!.withAlpha(230),
          borderRadius: const BorderRadius.all(Radius.circular(4)),
        ),
      ),
    };
    final defaultConstraints = BoxConstraints(
      // Flutter's TooltipState reads the deprecated height the same way.
      // ignore: deprecated_member_use
      minHeight: tooltipTheme.height ?? _defaultTooltipHeight(platform),
    );
    return AppTooltipLook._(
      box: (message) => _TooltipBox(
        constraints:
            tooltip?.constraints ??
            tooltipTheme.constraints ??
            defaultConstraints,
        textStyle:
            tooltip?.textStyle ?? tooltipTheme.textStyle ?? defaultTextStyle,
        textAlign:
            tooltip?.textAlign ?? tooltipTheme.textAlign ?? _defaultTextAlign,
        decoration:
            tooltip?.decoration ??
            tooltipTheme.decoration ??
            defaultDecoration,
        padding:
            tooltip?.padding ??
            tooltipTheme.padding ??
            _defaultPadding(platform),
        margin: tooltip?.margin ?? tooltipTheme.margin ?? _defaultMargin,
        richMessage: message,
      ),
      verticalOffset:
          tooltip?.verticalOffset ??
          tooltipTheme.verticalOffset ??
          _defaultVerticalOffset,
      preferBelow:
          tooltip?.preferBelow ??
          tooltipTheme.preferBelow ??
          _defaultPreferBelow,
      hoverDelay:
          tooltip?.waitDuration ??
          tooltipTheme.waitDuration ??
          _defaultWaitDuration,
      touchDelay:
          tooltip?.showDuration ??
          tooltipTheme.showDuration ??
          _defaultShowDuration,
      dismissDelay:
          tooltip?.exitDuration ??
          tooltipTheme.exitDuration ??
          _defaultExitDuration,
      triggerMode:
          tooltip?.triggerMode ??
          tooltipTheme.triggerMode ??
          _defaultTriggerMode,
      enableFeedback:
          tooltip?.enableFeedback ??
          tooltipTheme.enableFeedback ??
          _defaultEnableFeedback,
      excludeFromSemantics:
          tooltip?.excludeFromSemantics ??
          tooltipTheme.excludeFromSemantics ??
          _defaultExcludeFromSemantics,
    );
  }

  static const double _defaultVerticalOffset = 24.0;
  static const bool _defaultPreferBelow = true;
  static const EdgeInsetsGeometry _defaultMargin = EdgeInsets.zero;
  static const Duration _defaultShowDuration = Duration(milliseconds: 1500);
  static const Duration _defaultExitDuration = Duration(milliseconds: 100);
  static const Duration _defaultWaitDuration = Duration.zero;
  static const bool _defaultExcludeFromSemantics = false;
  static const TooltipTriggerMode _defaultTriggerMode =
      TooltipTriggerMode.longPress;
  static const bool _defaultEnableFeedback = true;
  static const TextAlign _defaultTextAlign = TextAlign.start;

  static double _defaultTooltipHeight(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.macOS ||
        TargetPlatform.linux ||
        TargetPlatform.windows => 24.0,
        TargetPlatform.android ||
        TargetPlatform.fuchsia ||
        TargetPlatform.iOS => 32.0,
      };

  static EdgeInsets _defaultPadding(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.macOS ||
        TargetPlatform.linux ||
        TargetPlatform.windows => const EdgeInsets.symmetric(
          horizontal: 8.0,
          vertical: 4.0,
        ),
        TargetPlatform.android ||
        TargetPlatform.fuchsia ||
        TargetPlatform.iOS => const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 4.0,
        ),
      };

  static double _defaultFontSize(TargetPlatform platform) => switch (platform) {
    TargetPlatform.macOS ||
    TargetPlatform.linux ||
    TargetPlatform.windows => 12.0,
    TargetPlatform.android ||
    TargetPlatform.fuchsia ||
    TargetPlatform.iOS => 14.0,
  };

  /// The window [message] is shown in.
  final Widget Function(InlineSpan message) box;

  /// [box] fading in and out with [opacity] — Flutter's tooltip fade, the
  /// one both windows wear.
  Widget fadingBox(InlineSpan message, Animation<double> opacity) =>
      FadeTransition(opacity: opacity, child: box(message));
  final double verticalOffset;
  final bool preferBelow;

  /// A hovering mouse's wait before the window opens — zero in this app
  /// (유저 F-53).
  final Duration hoverDelay;

  /// How long a long-pressed window stays after the lift.
  final Duration touchDelay;

  /// How long a hovered window stays after the mouse leaves.
  final Duration dismissDelay;
  final TooltipTriggerMode triggerMode;
  final bool enableFeedback;
  final bool excludeFromSemantics;

  /// Where a window of [context]'s size stands for its target —
  /// [positionDependentBox] at this look's offset and side.
  Offset positionFor(TooltipPositionContext context) => positionDependentBox(
    size: context.overlaySize,
    childSize: context.tooltipSize,
    target: context.target,
    verticalOffset: verticalOffset,
    preferBelow: preferBelow,
  );
}

/// The state of an [AppTooltip] — [TooltipState]'s look ([AppTooltipLook]),
/// built over the route-holding raw tooltip.
class AppTooltipState extends State<AppTooltip> {
  final GlobalKey<_HoldingRawTooltipState> _tooltipKey =
      GlobalKey<_HoldingRawTooltipState>();

  late bool _visible;

  String get _tooltipMessage =>
      widget.message ?? widget.richMessage!.toPlainText();

  /// Shows the tooltip if it is not already visible — [TooltipState]'s.
  bool ensureTooltipVisible() =>
      _tooltipKey.currentState?.ensureTooltipVisible() ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TooltipVisibility.of(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_tooltipMessage.isEmpty) {
      return widget.child ?? const SizedBox.shrink();
    }
    final look = AppTooltipLook.of(context, tooltip: widget);
    final message = widget.richMessage ?? TextSpan(text: widget.message);

    Widget effectiveChild = MouseRegion(
      cursor: widget.mouseCursor ?? MouseCursor.defer,
      child: widget.child ?? const SizedBox.shrink(),
    );

    if (_visible) {
      effectiveChild = _HoldingRawTooltip(
        key: _tooltipKey,
        semanticsTooltip: look.excludeFromSemantics ? null : _tooltipMessage,
        tooltipBuilder: (BuildContext context, Animation<double> animation) =>
            look.fadingBox(message, animation),
        touchDelay: look.touchDelay,
        triggerMode: look.triggerMode,
        enableFeedback: look.enableFeedback,
        hoverDelay: look.hoverDelay,
        enableTapToDismiss: widget.enableTapToDismiss,
        onTriggered: widget.onTriggered,
        dismissDelay: look.dismissDelay,
        positionDelegate: (context) {
          final resolved = TooltipPositionContext(
            target: context.target,
            targetSize: context.targetSize,
            tooltipSize: context.tooltipSize,
            overlaySize: context.overlaySize,
            verticalOffset: look.verticalOffset,
            preferBelow: look.preferBelow,
          );
          return widget.positionDelegate?.call(resolved) ??
              look.positionFor(resolved);
        },
        ignorePointer: widget.ignorePointer ?? widget.message != null,
        child: effectiveChild,
      );
    }

    return effectiveChild;
  }
}

const AnimationStyle _kDefaultAnimationStyle = AnimationStyle(
  curve: Curves.fastOutSlowIn,
  duration: Duration(milliseconds: 150),
  reverseDuration: Duration(milliseconds: 75),
);

/// Flutter's `_ExclusiveMouseRegion`: when nested, only the first one hit in
/// hit-testing order is added to the result — a chip's delete icon and the
/// chip do not both show a tooltip.
class _ExclusiveMouseRegion extends MouseRegion {
  const _ExclusiveMouseRegion({super.onEnter, super.onExit, super.child});

  @override
  _RenderExclusiveMouseRegion createRenderObject(BuildContext context) {
    return _RenderExclusiveMouseRegion(onEnter: onEnter, onExit: onExit);
  }
}

class _RenderExclusiveMouseRegion extends RenderMouseRegion {
  _RenderExclusiveMouseRegion({super.onEnter, super.onExit});

  static bool isOutermostMouseRegion = true;
  static bool foundInnermostMouseRegion = false;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    var isHit = false;
    final outermost = isOutermostMouseRegion;
    isOutermostMouseRegion = false;
    if (size.contains(position)) {
      isHit =
          hitTestChildren(result, position: position) || hitTestSelf(position);
      if ((isHit || behavior == HitTestBehavior.translucent) &&
          !foundInnermostMouseRegion) {
        foundInnermostMouseRegion = true;
        result.add(BoxHitTestEntry(this, position));
      }
    }

    if (outermost) {
      // The outermost region resets the global states.
      isOutermostMouseRegion = true;
      foundInnermostMouseRegion = false;
    }
    return isHit;
  }
}

/// Flutter's `RawTooltip`, holding its global pointer route only while the
/// tooltip is pending or showing ([_HoldingRawTooltipState._holdRoute]).
///
/// It IS a [RawTooltip] — Flutter's configuration, this file's state — so
/// `find.byTooltip`, which reads a raw tooltip's semantics message, finds
/// it the way it finds Flutter's.
class _HoldingRawTooltip extends RawTooltip {
  const _HoldingRawTooltip({
    super.key,
    required super.semanticsTooltip,
    required super.tooltipBuilder,
    super.hoverDelay,
    super.touchDelay,
    super.dismissDelay,
    super.enableTapToDismiss,
    super.triggerMode,
    super.enableFeedback,
    super.onTriggered,
    super.positionDelegate,
    super.ignorePointer,
    required super.child,
  });

  static final List<_HoldingRawTooltipState> _openedTooltips =
      <_HoldingRawTooltipState>[];

  static bool dismissAll() {
    if (_openedTooltips.isEmpty) {
      return false;
    }
    // Avoid concurrent modification.
    final openedTooltips = _openedTooltips.toList();
    for (final state in openedTooltips) {
      assert(state.mounted);
      state._scheduleDismissTooltip();
    }
    return true;
  }

  @override
  State<RawTooltip> createState() => _HoldingRawTooltipState();
}

class _HoldingRawTooltipState extends State<RawTooltip>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _overlayController = OverlayPortalController();

  Timer? _timer;
  AnimationController? _backingController;
  AnimationController get _controller {
    return _backingController ??= AnimationController(
      duration: widget.animationStyle.duration,
      reverseDuration: widget.animationStyle.reverseDuration,
      vsync: this,
    )..addStatusListener(_handleStatusChanged);
  }

  CurvedAnimation? _backingOverlayAnimation;
  CurvedAnimation get _overlayAnimation {
    return _backingOverlayAnimation ??= CurvedAnimation(
      parent: _controller,
      curve: widget.animationStyle.curve ?? _kDefaultAnimationStyle.curve!,
    );
  }

  LongPressGestureRecognizer? _longPressRecognizer;
  TapGestureRecognizer? _tapRecognizer;

  // The ids of mouse devices that are keeping the tooltip from being
  // dismissed.
  final Set<int> _activeHoveringPointerDevices = <int>{};

  /// 🚨THE ONE DEPARTURE FROM FLUTTER. `RawTooltipState` adds its global
  /// route in `initState` and keeps it for its whole life; this one holds it
  /// exactly while [_handleGlobalPointerEvent] could do anything — a timer
  /// pending, or the controller anywhere but dismissed. Outside that window
  /// the handler returns before it looks at the event, so an unheld route
  /// is the same tooltip at none of the cost.
  bool _routeHeld = false;
  static int _routesHeld = 0;

  bool get _wantsRoute =>
      (_timer?.isActive ?? false) || !(_backingController?.isDismissed ?? true);

  void _holdRoute() {
    final wants = mounted && _wantsRoute;
    if (wants == _routeHeld) {
      return;
    }
    _routeHeld = wants;
    if (wants) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(
        _handleGlobalPointerEvent,
      );
      _routesHeld += 1;
    } else {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(
        _handleGlobalPointerEvent,
      );
      _routesHeld -= 1;
    }
  }

  AnimationStatus _animationStatus = AnimationStatus.dismissed;
  void _handleStatusChanged(AnimationStatus status) {
    assert(mounted);
    switch ((_animationStatus.isDismissed, status.isDismissed)) {
      case (false, true):
        _HoldingRawTooltip._openedTooltips.remove(this);
        _overlayController.hide();
      case (true, false):
        _overlayController.show();
        _HoldingRawTooltip._openedTooltips.add(this);
        unawaited(SemanticsService.tooltip(widget.semanticsTooltip ?? ''));
      case (true, true) || (false, false):
        break;
    }
    _animationStatus = status;
    _holdRoute();
  }

  void _scheduleShowTooltip({
    required Duration withDelay,
    Duration? touchDelay,
  }) {
    assert(mounted);
    void show() {
      assert(mounted);

      _controller.forward();
      _timer?.cancel();
      _timer = touchDelay == null ? null : Timer(touchDelay, _hideAfterTouch);
      _holdRoute();
    }

    assert(
      !(_timer?.isActive ?? false) ||
          _controller.status != AnimationStatus.reverse,
      'timer must not be active when the tooltip is animating out',
    );
    if (_controller.isDismissed && withDelay.inMicroseconds > 0) {
      _timer?.cancel();
      _timer = Timer(withDelay, show);
    } else {
      // If the tooltip is already animating in or fully visible, skip
      // the animation and show the tooltip immediately.
      show();
    }
    _holdRoute();
  }

  // Flutter's `Timer(touchDelay, _controller.reverse)`, and the route
  // re-asked once the timer is spent.
  void _hideAfterTouch() {
    _controller.reverse();
    _holdRoute();
  }

  void _scheduleDismissTooltip({Duration withDelay = Duration.zero}) {
    assert(mounted);
    assert(
      !(_timer?.isActive ?? false) ||
          _backingController?.status != AnimationStatus.reverse,
      'timer must not be active when the tooltip is animating out',
    );

    _timer?.cancel();
    _timer = null;
    // Use _backingController instead of _controller to prevent the lazy
    // getter from instantiating an AnimationController unnecessarily.
    if (_backingController?.isForwardOrCompleted ?? false) {
      // Dismiss when the tooltip is animating in: if there's a dismiss delay
      // we'll allow the animation to continue until the delay timer fires.
      if (withDelay.inMicroseconds > 0) {
        _timer = Timer(withDelay, _hideAfterTouch);
      } else {
        _controller.reverse();
      }
    }
    _holdRoute();
  }

  void _handlePointerDown(PointerDownEvent event) {
    // PointerDeviceKinds that don't support hovering.
    const triggerModeDeviceKinds = <PointerDeviceKind>{
      PointerDeviceKind.invertedStylus,
      PointerDeviceKind.stylus,
      PointerDeviceKind.touch,
      PointerDeviceKind.unknown,
      // MouseRegion only tracks PointerDeviceKind == mouse.
      PointerDeviceKind.trackpad,
    };
    switch (widget.triggerMode) {
      case TooltipTriggerMode.longPress:
        final recognizer = _longPressRecognizer ??= LongPressGestureRecognizer(
          debugOwner: this,
          supportedDevices: triggerModeDeviceKinds,
        );
        recognizer
          ..onLongPressCancel = _handleTapToDismiss
          ..onLongPress = _handleLongPress
          ..onLongPressUp = _handlePressUp
          ..addPointer(event);
      case TooltipTriggerMode.tap:
        final recognizer = _tapRecognizer ??= TapGestureRecognizer(
          debugOwner: this,
          supportedDevices: triggerModeDeviceKinds,
        );
        recognizer
          ..onTapCancel = _handleTapToDismiss
          ..onTap = _handleTap
          ..addPointer(event);
      case TooltipTriggerMode.manual:
        break;
    }
  }

  // For PointerDownEvents, this method will be called after
  // _handlePointerDown.
  void _handleGlobalPointerEvent(PointerEvent event) {
    assert(mounted);
    if (_tapRecognizer?.primaryPointer == event.pointer ||
        _longPressRecognizer?.primaryPointer == event.pointer) {
      // This is a pointer of interest specified by the trigger mode, since
      // it's picked up by the recognizer.
      return;
    }
    if ((_timer == null && _controller.isDismissed) ||
        event is! PointerDownEvent) {
      return;
    }
    _handleTapToDismiss();
  }

  // The primary pointer is not part of a "trigger" gesture so the tooltip
  // should be dismissed.
  void _handleTapToDismiss() {
    if (!widget.enableTapToDismiss) {
      return;
    }
    _scheduleDismissTooltip();
    _activeHoveringPointerDevices.clear();
  }

  void _handleTap() {
    final tooltipCreated = _controller.isDismissed;
    if (tooltipCreated && widget.enableFeedback) {
      assert(widget.triggerMode == TooltipTriggerMode.tap);
      unawaited(Feedback.forTap(context));
    }
    widget.onTriggered?.call();
    _scheduleShowTooltip(
      withDelay: Duration.zero,
      // _activeHoveringPointerDevices keep the tooltip visible.
      touchDelay: _activeHoveringPointerDevices.isEmpty
          ? widget.touchDelay
          : null,
    );
  }

  // When a "trigger" gesture is recognized and the pointer down even is a
  // part of it.
  void _handleLongPress() {
    final tooltipCreated = _controller.isDismissed;
    if (tooltipCreated && widget.enableFeedback) {
      assert(widget.triggerMode == TooltipTriggerMode.longPress);
      unawaited(Feedback.forLongPress(context));
    }
    widget.onTriggered?.call();
    _scheduleShowTooltip(withDelay: Duration.zero);
  }

  void _handlePressUp() {
    if (_activeHoveringPointerDevices.isNotEmpty) {
      return;
    }
    _scheduleDismissTooltip(withDelay: widget.touchDelay);
  }

  void _handleMouseEnter(PointerEnterEvent event) {
    // Called only when the mouse starts to hover over this tooltip (including
    // the actual tooltip it shows on the overlay), and this tooltip is the
    // first to be hit in the widget tree's hit testing order.
    _activeHoveringPointerDevices.add(event.device);
    // Dismiss other open tooltips unless they're kept visible by other mice.
    // The mouse tracker always dispatches all `onExit` events before any
    // `onEnter` events, so `event.device` must have already been removed
    // from the tooltips that are no longer being hovered over.
    final tooltipsToDismiss = _HoldingRawTooltip._openedTooltips
        .where((tooltip) => tooltip._activeHoveringPointerDevices.isEmpty)
        .toList();
    for (final tooltip in tooltipsToDismiss) {
      assert(tooltip.mounted);
      tooltip._scheduleDismissTooltip();
    }
    _scheduleShowTooltip(
      withDelay: tooltipsToDismiss.isNotEmpty
          ? Duration.zero
          : widget.hoverDelay,
    );
  }

  void _handleMouseExit(PointerExitEvent event) {
    if (_activeHoveringPointerDevices.isEmpty) {
      return;
    }
    _activeHoveringPointerDevices.remove(event.device);
    if (_activeHoveringPointerDevices.isEmpty) {
      _scheduleDismissTooltip(withDelay: widget.dismissDelay);
    }
  }

  /// Shows the tooltip if it is not already visible.
  bool ensureTooltipVisible() {
    _timer?.cancel();
    _timer = null;
    if (_controller.isForwardOrCompleted) {
      _holdRoute();
      return false;
    }
    _scheduleShowTooltip(withDelay: Duration.zero);
    return true;
  }

  Widget _buildTooltipOverlay(
    BuildContext context,
    OverlayChildLayoutInfo layoutInfo,
  ) {
    if (layoutInfo.childPaintTransform.determinant() == 0.0) {
      // The child is not visible.
      return const SizedBox.shrink();
    }
    final target = MatrixUtils.transformPoint(
      layoutInfo.childPaintTransform,
      layoutInfo.childSize.center(Offset.zero),
    );

    // Keep the tooltip visible while the overlay child is hovered.
    final Widget tooltip = IgnorePointer(
      ignoring: widget.ignorePointer,
      child: _ExclusiveMouseRegion(
        onEnter: _handleMouseEnter,
        onExit: _handleMouseExit,
        child: widget.tooltipBuilder(context, _overlayAnimation),
      ),
    );

    final Widget overlayChild = Positioned.fill(
      bottom: MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0.0,
      child: CustomSingleChildLayout(
        delegate: _TooltipPositionDelegate(
          target: target,
          targetSize: layoutInfo.childSize,
          positionDelegate: widget.positionDelegate,
        ),
        child: tooltip,
      ),
    );

    return SelectionContainer.maybeOf(context) == null
        ? overlayChild
        : SelectionContainer.disabled(child: overlayChild);
  }

  @override
  void dispose() {
    if (_routeHeld) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(
        _handleGlobalPointerEvent,
      );
      _routeHeld = false;
      _routesHeld -= 1;
    }
    _HoldingRawTooltip._openedTooltips.remove(this);
    // _longPressRecognizer.dispose() and _tapRecognizer.dispose() may call
    // their registered onCancel callbacks if there's a gesture in progress.
    // Remove the onCancel callbacks to prevent the registered callbacks from
    // triggering unnecessary side effects (such as animations).
    _longPressRecognizer?.onLongPressCancel = null;
    _longPressRecognizer?.dispose();
    _tapRecognizer?.onTapCancel = null;
    _tapRecognizer?.dispose();
    _timer?.cancel();
    _backingController?.dispose();
    _backingOverlayAnimation?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If message is empty then no need to create a tooltip overlay to show
    // the empty black container so just return the wrapped child as is or
    // empty container if child is not specified.
    if (widget.semanticsTooltip?.isEmpty ?? false) {
      return widget.child;
    }
    assert(debugCheckHasOverlay(context));
    final excludeFromSemantics =
        widget.semanticsTooltip == null || widget.semanticsTooltip!.isEmpty;
    Widget result = Semantics(
      tooltip: excludeFromSemantics ? null : widget.semanticsTooltip,
      child: widget.child,
    );

    // Only check for gestures if tooltip should be visible.
    result = _ExclusiveMouseRegion(
      onEnter: _handleMouseEnter,
      onExit: _handleMouseExit,
      child: Listener(
        onPointerDown: _handlePointerDown,
        behavior: HitTestBehavior.opaque,
        child: result,
      ),
    );

    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _overlayController,
      overlayChildBuilder: _buildTooltipOverlay,
      child: result,
    );
  }
}

/// Flutter's `_TooltipPositionDelegate`.
class _TooltipPositionDelegate extends SingleChildLayoutDelegate {
  _TooltipPositionDelegate({
    required this.target,
    required this.targetSize,
    this.positionDelegate,
  });

  final Offset target;
  final Size targetSize;
  final TooltipPositionDelegate? positionDelegate;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    if (positionDelegate != null) {
      return positionDelegate!(
        TooltipPositionContext(
          target: target,
          targetSize: targetSize,
          tooltipSize: childSize,
          overlaySize: size,
          verticalOffset: 0.0,
        ),
      );
    }
    return positionDependentBox(
      size: size,
      childSize: childSize,
      target: target,
      preferBelow: true,
    );
  }

  @override
  bool shouldRelayout(_TooltipPositionDelegate oldDelegate) {
    return target != oldDelegate.target ||
        targetSize != oldDelegate.targetSize ||
        positionDelegate != oldDelegate.positionDelegate;
  }
}

/// Material's `_TooltipBox`.
class _TooltipBox extends StatelessWidget {
  const _TooltipBox({
    required this.constraints,
    required this.textStyle,
    required this.textAlign,
    required this.decoration,
    required this.padding,
    required this.margin,
    required this.richMessage,
  });

  final BoxConstraints constraints;
  final TextStyle textStyle;
  final TextAlign textAlign;
  final Decoration? decoration;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final InlineSpan richMessage;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: constraints,
      child: DefaultTextStyle(
        style: textStyle,
        textAlign: textAlign,
        child: Container(
          decoration: decoration,
          padding: padding,
          margin: margin,
          child: Center(
            widthFactor: 1.0,
            heightFactor: 1.0,
            child: Text.rich(
              richMessage,
              style: textStyle,
              textAlign: textAlign,
            ),
          ),
        ),
      ),
    );
  }
}

/// What a summoned tooltip stands over ([SummonedTooltip]): its message,
/// where it stands on screen, and the context its window is shown from.
abstract interface class SummonedTooltipTarget {
  String get tooltipMessage;

  /// Where the target stands, in global coordinates — null while it is not
  /// laid out on screen.
  Rect? get tooltipGlobalRect;

  /// The context the window is shown from — its overlay and its theme. Null
  /// once the target is gone.
  BuildContext? get tooltipContext;
}

/// ONE TOOLTIP WINDOW, summoned by whatever is under the pointer — for the
/// controls that are too many to each hold a tooltip of their own.
///
/// 🚨WHY (I-57 ①, 10-09): a timeline rail row carried seven tooltips, each
/// with its own state, its own overlay portal and its own pointer handlers —
/// nine elements apiece, every one of them made again on a cut switch,
/// which mounts every visible row anew. Only one tooltip is ever open at a
/// time, so one window is all a crowd of them needs.
///
/// ⛔The rules are [AppTooltip]'s — Flutter's — and only the HOLDER is new:
/// a hovering mouse opens the window after the hover wait (zero here, 유저
/// F-53) and lets it go after the exit delay; a long press opens it and the
/// lift lets it go after the show duration; a press anywhere else dismisses
/// it. It looks and times as [AppTooltipLook] says, the same resolution an
/// [AppTooltip] wears.
abstract final class SummonedTooltip {
  static _Window? _window;

  /// The target the window is open over, or about to open over — for tests.
  @visibleForTesting
  static SummonedTooltipTarget? get debugTarget => _window?.target;

  /// The message of the open window, or null — for tests.
  @visibleForTesting
  static String? get debugShownMessage =>
      _window?.isShown ?? false ? _window!.target.tooltipMessage : null;

  /// A mouse entered [target].
  static void hover(SummonedTooltipTarget target) {
    final window = _windowFor(target);
    window?.showAfter(window.look.hoverDelay);
  }

  /// The mouse left [target].
  static void unhover(SummonedTooltipTarget target) {
    final window = _window;
    if (window != null && identical(window.target, target)) {
      window.hideAfter(window.look.dismissDelay);
    }
  }

  /// [target] was pressed long enough: the window opens at once, with the
  /// feedback a long-pressed tooltip gives.
  static void longPressed(SummonedTooltipTarget target, int pointer) {
    final window = _windowFor(target);
    if (window == null) {
      return;
    }
    final context = target.tooltipContext;
    if (context != null && window.look.enableFeedback) {
      unawaited(Feedback.forLongPress(context));
    }
    window
      ..triggerPointer = pointer
      ..showAfter(Duration.zero);
  }

  /// The press that opened [target]'s window came up: the window stays for
  /// the show duration.
  static void lifted(SummonedTooltipTarget target) {
    final window = _window;
    if (window != null && identical(window.target, target)) {
      window.hideAfter(window.look.touchDelay);
    }
  }

  /// A target with something to say was hit — so an [AppTooltip] around it
  /// does not answer the same hover. Flutter's rule for nested tooltips
  /// ([_ExclusiveMouseRegion]): only the innermost one shows. 🧪Measured
  /// 2026-10-24: a project tab's ✕ stands inside the tab's own tooltip, and
  /// both would show over the ✕ without this.
  static void standInnermost() {
    if (!_RenderExclusiveMouseRegion.isOutermostMouseRegion) {
      _RenderExclusiveMouseRegion.foundInnermostMouseRegion = true;
    }
  }

  /// [target] is gone: its window goes with it, at once.
  static void forget(SummonedTooltipTarget target) {
    final window = _window;
    if (window != null && identical(window.target, target)) {
      window.close();
    }
  }

  /// Lets the window go, if one is open — the fade out a dismissed
  /// [AppTooltip] gives. Answers whether one was.
  static bool dismiss() {
    final window = _window;
    if (window == null) {
      return false;
    }
    window.dismiss();
    return true;
  }

  /// The window for [target]: the open one when it is already over
  /// [target], else a new one replacing whatever was open — or null when
  /// [target] has nothing to say (an empty message shows nothing, as on an
  /// [AppTooltip]) or nowhere to say it.
  static _Window? _windowFor(SummonedTooltipTarget target) {
    if (target.tooltipMessage.isEmpty) {
      return null;
    }
    final current = _window;
    if (current != null && identical(current.target, target)) {
      return current;
    }
    final context = target.tooltipContext;
    if (context == null || !TooltipVisibility.of(context)) {
      return null;
    }
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      return null;
    }
    // The window it replaces fades out as the new one fades in — Flutter's
    // hover dismisses the other open tooltips, it does not tear them down.
    current?.retire();
    return _window = _Window(
      target: target,
      overlay: overlay,
      look: AppTooltipLook.of(context),
    );
  }
}

/// The one open window: its overlay entry, its fade and its timers.
final class _Window implements TickerProvider {
  _Window({required this.target, required this.overlay, required this.look});

  final SummonedTooltipTarget target;
  final OverlayState overlay;
  final AppTooltipLook look;

  /// The pointer whose long press opened the window — its own events do not
  /// dismiss it.
  int? triggerPointer;

  Timer? _timer;
  OverlayEntry? _entry;
  bool _routeHeld = false;

  late final AnimationController _fade = AnimationController(
    duration: const Duration(milliseconds: 150),
    reverseDuration: const Duration(milliseconds: 75),
    vsync: this,
  )..addStatusListener(_onFadeStatus);

  late final CurvedAnimation _opacity = CurvedAnimation(
    parent: _fade,
    curve: Curves.fastOutSlowIn,
  );

  bool get isShown => _entry != null && !_fade.isDismissed;

  @override
  Ticker createTicker(TickerCallback onTick) =>
      Ticker(onTick, debugLabel: 'SummonedTooltip');

  void showAfter(Duration delay) {
    if (_closed) {
      return;
    }
    // Held BEFORE the step: a show that finds its target gone closes the
    // window, and the close has to find the route to let it go.
    _holdRoute(true);
    _after(delay, _show);
  }

  void hideAfter(Duration delay) {
    if (!_closed) {
      _after(delay, _hide);
    }
  }

  /// [step] after [delay] — at once where there is none — in place of any
  /// step still waiting.
  void _after(Duration delay, VoidCallback step) {
    _timer?.cancel();
    _timer = delay > Duration.zero ? Timer(delay, step) : null;
    if (delay <= Duration.zero) {
      step();
    }
  }

  void _show() {
    _timer = null;
    if (_closed) {
      return;
    }
    final rect = target.tooltipGlobalRect;
    if (rect == null || !overlay.mounted) {
      close();
      return;
    }
    if (_entry == null) {
      final entry = _entry = OverlayEntry(
        builder: (context) => _SummonedWindow(
          overlay: overlay,
          targetGlobalRect: rect,
          look: look,
          message: target.tooltipMessage,
          opacity: _opacity,
        ),
      );
      overlay.insert(entry);
      unawaited(SemanticsService.tooltip(target.tooltipMessage));
    }
    _fade.forward();
  }

  void _hide() {
    _timer = null;
    _fade.reverse();
  }

  void _onFadeStatus(AnimationStatus status) {
    if (status.isDismissed) {
      if (_retired) {
        close();
        return;
      }
      _removeEntry();
      _holdRoute(_timer?.isActive ?? false);
    }
  }

  /// Flutter's `_scheduleDismissTooltip()`: a step still waiting is dropped,
  /// and a window that is showing, or on its way, fades out.
  ///
  /// ↩️A press elsewhere and a hover onto another target tore the window
  /// down at once (I-57 ①, 10-09), where every [AppTooltip] fades out over
  /// 75ms. 🧪Measured 2026-10-25 side by side — a click on the target, a
  /// hover from one target to the next — and the rail's glyphs and, since
  /// the day before, the icon buttons were the ones that blinked out.
  void dismiss() {
    if (_closed) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    if (_fade.isForwardOrCompleted) {
      _fade.reverse();
    } else if (_fade.isDismissed) {
      _holdRoute(false);
    }
  }

  bool _retired = false;

  /// No longer the open window — another target's took its place. It fades
  /// out as [dismiss] lets it go, and is gone for good once it has.
  void retire() {
    _retired = true;
    dismiss();
    if (_fade.isDismissed) {
      close();
    }
  }

  void _removeEntry() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  bool _closed = false;

  /// Gone for good — the timers, the entry, the route and the fade. Closing
  /// twice is closing once.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _removeEntry();
    _holdRoute(false);
    _opacity.dispose();
    _fade.dispose();
    if (identical(SummonedTooltip._window, this)) {
      SummonedTooltip._window = null;
    }
  }

  /// The global route a press elsewhere dismisses the window by — held only
  /// while a window is pending or open, as [AppTooltip] holds its own.
  void _holdRoute(bool wants) {
    if (wants == _routeHeld) {
      return;
    }
    _routeHeld = wants;
    final router = GestureBinding.instance.pointerRouter;
    if (wants) {
      router.addGlobalRoute(_onGlobalPointer);
    } else {
      router.removeGlobalRoute(_onGlobalPointer);
    }
  }

  void _onGlobalPointer(PointerEvent event) {
    if (event is! PointerDownEvent || event.pointer == triggerPointer) {
      return;
    }
    // Any press elsewhere: the window goes — on a later turn, so the router
    // is not handed a route list it is walking.
    scheduleMicrotask(() {
      if (identical(SummonedTooltip._window, this)) {
        dismiss();
      }
    });
  }
}

/// The window itself: [look]'s box with [message], standing where
/// [look] places a tooltip for the target's box, fading with [opacity].
/// Pointers pass through it, as a message tooltip's do.
class _SummonedWindow extends StatelessWidget {
  const _SummonedWindow({
    required this.overlay,
    required this.targetGlobalRect,
    required this.look,
    required this.message,
    required this.opacity,
  });

  final OverlayState overlay;
  final Rect targetGlobalRect;
  final AppTooltipLook look;
  final String message;
  final Animation<double> opacity;

  @override
  Widget build(BuildContext context) {
    final overlayBox = overlay.context.findRenderObject();
    final origin = overlayBox is RenderBox && overlayBox.hasSize
        ? overlayBox.globalToLocal(targetGlobalRect.topLeft)
        : targetGlobalRect.topLeft;
    final target = origin & targetGlobalRect.size;
    return Positioned.fill(
      bottom: MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0.0,
      child: CustomSingleChildLayout(
        delegate: _WindowPosition(target: target, look: look),
        child: IgnorePointer(
          child: look.fadingBox(TextSpan(text: message), opacity),
        ),
      ),
    );
  }
}

class _WindowPosition extends SingleChildLayoutDelegate {
  _WindowPosition({required this.target, required this.look});

  final Rect target;
  final AppTooltipLook look;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => look.positionFor(
    TooltipPositionContext(
      target: target.center,
      targetSize: target.size,
      tooltipSize: childSize,
      overlaySize: size,
      verticalOffset: look.verticalOffset,
      preferBelow: look.preferBelow,
    ),
  );

  @override
  bool shouldRelayout(_WindowPosition oldDelegate) =>
      target != oldDelegate.target || !identical(look, oldDelegate.look);
}
