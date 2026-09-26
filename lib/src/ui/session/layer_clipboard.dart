import '../../models/attached_layer_resolve.dart';
import '../../models/bitmap_surface.dart';
import '../../models/frame_id.dart';
import '../../services/clipboard/layer_copy_payload.dart';
import 'independent_clip_mint.dart';
import 'layer_stack.dart';
import 'render_caches.dart';
import 'session_roles.dart';

/// The LAYER CLIPBOARD — the layer the user copied, and pasting it into a
/// cut — as its own object.
///
/// 🚨Split out of `FrameClipboard` (G0-2, 2026-09-06). A frame board and a
/// layer board are two boards: they hold different payloads, answer to
/// different verbs, and the only thing they shared was the object that
/// happened to hold both. What kept them together was that one class held
/// them, which is not a reason.
class LayerClipboard {
  LayerClipboard({
    required LayerBoard board,
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required LayerStack layerStack,
    required SessionInternals internals,
    required RenderCaches renderCaches,
  }) : _board = board,
       _project = project,
       _selection = selection,
       _changes = changes,
       _layerStack = layerStack,
       _internals = internals,
       _renderCaches = renderCaches;

  /// The app's layer board ([LayerBoard]) — every open project's clipboard
  /// reads and writes the same one (I-7).
  final LayerBoard _board;
  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final LayerStack _layerStack;
  final SessionInternals _internals;
  final RenderCaches _renderCaches;

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

    _board._copy = (
      payload: copyLayerToPayload(activeLayer),
      // A non-null active layer implies an active cut (gap state has no
      // rows at all).
      pictures: picturesShownBy(
        internals: _internals,
        store: _renderCaches.brushFrameStore,
        cut: _project.requireActiveCut,
        row: activeLayer.id,
        cels: activeLayer.frames,
      ),
    );
    _changes.notifyChanged();
  }

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
    final activeLayer = _selection.activeLayer;
    final targetLayers = cut.layers;
    final activeLayerIndex = activeLayer == null
        ? -1
        : targetLayers.indexWhere((layer) => layer.id == activeLayer.id);
    final insertionIndex = activeLayerIndex == -1
        ? targetLayers.length
        : activeLayerIndex + 1;

    final pasted = _project.cutCommandCoordinator.pasteLayer(
      cutId: cut.id,
      payload: copy.payload,
      insertionIndex: insertionIndex,
    );
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
}

/// What the app holds from the last LAYER copy — one board for every open
/// project (I-7), the frame board's twin (`FrameBoard`). Only the next copy
/// replaces it.
class LayerBoard {
  _CopiedLayer? _copy;
}

/// A layer on the board: the row as [copyLayerToPayload] carries it, and
/// the pictures its cels showed when it was copied, by cel id — BY VALUE,
/// for the frame board's reason ([picturesShownBy], F-161): the paste may
/// land in another cut or another project, whose store has nothing under
/// the source's keys, and a source drawn over after the copy is not what
/// was copied.
typedef _CopiedLayer = ({
  LayerCopyPayload payload,
  Map<FrameId, BitmapSurface> pictures,
});
