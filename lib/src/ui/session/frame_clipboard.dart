import '../../controllers/timeline_controller.dart' show SpliceRider;
import '../../models/attached_layer_resolve.dart';
import '../../models/audio_clip.dart';
import '../../models/bitmap_surface.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_link_registry.dart';
import '../../models/timeline_coverage.dart' show coveringDrawingBlockAt;
import '../../models/timeline_exposure.dart';
import '../../models/timeline_row_address.dart';
import '../../models/timeline_repeat.dart' show ghostFreeTimeline;
import '../../models/timeline_splice.dart';
import '../../services/media/media_byte_source.dart' show MediaByteSource;
import '../../services/project_lookup.dart' show attachedMirrorGroupOf;
import '../../services/persistence/media_staging_store.dart';
import 'render_caches.dart';
import 'active_cut_controllers.dart';
import 'frame_verbs.dart' show rowTakesNewCels;
import 'independent_clip_mint.dart';
import 'session_roles.dart';
import 'what_a_copy_brings.dart';

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
class FrameClipboard implements BringsMedia {
  FrameClipboard({
    required FrameBoard board,
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required FrameIds frameIds,
    required ActiveCutControllers controllers,
    required RenderCaches renderCaches,
    required MediaByteSource Function(String poolPath) mediaBytesOf,
    required MediaStagingStore staging,
  }) : _board = board,
       _project = project,
       _selection = selection,
       _changes = changes,
       _frameIds = frameIds,
       _controllers = controllers,
       _renderCaches = renderCaches,
       _mediaBytesOf = mediaBytesOf,
       _staging = staging;

  /// Where this project keeps a medium's bytes — what a copy made HERE
  /// tells a paste into another project to read ([CopiedNames.bytesOf]).
  final MediaByteSource Function(String poolPath) _mediaBytesOf;

  /// Where a paste from another project stages the media it carries in.
  final MediaStagingStore _staging;

  /// What a wait held for the next paste of the board's copy.
  final HeldArrival _held = HeldArrival();

  /// The app's frame board ([FrameBoard]) — every open project's clipboard
  /// reads and writes the same one (I-7).
  final FrameBoard _board;
  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final FrameIds _frameIds;
  final ActiveCutControllers _controllers;
  final RenderCaches _renderCaches;

  _CopiedFrameReference? get _copiedFrame => _board._copy;

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

  // --- WHERE a press acts (F-281) -----------------------------------------
  //
  // Every verb below is said of a PLACE — a row, the cursor on that row's
  // own axis, THE selection — and each panel answers only where its press
  // stands. The `…AtCurrentFrame` members are the timeline's doors.

  /// The TIMELINE's place: the cut's active row, at the cut's playhead.
  ClipboardPlace? get timelinePlace {
    final row = _selection.activeLayer;
    return row == null
        ? null
        : ClipboardPlace._(
            row: row,
            cel: _selection.selectedFrame,
            index:
                _controllers.timelineController.currentFrameIndex +
                _project.rowAxisOffset(row.id),
            band: _band,
          );
  }

  /// The STORYBOARD's place: the track's S row its rail stands on, at the
  /// track's playhead — the row and the frame as the row itself keys them,
  /// so it answers inside a cut and parked in a gap alike (H11, 유저
  /// 2026-08-22: 「각 행들은 독립적인 글로벌행이라 뭐든 가능해야함」). Null
  /// where that rail stands on a row that holds no cels: the V row, the
  /// transition row, a lane.
  ClipboardPlace? get storyboardPlace {
    final standing = _selection.storyboardStandingRow;
    final row = standing is LayerRowAddress
        ? _project.trackSeGlobalLayerById(standing.layerId)
        : null;
    final index = _selection.editingGlobalFrame;
    if (row == null || index < 0) {
      return null;
    }
    final shown = coveringDrawingBlockAt(row.timeline, index)?.frameId;
    return ClipboardPlace._(
      row: row,
      cel: shown == null ? null : row.frameById(shown),
      index: index,
      band: _band,
    );
  }

  /// THE selection as a press reads it, whichever axis it was swept on (the
  /// two are mutually exclusive, so at most one answers) — the rows it
  /// names, and where it starts on each row's OWN axis.
  ///
  /// The cut's band is a run of CELLS — 「the range means exactly its
  /// cells」 — so it moves by the row's axis offset. ⛔Not
  /// `TrackSeDisplay.commitBlockStart`: that names the BLOCK a display start
  /// stands for, and at 0 over a block spilling in from an earlier cut it
  /// answered that block's start there (F-115). The track's band is stated
  /// on the track's axis, which is the axis its rows key.
  ///
  /// ↩️Only the cut's band was read. One swept on the storyboard's S rows
  /// was no selection to this board at all: a copy there banked the one
  /// cell under the cursor, and a paste went in beside the band instead of
  /// replacing it (F-281).
  _ClipboardBand? get _band {
    final inCut = _selection.frameRangeSelection.value;
    if (inCut != null) {
      return _ClipboardBand(
        rows: inCut.spanLayerIds,
        length: inCut.lengthFrames,
        startOn: (row) => inCut.startIndex + _project.rowAxisOffset(row),
        clear: _selection.clearFrameRangeSelection,
      );
    }
    final onTrack = _selection.trackFrameRangeSelection.value;
    if (onTrack == null) {
      return null;
    }
    return _ClipboardBand(
      rows: [
        for (final row in onTrack.spanRows)
          if (row is LayerRowAddress) row.layerId,
      ],
      length: onTrack.lengthFrames,
      startOn: (_) => onTrack.startFrame,
      clear: _selection.clearStoryboardCutSelection,
    );
  }

  bool get canCopyFrameAtCurrentFrame => canCopyAt(timelinePlace);

  bool canCopyAt(ClipboardPlace? place) {
    // 복사 and 잘라내기 are ONE pair by the user's own definition
    // (「복사=원본 남기고 클립 저장 · 잘라내기=원본 지우고 클립 저장」) and
    // share a resolver — [cutAt] literally calls this one. So they must
    // agree about the subject.
    //
    // ⛔The exemption written next to the cut standdown, "COPY is left lit:
    // it only reads", does not survive contact with what copy does: it
    // WRITES the clipboard, which is user state, and under a band naming
    // other rows it wrote the wrong row's run — the same wrong subject
    // that standdown was added for, banked for a later paste.
    if (place == null || place._bandMissesTheRow) {
      return false;
    }
    return place._cel != null;
  }

  bool get canPasteLinkedFrameAtCurrentFrame =>
      canPasteLinkedAt(timelinePlace);

  bool canPasteLinkedAt(ClipboardPlace? place) {
    // Same law as its independent twin: this lands on the row the press
    // stands on and serves only a band that covers it ([_pasteRun]'s
    // `replacing`).
    if (place == null || place._bandMissesTheRow) {
      return false;
    }
    final layer = place._row;
    final copiedFrame = _copiedFrame;
    if (copiedFrame == null ||
        // 🚨I-7 — a link is 「the same cel」, and no cel of another project
        // is a cel of this one: its ids were minted THERE, so the same
        // spelling here names another drawing, or nothing (유저 2026-09-26:
        // 「레이어 id가 다른거?라던가 … 알아서 조심하고」). From another
        // project the copy pastes independent only.
        !identical(copiedFrame.from, this) ||
        !rowHoldsLinks(layer) ||
        // An IMAGE row holds ONE block: once it stands, a second exposure
        // has no place on it ([canPasteIndependentFrameAtCurrentFrame]'s
        // stand-down). ↩️Every image row was turned away, by kind; one
        // standing EMPTY takes its picture back (image-row-cut-paste, 유저
        // 2026-10-04 — the cut's other half, [canCutRunAtCurrentFrame]).
        (layer.kind.holdsSingleCel && !pictureRowStandsEmpty(layer))) {
      return false;
    }
    // 🗣️I-71 — on a row the copy was NOT taken from, the link is by NAME
    // ([_keepsNamesOn]). ↩️Every other row was turned away here: 「is that
    // cel in THIS row」 was the whole of what a link could mean.
    if (layer.id != copiedFrame.layerId) {
      return _keepsNamesOn(layer, copiedFrame) && place._index >= 0;
    }

    // 🚨T3 — the clipboard may be holding cels the layer no longer has: a
    // 잘라내기 lifted them out and orphaned them. They come BACK on the
    // paste (same ids, so it is the same cel), and gating on "the layer
    // still has it" would have made cut-then-paste-back impossible while
    // the button sat lit.
    if (copiedFrame.cels.any((cel) => cel.id == copiedFrame.frameId)) {
      return place._index >= 0;
    }

    return _controllers.timelineController.canPasteLinkedFrameAt(
      layer: layer,
      frameIndex: place._index,
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
  List<_CopiedRow> _copiedRowsBesides(ClipboardPlace place) {
    final band = place._band;
    if (band == null || !band.covers(place._row.id)) {
      return const [];
    }
    final entries = <_CopiedRow>[];
    for (final row in _pasteTargetRowsBesides(place)) {
      final clip = _controllers.timelineController.copyRunForLayer(
        layerId: row.id,
        index: band.startOn(row.id),
        count: band.length,
      );
      entries.add(_copiedRowFor(row, clip));
    }
    return entries;
  }

  /// The cels [clip] carries: the ones [row] holds that its cells actually
  /// point at. The clipboard travels BY VALUE, so what the run exposes has
  /// to come with it — a paste onto another row has no source in
  /// `layer.frames` by definition.
  ///
  /// Each as the row PRINTS it ([_namePrintedOn]): the name a block shows is
  /// the name a linked paste keeps.
  List<Frame> _celsCarriedBy(Layer row, TimelineClipRow clip) {
    final ids = <FrameId>{
      for (final exposure in clip.exposures.values)
        if (exposure.frameId != null) exposure.frameId!,
    };
    final printed = _namePrintedOn(row);
    return [
      for (final cel in row.frames)
        if (ids.contains(cel.id))
          if (printed == null) cel else cel.copyWith(name: printed(cel.id)),
    ];
  }

  /// The name a SYNCED attach row prints each of its drawings with — its
  /// BASE's (UI-R24 #2: a mirror's own cels are unnamed, and its blocks read
  /// the base cel they mirror); null for a row whose drawings wear their own.
  ///
  /// 🗣️I-71 (유저 2026-10-05): 「싱크레이어의 프레임블록이라도 복사는
  /// 가능하도록 … 링크면 이름유지된채로 붙여넣고 독립이면 모두 이름 리셋」.
  /// The name kept is the one on screen.
  String? Function(FrameId cel)? _namePrintedOn(Layer row) {
    if (!isSyncedAttachedLayer(row)) {
      return null;
    }
    final base = attachedBaseOf(
      row,
      _project.activeCutOrNull?.layers ?? const [],
    );
    return (cel) => switch (attachedBaseFrameIdOf(row, cel)) {
      final baseCel? => base?.frameById(baseCel)?.name,
      null => null,
    };
  }

  /// [count] cells off [row] from [index], read off the row AS IT IS SHOWN.
  ///
  /// A synced attach row stores no timeline — it shows its base's blocks
  /// with its own drawings in them ([attachedRowAsShown]) — so the stored
  /// row every other copy reads ([TimelineController.copyRunForLayer]) came
  /// back empty for one: the button was lit, and the paste laid nothing
  /// (I-71, 🧪measured 2026-10-06).
  TimelineClipRow _runCopiedOff(
    Layer row, {
    required int index,
    required int count,
  }) {
    final cut = _project.activeCutOrNull;
    if (cut == null || !isSyncedAttachedLayer(row)) {
      return _controllers.timelineController.copyRunForLayer(
        layerId: row.id,
        index: index,
        count: count,
      );
    }
    // Ghost-free, like the stored row's copy (F-134).
    return captureTimelineRun(
      timeline: ghostFreeTimeline(attachedRowAsShown(row, cut.layers)),
      index: index,
      count: count,
    );
  }

  _CopiedRow _copiedRowFor(Layer row, TimelineClipRow clip) {
    final cels = _celsCarriedBy(row, clip);
    final cut = _project.activeCutOrNull;
    return _CopiedRow(
      layerId: row.id,
      linkable: row.kind.isDrawingCel,
      clip: clip,
      cels: cels,
      sounds: _soundsCarriedBy(row, cels),
      pictures: _picturesCarriedBy(row, cels),
      handwriting: cut == null
          ? const {}
          : conteHandwritingShownBy(
              store: _renderCaches.conteInkRowStore,
              cut: cut.id,
              exposures: clip.exposures.values,
            ),
    );
  }

  /// The pictures [cels] show on [row], as they are NOW ([picturesShownBy])
  /// — taken at the copy, for the reason [_celsCarriedBy] gives.
  Map<FrameId, BitmapSurface> _picturesCarriedBy(Layer row, List<Frame> cels) {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return const {};
    }
    return picturesShownBy(
      store: _renderCaches.brushFrameStore,
      cels: cels,
      keyOf: (cel) => _project.brushFrameKeyForCut(cut, row.id, cel),
    );
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
  /// which is why it needs no rules of its own. What is cut has to be able
  /// to come BACK (the paste's T3 note), and on every row that holds
  /// drawings it can.
  ///
  /// ↩️A SINGLE-CEL (image) row was the ONE exception, for two reasons in
  /// turn:
  /// · the delete gate's (D22) — the covering normalization rebuilt the
  ///   block from the same write, so the press cost a phantom undo entry.
  ///   F-98 gave the image row its empty state and the DELETE was lit;
  /// · then that both pastes stood down there — 「the picture would leave
  ///   for a clipboard no image row takes it from … the cut waits for a
  ///   paste that can land on an image row」.
  /// That paste lands now (image-row-cut-paste, 유저 2026-10-04: a row
  /// standing empty takes the clip's first picture — 「첫장만」,
  /// [_pasteRun]), so the picture row's block is cut by the law every
  /// drawing row's is.
  bool get canCutRunAtCurrentFrame => canCutAt(timelinePlace);

  bool canCutAt(ClipboardPlace? place) {
    // 잘라내기 resolves its run on the row it stands on, so under a band
    // naming other rows it lifts a block the user never swept — and being
    // the destructive half of the clipboard pair, it did so while Delete sat
    // dark one button away on the same pill. No band rung to serve, so
    // the band ends the ladder — and so does COPY, its documented twin:
    // "it only reads" was wrong, since it writes the clipboard.
    if (place == null || place._bandMissesTheRow) {
      return false;
    }
    // 🚨F-107 (유저 2026-09-12: 「불가능한 버튼 비활성화 … 그 외도 있나
    // 확인」) — made STANDING, a cut lifts the block under the playhead, the
    // one Delete takes from the same press. Where none stands — the hold
    // past a block, a synced mirror's borrowed cell — it lifted nothing:
    // the button sat lit, and its press left the row as it was with the
    // drawing copied to the board and the undo stack one step heavier.
    // Measured on a picture row's hold cell, where opening the cut
    // (image-row-cut-paste) would have put that press on every frame but
    // the first. A copy is lit there, and is what that press was.
    //
    // ⚠️Asked AFTER the copy's gate: that one answering yes is what says the
    // row is a row the controller edits — it throws on any other.
    final layer = place._row;
    if (!canCopyAt(place)) {
      return false;
    }
    // A SYNCED attach row's blocks are its BASE's, shown again — it has none
    // of its own to lift, selected or stood on. ↩️Stood on, the line below
    // already said so; with a SELECTION the button was lit (🧪2026-10-06):
    // the press lifted nothing, let the selection go and banked the copy — a
    // 복사 wearing the cut's name. The copy is lit there (I-71), and is what
    // that press was.
    if (isSyncedAttachedLayer(layer)) {
      return false;
    }
    return place._band != null ||
        _controllers.timelineController.blockStandsOn(
          layer.id,
          at: place._index,
        );
  }

  void cutRunAtCurrentFrame() => cutAt(timelinePlace);

  void cutAt(ClipboardPlace? place) {
    final frame = place?._cel;
    if (place == null || frame == null || !canCutAt(place)) {
      return;
    }
    final layer = place._row;
    final run = _runAt(place);
    // ↩️F-277 (유저 2026-10-04): 「프레임 복사 붙여넣기시, 선택하지 않은채로
    // 그냥 블록에 선 채로 복사하면 붙여넣을때 1코마로 붙여넣는거처럼, 잘라내기도
    // 선택안하고 동일한 상황에서 잘라내면 1코마로 붙여넣도록」 — the cut banks
    // the clip a copy banks from the same press ([_clipToBank]): a
    // selection's run, or standing, ONE comma of the drawing.
    //
    // It read: 「⛔NOT copyFrameAtCurrentFrame: standing, a copy banks ONE
    // comma now (F-152) while this lifts the whole block — banking less than
    // it lifts would make it a delete (결정 14 ②ⓐ). A cut banks exactly what
    // it lifts.」 What 결정 14 ②ⓐ guards still stands where it was decided:
    // every ROW lifted is banked (below), and the DRAWING a standing cut
    // lifts is on the board, to come back. What stays behind is the block's
    // commas — as they do when the same block is copied.
    _bank(place: place, frame: frame, clip: _clipToBank(place, frame));
    // 🚨결정 14 ②ⓐ — the lift takes every row the copy just banked, in ONE
    // undo. ⛔It reads the CLIPBOARD's rows rather than re-resolving the
    // band: the two must not be able to disagree about which rows were
    // taken, because a row lifted but not banked is work that cannot come
    // back — 「클립보드가 담지 않은 것을 들어내면 그건 삭제지 잘라내기가
    // 아니다」.
    final band = place._band;
    final banked = bankedRowLayerIds;
    _controllers.timelineController.spliceRunsForLayers(
      runs: [
        for (final bankedLayerId in banked)
          (
            layerId: bankedLayerId,
            index: bankedLayerId == layer.id
                ? run.index
                : band!.startOn(bankedLayerId),
            liftCount: bankedLayerId == layer.id ? run.count : band!.length,
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
    band?.clear();
    _changes.notifyChanged();
  }

  void copyFrameAtCurrentFrame() => copyAt(timelinePlace);

  void copyAt(ClipboardPlace? place) {
    final frame = place?._cel;
    if (place == null || frame == null || !canCopyAt(place)) {
      return;
    }
    _bank(place: place, frame: frame, clip: _clipToBank(place, frame));
  }

  /// The clip a copy — or a 잘라내기 (F-277) — of [frame] on [layer] banks.
  ///
  /// 🚨★★WHAT A COPY BANKS DEPENDS ON WHETHER SOMETHING IS SELECTED
  /// (F-152, 유저 2026-09-16): 「프레임 복붙할때 그냥 그곳에 서있을떄
  /// 복사한거면 … 붙혀넣을때 1콤마로서 붙혀넣게. 해당 블록을 선택해서
  /// 복사하면 콤마 유지되도록」.
  ///
  /// • SELECTED — the selection's run, commas and gaps and all. That is
  ///   T3's rule (「프레임만 복붙이 아니라 코마까지 포함해서 블록 자체를
  ///   복붙한다는 느낌」), and selecting the block is how it is asked for.
  /// • STANDING — ONE cell of the drawing the cell SHOWS.
  ///
  /// ⚠️That second line is also F-140 (유저 2026-09-16: 「복사버튼이
  /// 작동하는건 좋은데 지금 붙여넣기해도 아무일 안일어나니까」). Standing on a
  /// hold's GHOST, the run was the ghost's span read off the GHOST-FREE row
  /// (F-134) — every cell of it empty — so the copy banked nothing while
  /// its button, lit by the drawing on screen, promised that drawing.
  /// [_oneCellOf] banks what is shown, a real cell, wherever it came from.
  ///
  /// ⚠️One comma of the DRAWING, not of the block: the memo, the dots and
  /// the edge properties are the BLOCK's ([TimelineExposure.memo] — 「re-
  /// exposing the same drawing gets its own」), and a hold edge riding
  /// along would ghost the paste past the one comma it was asked to be.
  ///
  /// ⛔The gate leaves no third case: a selection that misses this row
  /// stood the press down ([canCopyAt]).
  TimelineClipRow _clipToBank(ClipboardPlace place, Frame frame) {
    final run = place._band == null ? null : _runAt(place);
    return run == null
        ? _oneCellOf(frame.id)
        : _runCopiedOff(place._row, index: run.index, count: run.count);
  }

  /// One comma of [frameId] — the whole clip a copy or a cut with nothing
  /// selected banks.
  static TimelineClipRow _oneCellOf(FrameId frameId) =>
      TimelineClipRow.untimed(TimelineExposure.drawing(frameId, length: 1));

  /// Puts [clip] on the board as the copy of [frame] on [layer] — the
  /// half a copy and a 잘라내기 share, clip and all ([_clipToBank]).
  /// ↩️The clip used to differ: a cut banked the whole run it lifts (결정 14
  /// ②ⓐ — 「클립보드가 담지 않은 것을 들어내면 그건 삭제지 잘라내기가
  /// 아니다」) where a standing copy banked one comma. F-277 made the two one
  /// ([cutRunAtCurrentFrame]).
  void _bank({
    required ClipboardPlace place,
    required Frame frame,
    required TimelineClipRow clip,
  }) {
    final layer = place._row;
    final cels = _celsCarriedBy(layer, clip);
    // 🚨결정 14 ②ⓐ — the board takes EVERY swept row, the anchor first.
    final rows = [_copiedRowFor(layer, clip), ..._copiedRowsBesides(place)];
    _board._take(_CopiedFrameReference(
      from: this,
      layerId: layer.id,
      frameId: frame.id,
      frameName: frame.name,
      clip: clip,
      cels: cels,
      sounds: _soundsCarriedBy(layer, cels),
      rows: rows,
      names: namesOfACopy(
        project: _project.repository.requireProject(),
        media: {
          for (final row in rows)
            for (final sound in row.sounds) sound.filePath,
        },
        terms: termsSpelledBy([
          for (final row in rows) ...row.clip.exposures.values,
        ]),
        bytesOf: _mediaBytesOf,
      ),
    ));
    _changes.notifyChanged();
  }

  /// Whether a paste here must first HOLD the bytes of media the copy
  /// carries from another project — the UI's cue for its wait window
  /// (F-53: every wait has one).
  @override
  bool get pasteMustHoldMedia =>
      _held.mustHold(_copiedFrame, _project.repository.requireProject());

  /// Holds them — as carries of THIS project's own, staged before anything
  /// records them ([holdCarriedMediaOf]) — for the next paste of the copy.
  @override
  Future<void> holdWhatThePasteBrings() => _held.hold(
    _copiedFrame,
    _project.repository.requireProject(),
    _staging,
  );

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
  ///
  /// ↩️"Shared" was four conditions spelled a second time here, and the
  /// copy had gone stale: F-98 let a picture row standing EMPTY be authored
  /// into ([rowTakesNewCels]) while this door kept turning every image row
  /// away by kind. It asks the one answer now, which is what opens
  /// image-row-cut-paste (유저 2026-10-04): an empty picture row takes a
  /// paste — the clip's first picture ([_pasteRun]).
  bool get canPasteIndependentFrameAtCurrentFrame =>
      canPasteIndependentAt(timelinePlace);

  bool canPasteIndependentAt(ClipboardPlace? place) {
    // The paste lands on the row the press stands on, and its band rung
    // serves only a band that covers that row (`replacing` in [_pasteRun] —
    // 「복붙은 선택하고 붙여넣기가 기본」). A band naming other rows makes it
    // a plain insert on a row the user never swept, and the highlight then
    // stays put, because the clear runs on the replacing path alone.
    if (place == null || place._bandMissesTheRow) {
      return false;
    }
    final layer = place._row;
    if (_copiedFrame == null) {
      return false;
    }
    // The row's half of every door that makes a cel ([rowTakesNewCels]): a
    // direction row pastes blocks like every cel row (its span rides the
    // block it is, R27); a SYNCED attach row owns no timeline of its own; a
    // reference row's picture comes from the library; an IMAGE row holds
    // ONE cel, and takes one only while it stands empty.
    if (!rowTakesNewCels(layer)) {
      return false;
    }
    return place._index >= 0;
  }

  void pasteIndependentFrameAtCurrentFrame() =>
      pasteIndependentAt(timelinePlace);

  void pasteIndependentAt(ClipboardPlace? place) {
    final copiedFrame = _copiedFrame;
    if (place == null ||
        copiedFrame == null ||
        !canPasteIndependentAt(place)) {
      return;
    }
    _pasteRun(place: place, copied: copiedFrame, independent: true);
  }

  /// 링크 붙여넣기. Null when it pasted, or had nothing to do.
  ///
  /// 🗣️I-71 (유저 2026-10-05): 「해당행동시 기존에 이름 존재한다면 링크시킬지
  /// 묻는것도 띄우고」. On a row the copy was not taken from, a pasted block
  /// whose name the row already holds shows the row's OWN drawing of that
  /// name and the copied picture is not brought ([ClipLanding.sameNames]) —
  /// so where that would happen and [joinTakenNames] was not given, this
  /// writes NOTHING and hands back what it would join, for the caller to ask
  /// about once. The rename's own contract ([FrameVerbs.renameSelectedFrame]:
  /// the conflict comes back 「without mutating so the caller can offer to
  /// link instead」).
  LinkedPasteJoins? pasteLinkedFrameAtCurrentFrame({
    bool joinTakenNames = false,
  }) => pasteLinkedAt(timelinePlace, joinTakenNames: joinTakenNames);

  LinkedPasteJoins? pasteLinkedAt(
    ClipboardPlace? place, {
    bool joinTakenNames = false,
  }) {
    final copiedFrame = _copiedFrame;
    if (place == null || copiedFrame == null || !canPasteLinkedAt(place)) {
      return null;
    }
    if (!joinTakenNames) {
      final joins = _joinsOf(_landingsOn(place, copiedFrame));
      if (joins.isNotEmpty) {
        return joins;
      }
    }
    _pasteRun(place: place, copied: copiedFrame, independent: false);
    return null;
  }

  /// Whether a 링크 붙여넣기 of [copied] has anything to do on [layer], a row
  /// it was NOT copied from — the name-keeping paste (I-71).
  ///
  /// It makes drawings there, so the row has to take them
  /// ([rowTakesNewCels]) and to WEAR names: a direction row's drawings have
  /// none (유저 2026-09-12: 「이름없으면 독립적인거니까」). And the copy has
  /// to be one of NAMED drawings — with no name to keep, the press would be
  /// the independent paste under another button, and that button alone is
  /// lit (F-115, said of the SE row: 「링크붙여넣기의 차이점이 없기때문」).
  bool _keepsNamesOn(Layer layer, _CopiedFrameReference copied) =>
      rowTakesNewCels(layer) &&
      !layer.kind.spansRideBlocks &&
      (copied.rows.firstOrNull?.linkable ?? false) &&
      copied.cels.any((cel) => cel.name != null);

  /// 결정 14 ②ⓐ×③ⓐ — EVERY ROW a paste on [layer] lands on, each with the
  /// row of the board it receives.
  ///
  /// A ONE-row clip goes to every target (③ⓐ: 「모든 행에 같은 것을」). A
  /// clip that already holds several rows pairs with them IN ORDER — there
  /// is no other reading that preserves what was copied — and the pairing
  /// stops when the board runs out, because a target with no row to receive
  /// has nothing to be given.
  List<_PasteLanding> _landingsOn(
    ClipboardPlace place,
    _CopiedFrameReference copied,
  ) {
    final board = copied.rows;
    final landings = <_PasteLanding>[];
    for (final (i, target) in [
      place._row,
      ..._pasteTargetRowsBesides(place),
    ].indexed) {
      if (board.length > 1 && i >= board.length) {
        break;
      }
      // The anchor row is the board's first — the pictures live on rows.
      final mine = board[board.length <= 1 ? 0 : i];
      final clip = board.length <= 1 ? copied.clip : mine.clip;
      landings.add((
        target: target,
        source: board.length <= 1 ? copied.layerId : mine.layerId,
        linkable: mine.linkable,
        // 🗣️image-row-cut-paste (유저 2026-10-04): 「첫장만」 — a row that
        // holds ONE picture takes the clip's first, as one comma. The write
        // lays that as the row's held block; a second cel minted beside it
        // would sit in the bank with nothing showing it.
        clip: target.kind.holdsSingleCel ? _firstPictureOf(clip) : clip,
        cels: board.length <= 1 ? copied.cels : mine.cels,
        sounds: board.length <= 1 ? copied.sounds : mine.sounds,
        pictures: mine.pictures,
        handwriting: mine.handwriting,
      ));
    }
    return landings;
  }

  /// How [landing]'s row of the board lands by a 링크 붙여넣기: the SAME
  /// drawings on the row it was copied from; on any other, its names kept
  /// (I-71) — where the copy is one of drawings and the row wears names
  /// ([_keepsNamesOn]) — and else as drawings of the row's own.
  static ClipLanding _linkLandingOf(_PasteLanding landing) =>
      landing.target.id == landing.source
      ? ClipLanding.sameDrawings
      : landing.linkable && !landing.target.kind.spansRideBlocks
      ? ClipLanding.sameNames
      : ClipLanding.ownDrawings;

  /// The drawings a 링크 붙여넣기 of [landings] would JOIN, by row: the row's
  /// own that already answer to a name being pasted
  /// ([drawingsHeldUnderTheNamesOf]). Empty when it links nothing by name.
  static LinkedPasteJoins _joinsOf(List<_PasteLanding> landings) => [
    for (final landing in landings)
      if (_linkLandingOf(landing) == ClipLanding.sameNames)
        if (drawingsHeldUnderTheNamesOf(landing.target, (
              clip: landing.clip,
              cels: landing.cels,
            ))
            case final held when held.isNotEmpty)
          (layerId: landing.target.id, held: {...held.values}.toList()),
  ];

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
  /// ⚠️The kind filter is the paste gate's own: a SYNCED attach row has no
  /// timing of its own, and a SINGLE-CEL row holds one block the covering
  /// normalization keeps — a paste into either writes something the next
  /// normalize takes straight back out. ↩️It was called 「the delete
  /// collector's」 while that collector passed image rows over; the delete
  /// takes an image row's block now (F-98), and a paste still has no second
  /// place on one.
  ///
  /// ⚠️NOT the gate's any more, for one row: the press with no band lands
  /// on a picture row standing EMPTY (image-row-cut-paste), and a band
  /// still passes every picture row over, empty or not. That is kept on
  /// purpose, undecided rather than decided: these are also the rows a
  /// copy TAKES ([_copiedRowsBesides]), the board pairs its rows with the
  /// targets IN ORDER ([_pasteRun]), and a filter that changed with what a
  /// row holds would pair a clip with another row's seat the moment the
  /// row was emptied between the copy and the paste. What a band does with
  /// a picture row is asked on the board (image-row-cut-paste-Q1).
  List<Layer> _pasteTargetRowsBesides(ClipboardPlace place) {
    final band = place._band;
    final anchor = place._row;
    if (band == null || !band.covers(anchor.id)) {
      return const [];
    }
    final rows = <Layer>[];
    for (final id in band.rows) {
      if (id == anchor.id) {
        continue;
      }
      final row = _project.rangeLayerById(id);
      if (row == null ||
          !row.kind.takesAuthoredCels ||
          row.kind.holdsSingleCel ||
          isSyncedAttachedLayer(row)) {
        continue;
      }
      rows.add(row);
    }
    return rows;
  }

  void _pasteRun({
    required ClipboardPlace place,
    required _CopiedFrameReference copied,
    required bool independent,
  }) {
    // A paste lands with what the copy names and this project lacks — its
    // media, its terms, spelled as this project spells them (I-7). From
    // another project that is what makes the row whole; at home it is, as a
    // rule, nothing ([HeldArrival]).
    final arrival = _held.arrivalFor(
      copied,
      _project.repository.requireProject(),
    );
    final layer = place._row;
    final run = _runAt(place);
    // ⛔A selection REPLACES what it covers; with none, nothing comes out.
    // 「뭘 선택하든 덮어써버리면 선택범위를 조절하는 의미가 통째로 사라지잖아」
    final band = place._band;
    final replacing = band != null && band.covers(layer.id);
    // F-115: with nothing selected the clip goes in at the cursor ON THE
    // ROW'S OWN AXIS ([ClipboardPlace]) — a track-owned SE row keys the
    // track's frames, and the cut-local index landed it on an earlier cut's.
    final index = replacing ? run.index : place._index;
    final liftCount = replacing ? run.count : 0;

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
    // Which handwriting each pasted block starts as a copy of, per row —
    // linked or not, a block writes on the conte for itself.
    final handwritten =
        <(Map<String, String>, Map<String, BitmapSurface>)>[];
    for (final landing in _landingsOn(place, copied)) {
      final target = landing.target;
      // ⚠️ONCE per row. The independent branch MINTS inside here, so asking
      // twice would coin two sets of cels and reference only one of them —
      // the layer would carry orphans nothing points at.
      final placed = placedClipFor(
        layer: target,
        row: (
          clip: _respelled(landing.clip, arrival.respell),
          cels: landing.cels,
          sounds: landing.sounds,
        ),
        landing: independent
            ? ClipLanding.ownDrawings
            : _linkLandingOf(landing),
        ids: _frameIds,
      );
      if (placed.minted.isNotEmpty) {
        mintedByLayer.add((target.id, placed.minted, landing.pictures));
      }
      if (placed.handwriting.isNotEmpty) {
        handwritten.add((placed.handwriting, landing.handwriting));
      }
      runs.add((
        layerId: target.id,
        // Each row places the band's start on ITS OWN axis ([_band]): two
        // rows swept together need not key the same frames — a track-owned
        // SE row keys the track's.
        index: replacing ? band.startOn(target.id) : index,
        liftCount: liftCount,
        clip: placed.clip,
        bornFrames: placed.born,
        bornSounds: placed.bornSounds,
      ));
    }
    final description = independent ? 'Paste frames' : 'Paste linked frames';
    // ONE undo for the paste and what it brought.
    _project.historyManager.runAsOneStep(description, () {
      landArrival(_project, arrival);
      _controllers.timelineController.spliceRunsForLayers(
        runs: runs,
        description: description,
      );
    });
    final cut = _project.activeCutOrNull;
    for (final (targetId, minted, pictures) in mintedByLayer) {
      if (cut == null) {
        break; // Gap state: no cut, so no key to store a picture under.
      }
      carryBakedPictures(
        project: _project,
        store: _renderCaches.brushFrameStore,
        cut: cut,
        to: targetId,
        minted: minted,
        pictureOf: (source) => pictures[source],
      );
    }
    for (final (copies, handwriting) in handwritten) {
      if (cut == null) {
        break;
      }
      carryConteHandwriting(
        store: _renderCaches.conteInkRowStore,
        cut: cut.id,
        copies: copies,
        handwritingOf: (inkId) => handwriting[inkId],
      );
    }
    if (replacing) {
      band.clear();
    }
    _changes.notifyChanged();
  }

  /// The first drawing [clip] shows, as ONE comma — what a row that holds a
  /// single picture takes of a clip. A clip showing no drawing comes back as
  /// it is.
  ///
  /// The cels stay the board's: a cel is minted per drawing the clip SHOWS
  /// ([placedClipFor]), so the ones this leaves out mint nothing.
  static TimelineClipRow _firstPictureOf(TimelineClipRow clip) {
    for (final exposure in clip.exposures.values) {
      final id = exposure.frameId;
      if (exposure.isDrawing && id != null) {
        return _oneCellOf(id);
      }
    }
    return clip;
  }

  /// [clip] with every block's term spelled as [respell] says — a copy from
  /// another project spells its custom terms that project's way ([Arrival]).
  static TimelineClipRow _respelled(
    TimelineClipRow clip,
    Map<String, String> respell,
  ) {
    if (respell.isEmpty) {
      return clip;
    }
    return clip.withExposures({
      for (final MapEntry(key: index, value: exposure)
          in clip.exposures.entries)
        index: respelledExposure(exposure, respell),
    });
  }

  /// WHERE a copy, cut or paste acts on [place]'s row, in COMMIT keys.
  ///
  /// ★The one place the two halves of 「N칸을 들어내고 클립을 넣는다」 get
  /// their N: a live selection says its own range, and with none the verb
  /// means the block under the cursor. Copy, cut and paste all ask this,
  /// so they cannot disagree about what "the run" is — except that with
  /// nothing selected the BANK no longer asks: it holds one comma, a copy's
  /// (F-152) and a cut's (F-277) alike. The cut still asks it for what it
  /// LIFTS.
  ///
  /// ⚠️The ROW is the place's alone. T3's multi-row anchoring
  /// (「선택의 첫 행을 현재 행에 맞춘다」) needs a rail-display-order source
  /// the session does not have — [TimelineController.spliceRunsForLayers]
  /// already takes a list so the extension is additive, but nothing here
  /// pretends to do it yet.
  ///
  /// 🚨F-115 — BOTH halves answer on the ROW'S OWN axis (유저 2026-09-12:
  /// 「지금 붙여넣기하면 기존 블럭이 이상하게 움직일뿐 붙여넣어지지않음」). A
  /// selection's cells start where the band says on that row ([_band]);
  /// with nothing selected the controller answers from the row it edits
  /// ([TimelineController.runAtForLayer] — the block Delete takes from the
  /// same press). The unselected half used to come off the cut-local
  /// display clone, which on a track-owned SE row past the first cut read,
  /// lifted and inserted on an earlier cut's frames.
  ({int index, int count}) _runAt(ClipboardPlace place) {
    final row = place._row.id;
    final band = place._band;
    if (band != null && band.covers(row)) {
      return (index: band.startOn(row), count: band.length);
    }
    return _controllers.timelineController.runAtForLayer(row, place._index);
  }

  // --- 링크 독립 (I-45): the frame-axis rung ------------------------------

  /// Of [runs], the cels also shown somewhere ELSE — per row, the ids a
  /// link-independent press gives copies of their own.
  ///
  /// Shown elsewhere is 「the same picture exposed again」, which is all a
  /// link is (F-115): a block of this row outside its run (a link paste,
  /// Ctrl+B), or a block of a row linked to this one (링크 복제 · 겸용컷 —
  /// one cel bank, so one id per picture). ⛔Ghosts are not showings: a
  /// hold's ghost is its own block going on, not a second exposure.
  Map<LayerId, Set<FrameId>> sharedCelsIn(List<UnlinkRun> runs) {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return const {};
    }
    final registry = _project.repository.requireProject().linkRegistry;
    final shared = <LayerId, Set<FrameId>>{};
    for (final run in runs) {
      final end = run.index + run.count;
      final inRun = <FrameId>{};
      final elsewhere = <FrameId>{};
      for (final MapEntry(key: start, value: exposure)
          in run.layer.timeline.entries) {
        final id = exposure.frameId;
        if (id == null || exposure.ghost) {
          continue;
        }
        (start >= run.index && start < end ? inRun : elsewhere).add(id);
      }
      final group = registry.groupOf(cutId: cut.id, layerId: run.layer.id);
      for (final member in group?.members ?? const <LayerLinkMember>[]) {
        if (member.cutId == cut.id && member.layerId == run.layer.id) {
          continue;
        }
        final row = _project
            .cutById(member.cutId)
            ?.layers
            .where((layer) => layer.id == member.layerId)
            .firstOrNull;
        for (final exposure
            in row?.timeline.values ?? const <TimelineExposure>[]) {
          if (exposure.frameId case final id? when !exposure.ghost) {
            elsewhere.add(id);
          }
        }
      }
      final both = inRun.intersection(elsewhere);
      if (both.isNotEmpty) {
        shared[run.layer.id] = both;
      }
    }
    return shared;
  }

  /// 🚨I-45 — 링크 독립 on the frame axis: every cel of [runs] that is also
  /// shown somewhere else gets a copy of its own, and its run points at the
  /// copy. ONE undo step for every row.
  ///
  /// ★It IS the independent paste of each run's own cells over themselves
  /// — the same capture, the same mint ([mintIndependentClip]), the same
  /// splice and the same carried pictures — except that only SHARED cels are
  /// minted. A cel nobody else shows is independent already, and minting it
  /// would only take its name away (a minted cel comes out unnamed: a name is
  /// the cel's identity, [placedClipFor]).
  ///
  /// ⚠️ONE run per row: the splice plans every run against the row as it was
  /// before the step, so two runs on one row would overwrite each other.
  void unlinkRuns(List<UnlinkRun> runs) {
    final shared = sharedCelsIn(runs);
    if (shared.isEmpty) {
      return;
    }
    final splices =
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
    final mintedByLayer = <(LayerId, Map<FrameId, FrameId>)>[];
    final riders = <SpliceRider>[];
    for (final run in runs) {
      final ids = shared[run.layer.id];
      if (ids == null) {
        continue;
      }
      final clip = _controllers.timelineController.copyRunForLayer(
        layerId: run.layer.id,
        index: run.index,
        count: run.count,
      );
      final copies = mintIndependentClip(
        clip: clip.withExposures({
          for (final entry in clip.exposures.entries)
            if (ids.contains(entry.value.frameId)) entry.key: entry.value,
        }),
        from: [(cels: run.layer.frames, sounds: run.layer.audioClips)],
        namesAreIdentity: run.layer.kind.celNameIsIdentity,
        mint: () => _frameIds.mintFrameId(run.layer.id),
      );
      splices.add((
        layerId: run.layer.id,
        index: run.index,
        liftCount: run.count,
        clip: clip.withExposures({
          ...clip.exposures,
          ...copies.clip.exposures,
        }),
        bornFrames: copies.born,
        bornSounds: copies.bornSounds,
      ));
      mintedByLayer.add((run.layer.id, copies.minted));
      // F-275: the synced attach rows riding this row keep their pictures of
      // the cels re-cut — born in the same step, carried by the same loop.
      for (final mirrors in _mirrorCopiesRiding(run.layer, copies.minted)) {
        riders.add((
          layerId: mirrors.layerId,
          bornFrames: mirrors.born,
          bornBaseLinks: mirrors.baseLinks,
        ));
        mintedByLayer.add((mirrors.layerId, mirrors.minted));
      }
    }
    _controllers.timelineController.spliceRunsForLayers(
      runs: splices,
      description: 'Unlink frames',
      riders: riders,
    );
    final cut = _project.activeCutOrNull;
    if (cut != null) {
      final store = _renderCaches.brushFrameStore;
      for (final (layerId, minted) in mintedByLayer) {
        carryBakedPictures(
          project: _project,
          store: store,
          cut: cut,
          to: layerId,
          minted: minted,
          pictureOf: (source) => store.bakedSurfaceOrNull(
            _project.brushFrameKeyForCut(cut, layerId, source),
          ),
        );
      }
    }
    _changes.notifyChanged();
  }

  /// The mirrors [base]'s synced attach rows keep of the cels [minted]
  /// re-cut ([mirrorCopiesFor]) — each minted under its link group's row,
  /// as the settle mints them (F-278).
  List<MirrorCopies> _mirrorCopiesRiding(
    Layer base,
    Map<FrameId, FrameId> minted,
  ) {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return const [];
    }
    final project = _project.repository.requireProject();
    return mirrorCopiesFor(
      attachedRows: attachedLayersOf(
        base.id,
        cut.layers,
      ).where(isSyncedAttachedLayer),
      baseMinted: minted,
      mintedUnder: (attached) =>
          attachedMirrorGroupOf(
            project,
            cutId: cut.id,
            attached: attached,
          )?.mintedUnder ??
          attached.id,
    );
  }
}

/// One row's run for [FrameClipboard.unlinkRuns] — in the row's own COMMIT
/// keys, the ones [TimelineController.copyRunForLayer] reads.
typedef UnlinkRun = ({Layer layer, int index, int count});

/// What a 링크 붙여넣기 would JOIN, by row: on each row it lands on, the
/// row's own drawings that already answer to a name being pasted — the
/// drawings its blocks would show instead of the copied ones
/// ([FrameClipboard.pasteLinkedFrameAtCurrentFrame], I-71).
typedef LinkedPasteJoins = List<({LayerId layerId, List<FrameId> held})>;

/// One row a paste lands on, with the row of the board it receives: where
/// that was copied from ([source], [linkable]) and what it carries.
typedef _PasteLanding = ({
  Layer target,
  LayerId source,
  bool linkable,
  TimelineClipRow clip,
  List<Frame> cels,
  List<AudioClip> sounds,
  Map<FrameId, BitmapSurface> pictures,
  Map<String, BitmapSurface> handwriting,
});

/// Whether [layer] is a row a LINK can live on — the linked paste's gate and
/// 링크 독립's, stated once.
///
/// • F-115 (유저 2026-09-12): 「se 블록 복붙, 우선 복사하고나서는 독립
///   붙여넣기만 가능. 왜냐하면 링크붙여넣기의 차이점이 없기때문」. A link is
///   겸용 — the same PICTURE exposed again — and a row whose cels hold no
///   artwork has none to reuse.
/// • SYNCED attach rows own no timeline — linked reuse happens through the
///   BASE's links (link the base cel instead). Free attach rows author
///   normally (UI-R21 #3).
/// • ↩️An IMAGE row was turned away here too, for the linked paste's reason
///   — a second exposure on a row that holds one block (D22). That is the
///   PASTE's stand-down and it says so there
///   ([FrameClipboard.canPasteLinkedFrameAtCurrentFrame]); a link itself
///   lives on an image row like on any drawing row — its picture shared
///   with a 겸용 cut by name — and 링크 독립 gives it a copy of its own
///   (유저 2026-10-04: 「이미지레이어도 타임라인 링크독립버튼 가능하도록.
///   작동하면 애니메이션레이어와 동일하게 이름이 사라짐. 독립적인 개체로
///   돌아가는것」).
bool rowHoldsLinks(Layer layer) =>
    layer.kind.isDrawingCel && !isSyncedAttachedLayer(layer);

/// WHERE a clipboard press acts: the row a panel's cursor stands on, where
/// on that row's OWN axis, and THE selection.
///
/// 🗣️F-281 (유저 2026-10-04): 「se행의 복사,붙여넣기, 타임라인패널에선 되는데
/// 콘티패널에선 se블록을 복사가 안됨. 로컬이든 글로벌이든 가능하도록 통일.
/// 다른 로컬/글로벌 트랙 존재하는 행도 마찬가지 법 통일」.
///
/// ↩️The board read its place off the CUT's view — the active layer, the
/// cut's playhead, the cut's band — so the timeline was the only panel that
/// could press it. The storyboard stood on the very same sound, at the same
/// frame, and every button of the four was dark; parked in a gap, with no
/// cut to have an active layer, both panels' were (🧪measured 2026-10-06).
/// The verbs take the place now, and a panel answers only where it stands
/// ([FrameClipboard.timelinePlace] · [FrameClipboard.storyboardPlace]) — the
/// comma's shape (F-283).
///
/// Opaque outside this file: a panel hands one on, it does not read it.
class ClipboardPlace {
  const ClipboardPlace._({
    required Layer row,
    required Frame? cel,
    required int index,
    required _ClipboardBand? band,
  }) : _row = row,
       _cel = cel,
       _index = index,
       _band = band;

  final Layer _row;

  /// The drawing the cursor's cell SHOWS — a hold's ghost included (F-140).
  /// Null on an empty cell.
  final Frame? _cel;

  /// The cursor on [_row]'s own axis, in the keys its commit form stores.
  final int _index;

  final _ClipboardBand? _band;

  /// Whether THE selection names rows this press would MISS — the law
  /// [SelectionAccess.bandNamesRowsThisPressWouldMiss] states for the cut's
  /// band, asked of whichever band is up.
  bool get _bandMissesTheRow {
    final band = _band;
    return band != null && !band.covers(_row.id);
  }
}

/// THE selection as the clipboard reads it ([FrameClipboard._band]).
class _ClipboardBand {
  const _ClipboardBand({
    required this.rows,
    required this.length,
    required this.startOn,
    required this.clear,
  });

  /// The cel rows it names, in the span's own order.
  final List<LayerId> rows;

  /// How many cells it covers on each.
  final int length;

  /// Where it starts on a row, on that row's OWN axis.
  final int Function(LayerId row) startOn;

  /// Lets the selection go — a cut's and a replacing paste's last step.
  final void Function() clear;

  bool covers(LayerId row) => rows.contains(row);
}

/// 🚨결정 14 ②ⓐ (유저 확정 2026-08-22) — ONE ROW OF THE CLIPBOARD.
///
/// The board held a single row until copy learned the band. It holds a LIST
/// now, and this is one entry: which row it came from, the run of cells, and
/// the cels those cells point at.
class _CopiedRow {
  const _CopiedRow({
    required this.layerId,
    required this.linkable,
    required this.clip,
    this.cels = const [],
    this.sounds = const [],
    this.pictures = const {},
    this.handwriting = const {},
  });

  final LayerId layerId;

  /// Whether the row this was copied off holds DRAWINGS — what a link names.
  /// Taken at the copy, like everything a row of the board holds: the paste
  /// may stand in a cut that row is not in (F-161).
  ///
  /// F-115 (유저 2026-09-12): an SE row's copy 「독립 붙여넣기만 가능.
  /// 왜냐하면 링크붙여넣기의 차이점이 없기때문」 — its cels hold no artwork,
  /// and their names (the dialogue) repeat. A synced attach row's copy is
  /// one of drawings (I-71), though the row itself takes no paste.
  final bool linkable;
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

  /// The handwriting the clip's blocks showed on the conte when they were
  /// copied, by each block's id — BY VALUE for [pictures]' reason. A block
  /// never written on is simply absent.
  final Map<String, BitmapSurface> handwriting;
}

/// What the app holds from the last FRAME copy — ONE board for every open
/// project (I-7, `AppClipboard`); each project's [FrameClipboard] reads and
/// writes it.
///
/// 🚨★★THE COPY IS ALWAYS IN HAND (F-161, 유저 2026-09-17): 「복붙은
/// 어디서든 가능하게 … 복사는 항상 언제든 들고있게. 컷2의 레이어에서
/// 붙여넣기 가능. 복사는 언제나 하나 들고있음. 보통 프로그램이 그러니까」.
/// F-152 (09-16) had asked it inside one cut first: 「복사하고 무언가
/// 붙혀넣는다고 해서 복사한게 사라지지않게. 복사한거는 들고있음」. Only the
/// next copy replaces it.
///
/// ↩️What threw it away: every cut switch, gap park and cut-command
/// refresh — so an UNDO after a paste emptied it too (measured, F-152).
/// That drop predates the board carrying its cels, its sounds and now its
/// PICTURES by value ([_CopiedRow.pictures]); nothing it holds names a
/// place in one cut any more, so no cut change can make it stale.
///
/// ↩️And the project replaced (I-7): the board was the session's and went
/// with the project it was copied in, back when the app held one project.
/// It is the app's now, and opening or closing a project leaves it where it
/// is — what it holds is by value, and [_CopiedFrameReference.from] says
/// which project its ids are ids of.
class FrameBoard {
  _CopiedFrameReference? _copy;

  /// What this board taking a copy lets go of: the pill's other board
  /// (`AppClipboard`, I-77).
  void Function()? onTake;

  void _take(_CopiedFrameReference copy) {
    _copy = copy;
    onTake?.call();
  }

  /// Lets go of what it holds: the hand took a copy of the other kind.
  void letGo() => _copy = null;

  /// The pictures the copy holds, every swept row's — the memory census's
  /// to weigh.
  Iterable<BitmapSurface> get heldPictures => [
    for (final row in _copy?.rows ?? const <_CopiedRow>[])
      ...row.pictures.values,
  ];
}

class _CopiedFrameReference implements BoardCopy {
  const _CopiedFrameReference({
    required this.from,
    required this.names,
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

  /// The clipboard that banked it — the PROJECT whose ids [layerId], [frameId]
  /// and every cel below are. A linked paste serves only that project
  /// ([FrameClipboard.canPasteLinkedFrameAtCurrentFrame]).
  final FrameClipboard from;

  /// What the copy names in that project besides its ids — the media its
  /// sounds play, the terms its blocks spell — for a paste elsewhere.
  @override
  final CopiedNames names;

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
