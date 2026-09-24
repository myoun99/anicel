part of '../brush_canvas_panel.dart';

/// THE LIFT — a selection lifted off the picture, what the panel shows
/// underneath it until it lands, and the three ways a lift ends
/// (confirmed, reverted, landed).
///
/// 🚨A collaborator carved out of `_BrushCanvasPanelState` (the audit's SRP
/// cut, Round 6, 2026-09-03). It reaches the panel through `_state`.
///
/// 🚨★★★**A MOVE SESSION WRITES NOTHING UNTIL IT IS CONFIRMED** (유저
/// 2026-09-17, reversing the 09-08 answer to `undo-41-hole-scope`: 「원본은
/// 남기되, 일시적으로 구멍 픽셀 잘라내고 플로트 띄운단거지? … 그 방식대로
/// 구조/근본적으로 작업 가자」).
///
/// ↩️**What stood here, and why it is gone.** The erase used to be committed
/// into the cel at the instant of the lift, so this file held the apparatus
/// for taking it back: a pre-lift [UndoSurfaceSnapshot] per session, the
/// store's budget exception that kept those pixels alive
/// (`holdLiftedPixels`/`releaseLiftedPixels`), a `_takeAnchor` verb that had
/// to read and release in one act because a half-release left a scratch file
/// behind, and a revert path that restored the snapshot. **Every one of them
/// existed to undo a write nobody had asked for yet**, and they went with it.
///
/// 🔬The 09-08 research is still true and is why this is not a claim about
/// 「pro tools do it non-destructively」: Krita clears the source immediately
/// exactly as we did, and OpenToonz holds raw rasters on a global tool
/// object. ⛔The reason to leave that company is not tidiness — it is that a
/// committed erase means **leaving the frame leaves a hole behind**, which
/// is why a seek, a row press and a cut switch were refused for as long as a
/// box was open (F-116·F-86, 유저: 「타임라인쪽 조작이 안먹힘」).
class _CanvasPanelLift {
  _CanvasPanelLift(this._state);

  final _BrushCanvasPanelState _state;

  /// The open session, or null when no move is pending.
  _MoveSession? _session;

  /// What the interactive painter draws for [key] while a move is pending —
  /// null when nothing is pending, or when the panel has moved to another
  /// cel since (the hole belongs to the cel it was cut from, and only that
  /// one: F-86 keeps the REGION across a frame move, not the pixels).
  ///
  /// 🚨★★★**IT REBUILDS WHAT A MEMORY WARNING TOOK.** The holed picture is
  /// a derivation, and the store's discipline gives derivations back by
  /// dropping them ([BrushFrameStore.holdReclaimableView]) rather than by
  /// parking them to disk — a parked surface is one the next paint cannot
  /// draw, which is the blank frame 유저 forbade outright. So a null here
  /// after a warning means one recompute, not a lost edit.
  BitmapSurface? holedSurfaceFor(BrushFrameKey key) {
    final session = _session;
    if (session == null || session.key != key) {
      return null;
    }
    return session.holed ??= _state.widget._editableCoordinator
        ?.deriveSurfaceWith([session.eraseDab]);
  }

  void openSession({
    required CanvasSelectionRegion region,
    required CanvasSelectionRegion? userSelection,
    required int token,
    required BitmapSurface holed,
    required BrushDab eraseDab,
    required BrushFrameKey key,
  }) {
    final session = _MoveSession(
      region: region,
      userSelection: userSelection,
      token: token,
      key: key,
      eraseDab: eraseDab,
      holed: holed,
    );
    _session = session;
    final coordinator = _state.widget._editableCoordinator;
    // The bytes are declared the moment they exist — the half of 유저's
    // 09-08 answer that the 09-17 reversal did NOT overturn: an open
    // session is held to the same discipline as a confirmed one. And it
    // owes only what it does not SHARE with the cel, which for anything
    // short of a whole-picture box is a handful of tiles.
    //
    // ⛔These two capture the session and the coordinator and nothing else
    // — the closure-scope law C-ipad-crash ① is written in below. They die
    // with the session rather than living in the history, but a closure
    // made where `_state` is in scope keeps `_state`.
    coordinator?.frameStore.holdReclaimableView(
      token,
      bytes: () =>
          session.holed?.bytesNotSharedWith(
            coordinator.currentSurfaceOf(session.key),
          ) ??
          0,
      reclaim: () => session.holed = null,
    );
  }

  /// Takes the session back, or null when [liftToken] is not the open one.
  _MoveSession? _closeSession(int liftToken) {
    final session = _session;
    if (session == null || session.token != liftToken) {
      return null;
    }
    _session = null;
    _state.widget._editableCoordinator?.frameStore.releaseReclaimableView(
      liftToken,
    );
    return session;
  }

  /// The dabs a landing writes, in the order that makes the picture: the
  /// erase the session has been SHOWING, then the stamp where it ended up.
  ///
  /// 🚨★★★**BOTH, AND IN THIS ORDER** — the session's hole was a view, so
  /// the landing is the first time the cel hears about it at all. Landing
  /// the stamp alone (which is what this did while the erase was committed
  /// up front) would leave the original pixels under the moved copy: the
  /// ink twice, once where it was and once where it went.
  List<BrushDab> _landingDabs(BrushDab eraseDab, BrushDab stampDab) => [
    eraseDab,
    stampDab,
  ];

  /// 🚨★★★**THE OTHER CELS THE SAME CONFIRM LANDS ON** — the frame range's
  /// whole block (F-116-b / F-164).
  ///
  /// 🗣️유저 2026-09-17: 「몇 행에 걸쳐서 적용하던 **동시적용은 가능하게**.
  /// **적용시만 각 행에 따라 불가능하면 그냥 무시**하는방식」 · 2026-09-18:
  /// 「**여러프레임 확정가능**하게한다던가」.
  ///
  /// ⛔**THE SAME MOVE, NOT THE SAME PIXELS.** The float carries what was
  /// lifted from the cel the session started on; stamping it onto another
  /// cel would paste that drawing into this one. Each cel lifts its OWN
  /// pixels and takes the same transform.
  ///
  /// 🚨★★★**THROUGH THE USER'S SELECTION, ELSE ITS OWN WHOLE PICTURE** —
  /// 🗣️유저 2026-09-24 (H41): 「선택도구 사용했으면 어떤프레임이든 선택도구
  /// 안쪽만, 아니면 각자 그림 전체적용」 · 「다른 프레임 그림의 잘려서
  /// 변형안먹힌 부분이 있었어」. With nothing selected the session's region
  /// is the move tool's box around the STANDING cel's ink, and every other
  /// cel was cut through that same box: whatever of its drawing lay outside
  /// the standing cel's picture stayed where it was. Each cel now frames
  /// its own ink ([CanvasSelectionShape.wholePicture], the one the standing
  /// cel's box is), and only a selection the user made is shared.
  ///
  /// 🚨★★★**ONE LANDING PER CEL, AND THE MAP IS WHAT SAYS SO.** [landOn] —
  /// the standing cel's, carrying the float the preview already resampled —
  /// SEEDS the result under its own key, so the loop cannot add a second
  /// landing for that cel however the ladder is spelled. ⛔It is not a
  /// `key == session.key` skip: the ladder may also name one cel twice
  /// (two frame keys can fold onto one physical cel), and a skip that
  /// names only the session would let that through.
  ///
  /// 🧪A duplicate is invisible in the picture — the second erase wipes the
  /// second stamp's ground and the stamp puts back the same pixels, both
  /// built from the same pre-landing surface — so nothing on screen would
  /// ever have reported it. What it costs is a whole second resample and a
  /// whole second pre-landing surface held in history for that cel, which
  /// is what `retainedBytes` is pinned on.
  ///
  /// 「불가능하면 그냥 무시」 is the two nulls: a cel the ladder names but
  /// that yields no lift (nothing in it, nothing under the outline) simply
  /// contributes no landing.
  Map<BrushFrameKey, Command> _landingsPerCel(
    _MoveSession session,
    BrushDab stampDab,
    Command landOn,
    SelectionAffine? affine,
  ) {
    final ladder = _state.widget.transformTargetKeys?.call();
    final coordinator = _state.widget._editableCoordinator;
    if (ladder == null || coordinator == null) {
      return {session.key: landOn};
    }
    // 🚨★★★**KEYED BY THE PHYSICAL CEL.** `pixelVerbCellKeys` deliberately
    // does NOT dedupe — 「the one that owns the surfaces owns this」 — and
    // linked rows are windows onto one bank, so the ladder can name one
    // cel under two row keys. `CelPixelOverwriteCommand` answers that with
    // `canonicalKeyOf`; this is the same answer, not a second one.
    final store = coordinator.frameStore;
    final landings = {store.canonicalKeyOf(session.key): landOn};
    // 🚨★★★**WHAT THE TRANSFORM DID — ALL OF IT.**
    //
    // 🗣️유저 2026-09-22, 실기: 「1과 2 동일한 그림 만들고 **이동+확대**하고
    // **둘다 동시적용** 해봤는데 **한쪽 값의 확대가 사라졌어. 이동은
    // 남아있는데**」.
    //
    // ↩️This read a DISPLACEMENT off the float — `stampDab.center` against
    // where it was cut from — and offset each cel's own lift by it. That
    // is the move and nothing else: the scale and the rotation live in the
    // affine, which never came down here, so a pure ×2 (whose centre does
    // not move) shifted the other cels by exactly zero. The comment that
    // stood here argued for reading the dabs 「rather than the affine」,
    // which was true of the one number it was reading and false of the
    // three it was not.
    //
    // ⛔The pivot is the BOX's — 유저: 「확대/축소의 기준점은 **항상 상자의
    // 중심**」, and with a range live that is the one box on screen, so the
    // same affine describes every cel's landing.
    for (final key in ladder) {
      final cel = store.canonicalKeyOf(key);
      if (landings.containsKey(cel)) {
        continue;
      }
      final surface = coordinator.currentSurfaceOf(key);
      final lift = buildSelectionLiftDabs(
        region:
            session.userSelection ??
            CanvasSelectionRegion.shape(
              CanvasSelectionShape.wholePicture(
                _state.widget.canvasSize,
                bitmapSurfaceContentBounds(surface),
              ),
            ),
        surface: surface,
        liftId: '${session.token}-${landings.length}',
        options:
            _state.widget.selectionMaskOptions?.value ??
            SelectionMaskOptions.none,
      );
      if (lift == null) {
        continue;
      }
      landings[cel] = BrushLiftMoveHistoryCommand(
        coordinator: coordinator,
        frameKey: key,
        preLiftSurface: coordinator.currentSurfaceOf(key),
        landingDabs: _landingDabs(
          lift.eraseDab,
          // ⚠️The SAME resample the standing cel's float went through, on
          // this cel's own pixels. A pure translation still costs nothing:
          // `transformStampDab` carries it by moving the centre.
          affine == null
              ? lift.stampDab
              : transformStampDab(lift.stampDab, affine),
        ),
        cacheInvalidationSink: _state.widget.cacheInvalidationSink,
      );
    }
    return landings;
  }

  /// R16-① confirm: lands the move as ONE undo entry whose undo target is
  /// the picture the session opened on — which is simply the cel as it
  /// stands, because the session never wrote to it.
  void handleLiftConfirmed(
    int liftToken,
    BrushDab stampDab,
    SelectionAffine? affine,
  ) {
    final coordinator = _state.widget._editableCoordinator;
    final session = _closeSession(liftToken);
    if (coordinator == null || session == null) {
      return;
    }
    // The setState rebuilds the interactive view onto the post-confirm
    // surface (R17-①b: without it the landed stamp stayed invisible until
    // an unrelated rebuild). Mounted guard: the layer's unmount path
    // confirms post-frame, possibly after this panel went with it.
    void run() {
      final historyManager = _state.widget.historyManager;
      final dabs = _landingDabs(session.eraseDab, stampDab);
      if (historyManager == null) {
        // Headless hosts (focused tests): land raw.
        coordinator.commitSourceStroke(
          sourceDabs: dabs,
          cacheInvalidationSink: _state.widget.cacheInvalidationSink,
        );
        return;
      }
      final doors = _selectionDoors();
      final landOn = BrushLiftMoveHistoryCommand(
        coordinator: coordinator,
        frameKey: session.key,
        // ⛔THE LIVE SURFACE IS THE PRE-LIFT PICTURE NOW. It used to be a
        // snapshot taken before the erase and held for the whole session,
        // outside every budget; there is nothing to take a snapshot of
        // ahead of time when the session writes nothing.
        preLiftSurface: coordinator.currentSurfaceOf(session.key),
        landingDabs: dabs,
        cacheInvalidationSink: _state.widget.cacheInvalidationSink,
        // 🚨THE SELECTION TRAVELS WITH THE PIXELS. 유저 2026-08-27: 「언두
        // 하면 그림만 돌리는게아니라 선택도 이전 선택으로 되돌리기」 — a
        // transform moves the outline as much as the drawing, and one
        // confirm has to come back as one undo.
        regionBefore: _state.widget.selectionCommands?.region,
        readRegion: doors.read,
        restoreRegion: doors.restore,
      );
      final landings = _landingsPerCel(session, stampDab, landOn, affine);
      historyManager.execute(
        landings.length == 1
            ? landOn
            : CompositeCommand(
                description: landOn.description,
                commands: landings.values.toList(),
              ),
      );
    }

    if (_state.mounted) {
      _state._rebuild(run);
    } else {
      run();
    }
  }

  /// The selection doors a confirmed move's undo entry keeps for its whole
  /// life: read the live selection, put one back.
  ///
  /// 🚨★★★MADE HERE, AWAY FROM THE LANDING — AND THAT IS THE FIX, NOT A
  /// TIDY-UP (C-ipad-crash ①, 2026-09-15). A Dart closure keeps the whole
  /// SCOPE it was made in, not just the names it reads. Written inline in
  /// [handleLiftConfirmed], these two kept that call's pre-lift picture and
  /// the landed stamp's RGBA alive for as long as the entry stayed in the
  /// history — through parking, outside every budget, while
  /// [BrushLiftMoveHistoryCommand] nulled its own copies and reported zero.
  /// 🔬A VM heap snapshot after ten ×2 → ×0.5 transforms of a 2000×1400
  /// picture: 526.9MB of stamps and 70MB of tiles held by nothing but this
  /// context — the user's 「반복시마다 약 150mb」.
  /// ⛔Nothing big may be in scope where a closure that outlives the call is
  /// made; a method whose only local is `this` cannot hold anything else.
  ({
    CanvasSelectionRegion? Function() read,
    void Function(CanvasSelectionRegion? region) restore,
  })
  _selectionDoors() => (
    read: () => _state.widget.selectionCommands?.region,
    restore: (region) => _state.widget.selectionCommands?.setRegion(region),
  );

  /// REVERT of a session (R17-①): the picture is already the pre-lift
  /// picture, so there is nothing to restore and nothing lands in history.
  ///
  /// ↩️This used to put a held snapshot back and could FAIL doing it — the
  /// payload might have been parked to a file that was gone, and then 「the
  /// picture stays erased and the floating pixels are gone」 (the wager
  /// 유저 accepted on 09-08). A revert cannot fail any more: dropping a
  /// view is not an operation that can refuse.
  void handleLiftReverted(int liftToken) {
    if (_closeSession(liftToken) == null) {
      return;
    }
    if (_state.mounted) {
      _state._rebuild(() {});
    }
  }

  /// Raw landing of the floating stamp (no history entry) — the abandon
  /// fallback so a reset never loses the float's pixels.
  void handleLiftLanded(int liftToken, BrushDab stampDab) {
    final coordinator = _state.widget._editableCoordinator;
    final session = _closeSession(liftToken);
    if (coordinator == null || session == null) {
      return;
    }
    void run() {
      coordinator.commitSourceStroke(
        sourceDabs: _landingDabs(session.eraseDab, stampDab),
        cacheInvalidationSink: _state.widget.cacheInvalidationSink,
      );
    }

    if (_state.mounted) {
      _state._rebuild(run);
    } else {
      run();
    }
  }
}

/// An open move session: which cel it belongs to, the erase that makes its
/// hole, and the holed picture itself — which is a DERIVATION and may be
/// given back under memory pressure.
///
/// ⛔A class rather than a record because [holed] is reclaimable: the store
/// hands the bytes back by nulling it, and the next paint rebuilds them.
/// Everything else about the session survives that.
class _MoveSession {
  _MoveSession({
    required this.token,
    required this.key,
    required this.region,
    required this.userSelection,
    required this.eraseDab,
    required this.holed,
  });

  final int token;
  final BrushFrameKey key;

  /// The region THIS cel was cut from — the user's selection, or the move
  /// tool's box around this cel's own ink.
  final CanvasSelectionRegion region;

  /// The selection the USER made when this session was cut, or null when
  /// [region] is the move tool's own whole-picture box.
  ///
  /// 🚨★★★**IT IS WHAT THE OTHER CELS ARE CUT FROM TOO** (F-116-b / F-164)
  /// — and ONLY it (H41, 유저 2026-09-24: 「선택도구 사용했으면 어떤프레임이든
  /// 선택도구 안쪽만, 아니면 각자 그림 전체적용」). A confirm over a frame
  /// range moves every cel in it, and each lifts its OWN pixels: through
  /// this outline when there is one, through its own whole picture when
  /// there is not. ↩️Until 09-24 the other cels were cut through [region]
  /// either way, so with nothing selected they were cut by the STANDING
  /// cel's ink box and their drawing past it stayed behind.
  ///
  /// ⛔**THE SESSION'S OWN RECORD, NOT THE LIVE CHANNEL** — even though the
  /// two carry the same shape at confirm time today. 🧪Measured 2026-09-18:
  /// reading `selectionCommands.region` instead changes nothing, because
  /// the live region is still the pre-transform one when the confirm runs
  /// — which is exactly what `regionBefore` depends on to put the outline
  /// back on undo. That equality is a fact about the current confirm
  /// ORDER, not about what this field means: what the other cels must be
  /// cut through is where this session started, and only the session can
  /// answer that without the order having to stay put.
  final CanvasSelectionRegion? userSelection;
  final BrushDab eraseDab;

  /// Null after a memory warning took it — never a lost edit, only a lost
  /// computation.
  BitmapSurface? holed;
}
