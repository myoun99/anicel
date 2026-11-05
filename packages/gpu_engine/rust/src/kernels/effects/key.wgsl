// A run of colour keys over one straight pixel (gpu-int-spec-canvas 1b
// (3/4) F2, C's `qa_key_rgba`, which this takes over): its alpha what the
// keys leave it, its colour as it was. The executor's rows call it on a
// row's pixel before the row is laid (gpu-canonical-store ⑥).
//
// ⛔NO KEY IS DEFINED HERE. Which keys name a pixel and what each leaves of
// an alpha are TABLES the app makes from its one definition (`CelColorKey`);
// this walks them. A run is a block of words its host reads through
//   fn key_word(at: u32) -> u32
// — the word `at` of whichever buffer holds the runs:
//   [0, 256)          red: bit k says key k is within its tolerance of the
//                     pixel's red
//   [256, 512)        green, the same
//   [512, 768)        blue, the same
//   768               restores: bit k says key k gives back what the run
//                     erased of what it names (AE's Keep Colors, I-132-Q2)
//   769 + 64·k ...    key k's alpha map, 256 bytes four a word, low first:
//                     what key k leaves of an alpha
// Thirty-two keys at most a run; a longer chain is walked thirty-two at a
// time, in its order, each part against the same `original`.

const KEY_GREEN: u32 = 256u;
const KEY_BLUE: u32 = 512u;
const KEY_RESTORES: u32 = 768u;
const KEY_MAPS: u32 = 769u;
const KEY_MAP_WORDS: u32 = 64u;

// The byte of the map at `map` for an alpha `alpha`.
fn key_map(map: u32, alpha: u32) -> u32 {
  return (key_word(map + (alpha >> 2u)) >> ((alpha & 3u) * 8u)) & 0xffu;
}

// What the run at `run` leaves of `alpha` on a pixel of colour `rgb`
// (bytes) whose alpha was `original` before the run — a restore gives back
// to it, so `alpha` is never above it. A pixel empty before the run stays
// as it is.
fn key_alpha(run: u32, rgb: vec3<u32>, alpha: u32, original: u32) -> u32 {
  if (original == 0u) {
    return alpha;
  }
  var naming = key_word(run + rgb.x) & key_word(run + KEY_GREEN + rgb.y)
    & key_word(run + KEY_BLUE + rgb.z);
  var restoring = key_word(run + KEY_RESTORES);
  var next = alpha;
  var map = run + KEY_MAPS;
  while (naming != 0u) {
    if ((naming & 1u) != 0u) {
      if ((restoring & 1u) != 0u) {
        next = original - key_map(map, original - next);
      } else {
        next = key_map(map, next);
      }
    }
    naming >>= 1u;
    restoring >>= 1u;
    map += KEY_MAP_WORDS;
  }
  return next;
}

// The run at `run` over a straight RGBA8 word (A<<24|B<<16|G<<8|R) whose
// alpha was `original` before the run.
fn key_rgba8(run: u32, texel: u32, original: u32) -> u32 {
  let rgb = vec3<u32>(texel & 0xffu, (texel >> 8u) & 0xffu, (texel >> 16u) & 0xffu);
  return (texel & 0xffffffu) | (key_alpha(run, rgb, texel >> 24u, original) << 24u);
}
