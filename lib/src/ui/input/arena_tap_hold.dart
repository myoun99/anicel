import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'recognizer_box.dart';

/// A ROW BODY'S TAP: held in the gesture arena and answered with nothing —
/// the pick rides the raw pointer above it ([InstantTapRegion]) — so scroll
/// slop over a row behaves the way it always has.
///
/// It was an `InkWell` with a no-op `onTap`, on the timeline's layer rows
/// and the storyboard's labels: ~20 elements a row of focus, actions, a
/// mouse region and ink that drew nothing (F-138: the app's press shows no
/// ink), mounted anew for every row on every cut switch (I-57 ①). This is
/// the recognizer and nothing else — and since 2026-10-25 one render
/// object holding it ([RecognizerBox]), where a [RawGestureDetector] was
/// three elements more.
///
/// ⚠️Nothing in the app tells it apart today (measured 2026-10-10, a
/// mutant that drops it passes every row test): a timeline row's arena also
/// holds the label's double click and the row drag, and a storyboard track
/// label's only other member is the column swipe, whose band check makes a
/// win outside its columns nothing. It keeps the arena the `InkWell` left
/// when the pick moved off it (T10, 2026-08-14) — a tap the row answers with
/// nothing, which a tap of an ancestor's would lose to.
class ArenaTapHold extends RecognizerBox<TapGestureRecognizer> {
  const ArenaTapHold({super.key, this.holds = true, required super.child});

  /// False holds nothing — a display-only row stays inert, as an `InkWell`
  /// with no `onTap` left it.
  final bool holds;

  static void _answersNothing() {}

  @override
  bool get offers => holds;

  @override
  TapGestureRecognizer makeRecognizer() => TapGestureRecognizer();

  @override
  void configure(TapGestureRecognizer recognizer) =>
      recognizer.onTap = _answersNothing;

  // A screen reader's activation does what a tap does: nothing — as the
  // [RawGestureDetector] this was answered it.
  @override
  VoidCallback? get semanticTap => _answersNothing;
}
