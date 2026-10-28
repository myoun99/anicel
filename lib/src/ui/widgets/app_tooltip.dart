// Adapted from Flutter's `widgets/raw_tooltip.dart` and
// `material/tooltip.dart` (Flutter 3.47.4):
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// THE APP'S TOOLTIP around anything that is not a light face — ONE box
/// that summons the window every tooltip in the app shares
/// ([SummonedTooltip]), as the light faces do ([SummonsTooltip]).
///
/// 🚨WHY ONE BOX (card frame-panels-build-in-one-frame, 2026-10-25): it was
/// Flutter's `Tooltip` with its own state, overlay portal, exclusive mouse
/// region, listener and two semantics nodes — nine elements apiece, 33 of
/// them on the default screen, each made anew whenever a panel is shown
/// again. Only one tooltip is ever open at a time.
///
/// ↩️Before that (09-25, measured on the real app, the user's layout) it was
/// Flutter's, holding its global pointer route only while it showed: 288
/// tooltips mounted, and Flutter's registers a route for every one of them
/// that `PointerRouter` calls on every pen sample. The window holds the one
/// route only while it is pending or open.
///
/// ⛔The rules are Flutter's — the hover, the nesting (only the innermost
/// tooltip shows), the long press, the fade, the position and the Material
/// look from [TooltipTheme] ([AppTooltipLook]). Changing any of it here is
/// changing the app's tooltip, not fixing a cost.
class AppTooltip extends SingleChildRenderObjectWidget {
  const AppTooltip({
    super.key,
    required this.message,
    this.triggerMode,
    super.child,
  });

  /// What it says. Empty says nothing: the box is its child alone, as an
  /// empty `Tooltip` is.
  final String message;

  /// How a hand that cannot hover opens it — the theme's where null
  /// ([AppTooltipLook.triggerModeIn]). Only a long press opens it, as on
  /// every light face; anything else leaves it to the hover.
  final TooltipTriggerMode? triggerMode;

  /// Dismisses every tooltip on screen — the window ([SummonedTooltip]) and
  /// any of Flutter's own.
  static bool dismissAllToolTips() {
    final summoned = SummonedTooltip.dismiss();
    final theirs = Tooltip.dismissAllToolTips();
    return summoned || theirs;
  }

  _Saying _sayingIn(BuildContext context) => (
    message: message,
    triggerMode: triggerMode ?? AppTooltipLook.triggerModeIn(context),
    // A node that carries text says which way it reads, as [Semantics]
    // gives a tooltip the ambient direction.
    reading: Directionality.maybeOf(context),
  );

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAppTooltip(_sayingIn(context), tooltipContext: context);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderAppTooltip)
      ..tooltipContext = context
      .._wear(_sayingIn(context));
  }
}

/// What an [AppTooltip] says, read where it stands.
typedef _Saying = ({
  String message,
  TooltipTriggerMode triggerMode,
  TextDirection? reading,
});

/// [AppTooltip]'s box: its child, the press it takes for the long press, the
/// hover it hands the window and the tooltip a screen reader hears.
class _RenderAppTooltip extends RenderProxyBox with SummonsTooltip {
  _RenderAppTooltip(this._saying, {required BuildContext tooltipContext}) {
    this.tooltipContext = tooltipContext;
  }

  _Saying _saying;
  void _wear(_Saying value) {
    final old = _saying;
    // ⚠️Set before it is marked: marking reads the configuration at once.
    _saying = value;
    if (value.message != old.message || value.reading != old.reading) {
      markNeedsSemanticsUpdate();
    }
  }

  @override
  String get tooltipMessage => _saying.message;

  /// The hover's target, apart from the box: the box takes every press in
  /// it, but only the innermost tooltip answers a hover.
  late final _TooltipHover _hover = _TooltipHover(this);

  /// Flutter's tooltip: an OPAQUE listener over its child — the whole box
  /// takes a press, as the listener did — inside an EXCLUSIVE mouse region,
  /// on the path only when no tooltip inside it is ([_Nesting]).
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_saying.message.isEmpty) {
      return super.hitTest(result, position: position);
    }
    final outermost = _Nesting.outermost;
    _Nesting.outermost = false;
    var hit = false;
    if (size.contains(position)) {
      hitTestChildren(result, position: position);
      result.add(BoxHitTestEntry(this, position));
      hit = true;
      if (!_Nesting.innermostFound) {
        _Nesting.innermostFound = true;
        result.add(HitTestEntry(_hover));
      }
    }
    if (outermost) {
      _Nesting.outermost = true;
      _Nesting.innermostFound = false;
    }
    return hit;
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      summonOnLongPress(event, _saying.triggerMode);
    }
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    if (_saying.message.isEmpty) {
      return;
    }
    config.tooltip = _saying.message;
    if (_saying.reading case final reading?) {
      config.textDirection = reading;
    }
  }
}

/// What a mouse over an [AppTooltip] meets: the window opens as it enters
/// and goes as it leaves.
final class _TooltipHover
    with Diagnosticable
    implements HitTestTarget, MouseTrackerAnnotation {
  _TooltipHover(this._box);

  final _RenderAppTooltip _box;

  @override
  MouseCursor get cursor => MouseCursor.defer;

  @override
  PointerEnterEventListener? get onEnter =>
      (_) => SummonedTooltip.hover(_box);

  @override
  PointerExitEventListener? get onExit =>
      (_) => SummonedTooltip.unhover(_box);

  @override
  bool get validForMouseTracker => _box.attached;

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {}
}

/// Flutter's rule for nested tooltips (its `_ExclusiveMouseRegion`): only
/// the first tooltip hit in hit-testing order — the innermost — answers a
/// hover. The outermost tooltip's hit test resets both.
abstract final class _Nesting {
  static bool outermost = true;
  static bool innermostFound = false;
}

/// HOW THE APP'S TOOLTIPS LOOK AND TIME — [TooltipState]'s resolution,
/// lifted out of the widget: the theme's ([TooltipTheme]), then Material's
/// default.
///
/// ONE resolution for the one window every tooltip in the app summons
/// ([SummonedTooltip]), and for the trigger every summoner opens it by
/// ([triggerModeIn]).
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
  });

  /// The look in [context].
  factory AppTooltipLook.of(BuildContext context) {
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
            tooltipTheme.constraints ??
            defaultConstraints,
        textStyle:
            tooltipTheme.textStyle ?? defaultTextStyle,
        textAlign:
            tooltipTheme.textAlign ?? _defaultTextAlign,
        decoration:
            tooltipTheme.decoration ??
            defaultDecoration,
        padding:
            tooltipTheme.padding ??
            _defaultPadding(platform),
        margin: tooltipTheme.margin ?? _defaultMargin,
        richMessage: message,
      ),
      verticalOffset:
          tooltipTheme.verticalOffset ??
          _defaultVerticalOffset,
      preferBelow:
          tooltipTheme.preferBelow ??
          _defaultPreferBelow,
      hoverDelay:
          tooltipTheme.waitDuration ??
          _defaultWaitDuration,
      touchDelay:
          tooltipTheme.showDuration ??
          _defaultShowDuration,
      dismissDelay:
          tooltipTheme.exitDuration ??
          _defaultExitDuration,
      triggerMode: triggerModeIn(context),
      enableFeedback:
          tooltipTheme.enableFeedback ??
          _defaultEnableFeedback,
    );
  }

  static const double _defaultVerticalOffset = 24.0;
  static const bool _defaultPreferBelow = true;
  static const EdgeInsetsGeometry _defaultMargin = EdgeInsets.zero;
  static const Duration _defaultShowDuration = Duration(milliseconds: 1500);
  static const Duration _defaultExitDuration = Duration(milliseconds: 100);
  static const Duration _defaultWaitDuration = Duration.zero;
  static const TooltipTriggerMode _defaultTriggerMode =
      TooltipTriggerMode.longPress;

  /// How a hand that cannot hover opens a tooltip in [context] — the
  /// theme's, else a long press. What every summoner reads, the light faces
  /// and [AppTooltip] alike.
  static TooltipTriggerMode triggerModeIn(BuildContext context) =>
      TooltipTheme.of(context).triggerMode ?? _defaultTriggerMode;
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

/// WHAT SUMMONS THE WINDOW ([SummonedTooltip]) — the box it stands over,
/// the long press that opens it for a hand that cannot hover, and its going
/// with the box. One code for every box that says something: the light
/// faces (`PressFace`) and the tooltip around anything else ([AppTooltip]).
mixin SummonsTooltip on RenderBox implements SummonedTooltipTarget {
  BuildContext? _tooltipContext;
  set tooltipContext(BuildContext value) => _tooltipContext = value;

  /// The tooltip's own trigger on a touch or a pen: Flutter's, the devices
  /// that cannot hover.
  late final LongPressGestureRecognizer _longPress = LongPressGestureRecognizer(
    debugOwner: this,
    supportedDevices: const {
      PointerDeviceKind.invertedStylus,
      PointerDeviceKind.stylus,
      PointerDeviceKind.touch,
      PointerDeviceKind.unknown,
      PointerDeviceKind.trackpad,
    },
  )
    ..onLongPress = _onLongPress
    ..onLongPressUp = _onLongPressUp
    ..onLongPressCancel = _onLongPressCancel;

  /// Enters the press [event] begins into the long press that opens the
  /// window, where [mode] says a long press does.
  @protected
  void summonOnLongPress(PointerDownEvent event, TooltipTriggerMode mode) {
    if (mode == TooltipTriggerMode.longPress) {
      _longPress.addPointer(event);
    }
  }

  void _onLongPress() {
    if (_longPress.primaryPointer case final pointer?) {
      SummonedTooltip.longPressed(this, pointer);
    }
  }

  void _onLongPressUp() => SummonedTooltip.lifted(this);

  /// A press that moved off or was taken before it was long: whatever this
  /// box had summoned goes, as a tooltip's own cancel dismisses it.
  void _onLongPressCancel() => SummonedTooltip.forget(this);

  @override
  Rect? get tooltipGlobalRect => attached && hasSize
      ? MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size)
      : null;

  @override
  BuildContext? get tooltipContext => attached ? _tooltipContext : null;

  @override
  void detach() {
    SummonedTooltip.forget(this);
    super.detach();
  }

  @override
  void dispose() {
    _longPress.dispose();
    super.dispose();
  }
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
/// ⛔The rules are Flutter's tooltip's, and only the HOLDER is new:
/// a hovering mouse opens the window after the hover wait (zero here, 유저
/// F-53) and lets it go after the exit delay; a long press opens it and the
/// lift lets it go after the show duration; a press anywhere else dismisses
/// it. It looks and times as [AppTooltipLook] says.
abstract final class SummonedTooltip {
  static _Window? _window;

  /// The target the window is open over, or about to open over — for tests.
  @visibleForTesting
  static SummonedTooltipTarget? get debugTarget =>
      _window?.isPendingOrShown ?? false ? _window!.target : null;

  /// How many windows are not yet closed — the open one, and any another
  /// target's took the place of while it fades out — for tests.
  @visibleForTesting
  static int get debugWindowsAlive => _Window._alive;

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
  /// ([_Nesting]): only the innermost one shows. 🧪Measured
  /// 2026-10-24: a project tab's ✕ stands inside the tab's own tooltip, and
  /// both would show over the ✕ without this.
  static void standInnermost() {
    if (!_Nesting.outermost) {
      _Nesting.innermostFound = true;
    }
  }

  /// [target] is gone: its window goes with it, at once.
  static void forget(SummonedTooltipTarget target) {
    final window = _window;
    if (window != null && identical(window.target, target)) {
      window.close();
    }
  }

  /// Lets the window go, if one is open — the fade out a dismissed Flutter
  /// tooltip gives. Answers whether one was.
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
  /// [target] has nothing to say (an empty message shows nothing, as on a
  /// Flutter tooltip) or nowhere to say it.
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
  _Window({required this.target, required this.overlay, required this.look}) {
    _alive += 1;
  }

  static int _alive = 0;

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

  /// Whether the window is on screen or on its way — not one let go
  /// ([dismiss]) and kept for its target's next hover, as a dismissed
  /// Flutter tooltip keeps its state.
  bool get isPendingOrShown =>
      !_closed && ((_timer?.isActive ?? false) || !_fade.isDismissed);

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
  /// down at once (I-57 ①, 10-09), where Flutter's tooltip fades out over
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
    _alive -= 1;
    _timer?.cancel();
    _timer = null;
    if (_entry != null) {
      // Gone in THIS frame, as a tooltip unmounted with its target was: an
      // overlay lets go of an entry removed mid-frame only on the next one.
      _fade.value = 0;
    }
    _removeEntry();
    _holdRoute(false);
    _opacity.dispose();
    _fade.dispose();
    if (identical(SummonedTooltip._window, this)) {
      SummonedTooltip._window = null;
    }
  }

  /// The global route a press elsewhere dismisses the window by — held only
  /// while a window is pending or open. ↩️Flutter's tooltip holds one for
  /// as long as it is mounted — 288 of them in the user's layout (09-25).
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
