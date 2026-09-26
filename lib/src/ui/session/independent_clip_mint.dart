import '../../models/audio_clip.dart';
import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/conte/conte_ink_keys.dart'
    show conteHandwritingOfACopy, conteInkRowKey, conteInkRowLayerId;
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_exposure.dart';
import '../../models/timeline_splice.dart';
import '../../services/bitmap_surface_geometry.dart'
    show resizeBitmapSurfaceCanvas;
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
/// [from] is the places to look, IN ORDER: a caller with more than one
/// states its priority by the order it lists them. A source cel comes from
/// the FIRST place that holds it, and so do the sounds it carries.
///
/// 🚨One place per cel, not one list per kind (F-115). The places used to be
/// concatenated per kind — every cel, then every sound — and a cel's lookup
/// stopped at its first match while the sounds were collected from ALL of
/// them. A copy leaves its source on the row, so the source's sound was in
/// the row's list AND on the clipboard's: the pasted instance got it twice.
///
/// 🚨IT COMES OUT UNNAMED, and that is the point rather than an omission.
/// A cel's name is its IDENTITY inside the layer — the rename path REFUSES
/// a duplicate and offers to merge instead, which is this app's
/// 「같은 이름 = 같은 그림」 rule. Carrying the source's name would assert
/// the very link this verb exists to avoid, and do it behind that dialog's
/// back.
///
/// ↩️…where the name IS the row's identity ([namesAreIdentity], the kind's
/// `celNameIsIdentity`). On an SE row it is the entry's dialogue, which the
/// rename lets repeat, so the copy keeps it — and the SOUND linked to the
/// source instance comes along as a sound of the new one (F-115, 유저
/// 2026-09-12: 「내용은 이름/대사/링크된 오디오 등 모든 정보가 똑같음」).
({
  TimelineClipRow clip,
  List<Frame> born,
  List<AudioClip> bornSounds,
  Map<FrameId, FrameId> minted,
})
mintIndependentClip({
  required TimelineClipRow clip,
  required List<({List<Frame> cels, List<AudioClip> sounds})> from,
  required bool namesAreIdentity,
  required FrameId Function() mint,
}) {
  final born = <Frame>[];
  final bornSounds = <AudioClip>[];
  final minted = <FrameId, FrameId>{};
  final exposures = <int, TimelineExposure>{};
  for (final entry in clip.exposures.entries) {
    final sourceId = entry.value.frameId;
    if (sourceId == null) {
      continue;
    }
    final place = from
        .where((place) => place.cels.any((frame) => frame.id == sourceId))
        .firstOrNull;
    final source = place?.cels.firstWhere((frame) => frame.id == sourceId);
    if (place == null || source == null) {
      // ⛔An exposure with no cel behind it is the damage itself. Drop the
      // cell rather than author a reference nothing can resolve — an empty
      // cell is a state the row already knows how to be.
      continue;
    }
    final newId = minted.putIfAbsent(sourceId, () {
      // 🚨Through the MINT. An id formatted without advancing the count
      // (`nextFrameId`, gone since 2026-09-26) made two independent pastes
      // inside one clock tick the SAME cel — which is not "two cels that
      // look alike", it is one cel exposed twice, and the import round
      // already paid for that lesson once. A band paste makes that risk
      // ROUTINE: every swept row mints in the same tick as its neighbours.
      final id = mint();
      final copy = duplicateFrameContent(frame: source, newFrameId: id);
      born.add(namesAreIdentity ? copy.copyWith(name: null) : copy);
      for (final sound in place.sounds) {
        if (sound.frameId == sourceId) {
          bornSounds.add(sound.copyWith(frameId: id));
        }
      }
      return id;
    });
    exposures[entry.key] = entry.value.copyWith(frameId: newId);
  }
  return (
    clip: TimelineClipRow(exposures: exposures, length: clip.length),
    born: born,
    bornSounds: bornSounds,
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
/// the independent one, side by side, so a paste asks once per row, and a
/// block duplicate — a paste of the block beside itself — asks the same.
///
/// Split out of `FrameClipboard._pasteRun` when the paste learned the band:
/// the independent branch mints PER LAYER, so the arithmetic stopped being
/// something one row could keep inline. It sits HERE rather than on the
/// clipboard because it holds no clipboard state — [row] is the board's
/// row, [ids] is the caller's id source — and because the two functions
/// it is the sibling of already live in this file.
///
/// [row] is the clip AND the cels and sounds it carries as ONE argument,
/// because a board row that lost them is not a row this can place.
///
/// 🚨EVERY BLOCK IT PLACES WRITES ON THE CONTE UNDER AN ID OF ITS OWN,
/// linked or not ([conteHandwritingOfACopy]; [handwriting] says which
/// handwriting each starts as a copy of): a link shares a drawing, and the
/// handwriting is the block's (유저 2026-09-25, conte-drawing-target: blocks
/// of the same name are not linked).
({
  TimelineClipRow clip,
  List<Frame> born,
  List<AudioClip> bornSounds,
  Map<FrameId, FrameId> minted,
  Map<String, String> handwriting,
})
placedClipFor({
  required Layer layer,
  required ({TimelineClipRow clip, List<Frame> cels, List<AudioClip> sounds})
  row,
  required bool independent,
  required FrameIds ids,
}) {
  final placed = independent
      ? _independentClipOf(layer, row, () => ids.mintFrameId(layer.id))
      : (
          clip: row.clip,
          born: [
            // A 잘라내기 orphaned the cels it lifted, so the layer no longer
            // holds them; the clipboard does. Bringing back the SAME id is
            // what makes cut-then-paste-back a move rather than a deletion —
            // and re-adding only what is missing keeps a plain copy from
            // duplicating anything.
            for (final cel in row.cels)
              if (!layer.frames.any((frame) => frame.id == cel.id)) cel,
          ],
          bornSounds: const <AudioClip>[],
          minted: const <FrameId, FrameId>{},
        );
  final written = conteHandwritingOfACopy(
    placed.clip.exposures,
    () => ids.mintFrameId(conteInkRowLayerId).value,
  );
  return (
    clip: TimelineClipRow(
      exposures: written.exposures,
      length: placed.clip.length,
    ),
    born: placed.born,
    bornSounds: placed.bornSounds,
    minted: placed.minted,
    handwriting: written.copies,
  );
}

/// [row] minted as cels of [layer]'s own ([mintIndependentClip]).
({
  TimelineClipRow clip,
  List<Frame> born,
  List<AudioClip> bornSounds,
  Map<FrameId, FrameId> minted,
})
_independentClipOf(
  Layer layer,
  ({TimelineClipRow clip, List<Frame> cels, List<AudioClip> sounds}) row,
  FrameId Function() mint,
) {
  // 🚨[row]'S CELS ARE THE PLACE TO LOOK — the only one: the board's for a
  // paste, the row's own for a duplicate, whose source stands beside it.
  //
  // For a paste the board was the SECOND place, after the row, and after a
  // 잘라내기 already the only one (유저 #3, 2026-08-14): a cut orphans the
  // cels it lifted,
  // so they are gone from `layer.frames` by the time this runs. Reading
  // only the layer found nothing, minted an id anyway, and authored an
  // exposure pointing at a cel that does not exist: a white block, `?`
  // where the name goes, and every verb that resolves the cel refusing —
  // 「완전한 버그상태」. A band paste then reached rows the clip never came
  // from, where the row misses the source every time.
  //
  // ↩️And a copy from ANOTHER PROJECT (I-7) made the row-first order WRONG
  // rather than empty: that project's ids were minted there, so a cel of
  // THIS row can carry the very id that was copied — and asked first, the
  // row answered with its own drawing, its own name and its own sound for
  // the one on the board. The board holds every cel its clip points at, as
  // they were when copied (F-161), so it is the whole answer.
  return mintIndependentClip(
    clip: row.clip,
    from: [(cels: row.cels, sounds: row.sounds)],
    namesAreIdentity: layer.kind.celNameIsIdentity,
    mint: mint,
  );
}

/// 🚨★★★A COPY BRINGS ITS SURFACES: each of [sources] that shows one has
/// it stored under the key its copy is kept by ([keyOfCopy]) — a cel's
/// picture, a block's handwriting on a sheet — and one without is skipped.
///
/// ⚠️Surfaces are IMMUTABLE with structural tile sharing, so storing the
/// same object under the new key IS the copy — the same reasoning
/// `UnlinkLayerCommand` states where it forks a linked member's cels.
///
/// ⛔ONE law for every copy: the pictures a pasted or duplicated cel shows
/// ([carryBakedPictures]), the handwriting a copied block writes under an
/// id of its own ([carryConteHandwriting]) and a duplicated cut's sheets'
/// writing (`CutVerbs`) were three loops saying it when the third arrived
/// (2026-09-26).
void carrySurfaces<S>({
  required BrushFrameStore store,
  required Iterable<S> sources,
  required BitmapSurface? Function(S source) surfaceOf,
  required BrushFrameKey? Function(S source) keyOfCopy,
}) {
  for (final source in sources) {
    final surface = surfaceOf(source);
    final key = keyOfCopy(source);
    if (surface != null && key != null) {
      store.storeBakedSurface(key, surface);
    }
  }
}

/// 🚨★★★AND THE PICTURES COME WITH THEM (F-62) — [carrySurfaces], said of
/// the cels a copy minted.
///
/// ⛔A LINKED paste or duplicate copies nothing on purpose: it points the
/// new exposures at the cels that already exist, which is what 「링크」
/// means. [minted] is empty there, so this loop is the independent branch
/// only without a second flag saying so.
///
/// ⚠️AFTER the splice, not before: the born cels have to be in the layer
/// for the key to name something the app will read back.
///
/// [pictureOf] says where a source cel's picture IS: the store, now, for a
/// duplicate — its source stands beside it — and the copy's own snapshot for
/// a paste (F-161), whose source may be in another cut, drawn over since, or
/// cut away.
void carryBakedPictures({
  required SessionInternals internals,
  required BrushFrameStore store,
  required Cut cut,
  required LayerId to,
  required Map<FrameId, FrameId> minted,
  required BitmapSurface? Function(FrameId source) pictureOf,
}) => carrySurfaces(
  store: store,
  sources: minted.entries,
  surfaceOf: (minted) => switch (pictureOf(minted.key)) {
    // 🚨A picture is kept at ITS CUT's canvas size, or its cel opens BLANK
    // and the first stroke saves the blank over it — the D5 loss the load
    // heal exists for (`_healStaleCelSizes`). A copy can come from a cut,
    // or a project (I-7), of another size. It keeps its canvas numbers,
    // as a pasted layer's transform does (`LayerCopyPayload.transformTrack`
    // — 「the numbers travel」).
    final surface? => resizeBitmapSurfaceCanvas(surface, cut.canvasSize),
    null => null,
  },
  keyOfCopy: (minted) => internals.brushFrameKeyForCut(cut, to, minted.value),
);

/// The pictures [cels] show as they are NOW, each under the key [keyOf]
/// names — what a copy takes BY VALUE (F-161): a paste may land in another
/// cut, or another project (I-7), whose store has no picture under the
/// source's key, and a source drawn over or cut away after the copy is not
/// what was copied.
///
/// ⚠️Surfaces are immutable with structural tile sharing, so holding one is
/// holding a reference, not a second set of pixels — until the source is
/// drawn over, when the copy keeps the tiles it took.
Map<FrameId, BitmapSurface> picturesShownBy({
  required BrushFrameStore store,
  required Iterable<Frame> cels,
  required BrushFrameKey Function(FrameId cel) keyOf,
}) => {
  for (final cel in cels) cel.id: ?store.bakedSurfaceOrNull(keyOf(cel.id)),
};

/// 🚨AND THE HANDWRITING COMES WITH THEM: a copied block starts with the
/// handwriting its source had on the conte, under the id it was given
/// ([placedClipFor]'s `handwriting`), in [cut] — 유저 2026-09-26 (cut-
/// duplicate-sheet-ink-Q1) 「복제는 전부 복사」: the same, and from there
/// on apart. [carrySurfaces], said of the blocks a copy wrote anew.
///
/// ⚠️Stored as it is: a row plane's surface is the sheet body's whatever
/// the cut's canvas, so there is nothing to fit, unlike a picture.
void carryConteHandwriting({
  required BrushFrameStore store,
  required CutId cut,
  required Map<String, String> copies,
  required BitmapSurface? Function(String inkId) handwritingOf,
}) => carrySurfaces(
  store: store,
  sources: copies.entries,
  surfaceOf: (copy) => handwritingOf(copy.value),
  keyOfCopy: (copy) => conteInkRowKey(cut, copy.key),
);

/// The handwriting the blocks of [exposures] show on [cut]'s conte as it is
/// NOW, by each block's id — what a copy takes BY VALUE, for
/// [picturesShownBy]'s reason.
Map<String, BitmapSurface> conteHandwritingShownBy({
  required BrushFrameStore store,
  required CutId cut,
  required Iterable<TimelineExposure> exposures,
}) => {
  for (final exposure in exposures)
    if (exposure.memo?.inkId case final inkId? when inkId.isNotEmpty)
      inkId: ?store.bakedSurfaceOrNull(conteInkRowKey(cut, inkId)),
};
