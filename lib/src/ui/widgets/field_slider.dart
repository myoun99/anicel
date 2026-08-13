import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../input/value_control_pointers.dart';
import '../text/vertical_writing_text.dart';
import '../theme/app_theme.dart';
import 'axis_bar_gesture.dart';

/// How a [FieldSlider] maps track position to value.
enum FieldSliderScale {
  /// Uniform mapping across the track.
  linear,

  /// Logarithmic mapping: equal track distance multiplies the value by a
  /// constant factor, so the left half of the track covers the small values
  /// where precision matters (brush size, spacing). Requires `min > 0`.
  exponential,
}

/// The app's shared settings slider: a filled-bar *field* where the whole bar
/// is the control (no thumb — friendlier to touch/stylus) and the label and
/// value live inside the track, so one row carries what used to take a label
/// row plus a slider plus a trailing value text.
///
/// Variants and interactions:
/// - `label == null` renders the micro variant (value only, centered) for
///   tight inline slots such as timeline layer rows.
/// - Drag or tap sets the value by absolute track position; holding Shift
///   switches to relative movement at 1/10 speed for fine control.
/// - The scroll wheel steps the value by 1% of the track (Shift: 0.1%); with
///   [divisions] it steps one division instead.
/// - A tap sets the value and KEEPS it, in every host and from every input
///   device — however much the hand wobbled while it landed. A scroll that
///   takes the gesture rolls the tentative jump back instead, so bars
///   inside scrollables stay safe to scroll over. What separates the two is
///   the DIRECTION the pointer went, not how far — see [_FieldSliderState].
///
/// It does NOT type (R10 R5). A bar is a bar: tap or drag sets the value,
/// and that is the whole control. The inline editor it used to carry was
/// reached by a DOUBLE-tap, which held every ordinary tap hostage for
/// 300ms — on the one control whose entire job is to answer a tap
/// immediately. The user: "수동입력 없어져도 ok. 어차피 조작할때
/// 번거롭기만했어."
///
/// Where an exact number really is needed, put a [DragValueLabel] BESIDE
/// the bar rather than inside it: that one types on a single tap, so the
/// app-wide rule ("tap = pick or edit, double-tap = open") stays whole.
class FieldSlider extends StatefulWidget {
  const FieldSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.valueText,
    this.onChangeEnd,
    this.valueTextBuilder,
    this.restingAccent,
    this.label,
    this.scale = FieldSliderScale.linear,
    this.divisions,
    this.fillOrigin,
    this.height = 24,
    this.axis = Axis.horizontal,
  }) : assert(max > min, 'max must exceed min'),
       assert(
         scale != FieldSliderScale.exponential || min > 0,
         'exponential scale requires min > 0',
       ),
       assert(
         divisions == null || scale == FieldSliderScale.linear,
         'divisions only combine with the linear scale',
       );

  /// Current value in model units (e.g. 0..1 for opacity).
  final double value;

  final double min;
  final double max;

  /// Live per-move callback; `null` disables the control (dimmed, inert).
  final ValueChanged<double>? onChanged;

  /// Fires once when a drag ends or a wheel step lands — the hook for
  /// commit-on-release consumers (opacity/zoom drag
  /// smoothness, R4 #4/#5): route the cheap live preview through
  /// [onChanged] and the real write through this.
  final ValueChanged<double>? onChangeEnd;

  /// Formats the live display text during a drag. Commit-on-release
  /// consumers don't rebuild this widget per move, so [valueText] would
  /// freeze while the bar echoes the gesture — this builder keeps the text
  /// following. Null falls back to [valueText] throughout.
  final String Function(double value)? valueTextBuilder;

  /// Fill/edge color while NOT interacting; the drag always paints the
  /// accent (the legend's master-opacity bar reads gray at rest, accent
  /// while adjusting — R4 #6). Null = accent always.
  final Color? restingAccent;

  /// Inside-left label; `null` renders the micro variant (value only).
  final String? label;

  /// Preformatted display string ('80%', '24 px', '45°', 'off').
  final String valueText;

  final FieldSliderScale scale;

  /// Snaps values to `divisions` equal steps (linear scale only).
  final int? divisions;

  /// The value the filled bar grows FROM; null means [min], which is what a
  /// quantity wants (a fader reads "how much"). A BALANCE — pan, a signed
  /// offset — passes its neutral value instead, so the fill leaves centre
  /// in the direction of the setting and hard-left stops reading as empty.
  final double? fillOrigin;

  /// The bar's extent ACROSS its axis — thickness, not length. The length
  /// always comes from the host.
  final double height;

  /// Which way the track runs. Vertical fills upward from the bottom and
  /// is dragged up/down — the x-sheet's stood-up rail, where a 28px column
  /// has no room for a horizontal fader.
  ///
  /// A parameter and not a `RotatedBox`: the horizontal recognizer judges
  /// by the pointer's GLOBAL delta direction in the arena, so a turned
  /// slider never receives an on-screen vertical drag at all.
  final Axis axis;

  @override
  State<FieldSlider> createState() => _FieldSliderState();
}

class _FieldSliderState extends State<FieldSlider> {
  static const Color _valueInk = Color(0xFFE8ECEE);

  /// The track's length along [FieldSlider.axis].
  double _trackExtent = 0;

  bool get _vertical => widget.axis == Axis.vertical;

  /// Where a pointer sits along the track, 0..1.
  ///
  /// The vertical bar fills UPWARD — a fader's direction, and the same one
  /// the horizontal bar reads left-to-right — so the axis position is
  /// measured from the bottom.
  double _trackT(Offset localPosition) {
    if (_trackExtent <= 0) {
      return 0;
    }
    final along = _vertical
        ? _trackExtent - localPosition.dy
        : localPosition.dx;
    return (along / _trackExtent).clamp(0.0, 1.0);
  }

  double _deltaT(Offset delta) {
    if (_trackExtent <= 0) {
      return 0;
    }
    return (_vertical ? -delta.dy : delta.dx) / _trackExtent;
  }

  // Gesture-local position in t-space (0..1). Owned by the active drag so
  // Shift's relative fine mode has something to accumulate against; display
  // always derives from widget.value (the widget stays fully controlled).
  double? _gestureT;
  double? _preDownValue;

  /// Where the raw pointer went since it went down — SIGNED, and per axis.
  ///
  /// Measured from POINTER events rather than drag updates, because the two
  /// cases this has to tell apart look identical to the drag recognizer: it
  /// is rejected without ever seeing an update either way. Only the pointer
  /// knows where a finger went.
  ///
  /// It is a VECTOR and not a distance because the question is not "did the
  /// pointer move" but "did it move the way a SCROLL moves" — see
  /// [_handleCancel].
  Offset _pointerShift = Offset.zero;
  Offset? _pointerDownAt;

  /// The travel a scrollable above us needs before it may claim the gesture.
  ///
  /// Read from the platform rather than picked: Android hands down about 8
  /// logical px where Flutter's own default is 18, and this number only
  /// means anything if it is the SAME one our rival is using. Captured in
  /// `build` because inherited widgets are for build methods.
  double _scrollSlop = kTouchSlop;

  bool get _enabled => widget.onChanged != null;

  bool get _shiftHeld {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight) ||
        keys.contains(LogicalKeyboardKey.shift);
  }

  double _tFor(double value) {
    final double t;
    switch (widget.scale) {
      case FieldSliderScale.linear:
        t = (value - widget.min) / (widget.max - widget.min);
      case FieldSliderScale.exponential:
        t = math.log(value / widget.min) / math.log(widget.max / widget.min);
    }
    return t.clamp(0.0, 1.0);
  }

  double _valueFor(double t) {
    final clamped = t.clamp(0.0, 1.0);
    double value;
    switch (widget.scale) {
      case FieldSliderScale.linear:
        value = widget.min + clamped * (widget.max - widget.min);
      case FieldSliderScale.exponential:
        value = widget.min * math.pow(widget.max / widget.min, clamped);
    }
    final divisions = widget.divisions;
    if (divisions != null) {
      final step = (widget.max - widget.min) / divisions;
      value = widget.min + ((value - widget.min) / step).round() * step;
    }
    return value.clamp(widget.min, widget.max);
  }

  void _emit(double value) => widget.onChanged?.call(value);

  void _handleDown(DragDownDetails details) {
    if (!_enabled) {
      return;
    }
    _preDownValue = widget.value;
    if (_trackExtent <= 0) {
      return;
    }
    // setState: the bar ECHOES the gesture locally (R4 #4/#5) — commit-on-
    // release consumers don't rebuild the parent per move, so the display
    // must follow from gesture state, not widget.value.
    setState(() {
      _gestureT = _trackT(details.localPosition);
    });
    _emit(_valueFor(_gestureT!));
  }

  void _handleUpdate(DragUpdateDetails details) {
    if (!_enabled || _trackExtent <= 0) {
      return;
    }
    final current = _gestureT ?? _tFor(widget.value);
    setState(() {
      if (_shiftHeld) {
        _gestureT = (current + _deltaT(details.delta) / 10).clamp(0.0, 1.0);
      } else {
        _gestureT = _trackT(details.localPosition);
      }
    });
    _emit(_valueFor(_gestureT!));
  }

  void _handleEnd(DragEndDetails details) {
    final t = _gestureT;
    setState(() => _gestureT = null);
    _preDownValue = null;
    if (t != null) {
      widget.onChangeEnd?.call(_valueFor(t));
    }
  }

  /// The drag recognizer lost the pointer. What that MEANS depends on WHICH
  /// WAY the pointer went.
  ///
  /// ★THE BAR KEEPS WHAT MOVED ALONG ITS OWN AXIS. Only travel ACROSS the
  /// bar — the direction a scrollable above us scrolls — can mean the
  /// gesture was taken, so only that direction rolls the value back.
  /// Everything else is a tap, and a tap sets the value: the bar's whole
  /// job is to answer one immediately (R10 R5 retired the double-tap editor
  /// for exactly this).
  ///
  /// 🐛 This USED to ask how FAR the pointer had travelled, in any
  /// direction, and call anything past 6px a scroll. Which quietly made a
  /// wobble into a cancellation: a stylus tap that slid 8px sideways —
  /// still nowhere near the 18px a scrollable needs, so nothing had taken
  /// anything — rolled the value straight back, and the bar read as dead.
  /// 유저, R6 #1: "툴설정은 뭔가 제스쳐 경합된다고? 6px인가 안움직이면
  /// 변경인가 그랬는데 이거 진짜 못없애나? 아직도 불편해 ... 상단띠
  /// 브러시사이즈 변경처럼 대충눌러도 바뀌도록하고싶음."
  ///
  /// A DISTANCE cannot express the rule, because the two cases it has to
  /// separate are not near and far — they are along and across. So there is
  /// no tap slop any more, and no number of our own: the only threshold
  /// left is [_scrollSlop], which belongs to the rival and is asked for by
  /// name.
  ///
  /// 🚨 A cancel is the NORMAL end of a tap, not an error path — a drag
  /// recognizer that never met its threshold rejects itself when the
  /// pointer lifts, so this runs on every tap the bar ever receives,
  /// scrollable above or not. That is why the top strip and the tool
  /// settings only ever differed here: a desktop `Scrollable` puts a drag
  /// recognizer in the arena for touch and stylus alone, so a MOUSE tap had
  /// no rival to lose to and a PEN tap did.
  void _handleCancel() {
    final t = _gestureT;
    setState(() => _gestureT = null);
    final restore = _preDownValue;
    _preDownValue = null;
    // 「바는 자기 축을 따라 움직인 것을 지킨다」 — the rule itself lives in
    // [rivalOwnsGesture] now, because the splitter needs the identical one
    // and a second copy of it would drift.
    if (!rivalOwnsGesture(
      dragAxis: widget.axis,
      travelSinceDown: _pointerShift,
      rivalSlop: _scrollSlop,
    )) {
      if (t != null) {
        // Pointer-down already emitted this value; only the commit is owed.
        widget.onChangeEnd?.call(_valueFor(t));
      }
      return;
    }
    if (restore != null) {
      _emit(restore);
      widget.onChangeEnd?.call(restore);
    }
  }

  void _handleWheel(PointerScrollEvent event) {
    if (!_enabled || event.scrollDelta.dy == 0) {
      return;
    }
    final divisions = widget.divisions;
    final double step;
    if (divisions != null) {
      step = 1.0 / divisions;
    } else {
      step = _shiftHeld ? 0.001 : 0.01;
    }
    final direction = event.scrollDelta.dy < 0 ? 1.0 : -1.0;
    final t = (_tFor(widget.value) + direction * step).clamp(0.0, 1.0);
    final value = _valueFor(t);
    _emit(value);
    // A wheel step is a complete edit (no release to wait for): commit-on-
    // release consumers get their commit right away.
    widget.onChangeEnd?.call(value);
  }

  double get _radius => widget.height < 20 ? 3 : 4;

  /// Keeps [_pointerShift] current. One callback for move, up and cancel:
  /// they all answer the same question.
  void _trackShift(PointerEvent event) {
    final from = _pointerDownAt;
    if (from != null) {
      _pointerShift = event.position - from;
    }
  }

  @override
  Widget build(BuildContext context) {
    _scrollSlop = rivalScrollSlop(context);
    final textTheme = Theme.of(context).textTheme;
    final labelStyle = textTheme.labelSmall?.copyWith(color: AppColors.textDim);
    final valueStyle = textTheme.labelSmall?.copyWith(
      color: _valueInk,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // An active gesture echoes locally (snapped like the emitted value);
    // otherwise display derives from widget.value (fully controlled).
    final gestureT = _gestureT;
    final dragging = gestureT != null;
    final t = dragging ? _tFor(_valueFor(gestureT)) : _tFor(widget.value);
    final valueText = dragging && widget.valueTextBuilder != null
        ? widget.valueTextBuilder!(_valueFor(gestureT))
        : widget.valueText;

    final Widget inner;
    if (widget.label == null) {
      // Stood up, the readout reads DOWN the bar through the shared
      // vertical-writing table, with three-digit 縦中横 so `100%` costs
      // two cells rather than four.
      inner = Center(
        child: _vertical
            ? VerticalWritingText(
                text: valueText,
                tateChuYokoDigits: 3,
                style: valueStyle,
              )
            : Text(
                valueText,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: valueStyle,
              ),
      );
    } else {
      inner = Flex(
        direction: widget.axis,
        children: [
          Expanded(
            child: _vertical
                ? VerticalWritingText(text: widget.label!, style: labelStyle)
                : Text(
                    widget.label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle,
                  ),
          ),
          _vertical
              ? VerticalWritingText(
                  text: valueText,
                  tateChuYokoDigits: 3,
                  style: valueStyle,
                )
              : Text(valueText, maxLines: 1, style: valueStyle),
        ],
      );
    }

    Widget bar = LayoutBuilder(
      builder: (context, constraints) {
        _trackExtent = _vertical ? constraints.maxHeight : constraints.maxWidth;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(color: AppColors.hairline),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: CustomPaint(
              painter: _FieldSliderTrackPainter(
                axis: widget.axis,
                t: t,
                originT: widget.fillOrigin == null
                    ? 0.0
                    : _tFor(widget.fillOrigin!).clamp(0.0, 1.0),
                accent: dragging
                    ? AppColors.accent
                    : (widget.restingAccent ?? AppColors.accent),
              ),
              child: SizedBox(
                width: _vertical ? widget.height : null,
                height: _vertical ? null : widget.height,
                child: Padding(
                  padding: _vertical
                      ? const EdgeInsets.symmetric(vertical: 8)
                      : const EdgeInsets.symmetric(horizontal: 8),
                  child: inner,
                ),
              ),
            ),
          ),
        );
      },
    );

    if (!_enabled) {
      return Opacity(opacity: 0.4, child: bar);
    }
    bar = MouseRegion(
      cursor: _vertical
          ? SystemMouseCursors.resizeUpDown
          : SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragDown: _vertical ? null : _handleDown,
        onHorizontalDragUpdate: _vertical ? null : _handleUpdate,
        onHorizontalDragEnd: _vertical ? null : _handleEnd,
        onHorizontalDragCancel: _vertical ? null : _handleCancel,
        onVerticalDragDown: _vertical ? _handleDown : null,
        onVerticalDragUpdate: _vertical ? _handleUpdate : null,
        onVerticalDragEnd: _vertical ? _handleEnd : null,
        onVerticalDragCancel: _vertical ? _handleCancel : null,
        child: bar,
      ),
    );
    return Semantics(
      slider: true,
      label: widget.label,
      value: widget.valueText,
      child: Listener(
        // Raw pointer travel, watched here rather than in the drag
        // callbacks: a rejected recognizer reports no updates at all, so
        // this is the only place that can say WHICH WAY the gesture went
        // (see [_handleCancel]).
        onPointerDown: (event) {
          _pointerDownAt = event.position;
          _pointerShift = Offset.zero;
          // T11: this press is the slider's. Claimed HERE because hit-test
          // dispatch runs deepest-first, so the claim is already standing
          // by the time the row above is offered the same event and asks.
          claimPointerForValueControl(event.pointer);
        },
        onPointerMove: _trackShift,
        // The lift too: `Listener` sees it before the arena sweeps, and a
        // gesture whose last move arrived with the finger already leaving
        // would otherwise be judged on a stale position.
        onPointerUp: (event) {
          _trackShift(event);
          releasePointerForValueControl(event.pointer);
        },
        onPointerCancel: (event) {
          _trackShift(event);
          // Released on cancel too: a claim that outlives its gesture would
          // silently deafen whichever later pan is handed the same id.
          releasePointerForValueControl(event.pointer);
        },
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            _handleWheel(event);
          }
        },
        child: bar,
      ),
    );
  }
}

class _FieldSliderTrackPainter extends CustomPainter {
  const _FieldSliderTrackPainter({
    required this.t,
    required this.accent,
    this.axis = Axis.horizontal,
    this.originT = 0.0,
  });

  /// Vertical fills UPWARD from the bottom — a fader's direction.
  final Axis axis;

  final double t;

  /// Where the fill starts, in track space — 0 for a quantity, 0.5 for a
  /// balance (see [FieldSlider.fillOrigin]).
  final double originT;

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final trackExtent = axis == Axis.horizontal ? size.width : size.height;
    // Along the axis, measured from the fill's ORIGIN edge — the left for
    // a horizontal bar, the BOTTOM for a vertical one.
    double along(double fraction) => axis == Axis.horizontal
        ? trackExtent * fraction
        : trackExtent * (1 - fraction);
    final fillEnd = along(t);
    final fillStart = along(originT);
    final near = math.min(fillStart, fillEnd);
    final far = math.max(fillStart, fillEnd);
    final fill = Paint()..color = accent.withValues(alpha: 0.26);
    if (far > near) {
      canvas.drawRect(
        axis == Axis.horizontal
            ? Rect.fromLTWH(near, 0, far - near, size.height)
            : Rect.fromLTWH(0, near, size.width, far - near),
        fill,
      );
    }
    // 2px accent edge marks the position (the thumb's replacement); pinned
    // inside the track at both extremes so it never clips away.
    final edge = (fillEnd - 1).clamp(0.0, trackExtent - 2);
    canvas.drawRect(
      axis == Axis.horizontal
          ? Rect.fromLTWH(edge, 0, 2, size.height)
          : Rect.fromLTWH(0, edge, size.width, 2),
      Paint()..color = accent,
    );
  }

  @override
  bool shouldRepaint(_FieldSliderTrackPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.originT != originT ||
      oldDelegate.axis != axis ||
      oldDelegate.accent != accent;
}
