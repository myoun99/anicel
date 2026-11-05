// How a camera lens blur reads the light it spreads — the app's
// lens_light.glsl `lit`, by the integer spec gpu-int-spec-canvas 1b (4/4)
// on held.wgsl's scale: a channel is 65535 at one, so a pixel read in its
// stored light with nothing boosted is held_read's, exactly.
//
// A stored pixel's straight colour is its bytes widened, or — in linear
// light — sRGB's curve out of LIGHT_LINEAR. Its luma is Rec. 709's,
// weights summing to 2^16. Past the threshold its colour gains
// t · tint: t = luma · gain · (luma − threshold), tint its own colour over
// the luma by the saturation and white by the rest — as bright as each
// other. Then premultiplied, which past 65535 a boosted channel may be:
// the sums are wide.
//
// Needs shared/wide.wgsl and blend/blend.wgsl before it.

// sRGB's curve to linear light, round(65535 · c(byte / 255)), worked out
// once (no libm here) — gpu-int-spec-canvas 1b (4/4) ①: a table in the
// source. A var, as a const indexed by a value read is not.
var<private> LIGHT_LINEAR: array<u32, 256> = array<u32, 256>(
  0u, 20u, 40u, 60u, 80u, 99u, 119u, 139u,
  159u, 179u, 199u, 219u, 241u, 264u, 288u, 313u,
  340u, 367u, 396u, 427u, 458u, 491u, 526u, 562u,
  599u, 637u, 677u, 718u, 761u, 805u, 851u, 898u,
  947u, 997u, 1048u, 1101u, 1156u, 1212u, 1270u, 1330u,
  1391u, 1453u, 1517u, 1583u, 1651u, 1720u, 1790u, 1863u,
  1937u, 2013u, 2090u, 2170u, 2250u, 2333u, 2418u, 2504u,
  2592u, 2681u, 2773u, 2866u, 2961u, 3058u, 3157u, 3258u,
  3360u, 3464u, 3570u, 3678u, 3788u, 3900u, 4014u, 4129u,
  4247u, 4366u, 4488u, 4611u, 4736u, 4864u, 4993u, 5124u,
  5257u, 5392u, 5530u, 5669u, 5810u, 5953u, 6099u, 6246u,
  6395u, 6547u, 6700u, 6856u, 7014u, 7174u, 7335u, 7500u,
  7666u, 7834u, 8004u, 8177u, 8352u, 8528u, 8708u, 8889u,
  9072u, 9258u, 9445u, 9635u, 9828u, 10022u, 10219u, 10417u,
  10619u, 10822u, 11028u, 11235u, 11446u, 11658u, 11873u, 12090u,
  12309u, 12530u, 12754u, 12980u, 13209u, 13440u, 13673u, 13909u,
  14146u, 14387u, 14629u, 14874u, 15122u, 15371u, 15623u, 15878u,
  16135u, 16394u, 16656u, 16920u, 17187u, 17456u, 17727u, 18001u,
  18277u, 18556u, 18837u, 19121u, 19407u, 19696u, 19987u, 20281u,
  20577u, 20876u, 21177u, 21481u, 21787u, 22096u, 22407u, 22721u,
  23038u, 23357u, 23678u, 24002u, 24329u, 24658u, 24990u, 25325u,
  25662u, 26001u, 26344u, 26688u, 27036u, 27386u, 27739u, 28094u,
  28452u, 28813u, 29176u, 29542u, 29911u, 30282u, 30656u, 31033u,
  31412u, 31794u, 32179u, 32567u, 32957u, 33350u, 33745u, 34143u,
  34544u, 34948u, 35355u, 35764u, 36176u, 36591u, 37008u, 37429u,
  37852u, 38278u, 38706u, 39138u, 39572u, 40009u, 40449u, 40891u,
  41337u, 41785u, 42236u, 42690u, 43147u, 43606u, 44069u, 44534u,
  45002u, 45473u, 45947u, 46423u, 46903u, 47385u, 47871u, 48359u,
  48850u, 49344u, 49841u, 50341u, 50844u, 51349u, 51858u, 52369u,
  52884u, 53401u, 53921u, 54445u, 54971u, 55500u, 56032u, 56567u,
  57105u, 57646u, 58190u, 58737u, 59287u, 59840u, 60396u, 60955u,
  61517u, 62082u, 62650u, 63221u, 63795u, 64372u, 64952u, 65535u,
);

// A lens blur's light as the host gives it: its gain (Q.16, to 100), its
// threshold on the 16-bit scale, its saturation (Q.16, to 1) and 1 where it
// reads in linear light.
struct Light {
  gain: u32,
  threshold: u32,
  saturation: u32,
  linear: u32,
}

// A stored word as the lens blur sums it: premultiplied on the 16-bit
// scale, a boosted channel up to 101 times 65535.
fn light_read(word: u32, light: Light) -> vec4<u32> {
  let pixel = blend_unpack8(word);
  // A clear pixel is nothing, as premultiplying by no alpha below would
  // also make it — skipped for the boost's work, not changed (mutant t1,
  // 11-05: no value tells this line from its absence).
  if (pixel.w == 0u) {
    return vec4<u32>(0u);
  }
  var colour = pixel.xyz;
  if (light.linear == 1u) {
    colour = vec3<u32>(
      LIGHT_LINEAR[word & 0xffu],
      LIGHT_LINEAR[(word >> 8u) & 0xffu],
      LIGHT_LINEAR[(word >> 16u) & 0xffu],
    );
  }
  // At most 65536 · 65535 + 2^15: a u32.
  let luma = (13933u * colour.x + 46871u * colour.y + 4732u * colour.z + 32768u) >> 16u;
  var lit = colour;
  // No gain or no luma past the threshold boosts by nothing, as the sums
  // below would also say — they are skipped, not changed (so `>=` here
  // gives the same values: mutant t6, 11-05).
  if (light.gain > 0u && luma > light.threshold) {
    let gained = wide_round(wide_mul_u32(luma, light.gain), 16u).x;
    let t = wide_divr(wide_mul_u32(gained, luma - light.threshold), Wide(65535u, 0u), 24u);
    let white = wide_mul_u32(65536u - light.saturation, 65536u);
    for (var c = 0u; c < 3u; c++) {
      let over_luma = wide_divr(wide_mul_u32(colour[c], 65536u), Wide(max(luma, 1u), 0u), 32u);
      let tint = wide_round(wide_add(white, wide_mul_u32(light.saturation, over_luma)), 16u);
      // gain · (luma − threshold) · ((1 − s) · luma + s · colour) at most:
      // under 2^23.
      lit[c] = colour[c] + wide_round(wide_mul(Wide(t, 0u), tint), 16u).x;
    }
  }
  var premultiplied = vec4<u32>(0u, 0u, 0u, pixel.w);
  for (var c = 0u; c < 3u; c++) {
    if (lit[c] <= 65535u) {
      premultiplied[c] = blend_mul(lit[c], pixel.w);
    } else {
      // blend_mul's rounding — to the nearest, there being no half over
      // 65535 — on a wider product.
      premultiplied[c] = wide_divr(wide_mul_u32(lit[c], pixel.w), Wide(65535u, 0u), 24u);
    }
  }
  return premultiplied;
}
