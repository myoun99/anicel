import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/widgets.dart';

/// 🚨★★★ THE LAW: **A BAR KEEPS WHAT MOVED ALONG ITS OWN AXIS.**
///
/// A control that is dragged along one axis — a slider's track, a splitter's
/// grip — usually sits inside a `Scrollable` that scrolls along the OTHER
/// one. On the desktop that scrollable puts a drag recognizer in the arena
/// **for touch and stylus only**, so the same widget behaves differently
/// under a mouse (no rival, always works) than under a pen (a rival, and it
/// often wins). That single fact is what made the top strip's brush-size
/// slider feel instant while the tool-settings copy of the SAME widget felt
/// dead, and what makes a splitter grab about one try in five with a pen.
///
/// ★The answer is not to win the arena. It is to **not need it**: take the
/// pointer through a raw [Listener], which keeps delivering whoever wins,
/// and treat the arena's cancel as a QUESTION rather than an error —
///
///   *did this pointer travel far enough ACROSS my axis that the rival
///   legitimately owns it?*
///
/// A distance alone cannot express that, because the two cases to separate
/// are not near and far, they are **along and across**. And the threshold is
/// not ours to invent: [rivalScrollSlop] asks the rival for its own number
/// by name, which is why every hand-picked "6px" is gone.
///
/// R6 #1 solved this for [FieldSlider] (유저: 「상단띠 브러시사이즈 변경처럼
/// 대충눌러도 바뀌도록하고싶음」). It lives here because the splitter needs
/// the identical rule and a second copy would drift — the two are both bars
/// with an axis, which is the whole of what this asks about.

/// Whether the pointer's travel since it went down has crossed [dragAxis]
/// far enough that the rival scroller genuinely owns this gesture.
///
/// ⚠️[dragAxis] is the axis the bar **MOVES ALONG**, which is not always the
/// axis it is drawn along — a slider's track and its motion share an axis, a
/// splitter's line is perpendicular to its drag. Passing the drawn axis is
/// the one mistake this signature exists to make hard to hide.
bool rivalOwnsGesture({
  required Axis dragAxis,
  required Offset travelSinceDown,
  required double rivalSlop,
}) {
  final across = dragAxis == Axis.horizontal
      ? travelSinceDown.dy
      : travelSinceDown.dx;
  return across.abs() >= rivalSlop;
}

/// The RIVAL's drag threshold, asked for by name.
///
/// `MediaQuery.gestureSettings` is what the viewport's own recognizers are
/// configured with (≈8 logical pixels on Android, [kTouchSlop] elsewhere),
/// so a bar that measures against this is measuring against the very number
/// that will take the pointer away from it. Anything we picked ourselves
/// would be right on one device and wrong on the next.
double rivalScrollSlop(BuildContext context) =>
    MediaQuery.maybeGestureSettingsOf(context)?.touchSlop ?? kTouchSlop;
