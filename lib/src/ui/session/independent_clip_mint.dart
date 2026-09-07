import '../../models/cut.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
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

/// WHAT A CLIP BECOMES WHEN IT LANDS ON [layer] — the linked branch and
/// the independent one, side by side, so a paste asks once per row.
///
/// Split out of `FrameClipboard._pasteRun` when the paste learned the band:
/// the independent branch mints PER LAYER, so the arithmetic stopped being
/// something one row could keep inline. It sits HERE rather than on the
/// clipboard because it holds no clipboard state — [row] is the board's
/// row, [mint] is the caller's id source — and because the two functions
/// it is the sibling of already live in this file.
///
/// [row] is the clip AND the cels it carries as ONE argument, because a
/// board row that lost its cels is not a row this can place.
({TimelineClipRow clip, List<Frame> born, Map<FrameId, FrameId> minted})
placedClipFor({
  required Layer layer,
  required ({TimelineClipRow clip, List<Frame> cels}) row,
  required bool independent,
  required FrameId Function() mint,
}) {
  final born = <Frame>[
    // A 잘라내기 orphaned the cels it lifted, so the layer no longer holds
    // them; the clipboard does. Bringing back the SAME id is what makes
    // cut-then-paste-back a move rather than a deletion — and re-adding
    // only what is missing keeps a plain copy from duplicating anything.
    if (!independent)
      for (final cel in row.cels)
        if (!layer.frames.any((frame) => frame.id == cel.id)) cel,
  ];
  if (!independent) {
    return (clip: row.clip, born: born, minted: const {});
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
    clip: row.clip,
    sources: [...layer.frames, ...row.cels],
    born: born,
    mint: mint,
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
