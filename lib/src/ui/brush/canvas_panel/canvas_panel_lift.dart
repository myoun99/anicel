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

  /// What [key]'s cel is drawn as while a move is pending — null when
  /// nothing is pending, or when the session holds no such cel (the hole
  /// belongs to the cel it was cut from, and only that one: F-86 keeps the
  /// REGION across a frame move, not the pixels).
  ///
  /// 🚨★★★**IT REBUILDS WHAT A MEMORY WARNING TOOK.** The holed picture is
  /// a derivation, and the store's discipline gives derivations back by
  /// dropping them ([BrushFrameStore.holdReclaimableView]) rather than by
  /// parking them to disk — a parked surface is one the next paint cannot
  /// draw, which is the blank frame 유저 forbade outright. So a null here
  /// after a warning means one recompute, not a lost edit.
  BitmapSurface? holedSurfaceFor(BrushFrameKey key) {
    final cel = _session?.celOf(key);
    if (cel == null) {
      return null;
    }
    return cel.holed ??= _state.widget.coordinator?.deriveSurfaceWith([
      cel.eraseDab,
    ], key: cel.key);
  }

  /// The cels a lift holds for the composite — a folder's rows (I-37), a
  /// frame range's across rows (F-329): each one this canvas does not draw
  /// itself, as its holed surface with its float over it ([LiftedCel]).
  /// Empty for a cel's own lift — the canvas draws that one, as the live
  /// row.
  Map<BrushFrameKey, LiftedCel> get liftedRows {
    final session = _session;
    if (session == null) {
      return const {};
    }
    return {
      for (final cel in session.cels)
        if (cel.ownSlot case final slot?)
          if (holedSurfaceFor(cel.key) case final holed?)
            cel.key: (surface: holed, float: slot),
    };
  }

  void openSession({
    required int token,
    required CanvasSelectionRegion? userSelection,
    required List<_LiftedCel> cels,
  }) {
    final session = _MoveSession(
      token: token,
      userSelection: userSelection,
      cels: cels,
    );
    _session = session;
    final coordinator = _state.widget.coordinator;
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
      bytes: () => session.cels.fold(
        0,
        (bytes, cel) =>
            bytes +
            (cel.holed?.bytesNotSharedWith(
                  coordinator.currentSurfaceOf(cel.key),
                ) ??
                0),
      ),
      reclaim: () {
        for (final cel in session.cels) {
          cel.holed = null;
        }
      },
    );
  }

  /// Takes the session back, or null when [liftToken] is not the open one.
  ///
  /// ⚠️A cel's own slot ([_LiftedCel.ownSlot]) is NOT disposed here: the
  /// layer takes its float back from it at its own next build, which may
  /// come after this. It goes with the session, and the composite stops
  /// listening to it the build its row leaves [liftedRows].
  _MoveSession? _closeSession(int liftToken) {
    final session = _session;
    if (session == null || session.token != liftToken) {
      return null;
    }
    _session = null;
    _state.widget.coordinator?.frameStore.releaseReclaimableView(liftToken);
    for (final cel in session.cels) {
      cel.letTheLandingGo();
    }
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

  /// The landing of [cel]: its erase, then the float it ends with back in
  /// the artwork of the row it was lifted from — the one crossing a landing
  /// makes, through the same placement the lift crossed out through
  /// (a-marquee-on-a-posed-row).
  List<BrushDab> _landingOf(_LiftedCel cel, BrushDab stampDab) =>
      _landingDabs(cel.eraseDab, stampInArtwork(stampDab, cel.placement));

  /// What [key]'s cel will SHOW where [stampDab] — on the canvas — lands,
  /// through its row's leading [keys] ([FloatLandsOn.landingShown]): made
  /// once for each place a hand carries the float to, as the text in hand's
  /// landing is (`_CanvasPanelText._landingOf`, F-344-Q3), and let go of
  /// once another takes its place or the session ends.
  LandingPreview? landingShownOn(
    BrushFrameKey key,
    BrushDab stampDab,
    List<ResolvedLayerEffect> keys,
  ) {
    final cel = _session?.celOf(key);
    if (cel == null) {
      return null;
    }
    final signature = celSourceEffectSignature(keys);
    final plugin = celSourcePlugin(keys);
    final kept = cel.landing;
    if (kept != null &&
        identical(kept.stamp.stamp, stampDab.stamp) &&
        kept.stamp.center == stampDab.center &&
        listEquals(kept.keys, signature) &&
        kept.plugin == plugin) {
      return kept.shown;
    }
    cel.letTheLandingGo();
    final landed = _landedOn(cel, stampDab);
    final shown = landed == null
        ? null
        : _landingPicture(key, landed, keys, plugin: plugin);
    cel.landing = (
      stamp: stampDab,
      keys: signature,
      plugin: plugin,
      shown: shown,
    );
    return shown;
  }

  /// The picture of [landed] — [key]'s cel as a confirm leaves it — as its
  /// row shows it ([celSurfaceAsShown]): over the region it lands in, or,
  /// where the row's chain runs a [plugin], over the whole cel
  /// ([celLandingShownWhole], 🗣️I-132-Q32 b) — null where nothing shows.
  CelTextLanding? _landingPicture(
    BrushFrameKey key,
    ({BitmapSurface surface, DirtyRegion region}) landed,
    List<ResolvedLayerEffect> keys, {
    required ResolvedLayerEffect? plugin,
  }) {
    final holed = holedSurfaceFor(key);
    if (plugin == null || holed == null) {
      return CelTextLanding.of(
        landed.region,
        bitmapSurfaceRegionPixels(
          celSurfaceAsShown(landed.surface, keys),
          landed.region,
        ),
      );
    }
    final whole = celLandingShownWhole(
      under: holed,
      landed: landed.surface,
      effects: keys,
    );
    return whole == null
        ? null
        : CelTextLanding.of(whole.region, whole.straight);
  }

  /// [cel] as it will stand once [stampDab] — on the canvas — lands on it,
  /// and the region of the cel's grid it lands in: what its confirm lands
  /// ([_landingOf]). Null when the stamp lands past the pasteboard, or the
  /// hole cannot be cut.
  ///
  /// ⛔THE CONFIRM'S OWN LANDING, made on the hole the session already holds
  /// rather than cutting it again at every move of the hand: the erase is
  /// what [holedSurfaceFor] is, and a stamp is blended on what the dabs
  /// before it left (`materializeBrushDabSequenceOnBitmapSurface`, which
  /// the commit runs both through).
  ({BitmapSurface surface, DirtyRegion region})? _landedOn(
    _LiftedCel cel,
    BrushDab stampDab,
  ) {
    final holed = holedSurfaceFor(cel.key);
    if (holed == null) {
      return null;
    }
    final stamp = _landingOf(cel, stampDab).last;
    final region = stamp.stamp
        ?.landingRect(stamp.center)
        .intersection(holed.pasteboard.region);
    if (region == null) {
      return null;
    }
    return (
      surface: materializeBrushDabSequenceOnBitmapSurface(
        surface: holed,
        sequence: BrushDabSequence([stamp]),
      ).surface,
      region: region,
    );
  }

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
  /// 🚨★★★**ONE LANDING PER CEL, AND THE MAP IS WHAT SAYS SO.** [landed] —
  /// the session's own cels', each carrying the float its preview already
  /// resampled — SEEDS the result under their own keys, so the loop cannot
  /// add a second landing for one of them however the ladder is spelled.
  /// ⛔It is not a `key == session.key` skip: the ladder may also name one
  /// cel twice (two frame keys can fold onto one physical cel), and a skip
  /// that names only the session would let that through.
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
    Map<BrushFrameKey, Command> landed,
    StampCarry? carry,
  ) {
    final ladder = _state.widget.transformTargetKeys?.call();
    final coordinator = _state.widget.coordinator;
    if (ladder == null || coordinator == null) {
      return landed;
    }
    // 🚨★★★**KEYED BY THE PHYSICAL CEL.** `pixelVerbCellKeys` deliberately
    // does NOT dedupe — 「the one that owns the surfaces owns this」 — and
    // linked rows are windows onto one bank, so the ladder can name one
    // cel under two row keys. `CelPixelOverwriteCommand` answers that with
    // `canonicalKeyOf`; this is the same answer, not a second one — and
    // [landed] is keyed by it already.
    final store = coordinator.frameStore;
    final landings = {...landed};
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
    //
    // ↩️And the affine was not all of it either. Under 퍼스 and 메쉬 it is
    // the identity while the box's corners or grid carry the warp, so a
    // warp confirmed over a range bent the cel you stood on and left the
    // others untouched (measured 2026-10-06). What comes down here now is
    // the box's mapping of the canvas, whichever of the three it was
    // ([StampCarry]) — the one the float itself went through.
    // 🚨A POSED ROW'S CELS CROSS THE WAY THE STANDING ONE DID
    // (a-marquee-on-a-posed-row): the user's outline is taken back into the
    // cel's artwork, and the cel's own stamp goes out onto the canvas, takes
    // the box's transform there and comes back ([stampOnCanvas] ·
    // [stampInArtwork]) — each through its OWN row's placement
    // ([BrushCanvasPanel.cellPlacementOf]), since a range can name several
    // rows placed differently. A cel's own whole picture is already its
    // artwork.
    // A host that names no placements has one row: the one it stands on.
    final placementOf =
        _state.widget.cellPlacementOf ?? (_) => session.cels.first.placement;
    final userSelection = session.userSelection;
    for (final key in ladder) {
      final cel = store.canonicalKeyOf(key);
      if (landings.containsKey(cel)) {
        continue;
      }
      final placement = placementOf(key);
      // A row that shows this cel as NOTHING — scaled to zero on an axis,
      // the frame a flip passes through — has put nothing of it on the
      // canvas for the box to have moved (「불가능하면 그냥 무시」).
      // ↩️Only a cel read through the user's selection was turned away
      // here, by the region coming back null; a cel taken whole went on,
      // and was moved as if its row lay unplaced.
      if (placement != null && canvasToArtwork(placement) == null) {
        continue;
      }
      final userSelectionInArtwork = userSelection == null
          ? null
          : regionInArtworkSpace(
              region: userSelection,
              placement: placement,
            );
      final surface = coordinator.currentSurfaceOf(key);
      final lift = buildSelectionLiftDabs(
        region:
            userSelectionInArtwork ??
            CanvasSelectionRegion.shape(
              CanvasSelectionShape.wholePicture(
                surface.pasteboard,
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
          // ⚠️The SAME mapping the standing cel's float went through, on
          // this cel's own pixels — affine, quad or mesh, whichever the box
          // was doing ([StampCarry]). A pure translation still costs
          // nothing: the carry moves the centre.
          carry == null
              ? lift.stampDab
              : stampInArtwork(
                  carry.through(stampOnCanvas(lift.stampDab, placement)),
                  placement,
                ),
        ),
        cacheInvalidationSink: _state.widget.cacheInvalidationSink,
      );
    }
    return landings;
  }

  /// R16-① confirm: lands the move as ONE undo entry whose undo target is
  /// the picture the session opened on — which is simply each cel as it
  /// stands, because the session never wrote to any of them.
  ///
  /// [stampDabs] is one per float the lift gave the layer, in the order of
  /// [_MoveSession.cels].
  void handleLiftConfirmed(
    int liftToken,
    List<BrushDab> stampDabs,
    StampCarry? carry,
  ) {
    final coordinator = _state.widget.coordinator;
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
      final doors = _selectionDoors();
      final landed = <BrushFrameKey, Command>{};
      for (final (i, cel) in session.cels.indexed) {
        landed.putIfAbsent(
          coordinator.frameStore.canonicalKeyOf(cel.key),
          () => BrushLiftMoveHistoryCommand(
            coordinator: coordinator,
            frameKey: cel.key,
            // ⛔THE LIVE SURFACE IS THE PRE-LIFT PICTURE NOW. It used to be a
            // snapshot taken before the erase and held for the whole
            // session, outside every budget; there is nothing to take a
            // snapshot of ahead of time when the session writes nothing.
            preLiftSurface: coordinator.currentSurfaceOf(cel.key),
            landingDabs: _landingOf(cel, stampDabs[i]),
            cacheInvalidationSink: _state.widget.cacheInvalidationSink,
            // 🚨THE SELECTION TRAVELS WITH THE PIXELS. 유저 2026-08-27:
            // 「언두 하면 그림만 돌리는게아니라 선택도 이전 선택으로
            // 되돌리기」 — a transform moves the outline as much as the
            // drawing, and one confirm has to come back as one undo. It
            // rides the FIRST cel's landing, once: one outline, one step.
            //
            // 🚨★★★**THE SELECTION THE SESSION OPENED WITH, NOT THE ONE
            // STANDING NOW** (F-231 ②, 유저 2026-09-29: 「언두하면 선택도구
            // 개미행렬 라인이 과거로 안돌아가고 그것만 남아있는데」). This
            // read the channel here, at the confirm — after the box had
            // already moved the region onto the landed pixels — so the undo
            // "restored" the moved outline and only the pixels went back.
            regionBefore: i == 0 ? session.userSelection : null,
            readRegion: i == 0 ? doors.read : null,
            restoreRegion: i == 0 ? doors.restore : null,
          ),
        );
      }
      if (historyManager == null) {
        // Headless hosts (focused tests): every cel lands, none recorded.
        for (final landing in landed.values) {
          landing.execute();
        }
        return;
      }
      historyManager.executeAsOneStep(
        landed.values.first.description,
        _landingsPerCel(session, landed, carry).values.toList(),
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

}

/// An open move session: the cels it holds lifted, and the selection it was
/// cut through.
class _MoveSession {
  _MoveSession({
    required this.token,
    required this.userSelection,
    required this.cels,
  });

  final int token;

  /// Every cel the lift took pixels up from, in the order the layer floats
  /// them: the one this canvas edits — or, stood on a FOLDER, the cel of
  /// each drawing row inside it (I-37). Never empty.
  final List<_LiftedCel> cels;

  /// The cel [key] names, if this session holds it.
  _LiftedCel? celOf(BrushFrameKey key) {
    for (final cel in cels) {
      if (cel.key == key) {
        return cel;
      }
    }
    return null;
  }

  /// The selection the USER made when this session was cut, or null when
  /// the session was cut by the move tool's own whole-picture box.
  ///
  /// 🚨★★★**IT IS WHAT THE OTHER CELS ARE CUT FROM TOO** (F-116-b / F-164)
  /// — and ONLY it (H41, 유저 2026-09-24: 「선택도구 사용했으면 어떤프레임이든
  /// 선택도구 안쪽만, 아니면 각자 그림 전체적용」). A confirm over a frame
  /// range moves every cel in it, and each lifts its OWN pixels: through
  /// this outline when there is one, through its own whole picture when
  /// there is not. ↩️Until 09-24 the other cels were cut through the
  /// region the session was cut through either way, so with nothing
  /// selected they were cut by the STANDING cel's ink box and their drawing
  /// past it stayed behind.
  ///
  /// ⛔**THE SESSION'S OWN RECORD, NOT THE LIVE CHANNEL.** What the other
  /// cels must be cut through, and what an undo puts the outline back to
  /// (`regionBefore`), is where this session STARTED — and only the
  /// session can answer that without the confirm's order having to stay
  /// put. ↩️On 2026-09-18 the two were measured equal at confirm time, and
  /// this note warned that the equality was a fact about the order, not
  /// about the field. The order changed (the box now moves the region onto
  /// the landed pixels before the confirm), the live read went on standing
  /// in for this one in `regionBefore`, and undo stopped bringing the ants
  /// back — F-231 ②.
  final CanvasSelectionRegion? userSelection;
}

/// One cel an open move session holds lifted: which cel, the erase that
/// makes its hole, where its row stands, where its float shows, and the
/// holed picture itself — which is a DERIVATION and may be given back
/// under memory pressure.
///
/// ⛔A class rather than a record because [holed] is reclaimable: the store
/// hands the bytes back by nulling it, and the next paint rebuilds them.
/// Everything else about the cel survives that.
class _LiftedCel {
  _LiftedCel({
    required this.key,
    required this.eraseDab,
    required this.placement,
    required this.ownSlot,
    required this.holed,
  });

  final BrushFrameKey key;
  final BrushDab eraseDab;

  /// Where the cel's row stood on the canvas when it was cut — its
  /// placement, or null for an unplaced row. The stamp floats on the canvas
  /// and lands back through THIS ([stampInArtwork]), the one it was lifted
  /// through, so the two crossings cannot disagree (a-marquee-on-a-posed-
  /// row).
  final LayerPlacement? placement;

  /// The composite slot its float shows in when this canvas does not draw
  /// the cel itself — a folder's rows, a range's (I-37 · F-329,
  /// [_CanvasPanelLift.liftedRows]). Null for the cel the canvas edits: its
  /// float shows in the live row's.
  final SelectionFloatOverlay? ownSlot;

  /// Null after a memory warning took it — never a lost edit, only a lost
  /// computation.
  BitmapSurface? holed;

  /// What the cel will show where its float was last asked to land
  /// ([_CanvasPanelLift.landingShownOn]): the stamp it was made for, the
  /// keys it was made through, and the landing — null where it lands
  /// nowhere.
  ({
    BrushDab stamp,
    List<double> keys,
    ResolvedLayerEffect? plugin,
    CelTextLanding? shown,
  })?
  landing;

  /// The landing last made is shown no more.
  void letTheLandingGo() {
    landing?.shown?.letGo();
    landing = null;
  }
}

/// A lifted cel as the float taken up from it asks after it
/// ([FloatLandsOn]) — through the session, so a cel the session holds no
/// more answers nothing, and a hole a memory warning took is cut again.
class _CelUnderFloat implements FloatLandsOn {
  _CelUnderFloat(this._lift, this._key);

  final _CanvasPanelLift _lift;
  final BrushFrameKey _key;

  @override
  BitmapSurface? get holed => _lift.holedSurfaceFor(_key);

  @override
  bool get onCanvasGrid => _lift._session?.celOf(_key)?.placement == null;

  @override
  LandingPreview? landingShown(
    BrushDab stamp,
    List<ResolvedLayerEffect> keys,
  ) => _lift.landingShownOn(_key, stamp, keys);
}
