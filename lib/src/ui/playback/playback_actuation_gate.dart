import 'package:flutter/gestures.dart'
    show
        GestureBinding,
        PointerDownEvent,
        PointerEvent,
        PointerPanZoomStartEvent,
        PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show BoxHitTestResult, RenderProxyBox, SemanticsConfiguration;
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent, KeyUpEvent;

import '../shortcuts/editor_shortcut_scope.dart';
import '../shortcuts/shortcut_activator_codec.dart' show isModifierKey;
import 'playback_transport.dart';

/// 🚨★★★ T28-c — WHILE PLAYING, THE FIRST ACTUATION IS STOP, AND ONLY STOP.
/// D13 (2026-08-17) amends exactly ONE carve-out: a pointer actuation whose
/// hit path CLAIMS into the canvas panel's subtree NAVIGATES (pan/zoom keep
/// working during playback); every other actuation stops and is consumed,
/// unchanged.
///
/// 유저 2026-08-13: 「재생중에 **뭘 누르든 입력이 존재하면 정지**. 키보드든
/// 터치든 펜이든 **어떤식으로든** 입력 들어오면 정지」 · 「뭘 하든 정지만.
/// **입력 일 안함**」. 유저 2026-08-17 (D13): 「재생 중 팬·줌 가능」.
///
/// ★It is one law and it has one home. Asking each surface to check
/// "am I playing?" before doing its job is the shape D and T5/T13 each spent
/// a round removing: the surface added tomorrow forgets, and the rule quietly
/// becomes "most places". Here the editor is wrapped once and nothing
/// downstream knows this exists — the D13 hole is likewise the GATE's
/// (it asks whose surface the pointer actually lands on), never a
/// surface's own check.
///
/// 🚨★★★AND "PLAYING" MEANS EVERY [PlaybackTransport], NOT THE CANVAS.
/// 유저 2026-09-07 chose `exclusive` for the media viewer's sound: 「나중에
/// 누른 쪽이 이기고 진 쪽은 정지」, both directions. This used to hold a
/// `CanvasPlaybackController` by its concrete type, so the canvas→viewer
/// direction worked (the viewer's button is under this gate) and the
/// viewer→canvas direction did not exist at all — the gate could not hear
/// a timer it had never been told about. Holding [PlaybackTransports]
/// instead makes exclusive fall out of the law already written here: while
/// ANY transport plays, the first actuation stops ALL of them and is
/// eaten, so the second press starts whichever surface it landed on.
/// ⛔That double press is not a bug to smooth over per surface — 유저
/// 2026-09-08, asked exactly that: 「그대로 둠. 그게 직관적임」.
///
/// 📐The D13 hole is decided by the HIT PATH, not by a rectangle: the
/// floating timeline overlaps the canvas panel's rect, so 「캔버스 위 좌표」
/// would have let a timeline press act during playback. The absorber
/// hit-tests the subtree and passes the event ONLY when the hit CLAIMED
/// into [navigationRegion]'s subtree — the canvas panel: its
/// viewport gestures, zoom buttons and panbars (the chrome the playback
/// view renders inside on purpose, "so the panel chrome keeps working
/// during playback"). Drawing cannot leak through the hole: playback swaps
/// the panel's content, so the drawing surface is not mounted at all. A
/// plain TAP on the canvas picture stops playback — that is
/// `CanvasPlaybackView`'s own tap handler, awake again now that pointers
/// reach it (the pre-T28-c stop it always carried). KEYBOARD actuations
/// keep the stop law everywhere but one: a bound view ZOOM (R6q3, below).
///
/// ↩️The drawing surface was not all a press could reach (board
/// `playback-tap-taken-by-tool-layer`): the TOOL layers over it — the
/// eyedropper's and the stamp's tap layer, the selection tools' layer — were
/// mounted by the tool alone and took the press over the playing picture.
/// They stand down with the content now (`BrushCanvasPanel.toolInputEnabled`).
///
/// 🚨R6q3 (2026-08-25) — the user's answer to "어디까지 만질 수 있게 할까"
/// was 2번: 「키보드 줌도 통과시킨다. 재생 중 줌은 입력 수단과 무관하게 한
/// 법으로」. While no key zoomed, having no second case satisfied it — and the
/// sentence above once claimed zoom keys the registry did not have. I-19
/// bound two (유저 2026-09-13: 「shift+>(확대) shift+<(축소)」), so the law
/// has a subject: a viewport ZOOM passes whatever the device, where the
/// pointer's does — while the canvas run plays. It lives in this gate's key
/// half ([_PlaybackActuationGateState._onKey]) and in the action funnel, both
/// asking [viewZoomPassesPlayback]; never as a check inside a zoom action.
/// A modifier's own key-down waits for the chord (✅1 below, answered on
/// the board as `I-19-zoom-key-playback`), so the default Shift+. passes
/// as well.
///
/// ✅유저 확정 — the two questions this had, both answered (⛔재론 금지):
/// 1. **「입력」 = actuation only**: key DOWN, pointer DOWN, wheel/zoom.
///    🆕A MODIFIER alone is not one (유저 2026-09-13,
///    I-19-zoom-key-playback 1번: 「수식키는 혼자선 입력으로 치지
///    않는다」): its down waits for the key it modifies, and a modifier
///    let go with nothing after it stops on its release —
///    [_PlaybackActuationGateState._onKey].
///    ⛔Hover and plain mouse movement are not: 「커서만 움직여도 재생이
///    죽으면 데스크톱에서 못 쓴다」. Nothing here listens to move or hover.
/// 2. **The actuation is CONSUMED.** A pen touching the timeline leaves no
///    seek; `,` and `.` move no frame. That is what the absorber and
///    the handled key result are for — without them this would be "stop AND
///    do the thing", which is a different rule on every surface.
///    🪦Half of that sentence was a claim, not a behaviour, until
///    2026-09-08: `.` DID move a frame (실측). The key half now lives in
///    [_eatConsumedKey]; the note there says why the funnel could never
///    have done it.
///
/// 📐Stopping stands where it stopped ([PlaybackTransport.stop]);
/// 「재생아닌상태가 일시정지상태나 다름없음」 only holds if it does.
///
/// 🚨THE STOP DOES NOT GO THROUGH THE TREE, and that is not a shortcut — a
/// `Focus(onKeyEvent:)` cannot do it. Key events dispatch from the PRIMARY
/// FOCUS outward, so a widget only sees them if it is an ancestor of
/// whatever holds focus; anything nested deeper (a text field, a canvas
/// focus node) beats it, and 「뭘 누르든」 admits no such gap.
/// [HardwareKeyboard]'s handler list runs BEFORE focus dispatch, which is
/// the only position from which EVERY key can be seen.
///
/// ⚠️The CONSUMING half is the tree's, and where in the tree matters: the
/// gate wraps the editor's `FocusScope` rather than sitting inside it, so
/// its [Focus] node is on every key's way up to `Shortcuts`. That was not
/// true until 2026-09-08 — see [_PlaybackActuationGateState._eatConsumedKey].
///
/// ⚠️PERFORMANCE: it listens to [PlaybackTransports], which follows each
/// member's [PlaybackTransport.isActiveListenable] and NOT the transports
/// themselves. The canvas controller notifies once per played frame;
/// rebuilding a wrapper around the whole editor at fps is the exact
/// mistake the playback view's own comments were written to prevent. The
/// editor subtree rides through as `child`, so it is never rebuilt here at
/// all. The region verdict is computed per EVENT HIT TEST (a press, a wheel
/// notch, a hover test while playing) — never per played frame, and nothing
/// subscribes to layout.
///
/// 🚨🚨★★★AND THE SHAPE OF THIS TREE NEVER CHANGES, which is a second and
/// stronger requirement than not rebuilding (UI 08-14 #11). The gate used to
/// return the bare `child` when idle and wrap it in two widgets when playing.
/// Holding the same `child` INSTANCE is not enough: inserting ancestors moves
/// the subtree to a different position, Flutter finds a `Listener` where an
/// editor used to be, and it discards the whole element tree and inflates a
/// fresh one. Every [State] under this gate died on the first frame of
/// playback — the workspace's own included, which is why a folded timeline
/// sprang open the instant play was pressed and then folded again when the
/// saved layout was restored over the new state.
///
/// ⇒ The wrapper is ALWAYS mounted and only its flags move. A `Listener`
/// with null callbacks defers to its child, and the absorber that is not
/// absorbing is transparent, so the idle cost is two inert nodes and the
/// playing cost is a flag flip.
class PlaybackActuationGate extends StatefulWidget {
  const PlaybackActuationGate({
    super.key,
    required this.transports,
    required this.child,
    this.navigationRegion,
  });

  /// Everything that plays — the canvas and whatever media viewers are
  /// open. ⛔Never a single transport: the law is 「재생 중이면」, and the
  /// day a surface is missing from this list is the day the law becomes
  /// "most places".
  final PlaybackTransports transports;
  final Widget child;

  /// D13: the canvas panel's subtree key, TOGETHER WITH the run whose
  /// picture that subtree shows — pointer actuations whose hit path claims
  /// into it navigate instead of stopping, while that run is the one
  /// playing. Null keeps the pure T28-c law (every actuation stops).
  ///
  /// ⛔One field, not two: a key without its run is a hole that opens
  /// during somebody else's playback, which is [_regionBox]'s whole note.
  final ({GlobalKey key, PlaybackTransport transport})? navigationRegion;

  @override
  State<PlaybackActuationGate> createState() => _PlaybackActuationGateState();
}

/// 🚨R6q3 — whether a view ZOOM passes playback: exactly where the pointer's
/// does, while the canvas run (the run whose picture the D13 hole shows) is
/// the one playing.
///
/// ★ONE predicate for both halves of the pass-through — the gate's key half
/// and the action funnel's — so a zoom key and a bound touch gesture cannot
/// answer differently.
bool viewZoomPassesPlayback({
  required bool zoomsView,
  required PlaybackTransport? canvasRun,
}) => zoomsView && (canvasRun?.isPlaying ?? false);

class _PlaybackActuationGateState extends State<PlaybackActuationGate> {
  /// The absorber's per-event verdict, read by the stop handlers in the
  /// SAME event dispatch (hit test runs first, listeners after — single
  /// threaded, so the pair can never tear). One object for the widget's
  /// whole life: the render object writes it, the listeners read it.
  final _NavigationVerdict _verdict = _NavigationVerdict();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    super.dispose();
  }

  /// The key event this gate has already spent on a STOP, held only for
  /// the rest of that event's dispatch ([_eatConsumedKey] clears it).
  ///
  /// 🚨★★★**THE IDENTITY, NOT A FLAG.** A bare "just consumed one" boolean
  /// is set by every actuation and cleared by nobody in particular, so a
  /// press on the timeline would arm it and the NEXT bound key — pressed
  /// minutes later, with nothing playing — would be eaten by it.
  KeyEvent? _consumedKey;

  /// A modifier that went down while something played and has not been
  /// followed by another key or pointer actuation yet: its release stops
  /// playback, and whatever came after it decides otherwise
  /// (I-19-zoom-key-playback; the pointer half is [_onPointer]).
  bool _loneModifierDown = false;

  /// Registered for the gate's whole life, with the guard INSIDE.
  /// Subscribing and unsubscribing as playback comes and goes would make
  /// the handler's presence a second piece of state to keep true.
  ///
  /// ⚠️Returning true does NOT stop the key reaching the focus tree —
  /// measured, not assumed: Flutter dispatches the key message either way.
  /// So this handler owns only the STOP; [_eatConsumedKey] owns the other
  /// half. A key with no binding has nothing to eat.
  bool _onKey(KeyEvent event) {
    // Every key dispatch starts with the slot empty: a text field that
    // handles its own keys ends dispatch before [_eatConsumedKey], and a
    // note left there would outlive the event it describes.
    _consumedKey = null;
    if (!widget.transports.value) {
      _loneModifierDown = false;
      return false;
    }
    if (isModifierKey(event.logicalKey)) {
      // 🚨I-19-zoom-key-playback (유저 2026-09-13, 1번): 「수식키는 혼자선
      // 입력으로 치지 않는다」. A modifier's DOWN waits for the key it
      // modifies — Shift+. is one zoom, not a Shift that stopped playback
      // before the period existed. Not an input, so not eaten either: it
      // reaches the app like any modifier, and Alt's eyedropper hold takes
      // hold while the canvas plays. 🗣️유저, the same day, asked exactly
      // that: 「스포이드가 잡히는게 왜 문제지? 스포이드 작동할때 재생
      // 멈추게되는거아닌가? 전혀 문제없는데」 — the eyedropper's own press
      // is the input. ⚠️실측 the same day: over the playback view that press
      // does NOT stop yet — the tool tap layer takes it and samples, as it
      // did for the eyedropper TOOL before this (board:
      // `playback-tap-taken-by-tool-layer`). Let go with nothing after it,
      // the modifier was a press after all, and its UP is where that one
      // stops.
      if (event is KeyDownEvent) {
        _loneModifierDown = true;
      } else if (event is KeyUpEvent && _loneModifierDown) {
        _loneModifierDown = false;
        widget.transports.stopAll();
      }
      return false;
    }
    if (event is! KeyDownEvent) {
      // ⛔Key UP and repeat are not actuations. Eating the up of a key whose
      // down started playback would swallow half of an event the app never
      // saw the beginning of.
      return false;
    }
    _loneModifierDown = false;
    // 🚨R6q3: a bound ZOOM key is the key half of the D13 hole — it passes
    // while the canvas run plays, asked through the one predicate the action
    // funnel asks too.
    if (viewZoomPassesPlayback(
      zoomsView: EditorShortcutScope.peek(context)?.zoomsViewOn(event) ?? false,
      canvasRun: widget.navigationRegion?.transport,
    )) {
      return false;
    }
    widget.transports.stopAll();
    _consumedKey = event;
    return true;
  }

  /// Every pointer event, app-wide — only to hear that a held modifier was
  /// NOT alone (I-19-zoom-key-playback): a press, a wheel notch or a pinch
  /// after it — ✅1's pointer actuations — is the "something after".
  ///
  /// ⚠️Not the [Listener] in [build], measured: an actuation the D13 hole
  /// passes never reaches it (the panel shell's `MouseRegion` returns
  /// false, so nothing above the hole joins that hit path), and a Shift
  /// held through a canvas wheel zoom stopped playback on its release. A
  /// global route observes without joining hit testing — the way
  /// `home_page`'s activity clock already watches pointers.
  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent ||
        event is PointerSignalEvent ||
        event is PointerPanZoomStartEvent) {
      _loneModifierDown = false;
    }
  }

  /// 🚨★★★**「입력 일 안함」 FOR KEYS, AND IT LIVES HERE.**
  ///
  /// 🪦This half did not work at all until 2026-09-08, and the note above
  /// said where it was: 「the app's action funnel owns the other half」.
  /// It cannot. [HardwareKeyboard]'s handlers run BEFORE focus dispatch,
  /// so by the time the funnel is asked 「재생 중인가」 the answer is
  /// already no — [_onKey] just made it no. 실측: with playback running,
  /// pressing `.` stopped the transport AND stepped a frame, which is the
  /// 「stop AND do the thing」 this gate's own doc says it forbids.
  ///
  /// A [Focus] node CAN do this job, but ONLY from where the gate now
  /// sits: ABOVE the editor's `FocusScope` (`home_page`). Dispatch walks
  /// the focus-node chain UPWARD from the primary focus, and with no field
  /// focused that scope IS the primary focus — so the first attempt at
  /// this, with the gate mounted UNDER the scope as it had always been,
  /// changed nothing at all: the node was never consulted. Above the
  /// scope it is passed on the way to the `Shortcuts` higher up, whatever
  /// holds focus.
  ///
  /// ⛔It still cannot do the STOP: an unbound key must stop playback too,
  /// and dispatch never climbs this far when a descendant — a text field,
  /// a canvas focus node — handles the key first.
  ///
  /// ⚠️`canRequestFocus: false` + `skipTraversal: true` — a listening node
  /// only. A focusable one would join Tab order and could take focus away
  /// from the field the user is typing in.
  KeyEventResult _eatConsumedKey(FocusNode node, KeyEvent event) {
    if (!identical(_consumedKey, event)) {
      return KeyEventResult.ignored;
    }
    _consumedKey = null;
    return KeyEventResult.handled;
  }

  /// The navigation region's box — and ONLY while the run whose picture it
  /// shows is the one playing.
  ///
  /// 🚨★★★THE HOLE BELONGS TO ITS OWN RUN. D13 is 「재생 중 팬·줌 가능」
  /// for a CANVAS run, and the reason it cannot leak a drawing stroke is
  /// stated above: during one, the panel swaps its content, so the drawing
  /// surface is not mounted at all. Once a media viewer can be the thing
  /// playing, that stops being true — the panel is then showing the
  /// drawing surface, and an unconditional hole would let a press draw
  /// while the viewer ran, which is exactly what D13 says cannot happen.
  RenderBox? _regionBox() {
    final region = widget.navigationRegion;
    if (region == null || !region.transport.isPlaying) {
      return null;
    }
    final render = region.key.currentContext?.findRenderObject();
    return render is RenderBox && render.attached ? render : null;
  }

  void _stopUnlessNavigated() {
    if (!widget.transports.value) {
      return;
    }
    if (_verdict.navigated) {
      // D13: the event claimed into the canvas panel — it navigates;
      // the panel's own tap-to-stop covers the plain tap.
      return;
    }
    widget.transports.stopAll();
  }

  @override
  Widget build(BuildContext context) {
    // The key-consuming node wraps the WHOLE thing and is always mounted —
    // the tree-shape law again. It reads no state, so it never rebuilds.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _eatConsumedKey,
      child: ValueListenableBuilder<bool>(
        valueListenable: widget.transports,
        child: widget.child,
        builder: (context, playing, child) => Listener(
          onPointerDown: playing ? (_) => _stopUnlessNavigated() : null,
          // Wheel arrives as a signal; trackpad pinch/two-finger pan
          // arrive as PAN-ZOOM events (the viewport gesture layer's own
          // trackpad path reads exactly those) — the user named both:
          // 「휠/줌」. All three actuation kinds share the one verdict.
          onPointerSignal: playing ? (_) => _stopUnlessNavigated() : null,
          onPointerPanZoomStart: playing
              ? (_) => _stopUnlessNavigated()
              : null,
          // ★This is the 「입력 일 안함」 half. Without it the press would
          // stop playback AND land on whatever was under it. The D13 hole
          // and the stop above read ONE verdict — the absorber's — so
          // navigate-and-stop can never disagree about the same event.
          child: _NavigationHoleAbsorbPointer(
            absorbing: playing,
            regionBoxOf: _regionBox,
            verdict: _verdict,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The absorber's per-event answer: whether the last hit test (while
/// absorbing) passed the event through to the canvas panel.
class _NavigationVerdict {
  bool navigated = false;
}

/// [AbsorbPointer] with the D13 hole: while absorbing, an event whose
/// hit path actually CLAIMED into the navigation region's subtree
/// hit-tests normally (the canvas panel navigates); everywhere else it
/// behaves exactly like an absorbing [AbsorbPointer] (claims the
/// position, reaches no descendant) — including blocking SEMANTIC
/// actions, [RenderAbsorbPointer]'s other half: assistive-tech
/// activations bypass pointer hit tests entirely, so without
/// `isBlockingUserActions` a TalkBack double-tap would both act AND
/// leave playback running. The hit PATH decides the hole, not a rect —
/// the floating timeline overlaps the canvas panel's rectangle, and a
/// press on it must keep the stop-and-consume law. Always mounted — only
/// the flag flips (the tree-shape law above).
class _NavigationHoleAbsorbPointer extends SingleChildRenderObjectWidget {
  const _NavigationHoleAbsorbPointer({
    required this.absorbing,
    required this.regionBoxOf,
    required this.verdict,
    super.child,
  });

  final bool absorbing;
  final RenderBox? Function() regionBoxOf;
  final _NavigationVerdict verdict;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNavigationHoleAbsorbPointer(
        absorbing: absorbing,
        regionBoxOf: regionBoxOf,
        verdict: verdict,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderNavigationHoleAbsorbPointer renderObject,
  ) {
    renderObject
      ..absorbing = absorbing
      ..regionBoxOf = regionBoxOf
      ..verdict = verdict;
  }
}

class _RenderNavigationHoleAbsorbPointer extends RenderProxyBox {
  _RenderNavigationHoleAbsorbPointer({
    required bool absorbing,
    required this.regionBoxOf,
    required this.verdict,
  }) : _absorbing = absorbing;

  RenderBox? Function() regionBoxOf;
  _NavigationVerdict verdict;

  bool get absorbing => _absorbing;
  bool _absorbing;
  set absorbing(bool value) {
    if (_absorbing == value) {
      return;
    }
    _absorbing = value;
    // Like RenderAbsorbPointer: the flip changes hit-testing (no
    // paint/layout) AND the semantics blocking below.
    markNeedsSemanticsUpdate();
  }

  /// [RenderAbsorbPointer]'s other half, kept: while absorbing, semantic
  /// ACTIONS under the gate are inert. Assistive-tech activations
  /// dispatch straight to the target node — no pointer hit test, no key
  /// event — so this is the only place T28-c can hold for them.
  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isBlockingUserActions = _absorbing;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!_absorbing) {
      return super.hitTest(result, position: position);
    }
    verdict.navigated = false;
    final region = regionBoxOf();
    if (region != null) {
      // ⚠️The probe's RETURN VALUE is deliberately ignored: a hitTest
      // return is BLOCKING semantics (may this box's siblings still be
      // tested), while dispatch runs off the ENTRIES — and the panel
      // shell's `MouseRegion(opaque: false)` returns false forever while
      // still adding its whole claiming subtree to the path, so gating
      // on the return killed the hole everywhere in the real tree.
      final probe = BoxHitTestResult();
      super.hitTest(probe, position: position);
      if (_pathClaimedIntoRegion(probe, region)) {
        verdict.navigated = true;
        return super.hitTest(result, position: position);
      }
    }
    // RenderAbsorbPointer's exact shape: claim the position without
    // visiting descendants — the ancestor Listener still hears the down
    // (that is the stop), the editor below never does (that is the
    // 「입력 일 안함」 half).
    return size.contains(position);
  }

  /// Whether the probe's path contains the region box ITSELF — which is
  /// true exactly when a descendant of the canvas panel CLAIMED the hit
  /// (a proxy box joins the path only on a claiming child chain).
  ///
  /// ⛔Not `path.first`: translucent surfaces add themselves to the path
  /// without claiming — the full-bleed media drop target over the whole
  /// canvas tab is one, and reading the first entry declared IT the
  /// topmost surface everywhere, so the hole never opened (adversarial
  /// review). An opaque surface floating OVER the canvas (the timeline)
  /// still keeps the stop law: the stack never descends to the canvas
  /// under a claiming upper sibling, so the region box never joins that
  /// path. Identity scan per event, never per frame.
  static bool _pathClaimedIntoRegion(BoxHitTestResult probe, RenderBox region) {
    for (final entry in probe.path) {
      if (identical(entry.target, region)) {
        return true;
      }
    }
    return false;
  }
}
