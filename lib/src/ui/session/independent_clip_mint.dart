import '../../models/cut.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_exposure.dart';
import '../../models/timeline_splice.dart';
import '../../services/brush_frame_store.dart';
import '../../services/editing/cut_duplicate_helpers.dart'
    show duplicateFrameContent;
import 'session_roles.dart';

/// A run of cells re-cut as CELS OF ITS OWN: every distinct source cel the
/// run exposes is minted once, copied unnamed into [born], and the run is
/// rebuilt pointing at the new ids.
///
/// ONE kernel for the independent paste and the independent block
/// duplicate. They were the same twenty-five lines under two names, and
/// the second copy was the older one — it authored exposures for cels it
/// could not resolve, and it threw the minted map away, so the picture
/// never followed (see [carryBakedPictures]).
///
/// [sources] is searched IN ORDER, so a caller with more than one place to
/// look states its priority by concatenating.
///
/// 🚨IT COMES OUT UNNAMED, and that is the point rather than an omission.
/// A cel's name is its IDENTITY inside the layer — the rename path REFUSES
/// a duplicate and offers to merge instead, which is this app's
/// 「같은 이름 = 같은 그림」 rule. Carrying the source's name would assert
/// the very link this verb exists to avoid, and do it behind that dialog's
/// back.
({TimelineClipRow clip, List<Frame> born, Map<FrameId, FrameId> minted})
mintIndependentClip({
  required TimelineClipRow clip,
  required List<Frame> sources,
  required List<Frame> born,
  required FrameId Function() mint,
}) {
  final minted = <FrameId, FrameId>{};
  final exposures = <int, TimelineExposure>{};
  for (final entry in clip.exposures.entries) {
    final sourceId = entry.value.frameId;
    if (sourceId == null) {
      continue;
    }
    final source = sources.where((frame) => frame.id == sourceId).firstOrNull;
    if (source == null) {
      // ⛔An exposure with no cel behind it is the damage itself. Drop the
      // cell rather than author a reference nothing can resolve — an empty
      // cell is a state the row already knows how to be.
      continue;
    }
    final newId = minted.putIfAbsent(sourceId, () {
      // 🚨Through the MINT. `nextFrameId` reads the sequence without
      // advancing it, so two independent pastes inside one clock tick
      // would come out as the SAME cel — which is not "two cels that look
      // alike", it is one cel exposed twice, and the import round already
      // paid for that lesson once. A band paste makes that risk ROUTINE:
      // every swept row mints in the same tick as its neighbours.
      final id = mint();
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
    // The caller carries the baked surfaces across it after the splice.
    minted: minted,
  );
}

/// 🚨★★★AND THE PICTURES COME WITH THEM (F-62).
///
/// ⚠️Surfaces are IMMUTABLE with structural tile sharing, so storing the
/// same object under the new key IS the copy — the same reasoning
/// `UnlinkLayerCommand` states where it forks a linked member's cels.
///
/// ⛔A LINKED paste or duplicate copies nothing on purpose: it points the
/// new exposures at the cels that already exist, which is what 「링크」
/// means. [minted] is empty there, so this loop is the independent branch
/// only without a second flag saying so.
///
/// ⚠️AFTER the splice, not before: the born cels have to be in the layer
/// for the key to name something the app will read back.
void carryBakedPictures({
  required SessionInternals internals,
  required BrushFrameStore store,
  required Cut cut,
  required ({LayerId from, LayerId to}) between,
  required Map<FrameId, FrameId> minted,
}) {
  for (final entry in minted.entries) {
    final surface = store.bakedSurfaceOrNull(
      internals.brushFrameKeyForCut(cut, between.from, entry.key),
    );
    if (surface == null) {
      continue;
    }
    store.storeBakedSurface(
      internals.brushFrameKeyForCut(cut, between.to, entry.value),
      surface,
    );
  }
}
