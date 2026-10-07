import '../../models/bitmap_surface.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_row_address.dart';
import '../../services/clipboard/layer_copy_payload.dart';
import '../../services/commands/cut_command_coordinator.dart' show PastedLayer;
import '../../services/media/media_byte_source.dart' show MediaByteSource;
import '../../services/persistence/media_staging_store.dart';
import 'independent_clip_mint.dart';
import 'layer_stack.dart';
import 'render_caches.dart';
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
  }) : _board = board,
       _project = project,
       _selection = selection,
       _changes = changes,
       _layerStack = layerStack,
       _renderCaches = renderCaches,
       _mediaBytesOf = mediaBytesOf,
       _staging = staging;

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

  /// The selected rows a copy takes, bottom → top as the cut stacks them —
  /// whatever order they were selected in, a paste puts them down as they
  /// stood.
  ///
  /// A row no board can hold contributes nothing ([layerTakesACopy]): a
  /// track-owned SE row, an attach row. A row's kind decides what the edit
  /// DOES, never whether the row could be selected (뿌리 A).
  List<Layer> get _rowsToCopy {
    final selected = {
      for (final row in _selection.rowSelection.value)
        if (row is LayerRowAddress) row.layerId,
    };
    return [
      for (final layer in _project.activeCutOrNull?.layers ?? const <Layer>[])
        if (selected.contains(layer.id) && layerTakesACopy(layer)) layer,
    ];
  }

  /// Whether the row selection names a row the board can take — the ROWS
  /// rung of the shared pill's copy.
  bool get canCopySelectedRows => _rowsToCopy.isNotEmpty;

  void copySelectedRows() {
    final rows = _rowsToCopy;
    final cut = _project.activeCutOrNull;
    if (rows.isEmpty || cut == null) {
      return;
    }
    final copied = [for (final layer in rows) _copyOf(layer, cut)];
    _board._take(
      _CopiedRows(
        from: this,
        cutId: cut.id,
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
  _CopiedLayer _copyOf(Layer layer, Cut cut) => _CopiedLayer(
    sourceId: layer.id,
    payload: copyLayerToPayload(layer),
    pictures: picturesShownBy(
      store: _renderCaches.brushFrameStore,
      cels: layer.frames,
      keyOf: (cel) => _project.brushFrameKeyForCut(cut, layer.id, cel),
    ),
    handwriting: conteHandwritingShownBy(
      store: _renderCaches.conteInkRowStore,
      cut: cut.id,
      exposures: layer.timeline.values,
    ),
  );

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

  /// Whether a row of the board may land in this cut.
  ///
  /// R9 #7: a cut that already holds its one row of a kind takes no second.
  /// ⚠️`_lands` was NEVER APPLIED by any test while the board held one row
  /// (mutation, 2026-09-06 and again 09-08): nothing copied a
  /// single-instance row and pasted it into a cut that already had one.
  bool get canPasteRows =>
      _project.activeCutOrNull != null &&
      (_board._copy?.rows.any(_lands) ?? false);

  bool _lands(_CopiedLayer row) =>
      _layerStack.canAddLayerOfKind(row.payload.kind);

  /// The board's rows, each a row of its own in this cut — above the row
  /// you stand on, in the order they were copied in. ONE undo for the rows
  /// and what they brought.
  void pasteRows() {
    final copy = _board._copy;
    final cut = _project.activeCutOrNull;
    if (copy == null || cut == null || !canPasteRows) {
      return;
    }
    final standing = _selection.activeLayer?.id;
    // The rows land with what they name and this project lacks — their
    // media, their terms, spelled as this project spells them (I-7,
    // [HeldArrival]).
    final arrival = _held.arrivalFor(
      copy,
      _project.repository.requireProject(),
    );
    final pasted = <({_CopiedLayer row, PastedLayer landed})>[];
    _project.historyManager.runAsOneStep('Paste rows', () {
      landArrival(_project, arrival);
      // The TOP row first, each one above the standing row: every row put
      // down lifts the ones before it, so the block reads as it was copied.
      for (final row in copy.rows.reversed) {
        if (!_lands(row)) {
          continue;
        }
        pasted.add((
          row: row,
          landed: _project.cutCommandCoordinator.pasteLayer(
            cutId: cut.id,
            payload: _respelled(row.payload, arrival.respell),
            insertionIndex: _seatAbove(standing),
          ),
        ));
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

  /// The board's rows a LINKED paste copies here.
  ///
  /// A link is 「the same cel」 (I-7), so it serves the cut the rows were
  /// copied in, while they still stand there: a row of another project has
  /// no cel of this one, and a row that is gone has none to share. A copy
  /// lands beside its source, so a per-cut singleton has no second
  /// ([layerTakesACopyBesideIt]).
  List<LayerId> get _rowsToLink {
    final copy = _board._copy;
    final cut = _project.activeCutOrNull;
    if (copy == null ||
        cut == null ||
        !identical(copy.from, this) ||
        copy.cutId != cut.id) {
      return const [];
    }
    return [
      for (final row in copy.rows)
        if (cut.layers.byId(row.sourceId) case final layer?
            when layerTakesACopyBesideIt(layer))
          row.sourceId,
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
    final ids = _rowsToLink;
    final cut = _project.activeCutOrNull;
    if (ids.isEmpty || cut == null) {
      return;
    }
    final standing = _selection.activeLayer?.id;
    final copies = <LayerId>[];
    _project.historyManager.runAsOneStep('Paste rows linked', () {
      // Top first, for [pasteRows]' reason.
      for (final id in ids.reversed) {
        copies.add(
          _project.cutCommandCoordinator.linkDuplicateLayer(
            cutId: cut.id,
            layerId: id,
            insertionIndex: _seatAbove(standing),
          ),
        );
      }
    });
    _changes.refreshAfterCutCommand(preferredActiveLayerId: copies.first);
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

  /// Where a pasted row goes in the cut as it stands NOW: the seat above
  /// the row [standing] names, and the top of the stack when it names none
  /// here. Read again for every row a paste puts down — the one before it
  /// moved everything above.
  int _seatAbove(LayerId? standing) {
    final layers = _project.requireActiveCut.layers;
    final index = layers.indexWhere((layer) => layer.id == standing);
    return index == -1 ? layers.length : index + 1;
  }

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
    required this.cutId,
    required this.rows,
    required this.names,
  });

  /// The clipboard that banked them — the PROJECT whose ids [cutId] and
  /// every [_CopiedLayer.sourceId] are. A linked paste serves only that
  /// project ([LayerClipboard.canPasteRowsLinked]), as the frame board's
  /// does.
  final LayerClipboard from;

  /// The cut they were copied in.
  final CutId cutId;

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
    required this.sourceId,
    required this.payload,
    required this.pictures,
    required this.handwriting,
  });

  /// The row it was copied off — what a LINKED paste copies again.
  final LayerId sourceId;

  /// The row, as [copyLayerToPayload] carries it.
  final LayerCopyPayload payload;

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
