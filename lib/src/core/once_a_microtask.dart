import 'dart:async';

/// Work asked for any number of times while the code on its way runs, done
/// ONCE right after it, in a microtask — what is asked meanwhile goes in
/// that one. Asked while it is being done, it is done once more after.
///
/// 🚨Written once. It was written out by hand nine times (card
/// told-once-a-microtask-is-written-nine-times, 2026-11-13) — a plugin's
/// outcomes told (`FxPluginOutcomes`), a selection's change and a text in
/// hand told (`CanvasSelectionCommands`, `CelTextCommands` — the second
/// said in its own comment it answered the same way for the same reason),
/// a finger group's update (`CanvasViewportGestureLayer`), a frame's wait
/// mark (`FrameWaitMark`), a viewer's next render asked (`ShownRasters`),
/// the timeline grid's drain and its warm-up (`TimelineGridTileStore`) and
/// the storyboard's drawn cuts told (`StoryboardCutThumbnailStore`).
///
/// ⛔NOT `OnePassAtATime`: there the next pass waits for the one on its way
/// to END, however long that takes. Here nothing is on its way — the work
/// is done as soon as the code that asked for it is through.
///
/// Why each waits for the code on its way is its holder's to say — a build
/// or a paint a listener may not build in, a batch of fingers to take
/// together — and so is what gathers meanwhile and whether it is still
/// there to be done for.
final class OnceAMicrotask {
  OnceAMicrotask(this._work);

  final void Function() _work;

  bool _asked = false;

  /// Whether it is asked for and not done yet.
  bool get asked => _asked;

  /// [_work] done once the code on its way is through, if it is not asked
  /// for already.
  void ask() {
    if (_asked) {
      return;
    }
    _asked = true;
    scheduleMicrotask(() {
      // Let go of before the work, not after: what the work asks for again
      // is done once more, after it.
      _asked = false;
      _work();
    });
  }
}
