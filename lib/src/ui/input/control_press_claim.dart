import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../widgets/axis_bar_gesture.dart';
import 'value_control_pointers.dart';

/// 「Is [globalPosition] still inside the box [context] draws?」 — the ONE
/// predicate a click and a drag start both ask.
///
/// 🚨★★★**IT IS THE SAME SENTENCE, SO IT IS THE SAME FUNCTION.** A press
/// that comes up inside the box is a click ([_ControlPressClaimState.
/// _releasedInside]); a press that leaves it is a drag ([OwningDraggable.
/// stillOnTheThing], F-138). One question, two answers, no threshold —
/// which is what 유저 2026-08-30 asked for when they had every px
/// comparison taken out of this decision: 「**1px 이동했는지 같은 px 이동으로
/// 판단하는거** 설마 아직도 남아있나? … 싹 깔끔하게 걷어내」.
///
/// ⛔It was written twice first, and the clone ratchet said so
/// (`one_algorithm_one_place_test`, 90 → 91) while the doc comment on the
/// second copy was already claiming the two were the same question.
bool pointerIsStillOn(BuildContext context, Offset globalPosition) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) {
    return false;
  }
  return box.size.contains(box.globalToLocal(globalPosition));
}

/// When a claimed control acts. There are exactly two families, and 유저
/// stated the split in one line on 2026-08-30:
///
/// > 「**레이어 쪽 버튼은 탭다운, 헤더쪽은 손떼면**으로 충분할거같은데
/// > 맞지? 규칙 단순명쾌하게 정리했으면 하는데」
///
/// ★THE RULE, ONCE: **a button you can DRAG a column with acts on the press;
/// every other button acts when you let go inside it.**
///
/// That is not two preferences, it is one consequence. A drag down a rail
/// column paints every row it passes to match the one that was pressed — so
/// the pressed row has to be holding its new value already, or the sweep has
/// nothing to spread. Nothing else in the app has that requirement, headers
/// and toolbars included.
///
/// ⛔AND NEITHER OF THEM COMES FROM THE GESTURE ARENA. A press on a control
/// must never scroll, the only way to stop a scroller is to take the arena
/// first, and **whatever wins the arena also kills the button's own tap** —
/// so the action is fired from the raw pointer stream either way.
enum PressFire {
  /// 「레이어 쪽 버튼」 — the press IS the action.
  ///
  /// Nothing declares this per button: [PressFireScope] puts a swipe
  /// column's controls here, which is the same predicate stated once.
  down,

  /// 「헤더쪽」 and everything else — pressed inside, released inside.
  ///
  /// A drag off the control does nothing at all: not the action, and not a
  /// scroll either.
  upInside,
}

/// Puts every claimed control below it on [fireOn].
///
/// ⛔ONE WAY TO SAY IT. [ControlPressClaim] takes no per-site flag, because a
/// flag is how the two families stop being two families — the rails would
/// grow buttons that disagree with the column they sit in. The scope is
/// mounted by [RailSwipeColumnPointer] and nowhere else; everything outside
/// one is 「그 외 버튼」 by default.
class PressFireScope extends InheritedWidget {
  const PressFireScope({super.key, required this.fireOn, required super.child});

  final PressFire fireOn;

  static PressFire of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PressFireScope>()?.fireOn ??
      PressFire.upInside;

  @override
  bool updateShouldNotify(PressFireScope oldWidget) =>
      oldWidget.fireOn != fireOn;
}

/// What an inner button keeps so it still LOOKS like a button.
///
/// ⛔The ink, the hover and the disabled look all come from the widget having
/// a callback, and the disabled look comes from it being null — so the inner
/// widget keeps the shape of [real] and loses only the firing, which
/// [ControlPressClaim] does instead. Handing it `real` itself would fire
/// twice on the devices where Flutter's tap still gets through.
VoidCallback? silentPress(VoidCallback? real) => real == null ? null : () {};

/// The same for a control whose action carries a VALUE — a switch, a
/// checkbox, a radio.
///
/// ⛔It is [silentPress]'s sentence, not a second rule: the inner widget
/// keeps the shape of [real] — its enabled look, its ink, its hover — and
/// loses only the firing, which [ControlPressClaim] does instead. Null still
/// means disabled, and a disabled control still claims its press, so a dead
/// switch is not a scroll either.
///
/// ⚠️The claim fires a `VoidCallback`, so the site that mounts it is the one
/// that says what the new value is (`() => onChanged(!value)` for a switch).
/// That belongs at the site: only it knows what the control's press MEANS.
ValueChanged<T>? silentChange<T>(ValueChanged<T>? real) =>
    real == null ? null : (_) {};

/// 🚨★★★A PRESS THAT LANDS ON A CONTROL BELONGS TO THAT CONTROL.
///
/// The law is in CLAUDE.md and 유저 has stated it four times — 2026-08-14
/// for sliders (「슬라이더위에서 조작하기 시작하면 슬라이더조작하는거고 **그
/// 외가 스크롤인거야**」), 08-28 for buttons, 08-29:
///
/// > 「**터치 좌표가 버튼인데 거기서 움직였다고 스크롤이 발생하는게 심각한
/// > 버그야**」
///
/// and 08-30, striking down the threshold this file used to reach for:
///
/// > 「왜 18px 이딴규칙 설정하려고하는거지? 그게아니라 **클릭이 버튼이면
/// > 스크롤 절대 발생안하게한다**고. 다음 클릭으로 빈공간을 제대로 클릭해야
/// > 스크롤 발생하는거라고」
///
/// ⛔IT DOES NOT LIVE IN THE TIMELINE. It used to, as `RailControlPointer`
/// in `layer_label_controls.dart`, and the name plus the address is why the
/// x-sheet's toggles, the top strip's blend lock and the toolbar's 1·2·3·4·N
/// were still bare on 2026-08-29: a surface that is not the rail does not go
/// looking in a rail file for a rule that turns out to be the whole app's.
/// One home, so a button anywhere can wear it.
///
/// ⚠️Nesting is safe and the rail relies on it: the claims are `Set`s, so a
/// second claim on the same pointer is a no-op and both wrappers release on
/// the same event ([RailSwipeColumnPointer] adds the strong claim over this
/// one).
///
/// 🚨★★★IT TAKES THE DRAG FROM THE FIRST PIXEL, and it fires the control
/// itself.
///
/// Those two are one decision. A `Scrollable`'s own drag recogniser asks
/// nobody, so the only way to stop it is to win the arena before it does —
/// and Flutter hardcodes a MOUSE to `kPrecisePointerHitSlop`, ONE pixel,
/// ignoring the gesture settings for that kind alone. Winning that early
/// means the inner widget's tap is rejected on every click that wobbles,
/// which is exactly what 유저 reported on 08-30 (「**펜마우스만 그자리에서
/// 손떼야 작동함**」) when the mouse was first let in.
///
/// ⛔A THRESHOLD CANNOT SEPARATE THEM. This file spent a round asking its
/// slop with `PointerDeviceKind.touch` so a mouse got 18px instead of 1 —
/// that fixed the pen and left the scroller winning the pixel first. The
/// question was never 「how far」; it is 「what was pressed」.
///
/// So the arena is taken on the FIRST MOVEMENT with no distance compared at
/// all (유저: 「1px 이동했는지 같은 px 이동으로 판단하는거 설마 아직도
/// 남아있나?」 · 「싹 깔끔하게 걷어내」), and [onPressed] is called from the
/// raw pointer stream on the moment [PressFire] names. Nothing here depends
/// on winning a tap.
///
/// ⚠️WHAT THIS COSTS, measured rather than guessed: whoever wins the arena
/// cancels the inner widget's tap recogniser, and Material's PRESSED LOOK
/// rides on that. 🧪`onHighlightChanged` reports `[true]` on the down and
/// `[true, false]` two pixels later — so a press that wobbles goes back to
/// looking unpressed while the finger is still down. The action still fires
/// on the release.
///
/// ⛔It is not new and it is not this file's doing: any rival winning does
/// it, pen and touch have done it past their own threshold all along, and
/// what changed is only that a MOUSE now has a rival at all.
///
/// 🚨★★★AND IT STAYS (유저 확정 2026-08-30, board `press-look-dies-on-a-wobble`,
/// 답 `leave-it`): **동작이 우선.** The button always acts correctly; only the
/// ink is skipped on a press that wobbles. ⛔The two ways out were both real
/// and both are now REFUSED, so nobody re-opens this in six months:
///
///  * driving the pressed look from here would mean threading a states
///    controller through ~88 call sites, and `IconButton`/`TextButton` take
///    it through their style while a bare `InkWell` paints its own ink —
///    two paths for one look;
///  * giving the mouse a drag-scroll this app owns would mean rebuilding
///    ballistics, overscroll and nested scrollers.
class ControlPressClaim extends StatefulWidget {
  const ControlPressClaim({
    super.key,
    required this.onPressed,
    required this.child,
  });

  /// What this control does. Null means it is disabled, and then nothing
  /// fires — but the claim still stands, so a press on a dead button is
  /// still not a scroll.
  ///
  /// 🚨★REQUIRED, null included (F-120, 유저 2026-09-13: 「펜으로 … +버튼
  /// 옆의 생성할 레이어 여는 버튼같은게 작동안함」). It was optional, and a
  /// claim that was simply not told what to fire looked exactly like one
  /// that fires: the `＋` caret mounted this and opened its menu from the
  /// child's TAP instead — the tap this claim's own recognisers reject on
  /// the first movement, so it opened for a still mouse and never for a
  /// pen. Five more claims said nothing because a claim inside them
  /// already fired; they were deleted, not kept. ⇒ A claim now has to SAY
  /// what it fires, and `null` is a disabled control on purpose, never a
  /// forgotten argument.
  final VoidCallback? onPressed;

  final Widget child;

  @override
  State<ControlPressClaim> createState() => _ControlPressClaimState();
}

class _ControlPressClaimState extends State<ControlPressClaim> {
  /// Pointers this claim is the INNERMOST owner of.
  ///
  /// 🚨★★★THE DEEPEST CONTROL WINS, and that rule had to be brought back by
  /// hand. Flutter's arena gave it away for free — one winner per pointer —
  /// and firing from the raw pointer stream instead means EVERY claim on the
  /// path hears the same press. 🧪Measured: the import table's row and its
  /// cell are both claimed, so pressing a cell selected the row as well and
  /// the cell's own answer never landed
  /// (`import_dialog_test`: 「a cell speaks for the SELECTION when its row is
  /// in one」).
  ///
  /// ⛔The set is the shared one, not a second bookkeeping of the same fact
  /// ([[make-the-invariant-unrepresentable]]): pointer-down runs deepest
  /// first, so whoever finds [pressIsSpokenFor] still FALSE is the innermost,
  /// and everyone above it stands down for this press.
  final Set<int> _mine = <int>{};

  bool _releasedInside(Offset position) {
    // A control that left the tree while it was held — a playback view that
    // ended under the finger — still hears the lift, because pointer-up goes
    // to the path the DOWN was hit-tested on. It has no box to be inside of.
    if (!mounted) {
      return false;
    }
    return pointerIsStillOn(context, position);
  }

  @override
  Widget build(BuildContext context) {
    final fireOn = PressFireScope.of(context);
    return RawGestureDetector(
      behavior: HitTestBehavior.deferToChild,
      gestures: _absorbingPair(_VerbKnown.byTheFirstMove),
      child: Listener(
        onPointerDown: (event) {
          final innermost = !pressIsSpokenFor(event.pointer);
          claimTapForControl(event.pointer);
          if (!innermost) {
            return;
          }
          _mine.add(event.pointer);
          if (fireOn == PressFire.down) {
            widget.onPressed?.call();
          }
        },
        onPointerUp: (event) {
          releaseTapForControl(event.pointer);
          if (!_mine.remove(event.pointer)) {
            return;
          }
          // 🚨A PRESS SOMETHING TURNED INTO A DRAG VERB IS NOT A CLICK (H24,
          // 2026-09-15). The canvas takes the strong claim on the pointers it
          // makes into its own gestures — a pan, a pinch, a flip — and a
          // claimed control on that canvas (the playback view's stop, a conte
          // cell, the header editor's tap-away) must not fire when that
          // gesture lifts inside it. The playback view had already said so in
          // as many words (D13): 「a plain tap — a press that navigates
          // nothing — still means stop」. ⚠️Read BEFORE the canvas lets go:
          // pointer-up runs deepest first, so the claim is still standing.
          // The swipe columns are untouched — they fire on the DOWN.
          if (fireOn == PressFire.upInside &&
              _releasedInside(event.position) &&
              !valueControlOwnsPointer(event.pointer)) {
            widget.onPressed?.call();
          }
        },
        // ⛔Cancel too: a claim that outlives its gesture silently deafens
        // every later press handed the same pointer id. Nothing fires here —
        // a cancelled gesture is not a release.
        onPointerCancel: (event) {
          releaseTapForControl(event.pointer);
          _mine.remove(event.pointer);
        },
        child: widget.child,
      ),
    );
  }
}

/// The absorbing pair. They report nothing and change nothing — HOLDING the
/// pointer IS the whole job, and it is what stops an ancestor scroller from
/// starting on a control.
///
/// 🚨★★★NO DISTANCE IS COMPARED. 유저 2026-08-30, on finding the device's own
/// slop still being consulted here:
///
/// > 「**1px 이동했는지 같은 px 이동으로 판단하는거** 설마 아직도 남아있나?
/// > 내가 다른방법 제안하지 않았어?」 · 「싹 깔끔하게 걷어내」
///
/// They had proposed the other method already. A threshold is only ever asked
/// because something needs to know 「is this a click or a drag」 — and once
/// the click is decided by WHERE THE FINGER CAME UP instead, there is nothing
/// left for a distance to answer.
///
/// ⛔Every threshold this file carried is retired by that, and none may come
/// back: 18px asked with `PointerDeviceKind.touch` (which fixed the pen and
/// left the scroller winning the pixel first), and the device's own slop
/// (which only won on a tie-break against a rival using the same constant).
/// 「클릭이 버튼이면 스크롤 절대 발생안하게한다」 is not a threshold.
///
/// ★So they are [OwningHorizontalDragGestureRecognizer] and its twin — the
/// app's existing 「accept on the first movement」 pair, which the sliders and
/// the swipe columns already ride. ⛔They are NOT re-implemented here: this
/// file spent a round with two hand-written copies, one per axis, and the day
/// one of them was wrong the other was too ([[no-copy-to-share]]).
///
/// ⚠️THE FIRST MOVE, not the down. Pointer-down dispatch runs deepest-first,
/// so a rail button's own claim is offered the pointer BEFORE the swipe
/// column's strong claim above it exists — accepting there killed every
/// swipe column (measured). By the first move every down handler on the path
/// has run, which is the earliest moment the answer is complete. Nothing can
/// scroll in between: a scroller needs a move too, and this one is deeper, so
/// it is offered the same event first.
Map<Type, GestureRecognizerFactory> _absorbingPair(_VerbKnown known) =>
    <Type, GestureRecognizerFactory>{
      _AbsorbsHorizontalDrag:
          GestureRecognizerFactoryWithHandlers<_AbsorbsHorizontalDrag>(
            () => _AbsorbsHorizontalDrag(known),
            // ⛔A no-op handler is REQUIRED, not decoration:
            // `DragGestureRecognizer.isPointerAllowed` returns FALSE when
            // every callback is null, so a recogniser with nothing to report
            // is never even offered the pointer. 🧪Measured: with `(r) {}`
            // the absorb silently did nothing and the list scrolled from a
            // button exactly as before.
            (recognizer) => recognizer.onStart = (_) {},
          ),
      _AbsorbsVerticalDrag:
          GestureRecognizerFactoryWithHandlers<_AbsorbsVerticalDrag>(
            () => _AbsorbsVerticalDrag(known),
            (recognizer) => recognizer.onStart = (_) {},
          ),
    };

/// When a pointer's drag VERB is known well enough to make way for it.
///
/// ⛔A drag from here is somebody's VERB (a swipe column, a slider): the
/// absorbing pair stands down so the thing that owns it can run. What
/// differs between the two claims that mount the pair is only WHEN that is
/// known — one question, answered at the moment each of them can answer it.
enum _VerbKnown {
  /// By the FIRST MOVE — a button's claim ([ControlPressClaim]). The note on
  /// the pair above says why: a swipe column's strong claim sits ABOVE the
  /// button and is taken after the button is offered the pointer.
  byTheFirstMove,

  /// At the DOWN — a surface's claim ([SurfaceDragClaim]). The canvas above
  /// the surface takes the strong claim on the pointers it makes into its
  /// own gestures, and those are exactly the drags the surface is there to
  /// hold. Only a claim taken BELOW it — offered the down first — is a verb
  /// to make way for.
  atTheDown,
}

/// The pair's one question: hold this drag, or make way for a verb?
///
/// ⚠️A helper each recogniser HOLDS, not a mixin: `DragGestureRecognizer` is
/// sealed outside its own library, so nothing can be mixed in on it.
class _MakeWay {
  _MakeWay(this._known);

  final _VerbKnown _known;
  int? _pointer;
  bool _verbAtTheDown = false;

  void noteDown(PointerDownEvent event) {
    _pointer = event.pointer;
    _verbAtTheDown = valueControlOwnsPointer(event.pointer);
  }

  bool get forAVerb {
    final pointer = _pointer;
    return switch (_known) {
      _VerbKnown.byTheFirstMove =>
        pointer != null && valueControlOwnsPointer(pointer),
      _VerbKnown.atTheDown => _verbAtTheDown,
    };
  }
}

class _AbsorbsHorizontalDrag extends OwningHorizontalDragGestureRecognizer {
  _AbsorbsHorizontalDrag(_VerbKnown known) : _makeWay = _MakeWay(known);

  final _MakeWay _makeWay;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _makeWay.noteDown(event);
    super.addAllowedPointer(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => !_makeWay.forAVerb;
}

class _AbsorbsVerticalDrag extends OwningVerticalDragGestureRecognizer {
  _AbsorbsVerticalDrag(_VerbKnown known) : _makeWay = _MakeWay(known);

  final _MakeWay _makeWay;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _makeWay.noteDown(event);
    super.addAllowedPointer(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => !_makeWay.forAVerb;
}

/// 🚨★★★A DRAG FROM HERE IS THIS THING'S VERB — the STRONG claim, in one
/// place.
///
/// [ControlPressClaim] says 「the TAP is mine」 and absorbs the drag, which
/// is right for a button: a drag from a button is nobody's verb, so nothing
/// should happen. A slider, a splitter and a swipe column are the other
/// case — the drag IS the thing they do — and they say so with this.
///
/// What it buys, in one sentence each:
/// * [EagerPanGestureRecognizer] declines the pointer at `addPointer`, so
///   no edit pan above starts from a press that landed here;
/// * [ControlPressClaim]'s absorbing recognisers stand down at accept time,
///   so the drag reaches whatever mounted this.
///
/// ⛔It was written THREE times before this — `field_slider`,
/// `dock_edge_splitter` and the rail's swipe column each carried the same
/// four lines. Three copies of one law is how the day comes that one of
/// them learns something the others do not ([[no-copy-to-share]]).
///
/// ⚠️It does NOT mount the drag recogniser. What the drag DOES is the
/// caller's — a slider moves a value, a splitter moves an edge, a swipe
/// column paints its rows — and the recognisers for that live in
/// [axis_bar_gesture.dart], where accepting on the first movement is the
/// half that beats an ancestor scroller.
class DragVerbClaim extends StatelessWidget {
  const DragVerbClaim({
    super.key,
    required this.child,
    this.behavior = HitTestBehavior.deferToChild,
  });

  final Widget child;

  /// Opaque where the claim must cover its own padding — a splitter grip is
  /// mostly empty space and still has to be claimable.
  final HitTestBehavior behavior;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: behavior,
      // Claimed HERE because hit-test dispatch runs deepest-first, so the
      // claim is already standing by the time anything above is offered the
      // same event and asks.
      onPointerDown: (event) => claimPointerForValueControl(event.pointer),
      onPointerUp: (event) => releasePointerForValueControl(event.pointer),
      // ⛔Cancel too: a claim that outlives its gesture would silently
      // deafen whichever later pan is handed the same id.
      onPointerCancel: (event) => releasePointerForValueControl(event.pointer),
      child: child,
    );
  }
}

/// 🚨★★★A DRAG THAT STARTS ON A CANVAS SURFACE IS THAT SURFACE'S — the
/// claim a whole surface wears, where [ControlPressClaim] is a button's and
/// [DragVerbClaim] a bar's.
///
/// H24, reported three times: 08-26 「패널이 여러 개 열려 레일이 생기면 터치
/// 시 스크롤 발생」, 09-01 「내부 터치는 강한 클레임으로 애초에 다른 곳에서
/// 조작이 발생 안 하게」, 09-15 「스페이스바+클릭이나 터치조작이나 뷰어패널
/// 내부에 대한 조작이 … 스크롤바랑 동시적용 … 스크롤바 절대 적용안되게
/// 강한클레임으로 잡아줘. 캔버스 베이스패널은 전부 다 똑같이」.
///
/// It is the same absorbing pair a button wears, and it differs in one
/// thing, for one reason: it makes way only for a verb claimed BELOW it
/// ([_VerbKnown.atTheDown]). The canvas it is mounted inside claims the
/// pointers it turns into its own pans and pinches, and those are the very
/// drags this has to hold against an ancestor scroller — so a claim taken
/// ABOVE it cannot be a reason to let go.
///
/// ⚠️It holds; it does not act. Everything the canvas does reads raw
/// pointers, which no arena can take away, so nothing on the canvas loses
/// its gesture to this. What does lose is an ARENA member beneath it that
/// asks later: a handle that waited for a slop (it now accepts on the first
/// movement — [OwningPanGestureRecognizer]), a tap recogniser (the playback
/// view, the conte cells and the header editor's tap-away fire from
/// [ControlPressClaim] now), and a text field (it takes [DragVerbClaim], and
/// this makes way).
class SurfaceDragClaim extends StatelessWidget {
  const SurfaceDragClaim({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      // Translucent, as the canvas layer around it is: a blank canvas paints
      // nothing hit-testable, and a drag that starts there is still the
      // canvas's.
      behavior: HitTestBehavior.translucent,
      gestures: _absorbingPair(_VerbKnown.atTheDown),
      child: child,
    );
  }
}
