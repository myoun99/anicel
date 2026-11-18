// A mixing brush's colour, a dab at a time (밑바탕 혼색 — the law beside
// `BrushGroundColorMixer`; board
// `the-mixing-brush-reads-a-whole-tile-back-for-its-ground`, 11-17). The
// brush carries a reservoir of paint: each step lifts the ground under its
// dab into it, is refilled with the drawing colour and lays a blend of the
// two. One workgroup walks the steps in the stroke's order — the reservoir
// is the chain —, its 64 lanes a step's 64 points of the ground, summed
// together; lane 0 moves the reservoir and logs what the step lays. Then
// every lane colours the pile's records the steps name, before the pile
// reads them: the dab kernel lays a colour it was handed, as it always has.
//
// The numbers a step brings are the app's (the brush's curves, its dice,
// the fitted constants — `brush_ground_color_mixing.dart`); what reads the
// ground is here. Floats, as the app's reservoir is unrounded: only what a
// step lays is rounded.

// The mix's plan: its head; the steps, MIX_STEP_WORDS each; then the
// records it colours, two words each — the place of a record's colour in
// the pile's plan and the step whose colour it takes.
@group(0) @binding(0) var<storage, read> mix_plan: array<u32>;
// The pile's plan (dab.wgsl), whose records' colours it puts.
@group(0) @binding(1) var<storage, read_write> mix_dab_plan: array<u32>;
// The ground: the cel's tiles the steps' points are on, as the executor
// copies a row whole — straight RGBA8, red lowest, tile after tile.
@group(0) @binding(2) var<storage, read> mix_ground: array<u32>;
// The stroke's book: the reservoir as the last step left it — red, green
// and blue, whether it holds any, and a dry brush's thickness —, and from
// MIX_BOOK_LOG what each step of the stroke laid, ARGB as the app's dabs
// hold a colour.
@group(0) @binding(3) var<storage, read_write> mix_book: array<u32>;

const MIX_LANES: u32 = 64u;
const MIX_NONE: u32 = 0xffffffffu;

const MIX_HEAD_STEPS: u32 = 0u;
const MIX_HEAD_FIRST: u32 = 1u;
const MIX_HEAD_RECORDS: u32 = 2u;
const MIX_HEAD_RECORD_COUNT: u32 = 3u;
const MIX_HEAD_WORDS: u32 = 4u;

// A step: the drawing colour's three bytes, red lowest, and its alpha; the
// reservoir's refill toward it and the share of it laid on top (a loaded
// brush's); its density (a loaded brush's thickness); a dry brush's
// pickup; the share of a whole stamp it is and what a whole stamp lifts —
// floats' bits —; 1 for a dry brush; how many of its points lie in its
// circle; and each lane's point, a word of the ground, MIX_NONE where it
// is out of the circle or on no tile of the cel.
const MIX_STEP_COLOUR: u32 = 0u;
const MIX_STEP_ALPHA: u32 = 1u;
const MIX_STEP_REFILL: u32 = 2u;
const MIX_STEP_LAID: u32 = 3u;
const MIX_STEP_DENSITY: u32 = 4u;
const MIX_STEP_TAKE: u32 = 5u;
const MIX_STEP_SHARE: u32 = 6u;
const MIX_STEP_PICK: u32 = 7u;
const MIX_STEP_DRY: u32 = 8u;
const MIX_STEP_CONSIDERED: u32 = 9u;
const MIX_STEP_POINTS: u32 = 10u;
const MIX_STEP_WORDS: u32 = 74u;

const MIX_BOOK_SEEDED: u32 = 3u;
const MIX_BOOK_HELD: u32 = 4u;
const MIX_BOOK_LOG: u32 = 8u;

var<workgroup> mix_sums: array<vec4<f32>, 64>;

fn mix_float(at: u32) -> f32 {
  return bitcast<f32>(mix_plan[at]);
}

// `here` moved `t` of the way to `to`, channel by channel.
fn mix_towards(here: vec3<f32>, to: vec3<f32>, t: f32) -> vec3<f32> {
  if (t <= 0.0) {
    return here;
  }
  if (t >= 1.0) {
    return to;
  }
  return here + (to - here) * t;
}

// What a step that is `share` of a whole stamp moves by, where a whole one
// would move by `pull`: `1 − (1 − pull)^share`, the flow's law
// (`_pickedUp`; `eveningTableFor` builds the same numbers for a table).
fn mix_picked_up(share: f32, pull: f32) -> f32 {
  if (share >= 1.0) {
    return pull;
  }
  return 1.0 - pow(1.0 - pull, share);
}

// The three bytes of `colour`, red lowest.
fn mix_unpack(colour: u32) -> vec3<f32> {
  return vec3<f32>(
    f32(colour & 0xffu),
    f32((colour >> 8u) & 0xffu),
    f32((colour >> 16u) & 0xffu),
  );
}

// A value on 0..=255 rounded half up, as the app's `round` takes one.
fn mix_byte(value: f32) -> u32 {
  return u32(clamp(floor(value + 0.5), 0.0, 255.0));
}

// What lane `lane`'s point of the step at `at` adds to the sums: its
// colour by its alpha, and its alpha — nothing off the cel's tiles.
fn mix_point(at: u32, lane: u32) -> vec4<f32> {
  let point = mix_plan[at + MIX_STEP_POINTS + lane];
  if (point == MIX_NONE) {
    return vec4<f32>(0.0);
  }
  let texel = mix_ground[point];
  let alpha = f32(texel >> 24u) / 255.0;
  if (alpha <= 0.0) {
    return vec4<f32>(0.0);
  }
  return vec4<f32>(mix_unpack(texel) * alpha, alpha);
}

@compute @workgroup_size(64)
fn mix_steps(@builtin(local_invocation_index) lane: u32) {
  let first = mix_plan[MIX_HEAD_FIRST];
  // Lane 0's alone: the reservoir as the walk moves it.
  var paint = vec3<f32>(
    bitcast<f32>(mix_book[0]),
    bitcast<f32>(mix_book[1]),
    bitcast<f32>(mix_book[2]),
  );
  var seeded = mix_book[MIX_BOOK_SEEDED] != 0u;
  var held = bitcast<f32>(mix_book[MIX_BOOK_HELD]);
  for (var step = 0u; step < mix_plan[MIX_HEAD_STEPS]; step += 1u) {
    let at = MIX_HEAD_WORDS + step * MIX_STEP_WORDS;
    mix_sums[lane] = mix_point(at, lane);
    workgroupBarrier();
    for (var half = MIX_LANES / 2u; half > 0u; half = half / 2u) {
      if (lane < half) {
        mix_sums[lane] = mix_sums[lane] + mix_sums[lane + half];
      }
      workgroupBarrier();
    }
    if (lane == 0u) {
      // The ground: its painted pixels' colour, and how much of the circle
      // they cover — bare canvas lends the reservoir nothing.
      let sum = mix_sums[0];
      let considered = f32(mix_plan[at + MIX_STEP_CONSIDERED]);
      var ground = vec3<f32>(0.0);
      var coverage = 0.0;
      if (considered > 0.0 && sum.w > 0.0) {
        ground = clamp(floor(sum.xyz / sum.w + 0.5), vec3<f32>(0.0), vec3<f32>(255.0));
        coverage = clamp(sum.w / considered, 0.0, 1.0);
      }
      let drawing = mix_unpack(mix_plan[at + MIX_STEP_COLOUR]);
      var deposit: vec3<f32>;
      var thickness: f32;
      if (mix_plan[at + MIX_STEP_DRY] == 0u) {
        var carried = select(drawing, paint, seeded);
        if (coverage > 0.0) {
          let pull = mix_float(at + MIX_STEP_PICK) * coverage;
          let share = mix_float(at + MIX_STEP_SHARE);
          carried = mix_towards(carried, ground, mix_picked_up(share, pull));
        }
        carried = mix_towards(carried, drawing, mix_float(at + MIX_STEP_REFILL));
        paint = carried;
        seeded = true;
        deposit = mix_towards(carried, drawing, mix_float(at + MIX_STEP_LAID));
        thickness = mix_float(at + MIX_STEP_DENSITY);
      } else {
        let take = mix_float(at + MIX_STEP_TAKE);
        let now = held + (coverage - held) * take;
        if (now > 0.0) {
          paint = mix_towards(select(ground, paint, seeded), ground, coverage * take / now);
          seeded = true;
        }
        held = now;
        deposit = select(drawing, paint, seeded);
        thickness = now;
      }
      let alpha = mix_byte(f32(mix_plan[at + MIX_STEP_ALPHA]) * thickness);
      mix_book[MIX_BOOK_LOG + first + step] = alpha << 24u
        | mix_byte(deposit.x) << 16u
        | mix_byte(deposit.y) << 8u
        | mix_byte(deposit.z);
    }
    workgroupBarrier();
  }
  if (lane == 0u) {
    mix_book[0] = bitcast<u32>(paint.x);
    mix_book[1] = bitcast<u32>(paint.y);
    mix_book[2] = bitcast<u32>(paint.z);
    mix_book[MIX_BOOK_SEEDED] = select(0u, 1u, seeded);
    mix_book[MIX_BOOK_HELD] = bitcast<u32>(held);
  }
  storageBarrier();
  let records = mix_plan[MIX_HEAD_RECORDS];
  for (var record = lane; record < mix_plan[MIX_HEAD_RECORD_COUNT]; record += MIX_LANES) {
    let place = mix_plan[records + 2u * record];
    let laid = mix_book[MIX_BOOK_LOG + mix_plan[records + 2u * record + 1u]];
    mix_dab_plan[place] = ((laid >> 16u) & 0xffu) | (laid & 0xff00u) | ((laid & 0xffu) << 16u);
    mix_dab_plan[place + 1u] = (laid >> 24u) * 257u;
  }
}
