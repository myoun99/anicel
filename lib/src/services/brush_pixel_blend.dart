/// What a dab whose opacity is under one lays over [destinationAlpha]:
/// [laid] — what it would lay over nothing — scaled by how much of the way
/// to its [opacity] is left, or null where the pixel already stands there.
///
/// 🚨★★★A DAB'S OPACITY IS THE LEVEL IT SETTLES AT (F-205, 유저 2026-09-28:
/// 「최대 100%로 해두더라도 필압 약하게하면 해당 선들 겹쳐도 필압에맞춰서
/// 10%만큼만 진해진다」). A dab raises what is under it TOWARDS its opacity,
/// at its flow, and never past it: the ink its coverage and flow would lay
/// over nothing, scaled by how much of the way to the ceiling is left —
/// (o - d) / (1 - d). Over nothing that is exactly the old alpha, so a first
/// dab lands what it always did; where dabs pile up they settle at o, not at
/// opaque. ↩️Opacity multiplied the dab's alpha like flow did, and a light
/// press piled up to the full slider wherever a stroke crossed itself.
///
/// ⚠️What is under the dab is its STROKE's own buffer: a stroke of brush dabs
/// never lands on artwork dab by dab — it piles up on an empty buffer and
/// composites once (brush_commit_builder, erase-live-and-dab-route-round-
/// apart) — so d is how far the stroke itself has got, never the paint below.
///
/// An opacity of 1 settles at opaque, which is plain source-over — the old
/// arithmetic, kept byte for byte, so a brush whose opacity no dynamic moves
/// lands exactly what it did. An ERASE dab keeps the multiplier: a brush
/// eraser piles up coverage on its buffer (where this applies) and erases
/// once, and nothing else raises an alpha.
///
/// What the dab would lay whole goes through its share first ([evenedLaid]).
///
/// 🚨★★★AN EDGE SETTLES LOWER (board a-one-pixel-dab-drops-out-by-where-it-
/// lies Q4, 유저 2026-10-25 「AA 가장자리는 쌓이지 않는다」): where the tip's
/// coverage is part edge, the share of it that does not pile
/// (`edgeCeiling`) scales the level it settles at, and what it lays toward
/// it is the share that piles ([edgePiledShare]). At a ceiling of 1 both
/// are the numbers above to the bit; an erase keeps its multiplier.
///
/// This is the law's arithmetic for the brush swatch
/// (`rasterizeBrushStrokeSample`), which piled its dabs by the old
/// multiplied opacity until 2026-10-01. The engine's is `dab.wgsl`'s.
/// ↩️Till 2026-11-12 this text stood beside the C kernel's
/// `qa_dab_source_alpha`, which went with the C; till 2026-11-14 the Dart
/// reference blend read it too, which went with the off-engine commit.
double? settledDabAlpha({
  required double laid,
  required double opacity,
  required double destinationAlpha,
}) {
  if (destinationAlpha >= opacity) {
    return null;
  }
  return laid * (opacity - destinationAlpha) / (1.0 - destinationAlpha);
}
