// Adapted from Flutter's `widgets/raw_tooltip.dart` and
// `material/tooltip.dart` (Flutter 3.47.4):
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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

  /// Dismisses every tooltip on screen — these and any of Flutter's own.
  static bool dismissAllToolTips() {
    final ours = _HoldingRawTooltip.dismissAll();
    final theirs = Tooltip.dismissAllToolTips();
    return ours || theirs;
  }

  /// How many of these tooltips hold a global pointer route right now.
  @visibleForTesting
  static int get debugRoutesHeld => _HoldingRawTooltipState._routesHeld;

  @override
  State<Tooltip> createState() => AppTooltipState();
}

/// The state of an [AppTooltip] — [TooltipState]'s look, built over the
/// route-holding raw tooltip.
class AppTooltipState extends State<AppTooltip> {
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

  final GlobalKey<_HoldingRawTooltipState> _tooltipKey =
      GlobalKey<_HoldingRawTooltipState>();

  late bool _visible;
  late TooltipThemeData _tooltipTheme;

  String get _tooltipMessage =>
      widget.message ?? widget.richMessage!.toPlainText();

  /// Shows the tooltip if it is not already visible — [TooltipState]'s.
  bool ensureTooltipVisible() =>
      _tooltipKey.currentState?.ensureTooltipVisible() ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TooltipVisibility.of(context);
    _tooltipTheme = TooltipTheme.of(context);
  }

  double _getDefaultTooltipHeight() {
    return switch (Theme.of(context).platform) {
      TargetPlatform.macOS ||
      TargetPlatform.linux ||
      TargetPlatform.windows => 24.0,
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.iOS => 32.0,
    };
  }

  EdgeInsets _getDefaultPadding() {
    return switch (Theme.of(context).platform) {
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
  }

  static double _getDefaultFontSize(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.macOS ||
      TargetPlatform.linux ||
      TargetPlatform.windows => 12.0,
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.iOS => 14.0,
    };
  }

  Offset _getDefaultPositionDelegate(TooltipPositionContext context) {
    final effectiveVerticalOffset =
        widget.verticalOffset ??
        _tooltipTheme.verticalOffset ??
        _defaultVerticalOffset;
    final effectivePreferBelow =
        widget.preferBelow ?? _tooltipTheme.preferBelow ?? _defaultPreferBelow;
    final resolvedContext = TooltipPositionContext(
      target: context.target,
      targetSize: context.targetSize,
      tooltipSize: context.tooltipSize,
      overlaySize: context.overlaySize,
      verticalOffset: effectiveVerticalOffset,
      preferBelow: effectivePreferBelow,
    );
    return widget.positionDelegate?.call(resolvedContext) ??
        positionDependentBox(
          size: context.overlaySize,
          childSize: context.tooltipSize,
          target: context.target,
          verticalOffset: effectiveVerticalOffset,
          preferBelow: effectivePreferBelow,
        );
  }

  @override
  Widget build(BuildContext context) {
    if (_tooltipMessage.isEmpty) {
      return widget.child ?? const SizedBox.shrink();
    }
    final (
      TextStyle defaultTextStyle,
      BoxDecoration defaultDecoration,
    ) = switch (Theme.of(context)) {
      ThemeData(
        brightness: Brightness.dark,
        :final TextTheme textTheme,
        :final TargetPlatform platform,
      ) =>
        (
          textTheme.bodyMedium!.copyWith(
            color: Colors.black,
            fontSize: _getDefaultFontSize(platform),
          ),
          BoxDecoration(
            // Flutter's withOpacity(0.9): alpha (255 × 0.9).round().
            color: Colors.white.withAlpha(230),
            borderRadius: const BorderRadius.all(Radius.circular(4)),
          ),
        ),
      ThemeData(
        brightness: Brightness.light,
        :final TextTheme textTheme,
        :final TargetPlatform platform,
      ) =>
        (
          textTheme.bodyMedium!.copyWith(
            color: Colors.white,
            fontSize: _getDefaultFontSize(platform),
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
      minHeight: _tooltipTheme.height ?? _getDefaultTooltipHeight(),
    );

    final Widget tooltipBox = _TooltipBox(
      constraints:
          widget.constraints ?? _tooltipTheme.constraints ?? defaultConstraints,
      textStyle: widget.textStyle ?? _tooltipTheme.textStyle ?? defaultTextStyle,
      textAlign: widget.textAlign ?? _tooltipTheme.textAlign ?? _defaultTextAlign,
      decoration:
          widget.decoration ?? _tooltipTheme.decoration ?? defaultDecoration,
      padding: widget.padding ?? _tooltipTheme.padding ?? _getDefaultPadding(),
      margin: widget.margin ?? _tooltipTheme.margin ?? _defaultMargin,
      richMessage: widget.richMessage ?? TextSpan(text: widget.message),
    );

    Widget effectiveChild = MouseRegion(
      cursor: widget.mouseCursor ?? MouseCursor.defer,
      child: widget.child ?? const SizedBox.shrink(),
    );

    final excludeFromSemantics =
        widget.excludeFromSemantics ??
        _tooltipTheme.excludeFromSemantics ??
        _defaultExcludeFromSemantics;

    if (_visible) {
      effectiveChild = _HoldingRawTooltip(
        key: _tooltipKey,
        semanticsTooltip: excludeFromSemantics ? null : _tooltipMessage,
        tooltipBuilder: (BuildContext context, Animation<double> animation) =>
            FadeTransition(opacity: animation, child: tooltipBox),
        touchDelay:
            widget.showDuration ??
            _tooltipTheme.showDuration ??
            _defaultShowDuration,
        triggerMode:
            widget.triggerMode ??
            _tooltipTheme.triggerMode ??
            _defaultTriggerMode,
        enableFeedback:
            widget.enableFeedback ??
            _tooltipTheme.enableFeedback ??
            _defaultEnableFeedback,
        hoverDelay:
            widget.waitDuration ??
            _tooltipTheme.waitDuration ??
            _defaultWaitDuration,
        enableTapToDismiss: widget.enableTapToDismiss,
        onTriggered: widget.onTriggered,
        dismissDelay:
            widget.exitDuration ??
            _tooltipTheme.exitDuration ??
            _defaultExitDuration,
        positionDelegate: _getDefaultPositionDelegate,
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
