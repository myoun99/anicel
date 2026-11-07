// How a camera lens blur reads the light it spreads — the app's
// lens_light.glsl `lit`, by the integer spec gpu-int-spec-canvas 1b (4/4)
// on held.wgsl's scale: a channel is 65535 at one, so a pixel read in its
// stored light with nothing boosted is held_read's, exactly.
//
// A stored pixel's straight colour is its bytes widened, or — in linear
// light — sRGB's curve out of LIGHT_LINEAR. Its luma is Rec. 709's, by
// the app's weights (`light_luma`). Past the threshold its colour gains
// t · tint: t = luma · gain · (luma − threshold), tint its own colour over
// the luma by the saturation and white by the rest — as bright as each
// other. Then premultiplied, which past 65535 a boosted channel may be:
// the sums are wide. And back (`light_stored`): what the blur gathered, as
// a picture stores it — ⛔both ways here, lens_light.glsl's ONE COPY: a
// pixel read one way and stored another would seam.
//
// Needs shared/wide.wgsl, blend/blend.wgsl and held.wgsl.

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

// Rec. 709's luma of a colour by the app's own weights — 0.2126, 0.7152 and
// 0.0722 (the light's lens_light.glsl `kLuma`, the map's shaded_passes.dart
// `luminance`) as ten-thousandths, rounded half up — on the 16-bit scale or
// on bytes alike: the light's, and a blur map's where it reads one
// (gather.wgsl). At most 10000 · 65535 + 5000: a u32.
// 📐THE APP'S WEIGHTS, NOT A NEARBY 2^16 (11-07, every byte triple against
// iris_gather.frag's ⌊dot(map, uChannel) · 255 + ½⌋ taken exactly):
// weights summing to 2^16 (13933 · 46871 · 4732) put 7,564 of the
// 16,777,216 map levels one off it, where a GPU running the app's float
// puts 192 to 253 — these put none.
fn light_luma(colour: vec3<u32>) -> u32 {
  return (2126u * colour.x + 7152u * colour.y + 722u * colour.z + 5000u) / 10000u;
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
  let luma = light_luma(colour);
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

// What a lens blur gathered — premultiplied on the 16-bit scale, a boosted
// channel past 65535 — as a picture stores it: no brighter than white, no
// colour past its alpha. ⚠️LIGHT PAST ITS ALPHA COVERS (🗣️I-132-Q20 a,
// 유저 2026-10-28): the alpha rises to the brightest channel, so a lamp's
// bokeh shows over a clear cel as over a dark one. A gather of no boost
// holds no channel past its alpha, and is stored as every blur stores it
// (blend_pack8_premultiplied); in linear light each straight channel is put
// back through sRGB's curve.
fn light_stored(gathered: vec4<u32>, light: Light) -> u32 {
  let brightest = max(gathered.x, max(gathered.y, gathered.z));
  let alpha = min(max(gathered.w, brightest), 65535u);
  // Past white a channel is cut to it: in linear light the division's bound
  // below — no byte tells it from its absence, the curve and
  // blend_pack8_premultiplied stopping at white too (gather mutant l5, 11-05).
  let covered = vec4<u32>(min(gathered.xyz, vec3<u32>(alpha)), alpha);
  if (light.linear == 0u) {
    return blend_pack8_premultiplied(covered);
  }
  let byte = blend_to8(alpha);
  if (byte == 0u) {
    return 0u;
  }
  var word = byte << 24u;
  for (var c = 0u; c < 3u; c++) {
    let straight = wide_divr(wide_mul_u32(covered[c], 65535u), Wide(alpha, 0u), 16u);
    word = word | (light_encoded(straight) << (c * 8u));
  }
  return word;
}

// The least straight light — on the 16-bit scale — each byte from 1 is
// stored from: sRGB's curve back and rounded to a byte, ⌊255 · c⁻¹(s /
// 65535) + ½⌋, as the app's lens_light.glsl `storedOf` and its render
// target put it; worked out once (no libm here), as LIGHT_LINEAR is.
// 📐THE APP'S ROUNDING, NOT THE NEAREST LIGHT (11-07, every straight value):
// ↩️until then the byte was the one whose LIGHT_LINEAR lay nearest — one
// table read back, no second one — and that put 44 of the 65536 values one
// byte from the app's (a lone grey 42 among black: 169 of light, 9 where
// the app stores 8); this table puts none. No value comes within 1.5e-6 of
// a byte of a tie, so the f64 that worked it out decides each.
var<private> LIGHT_STORED_FROM: array<u32, 255> = array<u32, 255>(
  10u, 30u, 50u, 70u, 90u, 110u, 130u, 150u,
  170u, 189u, 209u, 230u, 253u, 276u, 301u, 327u,
  354u, 382u, 412u, 443u, 475u, 509u, 544u, 580u,
  618u, 657u, 698u, 740u, 783u, 828u, 875u, 923u,
  972u, 1023u, 1075u, 1129u, 1185u, 1242u, 1300u, 1360u,
  1422u, 1486u, 1551u, 1617u, 1685u, 1755u, 1827u, 1900u,
  1975u, 2052u, 2130u, 2210u, 2292u, 2376u, 2461u, 2548u,
  2637u, 2727u, 2820u, 2914u, 3010u, 3108u, 3208u, 3309u,
  3412u, 3518u, 3625u, 3734u, 3844u, 3957u, 4072u, 4188u,
  4307u, 4427u, 4550u, 4674u, 4800u, 4928u, 5059u, 5191u,
  5325u, 5461u, 5599u, 5740u, 5882u, 6026u, 6173u, 6321u,
  6471u, 6624u, 6778u, 6935u, 7094u, 7255u, 7418u, 7583u,
  7750u, 7919u, 8091u, 8265u, 8440u, 8618u, 8798u, 8981u,
  9165u, 9352u, 9541u, 9732u, 9925u, 10121u, 10318u, 10518u,
  10720u, 10925u, 11132u, 11341u, 11552u, 11765u, 11981u, 12199u,
  12420u, 12643u, 12868u, 13095u, 13325u, 13557u, 13791u, 14028u,
  14267u, 14508u, 14752u, 14998u, 15247u, 15498u, 15751u, 16007u,
  16265u, 16525u, 16788u, 17054u, 17321u, 17592u, 17864u, 18139u,
  18417u, 18697u, 18980u, 19264u, 19552u, 19842u, 20134u, 20429u,
  20727u, 21027u, 21329u, 21634u, 21942u, 22252u, 22564u, 22880u,
  23197u, 23518u, 23840u, 24166u, 24494u, 24824u, 25158u, 25493u,
  25832u, 26173u, 26516u, 26862u, 27211u, 27563u, 27917u, 28273u,
  28633u, 28995u, 29359u, 29727u, 30097u, 30469u, 30845u, 31223u,
  31603u, 31987u, 32373u, 32762u, 33153u, 33547u, 33944u, 34344u,
  34747u, 35152u, 35560u, 35970u, 36384u, 36800u, 37219u, 37640u,
  38065u, 38492u, 38922u, 39355u, 39790u, 40229u, 40670u, 41114u,
  41561u, 42011u, 42463u, 42918u, 43377u, 43838u, 44301u, 44768u,
  45238u, 45710u, 46185u, 46663u, 47144u, 47628u, 48115u, 48605u,
  49097u, 49593u, 50091u, 50592u, 51096u, 51604u, 52114u, 52627u,
  53142u, 53661u, 54183u, 54708u, 55235u, 55766u, 56300u, 56836u,
  57376u, 57918u, 58464u, 59012u, 59564u, 60118u, 60675u, 61236u,
  61799u, 62366u, 62935u, 63508u, 64083u, 64662u, 65244u,
);

// The byte linear light `straight` is stored as: how many of
// LIGHT_STORED_FROM lie at or below it, found a bit at a time.
fn light_encoded(straight: u32) -> u32 {
  var byte = 0u;
  for (var step = 128u; step > 0u; step = step >> 1u) {
    let next = byte + step;
    if (next <= 255u && LIGHT_STORED_FROM[next - 1u] <= straight) {
      byte = next;
    }
  }
  return byte;
}
