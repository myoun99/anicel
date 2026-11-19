part of '../brush_canvas_panel.dart';

/// The SELECTION SEAT — what the panel does with the selection layer:
/// recording its changes into history, answering the idle region, a
/// lift, and clipping a stroke to it — as its own object.
///
/// 🚨A collaborator carved out of `_BrushCanvasPanelState` (the audit's SRP
/// cut, 2026-09-02). Measured before cutting: three State members shared.
/// It reaches the State through `_state`.
class _CanvasPanelSelection {
  _CanvasPanelSelection(this._state);

  final _BrushCanvasPanelState _state;

  /// One undoable selection step (R11-⑧) — the layer's marquee commits and
  /// the channel's layer-less Ctrl+D both land here, so a selection change
  /// is recorded the same way whatever tool is armed. Null while this
  /// panel has no history host (focused tests apply directly).
  void Function(CanvasSelectionRegion? before, CanvasSelectionRegion? after)?
  get recordSelectionChange {
    final history = _state.widget.historyManager;
    final commands = _state.widget.selectionCommands;
    if (history == null || commands == null) {
      return null;
    }
    return (before, after) => history.execute(
      SelectionShapeHistoryCommand(
        channel: commands,
        before: before,
        after: after,
      ),
    );
  }

  /// The recorder [bindSelectionHistoryRecorder] last put on the channel.
  void Function(CanvasSelectionRegion? before, CanvasSelectionRegion? after)?
  _installedRecorder;

  void bindSelectionHistoryRecorder() {
    _installedRecorder = recordSelectionChange;
    _state.widget.selectionCommands?.regionHistoryRecorder =
        _installedRecorder;
  }

  /// Takes off the recorder THIS panel installed, and only that one.
  ///
  /// 🚨The canvas built for a tab coming on screen installs its own BEFORE
  /// the one it replaces is disposed (I-7: the canvas is rebuilt per
  /// project, and a new element mounts in the build that retires the old),
  /// so an unconditional null here left the new project's marquee with no
  /// history. The paste and re-input handlers already guard the same way.
  void unbindSelectionHistoryRecorder() {
    final commands = _state.widget.selectionCommands;
    if (commands != null &&
        identical(commands.regionHistoryRecorder, _installedRecorder)) {
      commands.regionHistoryRecorder = null;
    }
    _installedRecorder = null;
  }

  void handleSelectionChannelChanged() {
    if (!_state.mounted) {
      return;
    }
    // The channel pings on EVERY selection mutation, including each step
    // of a marquee/move drag. Those all happen with a selection tool
    // armed, where the mounted layer draws and this panel has nothing to
    // redraw — so the guard keeps the notify structure (R27 #7/#20) out
    // of the drag loop and only rebuilds when the ants this panel owns
    // actually change.
    final next = idleSelectionRegion;
    if (next == _state._paintedIdleRegion) {
      return;
    }
    _state._rebuild(_state._syncIdleAnts);
  }

  /// Whether the selection layer is mounted: a selecting tool, over content
  /// that takes tool input ([BrushCanvasPanel.toolInputEnabled]). The deck
  /// mounts the layer on it and the idle ants paint on its negation, so a
  /// selection stays drawn by one or the other while playback plays.
  bool get selectionLayerMounted =>
      _state.widget.toolInputEnabled &&
      canvasToolSelects(_state._brush.tool);

  /// The region to paint when no selection layer is mounted (null while
  /// one is — it draws its own, session state included).
  CanvasSelectionRegion? get idleSelectionRegion {
    if (selectionLayerMounted) {
      return null;
    }
    return _state.widget.selectionCommands?.region;
  }

  int _liftTokenSeq = 0;

  /// [region] — drawn on the CANVAS — stated in the active row's own
  /// artwork: the pixels a canvas outline means on a posed row, through the
  /// placement the row is shown with. The pixel verbs' own restatement
  /// ([regionInArtworkSpace]); an unplaced row gets [region] back as it is.
  ///
  /// 🚨★★★**EVERY OUTLINE THAT REACHES THE ROW'S PIXELS CROSSES HERE**
  /// (a-marquee-on-a-posed-row, 2026-09-25) — the lift, the cut, the shape
  /// fill and the clip a stroke lands through. Each took the canvas outline
  /// as the row's own coordinates, so on a row placed 100 to the right they
  /// all acted 100 to the left of what the user drew around.
  ///
  /// Null when the placement has collapsed the row — it shows nothing, so
  /// there is nothing under the outline to act on.
  CanvasSelectionRegion? regionOnTheRow(CanvasSelectionRegion region) {
    final placement = _state.widget.interactiveContentPose;
    return regionInArtworkSpace(region: region, placement: placement);
  }

  /// What is drawn on the active row is cut by, as of now — [clipOf] the
  /// live selection, null with nothing selected.
  SelectionClip? clipNow() => switch (_state.widget.selectionCommands?.region) {
    null => null,
    final selection => clipOf(selection),
  };

  /// [selection] as what is drawn on the active row is cut by it: on the
  /// row's own artwork ([regionOnTheRow]), at the softness the tool settings
  /// give it. Null where [regionOnTheRow] is.
  SelectionClip? clipOf(CanvasSelectionRegion selection) {
    final onTheRow = regionOnTheRow(selection);
    return onTheRow == null
        ? null
        : SelectionClip.of(
            onTheRow,
            // Every surface the coordinator writes stops at this wall.
            wall: _state.widget.coordinator!.sessionStore.pasteboard,
            options:
                _state.widget.selectionMaskOptions?.value ??
                SelectionMaskOptions.none,
          );
  }

  /// A canvas point on the active row's artwork — where a press on the
  /// canvas lands on a posed row (a stamp's), the same inverse the eyedropper
  /// and the guides ask ([canvasToArtwork]).
  CanvasPoint? pointOnTheRow(CanvasPoint point) =>
      pointOnARow(point, _state.widget.interactiveContentPose);

  /// [pointOnTheRow] for a row standing at [placement] — any row a range
  /// names, each of which shows the press somewhere of its own (F-293).
  CanvasPoint? pointOnARow(CanvasPoint point, LayerPlacement? placement) {
    if (placement == null) {
      return point;
    }
    return canvasToArtwork(placement)?.apply(point);
  }

  /// [pointOnTheRow] run backwards: a point of the active row's artwork,
  /// where the canvas shows it.
  CanvasPoint pointOnTheCanvas(CanvasPoint onTheRow) =>
      _state.widget.interactiveContentPose?.apply(onTheRow) ?? onTheRow;

  /// Lifts [region]'s pixels out of the cel (R19 pixel model): the stamp
  /// comes back to float and the cel it came from shows the hole — **while
  /// the document keeps every byte it had**.
  ///
  /// 🚨★★★**THE ERASE IS NOT COMMITTED ANY MORE** (유저 2026-09-17, which
  /// REVERSED the 09-08 answer to `undo-41-hole-scope`: 「원본은 남기되,
  /// 일시적으로 구멍 픽셀 잘라내고 플로트 띄운단거지? … 그 방식대로
  /// 구조/근본적으로 작업 가자」). It used to land in the cel the moment the
  /// pixels were lifted, and everything that made that survivable — the
  /// pre-lift snapshot, the lift anchors, the store's budget exception, the
  /// revert path, a history command of its own — existed to take it back.
  /// ⇒ The session shows [BrushFrameEditingCoordinator.deriveSurfaceWith]'s
  /// answer instead: the same pixels the erase would have written, held by
  /// the session and dropped with it.
  ///
  /// 🎯**And that is what let the timeline move again.** A committed erase
  /// means leaving the frame leaves a HOLE behind, which is why a seek, a
  /// row press and a cut switch were all refused while a box was open
  /// (F-116·F-86, 유저: 「타임라인쪽 조작이 안먹힘」). With nothing written
  /// there is nothing to leave behind, so there is nothing to refuse.
  ///
  /// ⚠️The 09-08 card blocked this on a PLATFORM fact — an image hole needs
  /// a synchronous upload, which was Impeller-only while Windows was Skia.
  /// That expired on 09-16 (every platform is Impeller now), and this route
  /// needs no upload at all: the hole is a surface, not a paint-time punch,
  /// so there is no `saveLayer` and no `dstOut` over the layers below.
  ///
  /// Every cel underfoot is lifted the same way ([_BrushCanvasPanelState.
  /// _celsUnderfoot]) — the one this canvas edits, each drawing row's inside
  /// a folder (I-37), each row's across a frame range at the playhead
  /// (F-329): through the outline the box was opened on,
  /// restated on that cel's own row. ⛔ONE CODE: a cel's lift is a folder's
  /// with one cel, and it lifts exactly what it always lifted.
  ///
  /// Null when the shape covers no pixels of any of them.
  ///
  /// 🪦Two things stood at the end of this until 2026-09-11, both about the
  /// frame the lift opens on (F-68 ②, 「그림의 일부가 1프레임 이상한곳에
  /// 생겼다가 사라짐 … 매번 다른데」): the cel's stale-fallback bucket forgot
  /// the coordinates the lift took whole, and the erased tiles were seeded
  /// with the pre-lift picture cut by the erase's own bytes. From then until
  /// 2026-09-17 the commit funnel announced both surfaces of every edit and
  /// the painter composed each new tile from its predecessor plus the diff
  /// (M5: with that on and both of these off, every lift pin stayed green)
  /// — and the answer carried the pre-lift surface so the float's tiles had
  /// predecessors too. A tile pictures itself inside the paint now, the
  /// erased ones and the float's alike, so nothing is announced, composed
  /// or carried.
  ({int liftToken, List<LiftedFloat> floats})? handleSelectionLift(
    CanvasSelectionRegion region,
  ) {
    final coordinator = _state.widget.coordinator;
    if (coordinator == null) {
      return null;
    }
    final liftId = '${DateTime.now().microsecondsSinceEpoch}';
    final cels = <_LiftedCel>[];
    final floats = <LiftedFloat>[];
    for (final under in _state._celsUnderfoot()) {
      final cut = _cutAtThePress(
        coordinator,
        under,
        region,
        '$liftId-${cels.length}',
      );
      if (cut == null) {
        // 「불가능하면 그냥 무시」 — nothing of this cel under the outline.
        continue;
      }
      final (:lift, :holed) = cut;
      // The cel this canvas edits floats in the live row's slot; a cel it
      // does not edit, in a slot of its own the composite draws in its row.
      final ownSlot = under.live ? null : SelectionFloatOverlay(null);
      cels.add(
        _LiftedCel(
          key: under.key,
          eraseDab: lift.eraseDab,
          placement: under.placement,
          ownSlot: ownSlot,
          holed: holed,
        ),
      );
      final showsOn = ownSlot ?? _state._activeRowFloatSlot;
      floats.add((
        stampDab: stampOnCanvas(lift.stampDab, under.placement),
        showsOn: showsOn,
        // Landed in a row only where a row shows it.
        landsOn: showsOn == null
            ? null
            : _CelUnderFloat(_state._lift, under.key),
      ));
    }
    if (cels.isEmpty) {
      return null;
    }
    final token = ++_liftTokenSeq;
    _state._lift.openSession(
      token: token,
      // What the USER selected (F-108's [CanvasSelectionCommands.region]) —
      // null when this box is the move tool's own whole-picture target.
      userSelection: _state.widget.selectionCommands?.region,
      cels: cels,
    );
    _state._rebuild(() {});
    return (liftToken: token, floats: floats);
  }

  /// The mask a lift cuts with now.
  SelectionMaskOptions get _maskOptions =>
      _state.widget.selectionMaskOptions?.value ?? SelectionMaskOptions.none;

  /// [under]'s pixels on [surface] cut through [region] — the lift's dabs
  /// and the picture with its hole — or null with nothing of it under the
  /// outline. ⛔ONE CUT for the press and for the box at rest
  /// ([boxAtRest]): what is cut ahead is what the press would cut.
  _Cut? _cut(
    BrushFrameEditingCoordinator coordinator,
    _Underfoot under,
    CanvasSelectionRegion region,
    BitmapSurface surface,
    SelectionMaskOptions options,
    String liftId,
  ) {
    // 🚨THE SHAPE IS THE CANVAS'S, THE PIXELS ARE THE ROW'S OWN
    // (a-marquee-on-a-posed-row): the marquee is taken back to the
    // artwork it shows ([regionInArtworkSpace]), and the lifted stamp
    // comes out on the canvas, where the box that moves it lives
    // ([stampOnCanvas]). A row that shows nothing has nothing under it.
    final inArtwork = regionInArtworkSpace(
      region: region,
      placement: under.placement,
    );
    if (inArtwork == null) {
      return null;
    }
    final lift = buildSelectionLiftDabs(
      region: inArtwork,
      surface: surface,
      liftId: liftId,
      options: options,
    );
    // ⛔THE SAME DABS THE CONFIRM WILL LAND, through the same materialize:
    // the hole the user sees and the erase the commit writes cannot drift
    // apart at the mask's edge, because they are one computation.
    final holed = lift == null
        ? null
        : coordinator.deriveSurfaceWith([lift.eraseDab], key: under.key);
    return lift == null || holed == null ? null : (lift: lift, holed: holed);
  }

  /// [under] cut through [region] as the press lifts it: what the box at
  /// rest cut ahead, where it was cut through that region, where the row
  /// stands, with that mask, from the picture the cel holds now — else cut
  /// here (F-615's rule: work done ahead lands only on the picture it was
  /// done from).
  _Cut? _cutAtThePress(
    BrushFrameEditingCoordinator coordinator,
    _Underfoot under,
    CanvasSelectionRegion region,
    String liftId,
  ) {
    final options = _maskOptions;
    final surface = coordinator.currentSurfaceOf(under.key);
    final ahead = _ahead.cuts[under.key];
    if (ahead != null &&
        ahead.region == region &&
        ahead.placement == under.placement &&
        identical(ahead.options, options) &&
        identical(ahead.from, surface)) {
      return ahead.cut;
    }
    return _cut(coordinator, under, region, surface, options, liftId);
  }

  /// 🗣️opening-a-transform-box-holds-the-ui-over-half-a-second-Q1 (유저
  /// 2026-11-19, 「상자가 뜰 때 미리 들기」): the cels a box at rest frames
  /// through [region] are cut AHEAD, one at a time — each thawed on a
  /// worker and cut in a turn of its own — from the moment the box is up,
  /// so the press that opens it lifts what is cut already
  /// ([_cutAtThePress]) and cuts only a cel that changed since. Null: no
  /// box at rest.
  ///
  /// ↩️The press cut them all at once on the UI thread: 359–422 ms over six
  /// cels of S5_BA cut 352 (메인 PC · 테스트 VM, 11-19) — the transform box
  /// standing still under the hand that grabbed it.
  ///
  /// Told at every build of the layer; the cuts begin again only when the
  /// region or the cels under it changed — and a frame after, so a box
  /// told again at the next frame (the playhead dragged with the box up)
  /// leaves this run before it has cut anything.
  void boxAtRest(CanvasSelectionRegion? region) {
    final over = region == null
        ? const <_Underfoot>[]
        : _state._celsUnderfoot();
    final keys = [for (final under in over) under.key];
    if (region == _ahead.region && listEquals(keys, _ahead.over)) {
      return;
    }
    _ahead.letGo();
    if (region == null) {
      return;
    }
    _ahead
      ..region = region
      ..over = keys;
    unawaited(_cutAheadOf(_ahead.run, region, over));
  }

  Future<void> _cutAheadOf(
    int run,
    CanvasSelectionRegion region,
    List<_Underfoot> over,
  ) async {
    final coordinator = _state.widget.coordinator;
    if (coordinator == null) {
      return;
    }
    // The frame after the one that told it — asked for, since a box at rest
    // on a still screen asks for none, and the run would wait for the next
    // thing to move.
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    if (run != _ahead.run) {
      return;
    }
    final liftId = 'ahead-${DateTime.now().microsecondsSinceEpoch}';
    final canvasSize = coordinator.sessionStore.canvasSize;
    for (final (index, under) in over.indexed) {
      await coordinator.frameStore.thawAhead(
        under.key,
        canvasSize: canvasSize,
      );
      // Let go of while the worker thawed: a run gone takes no turn, so the
      // one it gave way to keeps its own to withdraw. Past the turn nothing
      // is checked — letting go withdraws it, the layer going included (it
      // tells no box at rest as it is disposed).
      if (run != _ahead.run) {
        return;
      }
      await _ahead.aTurn();
      final options = _maskOptions;
      final surface = coordinator.currentSurfaceOf(under.key);
      _ahead.cuts[under.key] = (
        region: region,
        placement: under.placement,
        options: options,
        from: surface,
        cut: _cut(
          coordinator,
          under,
          region,
          surface,
          options,
          '$liftId-$index',
        ),
      );
      _ahead.declareTo(coordinator);
    }
  }

  final _CutsAhead _ahead = _CutsAhead();

  /// R26 #18 ("선택하고 그리면 선택 내부만 그려진다"): a stroke that lands
  /// with a live selection is CLIPPED to it before it reaches the commit —
  /// on [surface], the cel it lands on ([clipStrokeCommitToSelection], the
  /// one funnel a sheet window's stroke takes too). Null
  /// return = the whole stroke fell outside the selection and there is
  /// nothing to commit.
  BrushStrokeCommitData? clipStrokeToSelection(
    BrushStrokeCommitData data, {
    required BitmapSurface surface,
  }) {
    final selection = _state.widget.selectionCommands?.region;
    if (selection == null) {
      return data;
    }
    // The stroke is the row's own artwork (the draw-through wrap); the
    // selection is the canvas's — on a posed row they meet only once the
    // selection is taken back to the artwork it shows.
    final clip = clipOf(selection);
    if (clip == null) {
      return null;
    }
    return clipStrokeCommitToSelection(data, clip: clip, surface: surface);
  }
}

/// A cel under the hand as a lift reads it
/// ([_BrushCanvasPanelState._celsUnderfoot]).
typedef _Underfoot = ({
  BrushFrameKey key,
  LayerPlacement? placement,
  bool live,
});

/// A cel's pixels cut through an outline: the lift's dabs, and the picture
/// with its hole ([_CanvasPanelSelection._cut]).
typedef _Cut = ({SelectionLiftDabs lift, BitmapSurface holed});

/// A cel cut ahead of the press ([_CanvasPanelSelection.boxAtRest]):
/// through [region], where its row stood ([placement]), with [options], on
/// [from] — the only picture it may be lifted from. [cut] null: nothing of
/// it under the outline.
typedef _CutAhead = ({
  CanvasSelectionRegion region,
  LayerPlacement? placement,
  SelectionMaskOptions options,
  BitmapSurface from,
  _Cut? cut,
});

/// What a box at rest has cut ahead of the press that opens it
/// ([_CanvasPanelSelection.boxAtRest]) — an object of its own so that what
/// the store is handed to weigh and reclaim it holds the cuts and the
/// coordinator, nothing of the panel (the closure-scope law
/// [_CanvasPanelLift.openSession] keeps).
final class _CutsAhead {
  /// The run cutting now: one that finds it moved on stops.
  int run = 0;

  /// The region the cuts are for, and the cels it stood over.
  CanvasSelectionRegion? region;
  List<BrushFrameKey> over = const [];

  final Map<BrushFrameKey, _CutAhead> cuts = {};

  /// Takes the cuts off the store's books; null while they are on none.
  VoidCallback? _undeclare;

  /// Puts the cuts on [coordinator]'s store as a view it may reclaim —
  /// their holes are bytes the cels do not share, held as an open
  /// session's are.
  void declareTo(BrushFrameEditingCoordinator coordinator) {
    if (_undeclare != null) {
      return;
    }
    final store = coordinator.frameStore;
    final cuts = this.cuts;
    store.holdReclaimableView(
      this,
      bytes: () => cuts.entries.fold(
        0,
        (bytes, entry) =>
            bytes +
            (entry.value.cut?.holed.bytesNotSharedWith(
                  coordinator.currentSurfaceOf(entry.key),
                ) ??
                0),
      ),
      reclaim: cuts.clear,
    );
    _undeclare = () => store.releaseReclaimableView(this);
  }

  /// The screen's turn between two cuts — withdrawn when the run is let go
  /// of ([letGo]), so a box gone leaves no turn behind; null with none.
  VoidCallback? _withdrawTurn;

  Future<void> aTurn() {
    final (:turn, :withdraw) = aScreensTurnToWithdraw();
    _withdrawTurn = withdraw;
    return turn;
  }

  void letGo() {
    run += 1;
    region = null;
    over = const [];
    cuts.clear();
    _withdrawTurn?.call();
    _withdrawTurn = null;
    _undeclare?.call();
    _undeclare = null;
  }
}
