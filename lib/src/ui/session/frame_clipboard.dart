import '../../models/attached_layer_resolve.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_exposure.dart';
import '../../models/timeline_splice.dart';
import 'independent_clip_mint.dart';
import 'session_roles.dart';

/// The FRAME CLIPBOARD — the frame the user copied, and pasting it back
/// linked or independent, on one row or the rows beside it — as its own
/// object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: two fields of its own and
/// nineteen session members touched. It names the roles it needs in
/// its constructor.
///
/// ⛔The LAYER board left in G0-2 (2026-09-06): see [LayerClipboard]. Two
/// payloads, two sets of verbs, one object holding both is not a reason.
class FrameClipboard {
  FrameClipboard({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required FrameIds frameIds,
    required TimelineAccess timeline,
    required SessionInternals internals,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _frameIds = frameIds,
       _timeline = timeline,
       _internals = internals;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final FrameIds _frameIds;
  final TimelineAccess _timeline;
  final SessionInternals _internals;

  _CopiedFrameReference? _copiedFrame;

  /// The rows the last copy BANKED, as layer ids in the order they were
  /// taken — empty when the frame board holds nothing.
  ///
  /// ⛔The board's own row records stay private: a caller that could see
  /// them could re-resolve the band and disagree with what was banked,
  /// which is exactly the disagreement 결정 14 ②ⓐ forbids. It asks the
  /// clipboard which rows it took, and gets only that.
  List<LayerId> get bankedRowLayerIds => [
    for (final row in _copiedFrame?.rows ?? const <_CopiedRow>[]) row.layerId,
  ];

  /// The frame board names cels by id inside the cut it was written in;
  /// every caller that switches cuts, parks in a gap or lands a cut
  /// command drops it here rather than let a stale id resolve.
  void dropCopiedFrame() {
    _copiedFrame = null;
  }

  /// The board goes when the project itself is replaced.
  void clear() {
    _copiedFrame = null;
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
    if (_selection.bandNamesRowsThisPressWouldMiss) {
      return false;
    }
    return _selection.selectedFrame != null;
  }

  bool get canPasteLinkedFrameAtCurrentFrame {
    // Same law as its independent twin: this lands on the ACTIVE row and
    // serves only a band that covers it ([_pasteRun]'s `replacing`).
    if (_selection.bandNamesRowsThisPressWouldMiss) {
      return false;
    }
    final layer = _selection.activeLayer;
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
        layer.kind.holdsSingleCel) {
      return false;
    }

    // 🚨T3 — the clipboard may be holding cels the layer no longer has: a
    // 잘라내기 lifted them out and orphaned them. They come BACK on the
    // paste (same ids, so it is the same cel), and gating on "the layer
    // still has it" would have made cut-then-paste-back impossible while
    // the button sat lit.
    if (copiedFrame.cels.any((cel) => cel.id == copiedFrame.frameId)) {
      return _timeline.timelineController.currentFrameIndex >= 0;
    }

    return _timeline.timelineController.canPasteLinkedFrameAt(
      layer: layer,
      frameIndex: _timeline.timelineController.currentFrameIndex,
      copiedFrameId: copiedFrame.frameId,
    );
  }

  String get copiedFrameStatusText {
    final copiedFrame = _copiedFrame;
    if (copiedFrame == null) {
      return 'Copy: -';
    }

    final label = copiedFrame.frameName?.isNotEmpty ?? false
        ? copiedFrame.frameName!
        : copiedFrame.frameId.value;
    return 'Copy: $label';
  }

  String get linkedFrameUsesStatusText {
    final layer = _selection.activeLayer;
    final frame = _selection.selectedFrame;
    if (layer == null || frame == null) {
      return 'Links: -';
    }

    final uses = _timeline.timelineController.linkedUseCountForLayerFrame(
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
    final selection = _selection.frameRangeSelection.value;
    if (selection == null || !selection.coversLayer(anchor.id)) {
      return const [];
    }
    final entries = <_CopiedRow>[];
    for (final row in _pasteTargetRowsBesides(anchor)) {
      final clip = _timeline.timelineController.copyRunForLayer(
        layerId: row.id,
        index: _internals.commitBlockStart(row.id, selection.startIndex),
        count: selection.lengthFrames,
      );
      entries.add(_copiedRowFor(row, clip));
    }
    return entries;
  }

  /// The cels [clip] carries: the ones [row] holds that its cells actually
  /// point at. The clipboard travels BY VALUE, so what the run exposes has
  /// to come with it — a paste onto another row has no source in
  /// `layer.frames` by definition.
  List<Frame> _celsCarriedBy(Layer row, TimelineClipRow clip) {
    final ids = <FrameId>{
      for (final exposure in clip.exposures.values)
        if (exposure.frameId != null) exposure.frameId!,
    };
    return [
      for (final cel in row.frames)
        if (ids.contains(cel.id)) cel,
    ];
  }

  _CopiedRow _copiedRowFor(Layer row, TimelineClipRow clip) =>
      _CopiedRow(layerId: row.id, clip: clip, cels: _celsCarriedBy(row, clip));

  void copyFrameAtCurrentFrame() {
    final layer = _selection.activeLayer;
    final frame = _selection.selectedFrame;
    if (layer == null || frame == null || !canCopyFrameAtCurrentFrame) {
      return;
    }

    final run = _internals.spliceRunOnActiveRow();
    // 🚨T3 — the clip brings its LENGTH: 「내가 하고싶은건 프레임만 복붙이
    // 아니라 코마까지 포함해서 블록 자체를 복붙한다는 느낌」. What travels is
    // the run of cells, gaps and all, not one cel id that the destination
    // then decides a length for.
    final clip = run == null
        ? null
        : _timeline.timelineController.copyRunForLayer(
            layerId: layer.id,
            index: run.index,
            count: run.count,
          );
    _copiedFrame = _CopiedFrameReference(
      layerId: layer.id,
      frameId: frame.id,
      frameName: frame.name,
      clip: clip,
      cels: clip == null ? const [] : _celsCarriedBy(layer, clip),
      // 🚨결정 14 ②ⓐ — the board takes EVERY swept row, the anchor first.
      rows: [
        if (clip != null) _copiedRowFor(layer, clip),
        ..._copiedRowsBesides(layer),
      ],
    );
    _changes.notifyChanged();
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
  /// [FrameVerbs.canCreateDrawingAtCurrentFrame] deliberately; what is NOT shared is
  /// its block-start refusal, which exists because there is nothing there
  /// to divide — a paste inserts rather than divides.
  bool get canPasteIndependentFrameAtCurrentFrame {
    // The paste lands on the ACTIVE row, and its band rung serves only a
    // band that covers that row (`replacing` in [_pasteRun] — 「복붙은
    // 선택하고 붙여넣기가 기본」). A band naming other rows makes it a
    // plain insert on a row the user never swept, and the highlight then
    // stays put, because the clear runs on the replacing path alone.
    if (_selection.bandNamesRowsThisPressWouldMiss) {
      return false;
    }
    final layer = _selection.activeLayer;
    if (layer == null || _copiedFrame == null) {
      return false;
    }
    if (!layer.kind.holdsDrawings ||
        // SYNCED attach rows own no timeline of their own.
        isSyncedAttachedLayer(layer) ||
        // A reference row's picture comes from the library.
        layer.mediaReference != null ||
        // An IMAGE row holds ONE cel by definition.
        layer.kind.holdsSingleCel) {
      return false;
    }
    return _timeline.timelineController.currentFrameIndex >= 0;
  }

  void pasteIndependentFrameAtCurrentFrame() {
    final layer = _selection.activeLayer;
    final copiedFrame = _copiedFrame;
    if (layer == null ||
        copiedFrame == null ||
        !canPasteIndependentFrameAtCurrentFrame) {
      return;
    }
    _pasteRun(layer: layer, copied: copiedFrame, independent: true);
  }

  void pasteLinkedFrameAtCurrentFrame() {
    final layer = _selection.activeLayer;
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
    final selection = _selection.frameRangeSelection.value;
    if (selection == null || !selection.coversLayer(anchor.id)) {
      return const [];
    }
    final rows = <Layer>[];
    for (final id in selection.spanLayerIds) {
      if (id == anchor.id) {
        continue;
      }
      final row = _project.rangeLayerById(id);
      if (row == null ||
          !row.kind.holdsDrawings ||
          row.kind.holdsSingleCel ||
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
    return mintIndependentClip(
      clip: clip,
      sources: [...layer.frames, ...copied.cels],
      born: born,
      mint: () => _frameIds.mintFrameId(layer.id),
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
    final run = _internals.spliceRunOnActiveRow();
    // ⛔A selection REPLACES what it covers; with none, nothing comes out.
    // 「뭘 선택하든 덮어써버리면 선택범위를 조절하는 의미가 통째로 사라지잖아」
    final selection = _selection.frameRangeSelection.value;
    final replacing = selection != null && selection.coversLayer(layer.id);
    final index = replacing
        ? run!.index
        : _timeline.timelineController.currentFrameIndex;
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
            ? _internals.commitBlockStart(target.id, selection.startIndex)
            : index,
        liftCount: liftCount,
        clip: placed.clip,
        bornFrames: placed.born,
      ));
    }
    _timeline.timelineController.spliceRunsForLayers(
      runs: runs,
      description: independent ? 'Paste frames' : 'Paste linked frames',
    );
    final cut = _project.activeCutOrNull;
    for (final (targetId, minted) in mintedByLayer) {
      if (cut == null) {
        break; // Gap state: no cut, so no key to store a picture under.
      }
      carryBakedPictures(
        internals: _internals,
        cut: cut,
        between: (from: copied.layerId, to: targetId),
        minted: minted,
      );
    }
    if (replacing) {
      _selection.clearFrameRangeSelection();
    }
    _changes.notifyChanged();
  }
}

/// 🚨결정 14 ②ⓐ (유저 확정 2026-08-22) — ONE ROW OF THE CLIPBOARD.
///
/// The board held a single row until copy learned the band. It holds a LIST
/// now, and this is one entry: which row it came from, the run of cells, and
/// the cels those cells point at.
class _CopiedRow {
  const _CopiedRow({
    required this.layerId,
    required this.clip,
    this.cels = const [],
  });

  final LayerId layerId;
  final TimelineClipRow clip;

  /// Carried BY VALUE, for [_CopiedFrameReference.cels]'s reason: a
  /// 잘라내기 orphans what it lifted, and a clipboard that does not hold
  /// what was put on it is not one.
  final List<Frame> cels;
}

class _CopiedFrameReference {
  const _CopiedFrameReference({
    required this.layerId,
    required this.frameId,
    required this.frameName,
    this.clip,
    this.cels = const [],
    this.rows = const [],
  });

  /// 🚨결정 14 ②ⓐ — EVERY swept row, in display order, the anchor first.
  ///
  /// > 「지우기 눌렀다고해서 현재 행만 지우는게아니라 **선택된 모든게**
  /// > 지워지는걸 말하는거임. **복사든 뭐든 마찬가지**」
  ///
  /// ⚠️The scalar fields below still describe the ANCHOR — the status line
  /// and the paste gates read those. This is the whole board. A copy with no
  /// band writes ONE entry, so the single-row clipboard is this list of
  /// length one rather than a second shape standing beside it.
  final List<_CopiedRow> rows;

  final LayerId layerId;

  /// The ANCHOR cel — what the status line names and what the old one-cel
  /// paste gate asks about. It is the clip's first drawing, kept as its own
  /// field because "is there something to paste into this row" is a
  /// question about a cel belonging to a layer, not about a run.
  final FrameId frameId;
  final String? frameName;

  /// 🚨T3 — the run that was copied, 코마째. Null only for a clipboard
  /// written before the run existed (no such writer remains); readers treat
  /// null as "one cell of [frameId]", which is exactly what the retired
  /// behaviour did.
  final TimelineClipRow? clip;

  /// 🚨The CELS the clip's exposures point at, carried by value.
  ///
  /// Without this a 잘라내기 is lossy: the lift orphans the cels it took
  /// out, the layer drops them, and pasting them back finds nothing to point
  /// at — cut-then-paste, the most ordinary thing anyone does with a
  /// clipboard, would silently do nothing. A clipboard that does not hold
  /// what was put on it is not one.
  ///
  /// ⛔Re-added only when MISSING. A copy leaves the originals where they
  /// are, and adding them again would put one cel in the layer twice.
  final List<Frame> cels;
}
