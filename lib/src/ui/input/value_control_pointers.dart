/// Which pointers a VALUE CONTROL is holding.
///
/// ## Why this is not a gesture-arena problem
///
/// The arena settles races between recognizers that both want a gesture.
/// This is not that race. A rail row's drag is an
/// `EagerPanGestureRecognizer`, which measures the VECTOR LENGTH of the
/// first move; a slider measures only |dx|. Both use `computeHitSlop`,
/// which is 18px for a pen and **1px for a mouse**.
///
/// Drag a slider straight down with a mouse and |dx| stays 0 forever: the
/// slider can never cross its own threshold, so the row does not beat it,
/// it walks over. Drag diagonally and a first move of (0.5, 1.2) gives the
/// row a length of 1.3 — past 1 — while the slider's 0.5 is still
/// stillness. That is why the user saw it as 「제스쳐끊기고 레이어선택
/// 작동」 and why it read as intermittent: the angle decided.
///
/// No arena rule fixes a walkover. The missing fact is not "who moved
/// further" but **where the press landed**, and only the widget under the
/// finger knows that.
///
/// ## The law
///
/// > **A press that lands on a value control belongs to that control.**
///
/// The control claims its pointer on down and releases it on up or cancel.
/// Any pan that would otherwise start from the same pointer asks here
/// first and declines.
///
/// Ordering works because hit-test dispatch runs deepest-first: the
/// control's `Listener` sits inside the row, so its down handler has
/// already claimed by the time the row's recognizer is offered the same
/// event.
///
/// ⛔Three earlier attempts at this bug came back green because they were
/// measured with `PointerDeviceKind.stylus`, where both thresholds are 18px
/// and the slider wins every angle. Measure with a mouse.
library;

/// The pointer ids currently held by a value control.
///
/// A `Set` rather than a single id: a second finger can land on a second
/// control while the first is still down, and blocking the wrong one would
/// be its own bug.
final Set<int> _held = <int>{};

/// Claims [pointer] for a value control. Call from the control's
/// `onPointerDown`.
void claimPointerForValueControl(int pointer) {
  _held.add(pointer);
}

/// Releases [pointer]. Call from BOTH `onPointerUp` and `onPointerCancel` —
/// a claim that outlives its gesture would silently deafen every later pan
/// that happened to be handed the same id.
void releasePointerForValueControl(int pointer) {
  _held.remove(pointer);
}

/// Whether a value control is holding [pointer].
bool valueControlOwnsPointer(int pointer) => _held.contains(pointer);

/// Pointers a BUTTON is holding — a WEAKER claim than [_held].
///
/// 🚨★★★ 유저 #1 (2026-08-14): a press on a rail row's button also fired the
/// row's PICK, which moved the drawing target, rebuilt the row, and took
/// the gesture still running on it with the old widget. So a button has to
/// own something.
///
/// ⛔But not the whole pointer. A button owns its TAP; it does not own
/// drags — and claiming the pointer outright broke a real one, because the
/// storyboard's row-order drag deliberately starts ON the visibility button
/// (its test says so in as many words). A slider is the opposite case:
/// dragging IS its verb, so it takes the strong claim above and pans
/// decline outright.
///
/// ⇒ Two sets, and the question that decides which a control joins is
/// 「is a drag that starts here mine?」. [InstantTapRegion] asks both; the
/// pan recogniser asks only the strong one.
final Set<int> _tapHeld = <int>{};

void claimTapForControl(int pointer) {
  _tapHeld.add(pointer);
}

void releaseTapForControl(int pointer) {
  _tapHeld.remove(pointer);
}

/// Whether ANY control — a button or a value control — owns [pointer]'s tap.
bool controlOwnsTap(int pointer) =>
    _tapHeld.contains(pointer) || _held.contains(pointer);

/// Test-only: drops every claim.
void debugClearValueControlPointers() {
  _held.clear();
  _tapHeld.clear();
}
