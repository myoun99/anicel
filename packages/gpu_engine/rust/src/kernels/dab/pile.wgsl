// The dab kernel's walk (dab.wgsl) over a stroke's tiles where they are
// kept, as the pool keeps a stored tile: a tile a slot of a page, its
// planes, its view and its second plane each on a page of their own, the
// three at the same k of a pass (shared/pages.rs; 캔버스 베이스 11-06
// 04:18, (가) the pool's form). A pass takes a run of the tiles.
//
// Needs dab.wgsl, then the pages named `planes`, `view` and `levels`
// (pages.rs's `Pages::named`), before it:
// - planes: a slot TILE_TEXELS pixels, two words a pixel — red and green,
//   then blue and alpha, the low half first;
// - view: their bytes (blend_pack8, dab_shown), a word a pixel;
// - levels: the second tip's plane, alpha alone, a word a pixel as the
//   view — where the stroke has a second tip; blank where it has none.

// The pass's run: where it starts among the plan's tiles, and where the
// plan holds each tile's k — its page's binding among the pass's.
@group(0) @binding(1) var<uniform> pile_run: vec4<u32>;

// What a stroke with a second tip shows where its first plane stands
// `first` high and its second `level` (`dualViewAlpha`, which has the
// law): the second blended over the first by the stroke's mode at its
// density — the second the source, the first the destination. Where the
// first tip laid nothing, nothing shows.
fn dab_shown(first: u32, level: u32) -> u32 {
  if (first == 0u) {
    return 0u;
  }
  let mode = plan[HEAD_SECOND];
  let density = plan[HEAD_SECOND_DENSITY];
  if (mode == BLEND_MULTIPLY) {
    // ⛔MULTIPLY KEEPS ITS OWN LINE (`dualViewLevel`): a·((1 − d) + d·s),
    // the default written plainly — the general form is the same number
    // and not the same rounding.
    return blend_mul(first, W_ONE - density + blend_mul(density, level));
  }
  // Never past W_ONE, which the C engine's double could round to: as
  // blend_mul only rises with what it multiplies, the two terms come to
  // at most W_ONE − density and density.
  return blend_mul(first, W_ONE - density) + blend_mul(density, blend_channel(mode, level, first));
}

@compute @workgroup_size(8, 8)
fn walk(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_id) local: vec3<u32>,
) {
  let index = pile_run.x + group.z;
  let tile = plan[HEAD_TILES] + index * TILE_WORDS;
  let k = plan[pile_run.y + index];
  let lx = group.x * 8u + local.x;
  let ly = group.y * 8u + local.y;
  let x = bitcast<i32>(plan[tile + TILE_COLUMN]) * i32(TILE_SIDE) + i32(lx);
  let y = bitcast<i32>(plan[tile + TILE_ROW]) * i32(TILE_SIDE) + i32(ly);
  let texel = plan[tile + TILE_SLOT] * TILE_TEXELS + tile_texel(lx, ly);
  let low = texel * 2u;
  var pixel = blend_unpack16(vec2<u32>(planes_word(k, low), planes_word(k, low + 1u)));
  var paper = 0u;
  if (plan[HEAD_PAPER] != NO_TABLE) {
    paper = dab_paper(tile, lx, ly);
  }
  let shown = plan[HEAD_SECOND] != NO_TABLE;
  var level = 0u;
  if (shown) {
    level = levels_word(k, texel);
  }
  let first = plan[tile + TILE_FIRST];
  let count = plan[tile + TILE_COUNT];
  for (var each = 0u; each < count; each = each + 1u) {
    let at = plan[first + each];
    if ((plan[at + DAB_FLAGS] & DAB_SECOND) == 0u) {
      pixel = dab_lay(at, x, y, pixel, paper);
      continue;
    }
    // A second tip's dab piles its plane as any dab piles its alpha. On a
    // stroke with no second plane it lays nothing (`blendDabTilesDart`).
    let source = dab_source(at, x, y, level, paper);
    if (source != NOTHING) {
      level = blend_alpha_over(source, level);
    }
  }
  let pair = blend_pack16(pixel);
  planes_put(k, low, pair.x);
  planes_put(k, low + 1u, pair.y);
  if (shown) {
    levels_put(k, texel, level);
    view_put(k, texel, blend_pack8(vec4<u32>(pixel.xyz, dab_shown(pixel.w, level))));
  } else {
    view_put(k, texel, blend_pack8(pixel));
  }
}
