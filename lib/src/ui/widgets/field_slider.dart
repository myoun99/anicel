import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../text/full_width_numerals.dart';

import '../theme/app_theme.dart';

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
/// - Double-tap opens inline numeric entry in display units (see
///   [displayFactor]); Enter or tapping away commits, Escape cancels. The
///   value jump caused by the first tap of the pair is rolled back.
/// - A vertical scroll gesture that wins the arena rolls back the tentative
///   value jump from pointer-down, so bars inside scrollables stay safe.
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
    this.displayFactor = 1.0,
    this.height = 24,
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

  /// Fires once when a drag ends, a wheel step lands or a typed value
  /// commits — the hook for commit-on-release consumers (opacity/zoom drag
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

  /// Multiplier from model units to the units the user types: opacity 0..1
  /// displayed as percent passes 100 so a typed `80` commits 0.8.
  final double displayFactor;

  final double height;

  @override
  State<FieldSlider> createState() => _FieldSliderState();
}

class _FieldSliderState extends State<FieldSlider> {
  static const Color _valueInk = Color(0xFFE8ECEE);
  static const Duration _doubleTapWindow = Duration(milliseconds: 300);
  static const double _doubleTapSlop = 16.0;

  bool _editing = false;
  late final TextEditingController _editController = TextEditingController();

  double _trackWidth = 0;

  // Gesture-local position in t-space (0..1). Owned by the active drag so
  // Shift's relative fine mode has something to accumulate against; display
  // always derives from widget.value (the widget stays fully controlled).
  double? _gestureT;
  double? _preDownValue;

  // Manual double-tap detection: a GestureDetector.onDoubleTap would hold
  // every tap hostage in the arena for 300ms (the S4 entry-unification
  // gotcha), so the down handler compares timestamps itself.
  DateTime? _lastDownTime;
  Offset? _lastDownPosition;
  double? _preSequenceValue;

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

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
    if (!_enabled || _editing) {
      return;
    }
    final now = DateTime.now();
    final lastTime = _lastDownTime;
    final lastPosition = _lastDownPosition;
    final isDoubleTap =
        lastTime != null &&
        lastPosition != null &&
        now.difference(lastTime) < _doubleTapWindow &&
        (details.localPosition - lastPosition).distance < _doubleTapSlop;
    if (isDoubleTap) {
      _lastDownTime = null;
      _lastDownPosition = null;
      // Unconditional: widget.value may be stale intra-frame (the first
      // tap's emit only lands on the next build), so an equality guard here
      // would swallow the rollback.
      final restore = _preSequenceValue;
      if (restore != null) {
        _emit(restore);
      }
      _startEdit(restore ?? widget.value);
      return;
    }
    _lastDownTime = now;
    _lastDownPosition = details.localPosition;
    _preSequenceValue = widget.value;
    _preDownValue = widget.value;
    if (_trackWidth <= 0) {
      return;
    }
    // setState: the bar ECHOES the gesture locally (R4 #4/#5) — commit-on-
    // release consumers don't rebuild the parent per move, so the display
    // must follow from gesture state, not widget.value.
    setState(() {
      _gestureT = (details.localPosition.dx / _trackWidth).clamp(0.0, 1.0);
    });
    _emit(_valueFor(_gestureT!));
  }

  void _handleUpdate(DragUpdateDetails details) {
    if (!_enabled || _editing || _trackWidth <= 0) {
      return;
    }
    final current = _gestureT ?? _tFor(widget.value);
    setState(() {
      if (_shiftHeld) {
        _gestureT = (current + details.delta.dx / _trackWidth / 10).clamp(
          0.0,
          1.0,
        );
      } else {
        _gestureT = (details.localPosition.dx / _trackWidth).clamp(0.0, 1.0);
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

  // The arena gave this pointer to someone else (a vertical scrollable):
  // roll back the tentative jump from pointer-down. onChangeEnd closes the
  // edit too — commit-on-release consumers must not be left with a live
  // preview channel.
  void _handleCancel() {
    setState(() => _gestureT = null);
    final restore = _preDownValue;
    _preDownValue = null;
    if (restore != null) {
      _emit(restore);
      widget.onChangeEnd?.call(restore);
    }
  }

  void _handleWheel(PointerScrollEvent event) {
    if (!_enabled || _editing || event.scrollDelta.dy == 0) {
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

  void _startEdit(double seedValue) {
    final display = seedValue * widget.displayFactor;
    final rounded = display.roundToDouble();
    _editController.text = (display - rounded).abs() < 0.05
        ? rounded.toStringAsFixed(0)
        : display.toStringAsFixed(1);
    _editController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _editController.text.length,
    );
    setState(() => _editing = true);
  }

  void _commitEdit() {
    if (!_editing) {
      return;
    }
    setState(() => _editing = false);
    final match = RegExp(r'-?\d+\.?\d*').firstMatch(_editController.text);
    final typed = match == null ? null : double.tryParse(match.group(0)!);
    if (typed == null) {
      return;
    }
    double value = (typed / widget.displayFactor).clamp(widget.min, widget.max);
    final divisions = widget.divisions;
    if (divisions != null) {
      final step = (widget.max - widget.min) / divisions;
      value = widget.min + ((value - widget.min) / step).round() * step;
    }
    _emit(value);
    widget.onChangeEnd?.call(value);
  }

  void _cancelEdit() {
    if (_editing) {
      setState(() => _editing = false);
    }
  }

  double get _radius => widget.height < 20 ? 3 : 4;

  Widget _buildEditor(TextStyle valueStyle) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancelEdit();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        controller: _editController,
        autofocus: true,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        // R9 #15: a Japanese IME sitting in 全角 types numerals this
        // field's parser cannot read; converting as they arrive is what
        // keeps every downstream tryParse innocent.
        inputFormatters: halfWidthNumerals,
        style: valueStyle,
        decoration: const InputDecoration(
          // Bare: the editor sits ON the slider track, so it opts out of
          // the app-wide filled box.
          filled: false,
          isDense: true,
          isCollapsed: true,
          border: InputBorder.none,
        ),
        onSubmitted: (_) => _commitEdit(),
        onTapOutside: (_) => _commitEdit(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
    if (_editing) {
      inner = Center(child: _buildEditor(valueStyle ?? const TextStyle()));
    } else if (widget.label == null) {
      inner = Center(
        child: Text(
          valueText,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: valueStyle,
        ),
      );
    } else {
      inner = Row(
        children: [
          Expanded(
            child: Text(
              widget.label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle,
            ),
          ),
          Text(valueText, maxLines: 1, style: valueStyle),
        ],
      );
    }

    Widget bar = LayoutBuilder(
      builder: (context, constraints) {
        _trackWidth = constraints.maxWidth;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(
              color: _editing ? AppColors.accent : AppColors.hairline,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: CustomPaint(
              painter: _editing
                  ? null
                  : _FieldSliderTrackPainter(
                      t: t,
                      accent: dragging
                          ? AppColors.accent
                          : (widget.restingAccent ?? AppColors.accent),
                    ),
              child: SizedBox(
                height: widget.height,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
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
    if (!_editing) {
      bar = MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragDown: _handleDown,
          onHorizontalDragUpdate: _handleUpdate,
          onHorizontalDragEnd: _handleEnd,
          onHorizontalDragCancel: _handleCancel,
          child: bar,
        ),
      );
    }
    return Semantics(
      slider: true,
      label: widget.label,
      value: widget.valueText,
      child: Listener(
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
  const _FieldSliderTrackPainter({required this.t, required this.accent});

  final double t;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final fillEnd = size.width * t;
    if (fillEnd > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, fillEnd, size.height),
        Paint()..color = accent.withValues(alpha: 0.26),
      );
    }
    // 2px accent edge marks the position (the thumb's replacement); pinned
    // inside the track at both extremes so it never clips away.
    final edgeLeft = (fillEnd - 1).clamp(0.0, size.width - 2);
    canvas.drawRect(
      Rect.fromLTWH(edgeLeft, 0, 2, size.height),
      Paint()..color = accent,
    );
  }

  @override
  bool shouldRepaint(_FieldSliderTrackPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.accent != accent;
}
