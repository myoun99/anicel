// A selection's picture through R1 into a window (gpu-census 변형 리샘플 ·
// R3): each pixel of the window by its map — one map for every pixel (an
// affine's, a quad's), or the map of the mesh triangle that owns it
// (mesh.wgsl's owners) — from a box of straight RGBA8 words, row after
// row: the lift's picture (cel_pixel/lift.rs), a stamp's. The app's
// `_resampleIntoWindow` and `transformStampDabMesh`.
//
// A pixel no triangle owns is nothing, and so is one owned by a triangle
// that lands nothing (past R1's ranges): the app's `covered` keeps such a
// pixel from the triangles after it all the same.
//
// Needs shared/wide.wgsl and shared/resample.wgsl before it.

struct Warp {
  // The box's pixels across and down.
  width: u32,
  height: u32,
  // The window's pixels across and down, and where its top-left pixel is
  // in the output the maps measure from.
  columns: u32,
  rows: u32,
  left: i32,
  top: i32,
  // 1 where each pixel takes the map of its owner; 0 where every pixel
  // takes the first.
  owned: u32,
}

// A map in the table: R1's words (resample.rs's ResampleMap::words), then
// 1 where it lands anything.
const WARP_MAP_WORDS: u32 = 16u;

@group(0) @binding(0) var<uniform> warp: Warp;
@group(0) @binding(1) var<storage, read> maps: array<u32>;
// Each pixel's owner, row after row, as the window lies — read where
// `warp.owned` says. None is u32::MAX (mesh.wgsl), past any table.
@group(0) @binding(2) var<storage, read> owners: array<u32>;
@group(0) @binding(3) var<storage, read> picture: array<u32>;
@group(0) @binding(4) var<storage, read_write> warped: array<u32>;

fn resample_texel(source: u32, x: i32, y: i32) -> u32 {
  if (x < 0 || y < 0 || u32(x) >= warp.width || u32(y) >= warp.height) {
    return 0u;
  }
  return picture[u32(y) * warp.width + u32(x)];
}

@compute @workgroup_size(8, 8, 1)
fn warp_window(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x >= warp.columns || id.y >= warp.rows) {
    return;
  }
  let pixel = id.y * warp.columns + id.x;
  var map = 0u;
  if (warp.owned != 0u) {
    map = owners[pixel];
  }
  var word = 0u;
  if (map < arrayLength(&maps) / WARP_MAP_WORDS && maps[map * WARP_MAP_WORDS + 15u] != 0u) {
    let at = map * WARP_MAP_WORDS;
    let taken = resample_map(array<u32, 15>(
      maps[at], maps[at + 1u], maps[at + 2u], maps[at + 3u], maps[at + 4u], maps[at + 5u],
      maps[at + 6u], maps[at + 7u], maps[at + 8u], maps[at + 9u], maps[at + 10u],
      maps[at + 11u], maps[at + 12u], maps[at + 13u], maps[at + 14u],
    ));
    word = resample(taken, 0u, warp.left + i32(id.x), warp.top + i32(id.y));
  }
  warped[pixel] = word;
}
