import '../../models/attached_layer_resolve.dart';
import '../../models/bitmap_surface.dart';
import '../../models/cut.dart';
import '../../models/frame_id.dart';
import '../../services/clipboard/layer_copy_payload.dart';
import '../../services/commands/cut_command_coordinator.dart' show PastedLayer;
import '../../services/media/media_byte_source.dart' show MediaByteSource;
import '../../services/persistence/media_staging_store.dart';
import 'independent_clip_mint.dart';
import 'layer_stack.dart';
import 'render_caches.dart';
import 'session_roles.dart';
import 'what_a_copy_brings.dart';

/// The LAYER CLIPBOARD — the layer the user copied, and pasting it into a
/// cut — as its own object.
///
/// 🚨Split out of `FrameClipboard` (G0-2, 2026-09-06). A frame board and a
/// layer board are two boards: they hold different payloads, answer to
/// different verbs, and the only thing they shared was the object that
/// happened to hold both. What kept them together was that one class held
/// them, which is not a reason.
class LayerClipboard implements BringsMedia {
  LayerClipboard({
    required LayerBoard board,
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required LayerStack layerStack,
    required SessionInternals internals,
    required RenderCaches renderCaches,
    required MediaByteSource Function(String poolPath) mediaBytesOf,
    required MediaStagingStore staging,
  }) : _board = board,
       _project = project,
       _selection = selection,
       _changes = changes,
       _layerStack = layerStack,
       _internals = internals,
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
  final SessionInternals _internals;
  final RenderCaches _renderCaches;

  /// Where this project keeps a medium's bytes ([CopiedNames.bytesOf]).
  final MediaByteSource Function(String poolPath) _mediaBytesOf;

  /// Where a paste from another project stages the media it carries in.
  final MediaStagingStore _staging;

  /// What a wait held for the next paste of the board's copy.
  final HeldArrival _held = HeldArrival();

  String? get layerClipboardName => _board._copy?.payload.name;

  bool get hasLayerClipboard => _board._copy != null;

  void copyActiveLayer() {
    final activeLayer = _selection.activeLayer;
    // SE rows are track-owned (global frame axis) — copying a cut-local
    // window onto the cut-layer clipboard would recreate the retired
    // cut-owned SE shape; stands down for now. Attach rows stand down too
    // (their cel links point into THIS cut's base).
    if (activeLayer == null ||
        !activeLayer.kind.isClipboardCopyable ||
        isAttachedLayer(activeLayer)) {
      return;
    }

    final payload = copyLayerToPayload(activeLayer);
    _board._copy = _CopiedLayer(
      payload: payload,
      // A non-null active layer implies an active cut (gap state has no
      // rows at all).
      pictures: picturesShownBy(
        store: _renderCaches.brushFrameStore,
        cels: activeLayer.frames,
        keyOf: (cel) => _internals.brushFrameKeyForCut(
          _project.requireActiveCut,
          activeLayer.id,
          cel,
        ),
      ),
      names: namesOfACopy(
        project: _project.repository.requireProject(),
        media: {
          ?payload.mediaReference?.assetPath,
          for (final sound in payload.audioClips) sound.filePath,
        },
        terms: termsSpelledBy(
          payload.timeline.values,
          payload.instructions.values,
        ),
        bytesOf: _mediaBytesOf,
      ),
    );
    _changes.notifyChanged();
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

  void pasteLayerFromClipboard() {
    final copy = _board._copy;
    if (copy == null) {
      return;
    }

    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return;
    }
    if (!_layerStack.canAddLayerOfKind(copy.payload.kind)) {
      // R9 #7: this cut already holds its one row of that kind.
      // ⚠️NEVER APPLIED by any test (mutation, 2026-09-06): nothing copies a
      // single-instance row and pastes it into a cut that already has one.
      //
      // ⚠️RE-MEASURED 2026-09-08, now that this file is NAMED by a test and
      // the campaign can reach it: `if (false)` here still SURVIVES. The
      // one test that tries — `r9_p1_instant_cel_test`'s 「copy/paste and
      // duplicate cannot make a second one」 — never gets here, because
      // [copyActiveLayer]'s `isClipboardCopyable` gate refuses a storyboard
      // row first and the board stays empty. Classification unchanged:
      // NEVER APPLIED, and the guard is kept as the second lock on R9 #7
      // for the day some kind is both copyable and singleton.
      return;
    }
    final insertionIndex = _rowBelowTheActiveOne(cut);

    // The row lands with what it names and this project lacks — its media,
    // its terms, spelled as this project spells them (I-7, [HeldArrival]).
    final arrival = _held.arrivalFor(copy, _project.repository.requireProject());
    final payload = _respelled(copy.payload, arrival.respell);
    late final PastedLayer pasted;
    // ONE undo for the row and what it brought.
    _project.historyManager.runAsOneStep('Paste layer ${payload.name}', () {
      landArrival(_project, arrival);
      pasted = _project.cutCommandCoordinator.pasteLayer(
        cutId: cut.id,
        payload: payload,
        insertionIndex: insertionIndex,
      );
    });
    // The paste minted every cel afresh, and a picture lives under its
    // cel's id — so the pictures the copy took follow them over (F-62's
    // law, at the layer's scale). ↩️Nothing did until 2026-09-26: a pasted
    // layer, and a duplicated one, came out with no drawing at all
    // (measured; card `duplicates-lose-their-pictures`).
    carryBakedPictures(
      internals: _internals,
      store: _renderCaches.brushFrameStore,
      cut: cut,
      to: pasted.layerId,
      minted: pasted.minted,
      pictureOf: (source) => copy.pictures[source],
    );
    _changes.refreshAfterCutCommand(preferredActiveLayerId: pasted.layerId);
    _changes.notifyChanged();
  }

  /// Where a pasted row goes in [cut]: right below the active row, and at
  /// the bottom when none is active there.
  int _rowBelowTheActiveOne(Cut cut) {
    final activeLayer = _selection.activeLayer;
    final activeIndex = activeLayer == null
        ? -1
        : cut.layers.indexWhere((layer) => layer.id == activeLayer.id);
    return activeIndex == -1 ? cut.layers.length : activeIndex + 1;
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
/// project (I-7), the frame board's twin (`FrameBoard`). Only the next copy
/// replaces it.
class LayerBoard {
  _CopiedLayer? _copy;

  /// The pictures the copy holds — the memory census's to weigh.
  Iterable<BitmapSurface> get heldPictures =>
      _copy?.pictures.values ?? const [];
}

/// A layer on the board.
class _CopiedLayer implements BoardCopy {
  const _CopiedLayer({
    required this.payload,
    required this.pictures,
    required this.names,
  });

  /// The row, as [copyLayerToPayload] carries it.
  final LayerCopyPayload payload;

  /// The pictures its cels showed when it was copied, by cel id — BY VALUE,
  /// for the frame board's reason ([picturesShownBy], F-161): the paste may
  /// land in another cut or another project, whose store has nothing under
  /// the source's keys, and a source drawn over after the copy is not what
  /// was copied.
  final Map<FrameId, BitmapSurface> pictures;

  /// What the row names in its project besides its ids — the medium it
  /// shows, the terms it spells — for a paste elsewhere.
  @override
  final CopiedNames names;
}
