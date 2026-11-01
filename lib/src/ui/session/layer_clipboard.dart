import '../../models/attached_layer_mount.dart';
import '../../models/attached_layer_resolve.dart';
import '../../models/bitmap_surface.dart';
import '../../models/cut.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/new_row_placement.dart' show seatAboveRow;
import '../../models/track_transitions.dart' show cutDrawnFrameCount;
import '../../services/clipboard/layer_copy_payload.dart';
import '../../services/commands/cut_command_coordinator.dart' show PastedLayer;
import '../../services/media/media_byte_source.dart' show MediaByteSource;
import '../../services/persistence/media_staging_store.dart';
import 'independent_clip_mint.dart';
import 'layer_stack.dart';
import 'layer_verbs.dart';
import 'render_caches.dart';
import 'row_selection.dart';
import 'session_roles.dart';
import 'what_a_copy_brings.dart';

/// The LAYER CLIPBOARD — the rows the user copied, and pasting them into a
/// cut — as its own object.
///
/// 🚨Split out of `FrameClipboard` (G0-2, 2026-09-06). A frame board and a
/// layer board are two boards: they hold different payloads, answer to
/// different verbs, and the only thing they shared was the object that
/// happened to hold both. What kept them together was that one class held
/// them, which is not a reason.
///
/// 🗣️I-77 (유저 2026-10-06): 「복사/붙여넣기버튼 레이어도 연결. 레이어 선택,
/// 다중선택등에서 복사 붙여넣기버튼 가능하게. 그러고 레이어버튼의
/// 레이어복사/붙여넣기는 필요없으니 삭제」 · 「타임라인의 공용 복사/
/// 독립붙여넣기/링크붙여넣기를 말한거였음. 링크해서 복제도 필요없어지니
/// 삭제」. ↩️The board held ONE row, the active one, and the layer menu's
/// three entries were its only doors. It holds the SELECTION now, and the
/// shared pill's copy and its two pastes press it (`toolbar_panel_context`).
class LayerClipboard implements BringsMedia {
  LayerClipboard({
    required LayerBoard board,
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required LayerStack layerStack,
    required RenderCaches renderCaches,
    required MediaByteSource Function(String poolPath) mediaBytesOf,
    required MediaStagingStore staging,
    required RowSelection rowSelection,
    required LayerVerbs layerVerbs,
  }) : _board = board,
       _project = project,
       _selection = selection,
       _changes = changes,
       _layerStack = layerStack,
       _renderCaches = renderCaches,
       _mediaBytesOf = mediaBytesOf,
       _staging = staging,
       _rowSelection = rowSelection,
       _layerVerbs = layerVerbs;

  /// The rows a copy of the selection takes
  /// ([RowSelection.selectedLayerIds]).
  final RowSelection _rowSelection;

  /// The delete a 잘라내기 lifts its rows with (I-123), and what it takes
  /// along ([LayerVerbs.rowsHeldBy]).
  final LayerVerbs _layerVerbs;

  /// The app's layer board ([LayerBoard]) — every open project's clipboard
  /// reads and writes the same one (I-7).
  final LayerBoard _board;
  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final LayerStack _layerStack;
  final RenderCaches _renderCaches;

  /// Where this project keeps a medium's bytes ([CopiedNames.bytesOf]).
  final MediaByteSource Function(String poolPath) _mediaBytesOf;

  /// Where a paste from another project stages the media it carries in.
  final MediaStagingStore _staging;

  /// What a wait held for the next paste of the board's copy.
  final HeldArrival _held = HeldArrival();

  bool get hasLayerClipboard => _board._copy != null;

  /// The rows of the cut stood in, bottom → top.
  List<Layer> get _stack => _project.activeCutOrNull?.layers ?? const [];

  /// Whether the board can hold [layer]: every row that is the cut's to
  /// lose — not a track's SE row, and not the camera, which stays.
  bool _boardHolds(Layer layer) => switch (layer.kind) {
    LayerKind.se || LayerKind.transition || LayerKind.camera => false,
    _ => true,
  };

  /// The selected rows the board can hold — whatever order they were
  /// selected in, a paste puts them down as they stood.
  ///
  /// A row no board can hold contributes nothing: a track-owned SE row, an
  /// attach row. A row's kind decides what the edit DOES, never whether the
  /// row could be selected (뿌리 A).
  List<Layer> get _selectedRows {
    final selected = _rowSelection.selectedLayerIds.toSet();
    return [
      for (final layer in _stack)
        if (selected.contains(layer.id) && _boardHolds(layer)) layer,
    ];
  }

  /// [rows] and what a delete of them takes along ([LayerVerbs.rowsHeldBy])
  /// — a folder what it holds, a base its attach rows — bottom → top as the
  /// cut stacks them, each once: the rows the board takes for them.
  ///
  /// 🗣️F-535 (유저 2026-11-01): 「기준레이어 잘라내면 삭제가 내부도
  /// 삭제하려하듯이 내부 어태치레이어들도 잘라냄. 법 통일」.
  List<Layer> _withWhatTheyHold(List<Layer> rows) {
    final held = _layerVerbs.rowsHeldBy([for (final row in rows) row.id]);
    final taken = {
      for (final row in [...rows, ...held])
        if (_boardHolds(row)) row.id,
    };
    return [
      for (final layer in _stack)
        if (taken.contains(layer.id)) layer,
    ];
  }

  /// The rows a copy of the selection takes.
  List<Layer> get _rowsToCopy => _withWhatTheyHold(_selectedRows);

  /// Whether the row selection names a row the board can take — the ROWS
  /// rung of the shared pill's copy.
  bool get canCopySelectedRows => _rowsToCopy.isNotEmpty;

  void copySelectedRows() {
    final rows = _rowsToCopy;
    if (rows.isEmpty) {
      return;
    }
    // A selected row of the cut implies the cut.
    final cut = _project.requireActiveCut;
    _bank([for (final layer in rows) _copyOf(layer, cut)]);
  }

  /// 🗣️I-123 (유저 2026-10-22): 「레이어도 타임라인 공용알약의 잘라내기 버튼
  /// 사용가능. 여러레이어 선택해서 사용한다던가 다른 규칙 참고해서 법 통일」.
  ///
  /// 🗣️F-532 (유저 2026-11-01): 「레이어에서 폴더도 잘라내기 가능하게.
  /// 폴더 삭제랑 동일하게 내부에도 적용되서 내부 다 잘라냄」.
  ///
  /// The rows a 잘라내기 lifts: those a copy takes that may go, each with
  /// what its delete takes along.
  ///
  /// 🚨결정 14 ②ⓐ, the frame cut's law (`FrameClipboard.cutAt`): a cut banks
  /// exactly what it lifts — 「클립보드가 담지 않은 것을 들어내면 그건 삭제지
  /// 잘라내기가 아니다」. ↩️So a base with attach rows stayed where it was
  /// while no board held them (I-123); the board holds them now (F-535).
  List<Layer> get _rowsToCut => _withWhatTheyHold([
    for (final layer in _selectedRows)
      if (_layerVerbs.canDeleteLayer(layer)) layer,
  ]);

  /// Whether the selected rows hold one a 잘라내기 may lift — the ROWS rung
  /// of the shared pill's cut, which the copy's rung claims
  /// (`toolbar_panel_context`).
  bool get canCutSelectedRows => _rowsToCut.isNotEmpty;

  /// Lifts [_rowsToCut] as ONE step and puts in hand the rows that went.
  ///
  /// ⚠️The board takes them AFTER the lift, of the rows it took: a delete
  /// may still refuse one at its floor (one instruction row stays), and a
  /// row that stayed is not in hand. What they showed is read BEFORE it,
  /// while the cut still shows it.
  void cutSelectedRows() {
    final rows = _rowsToCut;
    if (rows.isEmpty) {
      return;
    }
    final cut = _project.requireActiveCut;
    final taken = [for (final layer in rows) _copyOf(layer, cut)];
    _layerVerbs.deleteLayers(
      _layerVerbs.rowsNotTakenAlong([for (final row in taken) row.sourceId]),
      step: 'Cut rows',
    );
    final stayed = {
      for (final layer in _project.requireActiveCut.layers) layer.id,
    };
    _bank([
      for (final row in taken)
        if (!stayed.contains(row.sourceId)) row,
    ]);
  }

  /// Puts [copied] in hand, with what the rows name in this project.
  void _bank(List<_CopiedLayer> copied) {
    _board._take(
      _CopiedRows(
        from: this,
        rows: copied,
        names: namesOfACopy(
          project: _project.repository.requireProject(),
          media: {
            for (final row in copied) ...{
              ?row.payload.mediaReference?.assetPath,
              for (final sound in row.payload.audioClips) sound.filePath,
            },
          },
          terms: {
            for (final row in copied)
              ...termsSpelledBy(
                row.payload.timeline.values,
                row.payload.instructions.values,
              ),
          },
          bytesOf: _mediaBytesOf,
        ),
      ),
    );
    _changes.notifyChanged();
  }

  /// [layer] as the board holds it: the row, and what it showed.
  _CopiedLayer _copyOf(Layer layer, Cut cut) {
    final row = _ofItsOwn(layer, cut);
    return _CopiedLayer(
      source: layer,
      payload: copyLayerToPayload(row),
      pictures: picturesShownBy(
        store: _renderCaches.brushFrameStore,
        cels: row.frames,
        keyOf: (cel) => _project.brushFrameKeyForCut(cut, layer.id, cel),
      ),
      handwriting: conteHandwritingShownBy(
        store: _renderCaches.conteInkRowStore,
        cut: cut.id,
        exposures: row.timeline.values,
      ),
    );
  }

  /// [layer] as a row of its own — an attach row with the timing it wore
  /// baked in ([detachedLayer]), so that it lands whole with no base under
  /// it.
  Layer _ofItsOwn(Layer layer, Cut cut) {
    if (!isAttachedLayer(layer)) {
      return layer;
    }
    return detachedLayer(
      attached: layer,
      base: attachedBaseOf(layer, cut.layers),
      drawnFrameCount: cutDrawnFrameCount(
        _project.repository.requireProject(),
        cut.id,
      )!,
    );
  }

  /// Whether a paste here must first HOLD the bytes of media the copy
  /// carries from another project — the UI's cue for its wait window
  /// (F-53: every wait has one).
  @override
  bool get pasteMustHoldMedia =>
      _held.mustHold(_board._copy, _project.repository.requireProject());

  /// Holds them — as carries of THIS project's own, staged before anything
  /// records them ([holdCarriedMediaOf]) — for the next paste of the copy.
  @override
  Future<void> holdWhatThePasteBrings() => _held.hold(
    _board._copy,
    _project.repository.requireProject(),
    _staging,
  );

  /// Whether a row of the board may land here.
  bool get canPasteRows => _board._copy?.rows.any(_lands) ?? false;

  /// R9 #7: a cut that already holds its one row of a kind takes no second
  /// — and a gap, which has no cut, takes none at all
  /// ([LayerStack.canAddLayerOfKind]).
  ///
  /// ↩️This guard was NEVER APPLIED by any test while the board held one
  /// row (mutation, 2026-09-06 and again 09-08): the copy's own gate turned
  /// the conte row away first. The board takes that row now, and
  /// `r9_p1_instant_cel_test` reaches both paste arms with it.
  bool _lands(_CopiedLayer row) =>
      _layerStack.canAddLayerOfKind(row.alone.kind);

  /// The board's rows, each a row of its own in this cut — above the row
  /// you stand on, in the order they were copied in. ONE undo for the rows
  /// and what they brought.
  void pasteRows() {
    final copy = _board._copy;
    if (copy == null || !copy.rows.any(_lands)) {
      return;
    }
    // A row that may land implies a cut to land in.
    final cut = _project.requireActiveCut;
    final standing = _selection.activeLayer?.id;
    // The rows land with what they name and this project lacks — their
    // media, their terms, spelled as this project spells them (I-7,
    // [HeldArrival]).
    final arrival = _held.arrivalFor(
      copy,
      _project.repository.requireProject(),
    );
    final pasted = <({_CopiedLayer row, PastedLayer landed})>[];
    final landedAs = <LayerId, PastedLayer>{};
    final bases = {
      for (final row in copy.rows)
        if (_lands(row)) row.sourceId,
    };
    bool rides(_CopiedLayer row) =>
        bases.contains(row.riding?.attachedToLayerId);
    void land(_CopiedLayer row, int seat) {
      final landed = _project.cutCommandCoordinator.pasteLayer(
        cutId: cut.id,
        payload: _respelled(
          rides(row) ? row.payload : row.alone,
          arrival.respell,
        ),
        insertionIndex: seat,
        anchors: (
          folderId: landedAs[row.folderId]?.layerId,
          riding: rides(row)
              ? _ridingOn(landedAs[row.riding!.attachedToLayerId]!, row)
              : null,
        ),
      );
      landedAs[row.sourceId] = landed;
      pasted.add((row: row, landed: landed));
    }

    _project.historyManager.runAsOneStep('Paste rows', () {
      landArrival(_project, arrival);
      // The TOP row first, each one above the standing row: every row put
      // down lifts the ones before it, so the block reads as it was copied
      // — and a folder, standing right above what it holds, lands before it.
      for (final row in copy.rows.reversed) {
        if (_lands(row) && !rides(row)) {
          land(row, _seatAbove(standing));
        }
      }
      // An attach row names the base it rides, so it comes after it: into
      // the block from the top, for an organizer stands over the rows it
      // holds, each row right under the one it stood under.
      int seatOf(PastedLayer landed) => _project.requireActiveCut.layers
          .indexWhere((layer) => layer.id == landed.layerId);
      var seat = seatOf(pasted.first.landed) + 1;
      for (final row in copy.rows.reversed) {
        if (rides(row)) {
          land(row, seat);
        } else if (landedAs[row.sourceId] case final landed?) {
          seat = seatOf(landed);
        }
      }
    });
    for (final one in pasted) {
      _carryWhatTheCopyShowed(one.row, cut, one.landed);
    }
    _changes.refreshAfterCutCommand(
      preferredActiveLayerId: pasted.first.landed.layerId,
    );
    _changes.notifyChanged();
  }

  /// [row]'s ride on the row its base [landed] as: its side of the links
  /// still names the cels it was copied with.
  LayerAttachment _ridingOn(PastedLayer landed, _CopiedLayer row) {
    final riding = row.riding!;
    return LayerAttachment(
      attachedToLayerId: landed.layerId,
      placement: riding.placement,
      mode: riding.mode,
      timeline: riding.timeline,
      baseFrameLinks: {
        for (final link in riding.baseFrameLinks.entries)
          ?landed.minted[link.key]: link.value,
      },
    );
  }

  /// The board's rows a LINKED paste copies here.
  ///
  /// A link is 「the same cel」 (I-7), so it serves the cut the rows were
  /// copied in, while they still stand there: a row of another project has
  /// no cel of this one — though it may well wear the same id — and a row
  /// that is gone, or is in another cut, has none to share here. A copy
  /// lands beside its source, so a per-cut singleton has no second
  /// ([layerTakesACopyBesideIt]). A folder of the user's lands as it would
  /// in an independent paste, for the rows to go in: it has no cels to link
  /// (F-532-Q2). An organizer rides in the attach group its base copies.
  List<_CopiedLayer> get _rowsToLink {
    final copy = _board._copy;
    if (copy == null || !identical(copy.from, this)) {
      return const [];
    }
    // A row's id is its project's, so 「still in this cut」 is one lookup.
    final here = _stack;
    return [
      for (final row in copy.rows)
        if (here.byId(row.sourceId) case final layer?
            when layerTakesACopyBesideIt(layer) ||
                layer.kind.groupsLayers &&
                    attachOrganizerBaseOf(layer, here) == null)
          row,
    ];
  }

  bool get canPasteRowsLinked => _rowsToLink.isNotEmpty;

  /// The board's rows as LINKED copies — each with its whole attach group,
  /// sharing the originals' pictures (`LinkDuplicateLayerCommand`) — above
  /// the row you stand on, as ONE undo step.
  ///
  /// ↩️The layer menu's 「링크해서 복제」 did this for the active row alone,
  /// and put the copy above its source.
  void pasteRowsLinked() {
    final rows = _rowsToLink;
    if (rows.isEmpty) {
      return;
    }
    // A row still in the cut implies the cut.
    final cut = _project.requireActiveCut;
    final standing = _selection.activeLayer?.id;
    final landedAs = <LayerId, LayerId>{};
    final commands = _project.cutCommandCoordinator;
    _project.historyManager.runAsOneStep('Paste rows linked', () {
      // Top first, for [pasteRows]' reason.
      for (final row in rows.reversed) {
        final folder = landedAs[row.folderId];
        landedAs[row.sourceId] = row.payload.kind.groupsLayers
            ? commands
                  .pasteLayer(
                    cutId: cut.id,
                    payload: row.payload,
                    insertionIndex: _seatAbove(standing),
                    anchors: (folderId: folder, riding: null),
                  )
                  .layerId
            : commands.linkDuplicateLayer(
                cutId: cut.id,
                layerId: row.sourceId,
                insertionIndex: _seatAbove(standing),
                intoFolder: folder,
              );
      }
    });
    _changes.refreshAfterCutCommand(
      preferredActiveLayerId: landedAs[rows.last.sourceId],
    );
    _changes.notifyChanged();
  }

  /// The paste minted every cel afresh, and a picture lives under its
  /// cel's id — so the pictures the copy took follow them over (F-62's
  /// law, at the layer's scale). ↩️Nothing did until 2026-09-26: a pasted
  /// layer, and a duplicated one, came out with no drawing at all
  /// (measured; card `duplicates-lose-their-pictures`). Its blocks wrote
  /// on the conte anew, and their handwriting follows them the same way.
  void _carryWhatTheCopyShowed(
    _CopiedLayer copy,
    Cut cut,
    PastedLayer pasted,
  ) {
    carryBakedPictures(
      project: _project,
      store: _renderCaches.brushFrameStore,
      cut: cut,
      to: pasted.layerId,
      minted: pasted.minted,
      pictureOf: (source) => copy.pictures[source],
    );
    carryConteHandwriting(
      store: _renderCaches.conteInkRowStore,
      cut: cut.id,
      copies: pasted.handwriting,
      handwritingOf: (inkId) => copy.handwriting[inkId],
    );
  }

  /// Where a pasted row goes in the cut as it stands NOW ([seatAboveRow]):
  /// over the row [standing] names.
  int _seatAbove(LayerId? standing) =>
      seatAboveRow(_project.requireActiveCut.layers, standing);

  /// [payload] with its terms spelled as [respell] says ([Arrival]).
  static LayerCopyPayload _respelled(
    LayerCopyPayload payload,
    Map<String, String> respell,
  ) {
    if (respell.isEmpty) {
      return payload;
    }
    return payload.copyWith(
      timeline: payload.timeline.map(
        (index, exposure) =>
            MapEntry(index, respelledExposure(exposure, respell)),
      ),
      instructions: payload.instructions.map(
        (index, span) => MapEntry(index, respelledSpan(span, respell)),
      ),
    );
  }
}

/// What the app holds from the last LAYER copy — one board for every open
/// project (I-7), the frame board's twin (`FrameBoard`). The next copy the
/// pill takes replaces it, of rows or of frames ([onTake]).
class LayerBoard {
  _CopiedRows? _copy;

  /// What this board taking a copy lets go of: the pill's other board
  /// (`AppClipboard`).
  void Function()? onTake;

  void _take(_CopiedRows copy) {
    _copy = copy;
    onTake?.call();
  }

  /// Lets go of what it holds: the hand took a copy of the other kind.
  void letGo() => _copy = null;

  /// The pictures the copy holds — the memory census's to weigh.
  Iterable<BitmapSurface> get heldPictures => [
    for (final row in _copy?.rows ?? const <_CopiedLayer>[])
      ...row.pictures.values,
  ];
}

/// The rows on the board.
class _CopiedRows implements BoardCopy {
  const _CopiedRows({
    required this.from,
    required this.rows,
    required this.names,
  });

  /// The clipboard that banked them — the PROJECT whose ids every
  /// [_CopiedLayer.sourceId] is. A linked paste serves only that project
  /// ([LayerClipboard.canPasteRowsLinked]), as the frame board's does.
  final LayerClipboard from;

  /// Bottom → top, as that cut stacked them.
  final List<_CopiedLayer> rows;

  /// What the rows name in their project besides their ids — the media
  /// they show, the terms they spell — for a paste elsewhere.
  @override
  final CopiedNames names;
}

/// One row on the board.
class _CopiedLayer {
  const _CopiedLayer({
    required this.source,
    required this.payload,
    required this.pictures,
    required this.handwriting,
  });

  /// The row as it stood when it was copied.
  final Layer source;

  /// The row it was copied off — what a LINKED paste copies again.
  LayerId get sourceId => source.id;

  /// The folder it stood in — a paste puts it back there when the board
  /// holds that folder too. A payload names no folder ([LayerCopyPayload]):
  /// this one is only ever read against the rows beside it.
  LayerId? get folderId => source.folderId;

  /// What it rode — a paste puts it back on that base when the board holds
  /// it too, and it lands as [alone] when not. As the folder above, for the
  /// same reason.
  LayerAttachment? get riding =>
      isAttachedLayer(source) ? LayerAttachment.of(source) : null;

  /// The row, as [copyLayerToPayload] carries it.
  final LayerCopyPayload payload;

  /// [payload] to land with no base under it: an attach row of a kind the
  /// cut holds one of rode that row, and is not to take its place.
  LayerCopyPayload get alone => riding != null && payload.kind.isSingletonPerCut
      ? payload.copyWith(kind: LayerKind.animation)
      : payload;

  /// The pictures its cels showed when it was copied, by cel id — BY VALUE,
  /// for the frame board's reason ([picturesShownBy], F-161): the paste may
  /// land in another cut or another project, whose store has nothing under
  /// the source's keys, and a source drawn over after the copy is not what
  /// was copied.
  final Map<FrameId, BitmapSurface> pictures;

  /// The handwriting its blocks showed on the conte when it was copied, by
  /// each block's id — BY VALUE for [pictures]' reason.
  final Map<String, BitmapSurface> handwriting;
}
