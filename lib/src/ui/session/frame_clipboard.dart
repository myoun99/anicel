part of '../editor_session_manager.dart';

/// The FRAME CLIPBOARD — the frame the user copied and the layer they
/// copied, and pasting them back linked or independent, on one row or the
/// rows beside it — as its own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: two fields of its own and
/// nineteen session members touched. It reaches the session through
/// `_session`.
class _FrameClipboard {
  _FrameClipboard(this._session);

  final EditorSessionManager _session;

  _CopiedFrameReference? _copiedFrame;

  LayerCopyPayload? _layerClipboard;

  String? get layerClipboardName => _layerClipboard?.name;

  bool get hasLayerClipboard => _layerClipboard != null;

  void copyActiveLayer() {
    final activeLayer = _session.activeLayer;
    // SE rows are track-owned (global frame axis) — copying a cut-local
    // window onto the cut-layer clipboard would recreate the retired
    // cut-owned SE shape; stands down for now. Attach rows stand down too
    // (their cel links point into THIS cut's base).
    if (activeLayer == null ||
        !layerKindIsClipboardCopyable(activeLayer.kind) ||
        isAttachedLayer(activeLayer)) {
      return;
    }

    _layerClipboard = copyLayerToPayload(activeLayer);
    _session._notifyChanged();
  }

  void pasteLayerFromClipboard() {
    final payload = _layerClipboard;
    if (payload == null) {
      return;
    }

    final cut = _session.activeCutOrNull;
    if (cut == null) {
      return;
    }
    if (!_session.canAddLayerOfKind(payload.kind)) {
      return; // R9 #7: this cut already holds its one row of that kind.
    }
    final activeLayer = _session.activeLayer;
    final targetLayers = cut.layers;
    final activeLayerIndex = activeLayer == null
        ? -1
        : targetLayers.indexWhere((layer) => layer.id == activeLayer.id);
    final insertionIndex = activeLayerIndex == -1
        ? targetLayers.length
        : activeLayerIndex + 1;

    final pastedLayerId = _session._cutCommandCoordinator.pasteLayer(
      cutId: cut.id,
      payload: payload,
      insertionIndex: insertionIndex,
    );
    _session._refreshAfterCutCommand(preferredActiveLayerId: pastedLayerId);
    _session._notifyChanged();
  }

  bool get canCopyFrameAtCurrentFrame {
    // 복사 and 잘라내기 are ONE pair by the user's own definition
    // (「복사=원본 남기고 클립 저장 · 잘라내기=원본 지우고 클립 저장」) and
    // share a resolver — [cutRunAtCurrentFrame] literally calls this one.
    // So they must agree about the subject.
    //
    // ⛔The exemption written next to the cut standdown, "COPY is left lit:
    // it only reads", does not survive contact with what copy does: it
    // WRITES the clipboard, which is user state, and under a band naming
    // other rows it wrote the wrong row's run — the same wrong subject
    // that standdown was added for, banked for a later paste.
    if (_session.bandNamesRowsThisPressWouldMiss) {
      return false;
    }
    return _session.selectedFrame != null;
  }

  bool get canPasteLinkedFrameAtCurrentFrame {
    // Same law as its independent twin: this lands on the ACTIVE row and
    // serves only a band that covers it ([_pasteRun]'s `replacing`).
    if (_session.bandNamesRowsThisPressWouldMiss) {
      return false;
    }
    final layer = _session.activeLayer;
    final copiedFrame = _copiedFrame;
    if (layer == null ||
        copiedFrame == null ||
        layer.id != copiedFrame.layerId ||
        // SYNCED attach rows own no timeline — linked reuse happens
        // through the BASE's links (link the base cel instead). Free
        // attach rows author normally (UI-R21 #3).
        isSyncedAttachedLayer(layer) ||
        // An IMAGE row holds ONE cel by definition, so a second exposure
        // of it is a write the covering normalization rebuilds from the
        // same write (D22) — nothing changes and the press costs a
        // phantom undo entry. Its two neighbours on this pill already
        // refuse (독립 붙여넣기 always did, 잘라내기 since this round);
        // this was the third button still lit for a row nothing touches.
        layerKindHoldsSingleCel(layer.kind)) {
      return false;
    }

    // 🚨T3 — the clipboard may be holding cels the layer no longer has: a
    // 잘라내기 lifted them out and orphaned them. They come BACK on the
    // paste (same ids, so it is the same cel), and gating on "the layer
    // still has it" would have made cut-then-paste-back impossible while
    // the button sat lit.
    if (copiedFrame.cels.any((cel) => cel.id == copiedFrame.frameId)) {
      return _session._timelineController.currentFrameIndex >= 0;
    }

    return _session._timelineController.canPasteLinkedFrameAt(
      layer: layer,
      frameIndex: _session._timelineController.currentFrameIndex,
      copiedFrameId: copiedFrame.frameId,
    );
  }

  String get copiedFrameStatusText {
    final copiedFrame = _copiedFrame;
    if (copiedFrame == null) {
      return 'Copy: -';
    }

    final label = copiedFrame.frameName?.isNotEmpty == true
        ? copiedFrame.frameName!
        : copiedFrame.frameId.value;
    return 'Copy: $label';
  }

  String get linkedFrameUsesStatusText {
    final layer = _session.activeLayer;
    final frame = _session.selectedFrame;
    if (layer == null || frame == null) {
      return 'Links: -';
    }

    final uses = _session._timelineController.linkedUseCountForLayerFrame(
      layer: layer,
      frameId: frame.id,
    );
    return 'Links: $uses';
  }

  /// 결정 14 ②ⓐ — the clipboard entries for every swept row BESIDES the
  /// anchor, in the span's own order.
  ///
  /// Empty with no band, which is what makes the single-row copy the same
  /// code path rather than a branch beside it.
  ///
  /// ⚠️Same rows a paste would accept ([_pasteTargetRowsBesides]): a row
  /// that cannot receive a clip has no business putting one on the board,
  /// and a cut must not lift what a paste could never put back.
  List<_CopiedRow> _copiedRowsBesides(Layer anchor) {
    final selection = _session.frameRangeSelection.value;
    if (selection == null || !selection.coversLayer(anchor.id)) {
      return const [];
    }
    final entries = <_CopiedRow>[];
    for (final row in _pasteTargetRowsBesides(anchor)) {
      final clip = _session._timelineController.copyRunForLayer(
        layerId: row.id,
        index: _session._commitBlockStart(row.id, selection.startIndex),
        count: selection.lengthFrames,
      );
      final ids = <FrameId>{
        for (final exposure in clip.exposures.values)
          if (exposure.frameId != null) exposure.frameId!,
      };
      entries.add(
        _CopiedRow(
          layerId: row.id,
          clip: clip,
          cels: [
            for (final cel in row.frames)
              if (ids.contains(cel.id)) cel,
          ],
        ),
      );
    }
    return entries;
  }

  void copyFrameAtCurrentFrame() {
    final layer = _session.activeLayer;
    final frame = _session.selectedFrame;
    if (layer == null || frame == null || !canCopyFrameAtCurrentFrame) {
      return;
    }

    final run = _session._spliceRunOnActiveRow();
    // 🚨T3 — the clip brings its LENGTH: 「내가 하고싶은건 프레임만 복붙이
    // 아니라 코마까지 포함해서 블록 자체를 복붙한다는 느낌」. What travels is
    // the run of cells, gaps and all, not one cel id that the destination
    // then decides a length for.
    final clip = run == null
        ? null
        : _session._timelineController.copyRunForLayer(
            layerId: layer.id,
            index: run.index,
            count: run.count,
          );
    final cels = <FrameId>{
      for (final exposure
          in clip?.exposures.values ?? const <TimelineExposure>[])
        if (exposure.frameId != null) exposure.frameId!,
    };
    _copiedFrame = _CopiedFrameReference(
      layerId: layer.id,
      frameId: frame.id,
      frameName: frame.name,
      clip: clip,
      cels: [
        for (final cel in layer.frames)
          if (cels.contains(cel.id)) cel,
      ],
      // 🚨결정 14 ②ⓐ — the board takes EVERY swept row, the anchor first.
      rows: [
        if (clip != null)
          _CopiedRow(
            layerId: layer.id,
            clip: clip,
            cels: [
              for (final cel in layer.frames)
                if (cels.contains(cel.id)) cel,
            ],
          ),
        ..._copiedRowsBesides(layer),
      ],
    );
    _session._notifyChanged();
  }

  /// ㉕: the copied cel's content here, as a cel of its own.
  ///
  /// 🚨★★★ 유저 #4 (2026-08-14): 「프레임블록 복사하고 **다른 애니메이션행 등
  /// 이동가능한행에 붙혀넣기 불가.** 이런 붙혀넣기같은건 **같은 섹션 등
  /// 허용되는곳이라면 가능하도록**」.
  ///
  /// ⛔It used to delegate to the LINKED gate, which asks 「is that cel in
  /// THIS row」 — and for a link that question is the right one, because a
  /// link means *the same cel* and a cel belongs to a layer. This verb
  /// MINTS a cel, so the question does not apply to it: it asks whether
  /// this row can hold an authored drawing at all, which is what
  /// 「허용되는곳」 names.
  ///
  /// ⚠️Reachable only because the clipboard carries its cels by value
  /// (유저 #3's fix) — a cross-row paste has no source in `layer.frames` by
  /// definition, so this and that are one change made in two steps.
  ///
  /// ⛔The stand-downs are the AUTHORING ones and are shared with
  /// [_session.canCreateDrawingAtCurrentFrame] deliberately; what is NOT shared is
  /// its block-start refusal, which exists because there is nothing there
  /// to divide — a paste inserts rather than divides.
  bool get canPasteIndependentFrameAtCurrentFrame {
    // The paste lands on the ACTIVE row, and its band rung serves only a
    // band that covers that row (`replacing` in [_pasteRun] — 「복붙은
    // 선택하고 붙여넣기가 기본」). A band naming other rows makes it a
    // plain insert on a row the user never swept, and the highlight then
    // stays put, because the clear runs on the replacing path alone.
    if (_session.bandNamesRowsThisPressWouldMiss) {
      return false;
    }
    final layer = _session.activeLayer;
    if (layer == null || _copiedFrame == null) {
      return false;
    }
    if (!layerKindHoldsDrawings(layer.kind) ||
        // SYNCED attach rows own no timeline of their own.
        isSyncedAttachedLayer(layer) ||
        // A reference row's picture comes from the library.
        layer.mediaReference != null ||
        // An IMAGE row holds ONE cel by definition.
        layerKindHoldsSingleCel(layer.kind)) {
      return false;
    }
    return _session._timelineController.currentFrameIndex >= 0;
  }

  void pasteIndependentFrameAtCurrentFrame() {
    final layer = _session.activeLayer;
    final copiedFrame = _copiedFrame;
    if (layer == null ||
        copiedFrame == null ||
        !canPasteIndependentFrameAtCurrentFrame) {
      return;
    }
    _pasteRun(layer: layer, copied: copiedFrame, independent: true);
  }

  void pasteLinkedFrameAtCurrentFrame() {
    final layer = _session.activeLayer;
    final copiedFrame = _copiedFrame;
    if (layer == null ||
        copiedFrame == null ||
        !canPasteLinkedFrameAtCurrentFrame) {
      return;
    }
    _pasteRun(layer: layer, copied: copiedFrame, independent: false);
  }

  /// 🚨★★★ BOTH pastes, because they differ in ONE thing.
  ///
  /// 유저 확정: 「링크 붙여넣기 = 겸용(링크) 생성 · 독립 붙여넣기 = 그냥 복제」.
  /// That is the only difference — which cel the exposures end up pointing
  /// at — so the PLACEMENT is written once. Where the two used to share a
  /// private helper they now share the splice itself, and 「선택이 있으면
  /// 갈아끼우기, 없으면 끼워넣기」 is the same sentence for both.
  ///
  /// ⚠️A cel is minted PER SOURCE CEL, not per cell: a clip holding one
  /// drawing exposed three times pastes as one new drawing exposed three
  /// times. Minting per cell would quietly unlink a block from itself.
  /// 결정 14 ③ⓐ — the OTHER rows a paste lands on: every row the band names
  /// besides [anchor], minus the ones that cannot hold what is being pasted.
  ///
  /// Empty when no band covers the anchor, which is what keeps the
  /// single-row paste on the same code path instead of beside it.
  ///
  /// ⚠️The kind filter is the delete collector's, for its reason: a SYNCED
  /// attach row has no timing of its own and a SINGLE-CEL row's block is
  /// pinned by the covering normalization, so pasting into either writes
  /// something the next normalize takes straight back out.
  List<Layer> _pasteTargetRowsBesides(Layer anchor) {
    final selection = _session.frameRangeSelection.value;
    if (selection == null || !selection.coversLayer(anchor.id)) {
      return const [];
    }
    final rows = <Layer>[];
    for (final id in selection.spanLayerIds) {
      if (id == anchor.id) {
        continue;
      }
      final row = _session._rangeLayerById(id);
      if (row == null ||
          !layerKindHoldsDrawings(row.kind) ||
          layerKindHoldsSingleCel(row.kind) ||
          isSyncedAttachedLayer(row)) {
        continue;
      }
      rows.add(row);
    }
    return rows;
  }

  /// The clip as [layer] must receive it, with the cels that have to join
  /// the layer in the same command.
  ///
  /// Split out of [_pasteRun] when the paste learned the band: the
  /// independent branch mints PER LAYER, so the arithmetic stopped being
  /// something one row could keep inline.
  ({TimelineClipRow clip, List<Frame> born, Map<FrameId, FrameId> minted})
  _placedClipFor({
    required Layer layer,
    required TimelineClipRow clip,
    required _CopiedFrameReference copied,
    required bool independent,
  }) {
    final born = <Frame>[
      // A 잘라내기 orphaned the cels it lifted, so the layer no longer holds
      // them; the clipboard does. Bringing back the SAME id is what makes
      // cut-then-paste-back a move rather than a deletion — and re-adding
      // only what is missing keeps a plain copy from duplicating anything.
      if (!independent)
        for (final cel in copied.cels)
          if (!layer.frames.any((frame) => frame.id == cel.id)) cel,
    ];
    if (!independent) {
      return (clip: clip, born: born, minted: const {});
    }
    final minted = <FrameId, FrameId>{};
    final exposures = <int, TimelineExposure>{};
    for (final entry in clip.exposures.entries) {
      final sourceId = entry.value.frameId;
      if (sourceId == null) {
        continue;
      }
      // 🚨THE CLIPBOARD IS THE SECOND PLACE TO LOOK, and after a 잘라내기
      // it is the ONLY one (유저 #3, 2026-08-14).
      //
      // A cut orphans the cels it lifted, so they are gone from
      // `layer.frames` by the time this runs. Reading only the layer found
      // nothing, minted an id anyway, and authored an exposure pointing at a
      // cel that does not exist: a white block, `?` where the name goes, and
      // every verb that resolves the cel refusing — 「완전한 버그상태」.
      //
      // ⚠️It matters MORE now: a band paste reaches rows the clip never came
      // from, so `layer.frames` misses the source on every one of them and
      // the clipboard is the only place the picture lives.
      final source =
          layer.frames.where((frame) => frame.id == sourceId).firstOrNull ??
          copied.cels.where((frame) => frame.id == sourceId).firstOrNull;
      if (source == null) {
        // ⛔An exposure with no cel behind it is the damage itself. Drop the
        // cell rather than author a reference nothing can resolve — an empty
        // cell is a state the row already knows how to be.
        continue;
      }
      final newId = minted.putIfAbsent(sourceId, () {
        // 🚨Through the MINT. `_nextFrameId` reads the sequence without
        // advancing it, so two independent pastes inside one clock tick
        // would come out as the SAME cel — which is not "two cels that look
        // alike", it is one cel exposed twice, and the import round already
        // paid for that lesson once. A band paste makes that risk ROUTINE:
        // every swept row mints in the same tick as its neighbours.
        final id = _session._mintFrameId(layer.id);
        // 🚨IT COMES OUT UNNAMED, and that is the point rather than an
        // omission. A cel's name is its IDENTITY inside the layer — the
        // rename path REFUSES a duplicate and offers to merge instead, which
        // is this app's 「같은 이름 = 같은 그림」 rule. Carrying the source's
        // name would assert the very link this verb exists to avoid, and do
        // it behind that dialog's back.
        born.add(
          duplicateFrameContent(
            frame: source,
            newFrameId: id,
          ).copyWith(name: null),
        );
        return id;
      });
      exposures[entry.key] = entry.value.copyWith(frameId: newId);
    }
    return (
      clip: TimelineClipRow(exposures: exposures, length: clip.length),
      born: born,
      // 🚨★★★WHICH CEL CAME FROM WHICH — the picture needs it.
      //
      // ⛔`duplicateFrameContent` deep-copies `strokes`, and for a while that
      // read like 「the copy owes the source nothing」. It does not copy the
      // PICTURE: pixels live in `brushFrameStore` under a key that carries
      // the frame ID, so a minted cel resolves to an empty surface.
      // 유저 (F-62): 「프레임 복사후 독립붙여넣기시, **그림이 복제되지않음**」.
      //
      // The caller copies the baked surface across this map after the splice.
      minted: minted,
    );
  }

  void _pasteRun({
    required Layer layer,
    required _CopiedFrameReference copied,
    required bool independent,
  }) {
    final clip =
        copied.clip ??
        TimelineClipRow(
          exposures: {0: TimelineExposure.drawing(copied.frameId, length: 1)},
          length: 1,
        );
    final run = _session._spliceRunOnActiveRow();
    // ⛔A selection REPLACES what it covers; with none, nothing comes out.
    // 「뭘 선택하든 덮어써버리면 선택범위를 조절하는 의미가 통째로 사라지잖아」
    final selection = _session.frameRangeSelection.value;
    final replacing = selection != null && selection.coversLayer(layer.id);
    final index = replacing
        ? run!.index
        : _session._timelineController.currentFrameIndex;
    final liftCount = replacing ? run!.count : 0;

    // 🚨결정 14 ③ⓐ (유저 확정 2026-08-22) — **THE CLIP LANDS ON EVERY SWEPT
    // ROW.**
    //
    // > 「지우기 눌렀다고해서 현재 행만 지우는게아니라 **선택된 모든게**
    // > 지워지는걸 말하는거임. **복사든 뭐든 마찬가지**」, and for the paste
    // > specifically: 한 행짜리 클립이 여러 행 밴드에 떨어지면 **모든 행에
    // > 같은 것을**.
    //
    // The clipboard still holds ONE row, so a band across three rows gets
    // that row three times. With no band the list is the active row alone,
    // which is why this is one path rather than a branch beside the old one.
    final runs =
        <
          ({
            LayerId layerId,
            int index,
            int liftCount,
            TimelineClipRow? clip,
            List<Frame> bornFrames,
          })
        >[];
    // Which minted cel came from which source, per row — the pictures move
    // across this after the splice (F-62). Empty for a LINKED paste, which
    // mints nothing.
    final mintedByLayer = <(LayerId, Map<FrameId, FrameId>)>[];
    final targets = <Layer>[layer, ..._pasteTargetRowsBesides(layer)];
    for (var i = 0; i < targets.length; i += 1) {
      final target = targets[i];
      // 🚨결정 14 ②ⓐ×③ⓐ — WHICH row of the board this target receives.
      //
      // A ONE-row clip goes to every target (③ⓐ: 「모든 행에 같은 것을」).
      // A clip that already holds several rows pairs with them IN ORDER —
      // there is no other reading that preserves what was copied — and the
      // pairing stops when the board runs out, because a target with no row
      // to receive has nothing to be given.
      final board = copied.rows;
      final TimelineClipRow? mine;
      final List<Frame> mineCels;
      if (board.length <= 1) {
        mine = clip;
        mineCels = copied.cels;
      } else if (i < board.length) {
        mine = board[i].clip;
        mineCels = board[i].cels;
      } else {
        continue;
      }
      // ⚠️ONCE per row. The independent branch MINTS inside here, so asking
      // twice would coin two sets of cels and reference only one of them —
      // the layer would carry orphans nothing points at.
      final placed = _placedClipFor(
        layer: target,
        clip: mine,
        copied: _CopiedFrameReference(
          layerId: copied.layerId,
          frameId: copied.frameId,
          frameName: copied.frameName,
          clip: mine,
          cels: mineCels,
        ),
        independent: independent,
      );
      if (placed.minted.isNotEmpty) {
        mintedByLayer.add((target.id, placed.minted));
      }
      runs.add((
        layerId: target.id,
        // Each row resolves the band's start against ITS OWN blocks: a
        // splice index is a block boundary, and two rows swept together
        // rarely have their boundaries in the same place.
        index: replacing
            ? _session._commitBlockStart(target.id, selection.startIndex)
            : index,
        liftCount: liftCount,
        clip: placed.clip,
        bornFrames: placed.born,
      ));
    }
    _session._timelineController.spliceRunsForLayers(
      runs: runs,
      description: independent ? 'Paste frames' : 'Paste linked frames',
    );
    // 🚨★★★AND THE PICTURES COME WITH THEM (F-62).
    //
    // ⚠️Surfaces are IMMUTABLE with structural tile sharing, so storing the
    // same object under the new key IS the copy — the same reasoning
    // `UnlinkLayerCommand` states where it forks a linked member's cels.
    //
    // ⛔A LINKED paste copies nothing on purpose: it points the new
    // exposures at the cels that already exist, which is what 「링크」 means.
    // `minted` is empty there, so this loop is the independent branch only
    // without a second flag saying so.
    //
    // ⚠️After the splice, not before: the born cels have to be in the layer
    // for the key to name something the app will read back.
    final cut = _session.activeCutOrNull;
    for (final (targetId, minted) in mintedByLayer) {
      if (cut == null) {
        break; // Gap state: no cut, so no key to store a picture under.
      }
      for (final entry in minted.entries) {
        final surface = _session.brushFrameStore.bakedSurfaceOrNull(
          _session.brushFrameKeyForCut(cut, copied.layerId, entry.key),
        );
        if (surface == null) {
          continue;
        }
        _session.brushFrameStore.storeBakedSurface(
          _session.brushFrameKeyForCut(cut, targetId, entry.value),
          surface,
        );
      }
    }
    if (replacing) {
      _session.clearFrameRangeSelection();
    }
    _session._notifyChanged();
  }
}
