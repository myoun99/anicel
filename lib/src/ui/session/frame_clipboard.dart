import '../../models/attached_layer_resolve.dart';
import '../../models/audio_clip.dart';
import '../../models/bitmap_surface.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_exposure.dart';
import '../../models/timeline_frame_range.dart';
import '../../models/timeline_splice.dart';
import 'render_caches.dart';
import 'active_cut_controllers.dart';
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
    required ActiveCutControllers controllers,
    required SessionInternals internals,
    required RenderCaches renderCaches,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _frameIds = frameIds,
       _controllers = controllers,
       _internals = internals,
       _renderCaches = renderCaches;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final FrameIds _frameIds;
  final ActiveCutControllers _controllers;
  final SessionInternals _internals;
  final RenderCaches _renderCaches;

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

  /// The board goes when the project itself is replaced — and only then;
  /// until then it is replaced by the next copy.
  ///
  /// 🚨★★THE COPY IS ALWAYS IN HAND (F-161, 유저 2026-09-17): 「복붙은
  /// 어디서든 가능하게 … 복사는 항상 언제든 들고있게. 컷2의 레이어에서
  /// 붙여넣기 가능. 복사는 언제나 하나 들고있음. 보통 프로그램이 그러니까」.
  /// F-152 (09-16) had asked it inside one cut first: 「복사하고 무언가
  /// 붙혀넣는다고 해서 복사한게 사라지지않게. 복사한거는 들고있음」.
  ///
  /// ↩️What threw it away: every cut switch, gap park and cut-command
  /// refresh — so an UNDO after a paste emptied it too (measured, F-152).
  /// That drop predates the board carrying its cels, its sounds and now its
  /// PICTURES by value ([_CopiedRow.pictures]); nothing it holds names a
  /// place in one cut any more, so no cut change can make it stale.
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
        // F-115 (유저 2026-09-12): 「se 블록 복붙, 우선 복사하고나서는 독립
        // 붙여넣기만 가능. 왜냐하면 링크붙여넣기의 차이점이 없기때문」. A link
        // is 겸용 — the same PICTURE exposed again — and a row whose cels hold
        // no artwork has none to reuse.
        !layer.kind.isDrawingCel ||
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
      return _controllers.timelineController.currentFrameIndex >= 0;
    }

    return _controllers.timelineController.canPasteLinkedFrameAt(
      layer: layer,
      frameIndex: _controllers.timelineController.currentFrameIndex,
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

    final uses = _controllers.timelineController.linkedUseCountForLayerFrame(
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
      final clip = _controllers.timelineController.copyRunForLayer(
        layerId: row.id,
        index: _rangeStartOn(row.id, selection),
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

  _CopiedRow _copiedRowFor(Layer row, TimelineClipRow clip) {
    final cels = _celsCarriedBy(row, clip);
    return _CopiedRow(
      layerId: row.id,
      clip: clip,
      cels: cels,
      sounds: _soundsCarriedBy(row, cels),
      pictures: _picturesCarriedBy(row, cels),
    );
  }

  /// The pictures [cels] show on [row], as they are NOW — taken at the copy,
  /// for the reason [_celsCarriedBy] gives and F-161's: a paste may land in
  /// another cut, whose store has no picture under the source's key, and a
  /// source drawn over or cut away after the copy is not what was copied.
  ///
  /// ⚠️Surfaces are immutable with structural tile sharing, so holding one is
  /// holding a reference, not a second set of pixels — until the source is
  /// drawn over, when the board keeps the tiles it copied.
  Map<FrameId, BitmapSurface> _picturesCarriedBy(Layer row, List<Frame> cels) {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return const {};
    }
    final store = _renderCaches.brushFrameStore;
    return {
      for (final cel in cels)
        cel.id: ?store.bakedSurfaceOrNull(
          _internals.brushFrameKeyForCut(cut, row.id, cel.id),
        ),
    };
  }

  /// The sounds [cels] carry on [row] — BY VALUE for the reason
  /// [_celsCarriedBy] gives, and one more: a 잘라내기 takes a lifted
  /// instance's sound out of the row with it (REC1-A), so a board that did
  /// not hold it would paste the block back silent (F-115).
  List<AudioClip> _soundsCarriedBy(Layer row, List<Frame> cels) {
    final ids = {for (final cel in cels) cel.id};
    return [
      for (final sound in row.audioClips)
        if (ids.contains(sound.frameId)) sound,
    ];
  }

  /// 🚨T3 신설 — 잘라내기: the same lift the paste does, with the clip going
  /// to the clipboard instead of a row.
  ///
  /// 유저 확정 2026-08-13: 「잘라내기 버튼을 공용 알약에 신설 — 복사 버튼
  /// 왼쪽. 복사=원본 남기고 클립 저장 · 잘라내기=원본 지우고 클립 저장」.
  ///
  /// ★It is literally copy followed by the lift half of `spliceTimeline`,
  /// which is why it needs no rules of its own — with ONE exception: the
  /// lift has to survive the write. On a SINGLE-CEL (image) row it does
  /// not. The covering normalization rebuilds the picture's block from
  /// the same write, so the press changes nothing on screen and costs a
  /// phantom undo entry — the next Ctrl+Z then eats the user's real
  /// previous edit. Same standdown, same reason, as the delete gate
  /// (D22). COPY stays lit: it takes the cel to the clipboard without
  /// claiming to remove it, which is honest here.
  bool get canCutRunAtCurrentFrame {
    // 잘라내기 resolves its run on the ACTIVE row, so under a band naming
    // other rows it lifts a block the user never swept — and being the
    // destructive half of the clipboard pair, it did so while Delete sat
    // dark one button away on the same pill. No band rung to serve, so
    // the band ends the ladder — and so does COPY, its documented twin:
    // "it only reads" was wrong, since it writes the clipboard.
    if (_selection.bandNamesRowsThisPressWouldMiss) {
      return false;
    }
    final layer = _selection.activeLayer;
    if (layer != null && layer.kind.holdsSingleCel) {
      return false;
    }
    return canCopyFrameAtCurrentFrame;
  }

  void cutRunAtCurrentFrame() {
    final layer = _selection.activeLayer;
    final frame = _selection.selectedFrame;
    if (layer == null || frame == null || !canCutRunAtCurrentFrame) {
      return;
    }
    final run = spliceRunOnActiveRow();
    if (run == null) {
      return;
    }
    // ⛔NOT copyFrameAtCurrentFrame: standing, a copy banks ONE comma now
    // (F-152) while this lifts the whole block — banking less than it lifts
    // would make it a delete (결정 14 ②ⓐ). A cut banks exactly what it lifts.
    _bank(
      layer: layer,
      frame: frame,
      clip: _controllers.timelineController.copyRunForLayer(
        layerId: layer.id,
        index: run.index,
        count: run.count,
      ),
    );
    // 🚨결정 14 ②ⓐ — the lift takes every row the copy just banked, in ONE
    // undo. ⛔It reads the CLIPBOARD's rows rather than re-resolving the
    // band: the two must not be able to disagree about which rows were
    // taken, because a row lifted but not banked is work that cannot come
    // back — 「클립보드가 담지 않은 것을 들어내면 그건 삭제지 잘라내기가
    // 아니다」.
    final selection = _selection.frameRangeSelection.value;
    final banked = bankedRowLayerIds;
    _controllers.timelineController.spliceRunsForLayers(
      runs: [
        for (final bankedLayerId in banked)
          (
            layerId: bankedLayerId,
            index: bankedLayerId == layer.id
                ? run.index
                : _rangeStartOn(bankedLayerId, selection!),
            liftCount: bankedLayerId == layer.id
                ? run.count
                : selection!.lengthFrames,
            clip: null,
            bornFrames: const <Frame>[],
            bornSounds: const <AudioClip>[],
          ),
        // ⛔MUTANT SURVIVES HERE (`if (false)`), and the classification is
        // NEVER APPLIED (2026-09-07): the bank above is handed the very run
        // this verb resolved, so it always banks at least the anchor row.
        // Kept as the arm that keeps the lift honest if the board ever came
        // back empty — 결정 14 ②ⓐ says a row lifted but not banked is work
        // that cannot come back, and this is the other side of it.
        if (banked.isEmpty)
          (
            layerId: layer.id,
            index: run.index,
            liftCount: run.count,
            clip: null,
            bornFrames: const <Frame>[],
            bornSounds: const <AudioClip>[],
          ),
      ],
      description: 'Cut frames',
    );
    _selection.clearFrameRangeSelection();
    _changes.notifyChanged();
  }

  void copyFrameAtCurrentFrame() {
    final layer = _selection.activeLayer;
    final frame = _selection.selectedFrame;
    if (layer == null || frame == null || !canCopyFrameAtCurrentFrame) {
      return;
    }

    // 🚨★★WHAT A COPY BANKS DEPENDS ON WHETHER SOMETHING IS SELECTED
    // (F-152, 유저 2026-09-16): 「프레임 복붙할때 그냥 그곳에 서있을떄
    // 복사한거면 … 붙혀넣을때 1콤마로서 붙혀넣게. 해당 블록을 선택해서
    // 복사하면 콤마 유지되도록」.
    //
    // • SELECTED — the selection's run, commas and gaps and all. That is
    //   T3's rule (「프레임만 복붙이 아니라 코마까지 포함해서 블록 자체를
    //   복붙한다는 느낌」), and selecting the block is how it is asked for.
    // • STANDING — ONE cell of the drawing the cell SHOWS.
    //
    // ⚠️That second line is also F-140 (유저 2026-09-16: 「복사버튼이
    // 작동하는건 좋은데 지금 붙여넣기해도 아무일 안일어나니까」). Standing on a
    // hold's GHOST, the run was the ghost's span read off the GHOST-FREE row
    // (F-134) — every cell of it empty — so the copy banked nothing while
    // its button, lit by the drawing on screen, promised that drawing.
    // [_oneCellOf] banks what is shown, a real cell, wherever it came from.
    //
    // ⚠️One comma of the DRAWING, not of the block: the memo, the dots and
    // the edge properties are the BLOCK's ([TimelineExposure.memo] — 「re-
    // exposing the same drawing gets its own」), and a hold edge riding
    // along would ghost the paste past the one comma it was asked to be.
    //
    // ⛔The gate leaves no third case: a selection that misses this row
    // stood the press down ([canCopyFrameAtCurrentFrame]).
    final run = _selection.frameRangeSelection.value == null
        ? null
        : spliceRunOnActiveRow();
    _bank(
      layer: layer,
      frame: frame,
      clip: run == null
          ? _oneCellOf(frame.id)
          : _controllers.timelineController.copyRunForLayer(
              layerId: layer.id,
              index: run.index,
              count: run.count,
            ),
    );
  }

  /// One comma of [frameId] — the whole clip a copy with nothing selected
  /// banks.
  static TimelineClipRow _oneCellOf(FrameId frameId) => TimelineClipRow(
    exposures: {0: TimelineExposure.drawing(frameId, length: 1)},
    length: 1,
  );

  /// Puts [clip] on the board as the copy of [frame] on [layer] — the
  /// half a copy and a 잘라내기 share. What differs between them is only
  /// the CLIP: a cut must bank the whole run it lifts (결정 14 ②ⓐ —
  /// 「클립보드가 담지 않은 것을 들어내면 그건 삭제지 잘라내기가 아니다」),
  /// while a copy banks what [copyFrameAtCurrentFrame] decides.
  void _bank({
    required Layer layer,
    required Frame frame,
    required TimelineClipRow clip,
  }) {
    final cels = _celsCarriedBy(layer, clip);
    _copiedFrame = _CopiedFrameReference(
      layerId: layer.id,
      frameId: frame.id,
      frameName: frame.name,
      clip: clip,
      cels: cels,
      sounds: _soundsCarriedBy(layer, cels),
      // 🚨결정 14 ②ⓐ — the board takes EVERY swept row, the anchor first.
      rows: [_copiedRowFor(layer, clip), ..._copiedRowsBesides(layer)],
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
    return _controllers.timelineController.currentFrameIndex >= 0;
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

  void _pasteRun({
    required Layer layer,
    required _CopiedFrameReference copied,
    required bool independent,
  }) {
    final clip = copied.clip;
    final run = spliceRunOnActiveRow();
    // ⛔A selection REPLACES what it covers; with none, nothing comes out.
    // 「뭘 선택하든 덮어써버리면 선택범위를 조절하는 의미가 통째로 사라지잖아」
    final selection = _selection.frameRangeSelection.value;
    final replacing = selection != null && selection.coversLayer(layer.id);
    // F-115: with nothing selected the clip goes in at the playhead ON THE
    // ROW'S OWN AXIS — a track-owned SE row keys the track's frames, and the
    // cut-local index landed it on an earlier cut's.
    final index = replacing
        ? run!.index
        : _controllers.timelineController.currentFrameIndex +
              _project.rowAxisOffset(layer.id);
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
            List<AudioClip> bornSounds,
          })
        >[];
    // Which minted cel came from which source, per row — the pictures move
    // across this after the splice (F-62). Empty for a LINKED paste, which
    // mints nothing.
    final mintedByLayer =
        <(LayerId, Map<FrameId, FrameId>, Map<FrameId, BitmapSurface>)>[];
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
      final List<AudioClip> mineSounds;
      final Map<FrameId, BitmapSurface> minePictures;
      if (board.length <= 1) {
        mine = clip;
        mineCels = copied.cels;
        mineSounds = copied.sounds;
        // The anchor row is the board's first — the pictures live on rows.
        minePictures = board.first.pictures;
      } else if (i < board.length) {
        mine = board[i].clip;
        mineCels = board[i].cels;
        mineSounds = board[i].sounds;
        minePictures = board[i].pictures;
      } else {
        continue;
      }
      // ⚠️ONCE per row. The independent branch MINTS inside here, so asking
      // twice would coin two sets of cels and reference only one of them —
      // the layer would carry orphans nothing points at.
      final placed = placedClipFor(
        layer: target,
        row: (clip: mine, cels: mineCels, sounds: mineSounds),
        independent: independent,
        mint: () => _frameIds.mintFrameId(target.id),
      );
      if (placed.minted.isNotEmpty) {
        mintedByLayer.add((target.id, placed.minted, minePictures));
      }
      runs.add((
        layerId: target.id,
        // Each row places the band's start on ITS OWN axis ([_rangeStartOn]):
        // two rows swept together need not key the same frames — a
        // track-owned SE row keys the track's.
        index: replacing ? _rangeStartOn(target.id, selection) : index,
        liftCount: liftCount,
        clip: placed.clip,
        bornFrames: placed.born,
        bornSounds: placed.bornSounds,
      ));
    }
    _controllers.timelineController.spliceRunsForLayers(
      runs: runs,
      description: independent ? 'Paste frames' : 'Paste linked frames',
    );
    final cut = _project.activeCutOrNull;
    for (final (targetId, minted, pictures) in mintedByLayer) {
      if (cut == null) {
        break; // Gap state: no cut, so no key to store a picture under.
      }
      carryBakedPictures(
        internals: _internals,
        store: _renderCaches.brushFrameStore,
        cut: cut,
        to: targetId,
        minted: minted,
        pictureOf: (source) => pictures[source],
      );
    }
    if (replacing) {
      _selection.clearFrameRangeSelection();
    }
    _changes.notifyChanged();
  }

  /// WHERE a copy, cut or paste acts on the active row, in COMMIT keys.
  ///
  /// ★The one place the two halves of 「N칸을 들어내고 클립을 넣는다」 get
  /// their N: a live selection says its own range, and with none the verb
  /// means the block under the playhead. Copy, cut and paste all ask this,
  /// so they cannot disagree about what "the run" is — except that a COPY
  /// with nothing selected no longer asks: it banks one comma (F-152).
  ///
  /// ⚠️The ROW is the active layer's alone. T3's multi-row anchoring
  /// (「선택의 첫 행을 현재 행에 맞춘다」) needs a rail-display-order source
  /// the session does not have — [TimelineController.spliceRunsForLayers]
  /// already takes a list so the extension is additive, but nothing here
  /// pretends to do it yet.
  ///
  /// 🚨F-115 — BOTH halves answer on the ROW'S OWN axis (유저 2026-09-12:
  /// 「지금 붙여넣기하면 기존 블럭이 이상하게 움직일뿐 붙여넣어지지않음」). A
  /// selection's cells move by the row's axis offset ([_rangeStartOn]); with
  /// nothing selected the controller answers from the row it edits
  /// ([TimelineController.runAtPlayheadForLayer] — the block Delete takes from
  /// the same press). The unselected half used to come off the cut-local
  /// display clone, which on a track-owned SE row past the first cut read,
  /// lifted and inserted on an earlier cut's frames.
  ({int index, int count})? spliceRunOnActiveRow() {
    final layer = _selection.activeLayer;
    if (layer == null) {
      return null;
    }
    final selection = _selection.frameRangeSelection.value;
    if (selection != null && selection.coversLayer(layer.id)) {
      return (
        index: _rangeStartOn(layer.id, selection),
        count: selection.lengthFrames,
      );
    }
    return _controllers.timelineController.runAtPlayheadForLayer(layer.id);
  }

  /// Where [selection] starts on [layerId]'s own row. A selection is a run of
  /// CELLS — 「the range means exactly its cells」 — so it moves by the row's
  /// axis offset. ⛔Not [SessionInternals.commitBlockStart]: that names the
  /// BLOCK a display start stands for, and at 0 over a block spilling in from
  /// an earlier cut it answered that block's start there (F-115).
  int _rangeStartOn(LayerId layerId, TimelineFrameRangeSelection selection) =>
      selection.startIndex + _project.rowAxisOffset(layerId);
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
    this.sounds = const [],
    this.pictures = const {},
  });

  final LayerId layerId;
  final TimelineClipRow clip;

  /// Carried BY VALUE, for [_CopiedFrameReference.cels]'s reason: a
  /// 잘라내기 orphans what it lifted, and a clipboard that does not hold
  /// what was put on it is not one.
  final List<Frame> cels;

  /// The sounds those cels carry, BY VALUE for the same reason — a 잘라내기
  /// takes a lifted instance's sound out of the row with it (F-115).
  final List<AudioClip> sounds;

  /// The pictures those cels showed when they were copied, by cel id — BY
  /// VALUE so a paste in any cut brings the drawing (F-161). A cel with no
  /// picture of its own is simply absent.
  final Map<FrameId, BitmapSurface> pictures;
}

class _CopiedFrameReference {
  const _CopiedFrameReference({
    required this.layerId,
    required this.frameId,
    required this.frameName,
    required this.clip,
    this.cels = const [],
    this.sounds = const [],
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

  /// 🚨T3 — the run that was copied, 코마째 — or, copied standing, one comma
  /// of [frameId] (F-152).
  final TimelineClipRow clip;

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

  /// The sounds [cels] carry, BY VALUE (F-115): a 잘라내기 takes a lifted
  /// instance's sound out of the row with it (REC1-A), and an independent
  /// paste gives each new instance a copy of its source's.
  final List<AudioClip> sounds;
}
