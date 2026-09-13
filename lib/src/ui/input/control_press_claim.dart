import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../widgets/axis_bar_gesture.dart';
import 'value_control_pointers.dart';

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
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return false;
    }
    return box.size.contains(box.globalToLocal(position));
  }

  @override
  Widget build(BuildContext context) {
    final fireOn = PressFireScope.of(context);
    return RawGestureDetector(
      behavior: HitTestBehavior.deferToChild,
      gestures: <Type, GestureRecognizerFactory>{
        _ControlOwnsHorizontalDrag:
            GestureRecognizerFactoryWithHandlers<_ControlOwnsHorizontalDrag>(
              _ControlOwnsHorizontalDrag.new,
              // ⛔A no-op handler is REQUIRED, not decoration:
              // `DragGestureRecognizer.isPointerAllowed` returns FALSE when
              // every callback is null, so a recogniser with nothing to
              // report is never even offered the pointer. 🧪Measured: with
              // `(r) {}` the absorb silently did nothing and the list
              // scrolled from a button exactly as before.
              (recognizer) => recognizer.onStart = (_) {},
            ),
        _ControlOwnsVerticalDrag:
            GestureRecognizerFactoryWithHandlers<_ControlOwnsVerticalDrag>(
              _ControlOwnsVerticalDrag.new,
              (recognizer) => recognizer.onStart = (_) {},
            ),
      },
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
          if (fireOn == PressFire.upInside && _releasedInside(event.position)) {
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
bool _absorbsThisDrag(int? pointer) => !_standsDown(pointer);

class _ControlOwnsHorizontalDrag extends OwningHorizontalDragGestureRecognizer {
  int? _pointer;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _pointer = event.pointer;
    super.addAllowedPointer(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => _absorbsThisDrag(_pointer);
}

class _ControlOwnsVerticalDrag extends OwningVerticalDragGestureRecognizer {
  int? _pointer;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _pointer = event.pointer;
    super.addAllowedPointer(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => _absorbsThisDrag(_pointer);
}

/// ⛔A drag from here is somebody's VERB (a swipe column, a slider): the
/// weak claim stands down so the thing that owns it can run.
bool _standsDown(int? pointer) =>
    pointer != null && valueControlOwnsPointer(pointer);

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
