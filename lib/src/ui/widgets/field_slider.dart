import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../input/control_press_claim.dart';
import '../input/wheel_law.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart';
import '../theme/text_on_ground.dart';
import '../timeline/axis_turn.dart';
import 'app_icon_button.dart';
import 'axis_bar_gesture.dart';
import 'ground_ink_writing.dart';
import 'superellipse_clip.dart';
import '../repaint_props.dart';

/// THE number a slider writes: [value] to [decimals] places, then [unit].
///
/// F-9 (유저 2026-08-24):
///
/// > 「슬라이더 값에 소수점 텍스트 표시 (1.2px) … 브러시 사이즈만이 아니라
/// > **조절 가능한 모든 슬라이더**」
///
/// The panels used to `.round()` at each call site, so a bar you could set to
/// 1.2 read `1` — and then setting it again from the number you could see
/// moved the value. Rounding is a DISPLAY choice, and it was being made by
/// twenty call sites that could not agree.
///
/// 🚨F-34 (유저 확정 2026-09-01, 선택 1) is why [decimals] has NO DEFAULT:
///
/// > 「**슬라이더가 스스로 정한다 — 위젯이 자기 스텝을 보고 자릿수를
/// > 고른다**」
///
/// This used to hide the decimal whenever the value happened to be whole, so
/// one bar read `1`, then `1.2` under the same finger, then `1` again — 유저
/// 2026-08-31: 「소수점이 있는 슬라이더는 처음부터 소수점까지 보여주도록.
/// **없는 UI가 생겨나지 않게 하라는 원칙이 이 경우를 말함**」. The digit
/// count belongs to the BAR (`_FieldSliderState._decimals`), and the few
/// labels that are not plain numbers (`L50`, `off`, `Auto`) name their own.
String sliderValueText(num value, {required int decimals, String unit = ''}) {
  final text = value.toStringAsFixed(decimals);
  // ⚠️`-0`: a value a hair below zero rounds to zero and KEEPS its sign, and
  // `-0%` beside a `0%` reads as a different number. Rounding alone can reach
  // it, so the guard is here rather than at the values.
  final zero = 0.toStringAsFixed(decimals);
  return '${text == '-$zero' ? zero : text}$unit';
}

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
/// - `label == null` renders the micro variant (value only, centered) — the
///   timeline's inline slots, and equally a dialog row whose label is a
///   `Text` BESIDE the bar. ⚠️Those two are not the same situation even
///   though they take the same branch, which is why the `%`-dropping rule
///   sits in [FieldSlider.opacity] and not in the writing.
/// - A STOOD-UP bar writes the same row, turned a quarter clockwise.
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
    this.unit = '',
    this.displayScale = 1,
    this.onChangeEnd,
    this.valueTextBuilder,
    this.restingText,
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

  /// **An OPACITY bar**: 0..1 in the model, whole per cent on the screen.
  ///
  /// 🚨유저 2026-08-29 (F-34): 「슬라이더에서 데이터적으로 소수점이 필요없는
  /// 것들 정수화. **레이어나 브러시 불투명도가 소수점? 자연수가 아닐 이유가
  /// 없다고생각. 조절시 자연수이도록.**」
  ///
  /// The hundred divisions are what make that true WHILE DRAGGING.
  /// [sliderValueText] only ever rounded the label, so a bar reading `50%`
  /// could be holding 0.4963 — and the next thing to read that number (a
  /// composite, an export) got the 0.4963.
  ///
  /// ⛔THE RANGE AND THE FORMAT ARE FIXED HERE, not repeated per call. Six
  /// bars were each typing `min: 0, max: 1` with the same `value * 100`
  /// builder — six places to forget the divisions, and all six had. The
  /// resting [restingText] stays the caller's, because the legend's master
  /// bar reads `OPAC` at rest and the row's reads its number.
  ///
  /// ⚠️Not every slider is integral and this does not claim they are: brush
  /// SIZE goes down to 0.7, the pressure curve is a gamma, and the transform
  /// tool's scale is the exception 유저 named in the same sentence.
  const FieldSlider.opacity({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.restingText,
    this.restingAccent,
    this.label,
    this.height = 24,
    this.axis = Axis.horizontal,
  }) : min = 0,
       fillOrigin = null,
       max = 1,
       divisions = 100,
       scale = FieldSliderScale.linear,
       // 🚨THE MICRO OPACITY BAR WRITES THE NUMBER ALONE (유저 2026-09-10:
       // 「타임라인 레이어영역에 있는 슬라이더 미니버전. **미니버전은 텍스트에
       // % 표기 삭제. 그냥 안보이게**」) — the layer rows, the storyboard's SE
       // rows, the x-sheet's stood-up rail and the legend's master bar.
       //
       // ⛔Here and not in [_FieldSliderState._textFor]: `label == null` is
       // ALSO how a bar whose label sits BESIDE it is built (the stage
       // dialog's alpha, the export bitrate, the autosave minutes), and
       // those would have lost ` Mb` and their minutes with it. A bar that
       // says OPACITY in the column it lives in is what the user pointed at.
       unit = label == null ? '' : '%',
       // A hundred divisions of a 0..1 model IS a whole per cent on screen,
       // and saying the scale here is what lets the digit rule see that.
       displayScale = 100,
       valueTextBuilder = null;

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

  /// What follows the number — `%`, ` px`, `°`.
  ///
  /// ⛔THE DIGITS ARE NOT HERE and are not the caller's: the bar reads its
  /// own step for those (F-34, [_FieldSliderState._decimals]).
  final String unit;

  /// The factor between the number the MODEL holds and the number the bar
  /// WRITES — 100 for a 0..1 opacity shown as per cent.
  ///
  /// A field rather than arithmetic at the call site because the digit rule
  /// has to read the step THROUGH it: a per-cent bar with a hundred
  /// divisions steps by a whole per cent, and only this says so.
  final double displayScale;

  /// Replaces the number for values that do not READ as one — `off`, `Auto`,
  /// `L50`. It is handed the value AND the text the bar would have written,
  /// so an exception decorates the derived number instead of deriving a
  /// second one with a digit count of its own.
  final String Function(double value, String derived)? valueTextBuilder;

  /// Fill/edge color while NOT interacting; the drag always paints the
  /// accent (the legend's master-opacity bar reads gray at rest, accent
  /// while adjusting — R4 #6). Null = accent always.
  final Color? restingAccent;

  /// Inside-left label; `null` renders the micro variant (value only).
  final String? label;

  /// What the bar reads WHILE NOBODY IS TOUCHING IT, when that is not its
  /// number at all: the legend's master bar reads `OPAC` at rest and its per
  /// cent while it is being dragged (R4 #6). Null = the number, always.
  final String? restingText;

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
  /// ⛔THE BAR ITSELF IS NEVER A `RotatedBox`: the horizontal recognizer
  /// judges by the pointer's GLOBAL delta direction in the arena, so a
  /// turned slider would never receive an on-screen vertical drag at all.
  /// Its WRITING is turned, which is a different question — see [build].
  final Axis axis;

  @override
  State<FieldSlider> createState() => _FieldSliderState();
}

class _FieldSliderState extends State<FieldSlider> {
  /// The ink over each stretch of the bar: the text-on-ground law
  /// ([textOnColor]) over the fill and over the empty track, changing part
  /// way through a word where the fill ends.
  ///
  /// 🚨H38 again (유저 2026-09-11): 「공용 슬라이더 텍스트말인데, 검정색으로
  /// 하니 뒤가 비어있으면 안보인다. 그러니까 그냥 저번에 한대로 뒤 색에 따라
  /// 하양/검정 바꾸는거 있잖아. 그거대로 하자」. ↩️The history, so neither
  /// fixed ink comes back as a "fix": 09-08 laid the law on the bar (a
  /// `ShaderMask` over the fill's edge); 09-10 fixed it white — 「공용
  /// 색바뀌는 텍스트ui 쓰는게아니라 흰색 고정」; the morning of 09-11 (H38)
  /// fixed it black — 「그냥 검정색으로 통일해보자. 흰색 좀 보기힘들어」; and
  /// black vanished over the empty track. The law is back through
  /// [GroundInkWriting], without the mask's offscreen layer. (A brush row's
  /// name shared it from H38 again until F-82 put that name on a plate.)
  ///
  /// Label and value stay ONE ink per ground: 09-10 flattened their dim and
  /// bright pair by decision, and that is not what was reversed.
  List<GroundInkRun> _inkRuns(double t, Color accent) {
    final near = math.min(_originFraction, t);
    final far = math.max(_originFraction, t);
    // A stood-up bar's writing is the row turned a quarter clockwise, so its
    // x runs DOWN the bar while the fill grows UP it.
    return groundInkRunsForFill(
      near: _vertical ? 1 - far : near,
      far: _vertical ? 1 - near : far,
      onFill: textOnColor(accent),
      onTrack: textOnColor(AppColors.surface),
    );
  }

  /// The track's length along [FieldSlider.axis].
  double _trackExtent = 0;

  /// The +/− pair as last built, and what it was built from.
  ///
  /// 🔬H40 (유저 2026-09-11): 「고를때 렉있어서 그부분도 효율적으로 가볍게
  /// 하고싶어」. A bar rebuilds for every value it is handed and every frame
  /// of a drag, and the pair — two buttons, their tooltips, their ink —
  /// changes with none of that: only with the bar's height, whether it takes
  /// the gesture, and the language its tooltips speak.
  Widget? _stepper;
  Object? _stepperFor;

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

  // ⛔Four fields left with the workaround they served (유저 확정
  // 2026-08-14): the pre-down value to restore, the pointer's down position
  // and its signed travel from there — which together decided whether a
  // rival "legitimately" owned the gesture — and the rival's scroll slop
  // that travel was measured against.
  //
  // All four existed to answer *did someone take this from me, and were
  // they entitled to?* Nobody can take it any more — the recogniser accepts
  // on the first movement — so the question has no askers left, and a
  // restore path that never runs is a trap for whoever reads it next.

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
  /// no tap slop here and no number of our own.
  ///
  /// ★THIS WAS THE PRECEDENT, and the whole app reached it on 2026-08-30:
  /// 유저, on finding a device slop still being consulted for buttons —
  /// 「**1px 이동했는지 같은 px 이동으로 판단하는거** 설마 아직도 남아있나?
  /// 내가 다른방법 제안하지 않았어?」 · 「싹 깔끔하게 걷어내」. A button
  /// answers 「click or not」 by where the finger came UP, a slider by which
  /// way it went; neither needs a distance. See [ControlPressClaim].
  ///
  /// 🚨 A cancel is the NORMAL end of a tap, not an error path — a drag
  /// recognizer that never met its threshold rejects itself when the
  /// pointer lifts, so this runs on every tap the bar ever receives,
  /// scrollable above or not. That is why the top strip and the tool
  /// settings only ever differed here: a desktop `Scrollable` puts a drag
  /// recognizer in the arena for touch and stylus alone, so a MOUSE tap had
  /// no rival to lose to and a PEN tap did.
  /// Wires one drag recogniser. Both axes take the same four handlers, so
  /// the vertical and horizontal factories cannot drift apart.
  void _configureDrag(DragGestureRecognizer recognizer) {
    // Down, not start: the bar answers the press itself (R9 #12's rule for
    // grips) — and with acceptance now on the first movement there is no
    // slop left to discard anyway.
    recognizer
      ..dragStartBehavior = DragStartBehavior.down
      ..onDown = _handleDown
      ..onUpdate = _handleUpdate
      ..onEnd = _handleEnd
      ..onCancel = _handleCancel;
  }

  void _handleCancel() {
    final t = _gestureT;
    setState(() => _gestureT = null);
    // ⛔The 「did the pointer cross my axis far enough that the rival owns
    // this?」 branch is GONE (유저 확정 2026-08-14: 「슬라이더위에서 조작하기
    // 시작하면 슬라이더조작하는거고 그 외가 스크롤인거야」). There is no
    // rival to lose to any more — the recogniser takes the arena on the
    // first movement — so a cancel can only mean the one thing left:
    //
    // ★a TAP. A drag recogniser that never moved rejects itself when the
    // pointer lifts, so this is the normal end of every tap the bar
    // receives, not an error path. Pointer-down already emitted the value;
    // only the commit is owed.
    if (t != null) {
      widget.onChangeEnd?.call(_valueFor(t));
    }
  }

  void _handleWheel(PointerScrollEvent event) {
    if (event.scrollDelta.dy == 0) {
      return;
    }
    _stepBy(event.scrollDelta.dy < 0 ? 1 : -1);
  }

  /// One notch [direction] (+1 up, -1 down).
  ///
  /// 🚨★THE ONE PLACE A STEP IS DEFINED. The wheel and the +/− buttons are
  /// two ways of asking for the same thing, and 유저 확정 (2026-09-08) says
  /// so outright: 「`+1` = 휠과 같은 걸음」. Two implementations would be one
  /// question with two answers, and they would drift the first time either
  /// scale changed.
  ///
  /// A step is a COMPLETE edit — there is no release to wait for — so
  /// commit-on-release consumers get their commit right away.
  void _stepBy(int direction) {
    if (!_enabled) {
      return;
    }
    final divisions = widget.divisions;
    final double step;
    if (divisions != null) {
      step = 1.0 / divisions;
    } else {
      step = _shiftHeld ? 0.001 : 0.01;
    }
    final t = (_tFor(widget.value) + direction * step).clamp(0.0, 1.0);
    final value = _valueFor(t);
    _emit(value);
    widget.onChangeEnd?.call(value);
  }

  /// How many digits this bar writes after the point — THE SAME COUNT AT
  /// EVERY VALUE, which is the whole of F-34 (유저 확정 2026-09-01: 「위젯이
  /// 자기 스텝을 보고 자릿수를 고른다」).
  ///
  /// The only question is 「can this bar land BETWEEN two whole numbers?」:
  ///  * an EXPONENTIAL sweep multiplies, so it lands anywhere;
  ///  * a bar with no [FieldSlider.divisions] is continuous, so it lands
  ///    anywhere;
  ///  * otherwise every reachable value is `min + k·step`, whole for every
  ///    k exactly when min and step are both whole — IN DISPLAY UNITS,
  ///    which is what [FieldSlider.displayScale] is for.
  ///
  /// ⛔It does not ask what the CURRENT value is. That is the bug: a rule
  /// that hides the decimal for a whole value makes the digit count appear
  /// and disappear under the finger, which is 「없다가 생기는 UI」.
  int get _decimals {
    final divisions = widget.divisions;
    if (widget.scale == FieldSliderScale.exponential || divisions == null) {
      return 1;
    }
    final step = (widget.max - widget.min) * widget.displayScale / divisions;
    final origin = widget.min * widget.displayScale;
    return _isWhole(step) && _isWhole(origin) ? 0 : 1;
  }

  static bool _isWhole(double value) =>
      (value - value.roundToDouble()).abs() < 1e-9;

  /// The text this bar writes for [value] — the ONE place that is decided.
  String _textFor(double value) {
    final derived = sliderValueText(
      value * widget.displayScale,
      decimals: _decimals,
      unit: widget.unit,
    );
    return widget.valueTextBuilder?.call(value, derived) ?? derived;
  }

  double get _radius => widget.height < 20 ? 3 : 4;

  /// Where the fill starts, in track space — 0 for a quantity, the neutral
  /// value for a balance ([FieldSlider.fillOrigin]).
  double get _originFraction => widget.fillOrigin == null
      ? 0.0
      : _tFor(widget.fillOrigin!).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final labelStyle = textTheme.labelSmall;
    final valueStyle = textTheme.labelSmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      // ⛔NO LETTER SPACING ON THE NUMBER. `labelSmall` carries 0.5 and
      // Flutter lays it after the LAST glyph too, so a centred `50` sits
      // half a space left of centre — 유저 2026-09-10: 「해당 불투명도
      // 슬라이더의 텍스트가 제대로 중앙정렬이 아닌거같음. **두자리수가
      // 미묘하게 왼쪽에 치우쳐있음**」. A number is set solid; the LABEL
      // beside it is a word and keeps the theme's spacing.
      letterSpacing: 0,
    );
    // An active gesture echoes locally (snapped like the emitted value);
    // otherwise display derives from widget.value (fully controlled).
    final gestureT = _gestureT;
    final dragging = gestureT != null;
    final t = dragging ? _tFor(_valueFor(gestureT)) : _tFor(widget.value);
    final valueText = dragging
        ? _textFor(_valueFor(gestureT))
        : widget.restingText ?? _textFor(widget.value);

    final accent = dragging
        ? AppColors.accent
        : (widget.restingAccent ?? AppColors.accent);
    Widget writingIn(TextStyle ink) {
      final value = valueStyle?.merge(ink) ?? ink;
      if (widget.label == null) {
        return Center(
          child: Text(
            valueText,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: value,
          ),
        );
      }
      return Row(
        children: [
          Expanded(
            child: Text(
              widget.label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle?.merge(ink) ?? ink,
            ),
          ),
          Text(valueText, maxLines: 1, style: value),
        ],
      );
    }

    // 🚨A STOOD-UP BAR IS THE ROW, TURNED — 세로쓰기 세로표기 (유저
    // 2026-09-10: 「x시트의 불투명도바는 **세로쓰기 세로표기**로 바꾸자」).
    // That is the reading 유저 named on 2026-08-24 for the SE blocks —
    // 「se블록의 이름이 세로쓰기세로표기 인거같은데, 가로쓰기 세로표기가
    // 되도록」, where the before state was `VerticalLatinForm.sideways`:
    // the glyphs LIE DOWN and the line reads along the column.
    //
    // ⛔It is NOT the vertical-writing table any more. That stacked one
    // glyph per cell and set `100%` as three-digit 縦中横 to keep it to two
    // cells — a horizontal number inside a vertical column, which is
    // exactly the 가로쓰기 the user is asking away from.
    //
    // ⚠️A `RotatedBox` HERE and never around the bar: the writing has no
    // gesture, while a turned recognizer would never see an on-screen
    // vertical drag at all (see [FieldSlider.axis]).
    // The ink follows the ground under it — see [_inkRuns]. The writing's
    // box is the whole track, padding and all, so the runs' fractions are the
    // painter's.
    final Widget inner = GroundInkWriting(
      runs: _inkRuns(t, accent),
      builder: (context, ink) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: writingIn(ink),
      ),
    );

    Widget bar = LayoutBuilder(
      builder: (context, constraints) {
        _trackExtent = _vertical ? constraints.maxHeight : constraints.maxWidth;
        return DecoratedBox(
          decoration: ShapeDecoration(
            color: AppColors.surface,
            shape: AppShapes.container(
              _radius,
              side: const BorderSide(color: AppColors.hairline),
            ),
          ),
          child: SuperellipseClip(
            shape: AppShapes.container(_radius),
            child: CustomPaint(
              painter: _FieldSliderTrackPainter(
                axis: widget.axis,
                t: t,
                originT: _originFraction,
                accent: accent,
              ),
              child: SizedBox(
                width: _vertical ? widget.height : null,
                height: _vertical ? null : widget.height,
                child: _vertical
                    ? RotatedBox(quarterTurns: 1, child: inner)
                    : inner,
              ),
            ),
          ),
        );
      },
    );

    if (!_enabled) {
      // ⛔THE STEPPER STILL STANDS THERE, dimmed and inert. A disabled bar
      // that dropped it would be 「없다가 생기는 UI」 — the row would be
      // wider the moment the control came alive, and everything beside it
      // would shift.
      return _withStepper(Opacity(opacity: 0.4, child: bar));
    }
    bar = MouseRegion(
      cursor: _vertical
          ? SystemMouseCursors.resizeUpDown
          : SystemMouseCursors.resizeLeftRight,
      // ★유저 확정 2026-08-14: a press that lands on the bar is the bar's,
      // scrolling included. These recognisers take the arena on the FIRST
      // movement instead of at a slop, so no ancestor scrollable is ever in
      // a position to take the gesture away — see [axis_bar_gesture].
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: _vertical
            ? <Type, GestureRecognizerFactory>{
                OwningVerticalDragGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      OwningVerticalDragGestureRecognizer
                    >(
                      () =>
                          OwningVerticalDragGestureRecognizer(debugOwner: this),
                      _configureDrag,
                    ),
              }
            : <Type, GestureRecognizerFactory>{
                OwningHorizontalDragGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      OwningHorizontalDragGestureRecognizer
                    >(
                      () => OwningHorizontalDragGestureRecognizer(
                        debugOwner: this,
                      ),
                      _configureDrag,
                    ),
              },
        child: bar,
      ),
    );
    final claimed = Semantics(
      slider: true,
      label: widget.label,
      value: valueText,
      // T11: this press is the slider's. The claim is [DragVerbClaim] now —
      // the same four lines used to sit here, in the splitter and in the
      // rail's swipe column, three copies of one law.
      child: DragVerbClaim(
        child: Listener(
          // What is left here is the WHEEL. The raw travel this used to
          // track went with the workaround that read it.
          //
          // H23: registered rather than handled, so the notch this bar takes
          // is not also taken by the canvas layer above it.
          onPointerSignal: (event) =>
              handleWheelUnlessScrolling(event, context, _handleWheel),
          child: bar,
        ),
      ),
    );
    return _withStepper(claimed);
  }

  /// [bar] with the +/− pair beside it, when this is the kind of bar that
  /// carries one.
  ///
  /// 🚨★THERE ARE TWO KINDS OF BAR, AND THE VARIANT DECIDES WHICH — not the
  /// call site (유저 2026-09-09: 「슬라이더는 2개로 두자. 스텝퍼 적용 미적용
  /// 규칙. **초소형 변형은 기본적으로 빼도록**」).
  ///
  /// * A LABELLED bar is a settings row. It has room, it is read and nudged
  ///   deliberately, and it gets the stepper.
  /// * The MICRO variant (`label == null`) is the inline slot — a timeline
  ///   layer row, a lane header — where the whole control is already down to
  ///   a number in a gap. Two more buttons there would take the track it has
  ///   left, and the value is not being tuned to a digit in that context.
  ///
  /// ⛔NO PER-SITE FLAG. A boolean here is how the two kinds stop being two
  /// kinds — the same trap `ControlPressClaim` names about its own scope: the
  /// panels would grow bars that disagree with the rows beside them.
  ///
  /// A VERTICAL bar is out for a plainer reason: it is the timeline's turned
  /// axis, whose row has no horizontal room at all, and the buttons would
  /// have to stack into the track itself.
  Widget _withStepper(Widget bar) {
    if (widget.axis == Axis.vertical || widget.label == null) {
      return bar;
    }
    // Kept while nothing it shows changes (see [_stepper]). Its [_stepBy]
    // reads the bar's value at press time, so a pair built under an earlier
    // value steps from the current one.
    final key = (
      widget.height,
      _enabled,
      AppText.strings.stepUp,
      AppText.strings.stepDown,
    );
    final stepper = _stepper != null && _stepperFor == key
        ? _stepper!
        : _FieldSliderStepper(
            height: widget.height,
            enabled: _enabled,
            onStep: _stepBy,
          );
    _stepper = stepper;
    _stepperFor = key;
    return Row(
      children: [
        Expanded(child: bar),
        stepper,
      ],
    );
  }
}

/// The +/− pair at the right of a value bar (유저 확정 2026-09-08: 「+버튼을
/// 세로로 위아래로 나눠서 위에 +버튼, 아래 -버튼」).
///
/// ⛔It fires [FieldSlider]'s own `_stepBy`, NOT arithmetic of its own — one
/// notch here is one notch of the wheel, which is the whole of 유저's third
/// 착수 결정. A second implementation would be one question with two answers.
///
/// The two cells split the bar's height, so a row is exactly as tall with the
/// stepper as without it and nothing below shifts.
class _FieldSliderStepper extends StatelessWidget {
  const _FieldSliderStepper({
    required this.height,
    required this.enabled,
    required this.onStep,
  });

  final double height;
  final bool enabled;
  final ValueChanged<int> onStep;

  /// Narrow on purpose: this sits in panels already budgeted to the pixel,
  /// and it is a nudge, not a target you aim at from across the screen.
  static const double width = 14;

  /// The gap to the bar, so the buttons never look like part of the track.
  static const double _gap = 3;

  @override
  Widget build(BuildContext context) {
    final half = height / 2;
    return Padding(
      padding: const EdgeInsets.only(left: _gap),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            // 🚨THE PLUS WEARS THE ACCENT, like every other ＋ in the app
            // (유저 확정 2026-08-10: 「＋가있는 모든곳. 공통적으로」). The
            // MINUS does not: the accent rule is the plus's alone, and its
            // twin — the red one — is for DELETE, which this is not. The
            // pair looking uneven is the law's own shape, not an oversight.
            _cell(
              Icons.add,
              1,
              half,
              color: AppColors.addGlyph(enabled: enabled),
            ),
            _cell(Icons.remove, -1, half),
          ],
        ),
      ),
    );
  }

  Widget _cell(IconData icon, int direction, double half, {Color? color}) =>
      AppIconButton(
        keyValue: 'field-slider-step-${direction > 0 ? 'up' : 'down'}',
        tooltip: direction > 0
            ? AppText.strings.stepUp
            : AppText.strings.stepDown,
        size: AppIconButtonBox(width: width, height: half, iconSize: half - 2),
        icon: Icon(icon, color: color),
        onPressed: enabled ? () => onStep(direction) : null,
      );
}

class _FieldSliderTrackPainter extends CustomPainter with RepaintOnProps {
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
    final trackExtent = extentAlong(axis, size);
    // Along the axis, measured from the fill's ORIGIN edge — the left for
    // a horizontal bar, the BOTTOM for a vertical one.
    double along(double fraction) => axis == Axis.horizontal
        ? trackExtent * fraction
        : trackExtent * (1 - fraction);
    final fillEnd = along(t);
    final fillStart = along(originT);
    final near = math.min(fillStart, fillEnd);
    final far = math.max(fillStart, fillEnd);
    // 🚨THE FILL IS THE ACCENT ITSELF (유저 2026-09-08: 「그냥 깔끔하게 앱
    // 강조색 그대로 칠하도록. 이상한 세로선 넣지말고」).
    //
    // ⛔The 26%-alpha wash and the 2px accent edge that used to ride the
    // fill's end are BOTH gone, and they went together: the edge existed to
    // mark the position because a wash that pale did not read as an end. A
    // solid fill IS the position, so keeping the line would be marking the
    // same fact twice.
    final fill = Paint()..color = accent;
    if (far > near) {
      canvas.drawRect(
        axis == Axis.horizontal
            ? Rect.fromLTWH(near, 0, far - near, size.height)
            : Rect.fromLTWH(0, near, size.width, far - near),
        fill,
      );
    }
  }

  @override
  Object get props => (t, originT, axis, accent);
}
