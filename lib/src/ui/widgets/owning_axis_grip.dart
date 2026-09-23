import 'package:flutter/gestures.dart'
    show DragGestureRecognizer;
import 'package:flutter/widgets.dart';

import '../input/control_press_claim.dart';
import 'axis_bar_gesture.dart';

/// A GRIP that owns its press: the claim and the eager recogniser, together.
///
/// 🚨★★★**A GRIP SITS INSIDE A SCROLLER THAT RUNS THE OTHER WAY**, and both
/// halves of the law are needed to survive that:
///
///  * [DragVerbClaim], so a pan that ASKS declines a press that landed here
///    (the STRONG claim — the drag IS what a grip does);
///  * an `Owning*` recogniser, which accepts on the FIRST MOVEMENT, so the
///    scroller that asks nobody is beaten by being asked earlier.
///
/// ⛔Mounting only the first leaves the walkover: a grip pulled ACROSS its
/// own axis moves 0 along it, never reaches a threshold, and the ancestor
/// takes the gesture. 🗣️유저 2026-09-18 (F-163) on a block edge: 「프레임블록
/// 엣지 클릭한채로 세로이동하면 **세로스크롤 작동함** … 저번에 말한대로
/// 버튼은 절대 밖으로 제스쳐 새지않음. **해당 법 재사용/통일해서**」.
///
/// ⚠️ONE WIDGET for every drag verb that sits on a control: the dock
/// splitter (which wrote these four lines by hand first), the block edge's
/// comma grip, the cut end, and the sound's span in the SE audio lane. The
/// dense rows' chrome routes its grips by rect instead of mounting widgets,
/// so it wears the recogniser half directly (`TimelineRowEditChromeLayer`).
/// ⛔It is deliberately NOT inside `AxisGestureDetector`: the rail's swipe
/// column answers the press question its own way (the strong claim over the
/// buttons' weak one), and claiming twice made it stand down for itself.
/// 🧪Measured 2026-09-23, two suites red.
///
/// ↩️(F-163 재발, 유저 2026-09-23: 「버튼은 무조건 강한클레임」.) The first
/// landing counted the SE lane with the swipe column as answering its own
/// way — it did not: its span mounted a plain one-axis drag, and a pull
/// across the lane scrolled the timeline, as the cut end's did. Both wear
/// this now, as the splitter does.
class OwningAxisGrip extends StatelessWidget {
  const OwningAxisGrip({
    super.key,
    required this.axis,
    required this.configure,
    this.child,
    this.behavior = HitTestBehavior.opaque,
  });

  /// The axis the grip's VALUE follows. A cross-axis drag still holds the
  /// pointer and changes nothing, which is what 「you are operating this
  /// grip now」 means.
  final Axis axis;

  /// What the drag does — the caller's, exactly as `DragVerbClaim`'s note
  /// says: a splitter moves an edge, an exposure grip moves a comma.
  final void Function(DragGestureRecognizer recognizer) configure;

  final Widget? child;

  /// Opaque by default: a grip is mostly empty space and still has to be
  /// claimable.
  final HitTestBehavior behavior;

  @override
  Widget build(BuildContext context) {
    return DragVerbClaim(
      behavior: behavior,
      child: RawGestureDetector(
        behavior: behavior,
        gestures: <Type, GestureRecognizerFactory>{
          if (axis == Axis.horizontal)
            OwningHorizontalDragGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  OwningHorizontalDragGestureRecognizer
                >(
                  () => OwningHorizontalDragGestureRecognizer(debugOwner: this),
                  configure,
                )
          else
            OwningVerticalDragGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  OwningVerticalDragGestureRecognizer
                >(
                  () => OwningVerticalDragGestureRecognizer(debugOwner: this),
                  configure,
                ),
        },
        child: child,
      ),
    );
  }
}
