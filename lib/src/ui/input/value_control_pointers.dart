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
/// drags. A slider is the opposite case: dragging IS its verb, so it takes
/// the strong claim above and pans decline outright.
///
/// ⇒ Two sets, and the question that decides which a control joins is
/// 「is a drag that starts here mine?」.
///
/// 🚨THE REASON THAT USED TO STAND HERE WAS INVENTED, and it is kept as a
/// warning rather than deleted. It read: 「claiming the pointer outright
/// broke a real one, because the storyboard's row-order drag deliberately
/// starts ON the visibility button — its test says so in as many words」.
/// 유저 2026-08-29 asked what that meant. It is false three ways, measured:
///
///  - GEOMETRY. The row-order drag lands on the row's centre, x=233 — the
///    name area. The eye sits at x=359..381. They are 126px apart.
///  - BEHAVIOUR. Two drags begun on the eye leave the order untouched; the
///    same two on the row re-order it. Today's code already says the
///    opposite of the sentence.
///  - ORIGIN. `git log -S` puts it in 0ccc1163 (08-14), and the test AS OF
///    THAT COMMIT also dragged the row by its key. The word "visibility"
///    never appears in it. The sentence was false when it was written.
///
/// ⚠️It then spread: [RailSwipeColumnPointer] quoted it to say the
/// storyboard still needed the old answer, and that is why the storyboard
/// rail went without swipe columns. An unsourced reason in a decision
/// comment does not stay a comment — it becomes the design.
///
/// 🚨BOTH READERS ASK BOTH SETS NOW (#1349, 유저 2026-08-29: 「**터치 좌표가
/// 버튼인데 거기서 움직였다고 스크롤이 발생하는게 심각한 버그야**」). The pan
/// recogniser used to ask only the strong one, which is why a drag begun on
/// a button still scrolled. The two sets have NOT collapsed — the strong one
/// is still what a swipe column takes so its own drag verb survives — but
/// nothing reads the weak set alone any more.
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

/// Whether a control has ALREADY taken this press.
///
/// 🚨★★★A DIFFERENT QUESTION FROM [controlOwnsTap], and the difference bit:
/// that one asks 「is this pointer any control's」 and answers yes for the
/// STRONG claim too — so a swipe column, which mounts [DragVerbClaim] INSIDE
/// its [ControlPressClaim], made its own claim believe something deeper had
/// spoken for the press and stand down. 🧪Measured: every storyboard lane
/// twirl stopped opening (`storyboard_lane_controls_test`, five cases).
///
/// This one asks only 「has another [ControlPressClaim] taken it」, which is
/// what 「the deepest control wins」 needs and nothing else.
bool pressIsSpokenFor(int pointer) => _tapHeld.contains(pointer);

/// Test-only: drops every claim.
void debugClearValueControlPointers() {
  _held.clear();
  _tapHeld.clear();
}
