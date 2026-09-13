import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../debug/input_inspector.dart';
import '../input/pen_friendly_scroll_controller.dart';

/// PEN-9: a stylus approaching the timeline stops any COASTING scroll.
///
/// While a fling glides, the scrollable ignore-pointers its children, so
/// a pen landing mid-glide never reaches the cell/selection layers — the
/// drag falls to the scroll recognizer and the pen "scrolls" no matter
/// how the arena is tuned (the tablet's "touch fling, then pen selects →
/// scroll" bug; R22F's eager slop can't help a child that was never hit-
/// tested). EMR pens (S-Pen/Wacom) hover before contact, so stopping the
/// glide on hover restores the child hit-test before the tip lands; the
/// pointer-down stop is the fallback for the first contact of pens that
/// deliver no hover. Stopping a coast is exactly the tap-to-stop gesture,
/// so the pen loses nothing.
///
/// PEN-10 adds the second belt: every stylus event marks the wrapped
/// [PenFriendlyScrollPosition]s pen-nearby for a short window, so a coast
/// that starts (or survives) with the pen close keeps the children
/// hittable even when no hover movement precedes the landing.
///
/// A FINGER drag must never be yanked from under the hand (pens hover
/// while fingers scroll), so only axes whose latest update was not
/// finger-driven — a ballistic coast or an auto-scroll — are stopped.
class StylusGlideStop extends StatefulWidget {
  const StylusGlideStop({
    super.key,
    required this.controllers,
    required this.child,
  });

  /// The wrapped grid's own scroll controllers (the ones whose viewports
  /// sit below this widget — synced mirror controllers need no entry:
  /// they follow by jumpTo, which never ignore-pointers).
  final List<ScrollController> controllers;

  final Widget child;

  @override
  State<StylusGlideStop> createState() => _StylusGlideStopState();
}

class _StylusGlideStopState extends State<StylusGlideStop> {
  /// Axes whose most recent scroll update carried no drag details — a
  /// coasting fling (or a programmatic scroll; stopping those on pen
  /// approach is equally safe).
  final Set<Axis> _coasting = <Axis>{};

  Timer? _penNearbyTimer;

  @override
  void dispose() {
    _penNearbyTimer?.cancel();
    super.dispose();
  }

  bool _handleNotification(ScrollNotification notification) {
    final axis = notification.metrics.axis;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      // PEN-11 probe: a USER drag just claimed a timeline scroll — the
      // arena verdict from the scroll's side.
      InputInspector.note('scr dragstart ${axis.name[0]}');
    }
    if (notification is ScrollUpdateNotification) {
      if (notification.dragDetails == null) {
        _coasting.add(axis);
      } else {
        _coasting.remove(axis);
      }
    } else if (notification is ScrollEndNotification) {
      _coasting.remove(axis);
    }
    return false;
  }

  bool _isStylus(PointerEvent event) =>
      event.kind == PointerDeviceKind.stylus ||
      event.kind == PointerDeviceKind.invertedStylus;

  void _stopGlides(PointerEvent event) {
    if (!_isStylus(event)) {
      return;
    }
    _markPenNearby();
    if (_coasting.isEmpty) {
      return;
    }
    for (final controller in widget.controllers) {
      for (final position in controller.positions) {
        if (_coasting.contains(position.axis) &&
            position.isScrollingNotifier.value) {
          position.jumpTo(position.pixels);
        }
      }
    }
    _coasting.clear();
  }

  /// PEN-10: the pen was just seen — keep coasting viewports hittable
  /// for a short window (see [PenFriendlyScrollPosition.penNearby]).
  void _markPenNearby() {
    _setPenNearby(true);
    _penNearbyTimer?.cancel();
    _penNearbyTimer = Timer(
      const Duration(seconds: 2),
      () => _setPenNearby(false),
    );
  }

  void _setPenNearby(bool value) {
    for (final controller in widget.controllers) {
      for (final position in controller.positions) {
        if (position is PenFriendlyScrollPosition) {
          position.penNearby = value;
        }
      }
    }
  }

  /// PEN-10 field diagnosis: with the Input Inspector open, every
  /// pointer-down over the timeline logs its kind plus the scroll state
  /// it landed into ('cst'=coasting axes, 'scr'=axes with a live scroll
  /// activity). Paired with the range layer's `range IN=` note, one glance
  /// separates a kind misreport (dn=touch while using the pen) from a
  /// hit-test exclusion (dn=stylus without a following IN) — two slots on
  /// the inspector, so the pair can be read together.
  void _noteDown(PointerEvent event) {
    if (!InputInspector.visible.value) {
      return;
    }
    final scrolling = <String>[];
    for (final controller in widget.controllers) {
      for (final position in controller.positions) {
        if (position.isScrollingNotifier.value) {
          scrolling.add(position.axis.name[0]);
        }
      }
    }
    InputInspector.note(
      'tl dn=${event.kind.name}'
      ' cst=${_coasting.map((axis) => axis.name[0]).join()}'
      ' scr=${scrolling.join()}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _handleNotification,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: _stopGlides,
        onPointerDown: (event) {
          _noteDown(event);
          _stopGlides(event);
        },
        child: widget.child,
      ),
    );
  }
}
