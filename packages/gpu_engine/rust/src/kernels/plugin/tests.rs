//! The device's run of a plugin held to the CPU's, pixel for pixel and cut
//! for cut. That is no CPU copy of a kernel's formula (kernels/mod.rs): a
//! plugin's formula is written once, by its author, and both runs run the
//! same counted module — the CPU's is the run the chain's plan asks the
//! reach of anyway (fx_wgsl's run.rs), and what it computes is WGSL's.

use std::time::Duration;

use fx_wgsl::{Cut, Frame, Kernel, open, open_uncut};

use super::{Batches, Pace, Plugin, Tiled};
use crate::device::gpu_engine_waits_here;
use crate::kernels::chain::tests::put_over;
use crate::kernels::composite::TILE;
use crate::kernels::effects::blur::TileRect;
use crate::kernels::shared::le_bytes;
use crate::kernels::shared::{Encoded, encode, pipeline_or_why, whole};
use crate::testing::first_engine;

const INVERT: &str = include_str!("../../../native/fx_wgsl/fixtures/invert.wgsl");
const BLUR: &str = include_str!("../../../native/fx_wgsl/fixtures/blur.wgsl");
const LAYER: &str = include_str!("../../../native/fx_wgsl/fixtures/layer.wgsl");
const ENDLESS: &str = include_str!("../../../native/fx_wgsl/fixtures/endless.wgsl");
const ROW_BLUR: &str = include_str!("../../../native/fx_wgsl/fixtures/row_blur.wgsl");
const HISTOGRAM: &str = include_str!("../../../native/fx_wgsl/fixtures/histogram.wgsl");
const GROUP_SUM: &str = include_str!("../../../native/fx_wgsl/fixtures/group_sum.wgsl");

/// `count` words, each its place hashed — every channel and every bit
/// varied.
pub(super) fn hashed(count: usize, seed: u32) -> Vec<u32> {
    (0..count as u32).map(|i| (i ^ seed).wrapping_mul(2654435761).rotate_left(i % 29) ^ seed).collect()
}

/// What one run is handed: its output `size` at canvas (10, 20), its input
/// and two layer planes `reach` wider, and `values`.
struct Given {
    size: [i32; 2],
    reach: i32,
    input: Vec<u32>,
    rows: Vec<u32>,
    values: Vec<[i32; 4]>,
    fuel: u32,
}

impl Given {
    fn new(size: [i32; 2], reach: i32, values: &[[i32; 4]]) -> Self {
        let plane = ((size[0] + 2 * reach) * (size[1] + 2 * reach)) as usize;
        Given { size, reach, input: hashed(plane, 1), rows: hashed(2 * plane, 2), values: values.to_vec(), fuel: 1_000_000 }
    }

    fn frame(&self) -> Frame<'_> {
        Frame {
            out_origin: [10, 20],
            out_size: self.size,
            in_origin: [10 - self.reach, 20 - self.reach],
            in_size: [self.size[0] + 2 * self.reach, self.size[1] + 2 * self.reach],
            frame: 3,
            time_q16: 3 << 16,
            rate_q16: 24 << 16,
            scale_q16: 1 << 16,
            fuel: self.fuel,
            input: &self.input,
            rows: &self.rows,
            values: &self.values,
        }
    }
}

/// `source`'s picture and cut from the device and from the CPU, each run
/// from the same output words.
fn both(source: &str, given: &Given) -> [(Vec<u32>, Result<(), Cut>); 2] {
    let engine = first_engine();
    let kernel = open(source).unwrap_or_else(|refusal| panic!("refused: {refusal}"));
    let frame = given.frame();
    let start = hashed((given.size[0] * given.size[1]) as usize, 3);
    let mut cpu = start.clone();
    let cpu_cut = kernel.render(&frame, &mut cpu);
    let plugin = Plugin::open(engine, kernel).unwrap_or_else(|why| panic!("the device refused: {why}"));
    let mut gpu = start;
    let gpu_cut = plugin.render(engine, &frame, &mut gpu).expect("the device ran it");
    [(gpu, gpu_cut), (cpu, cpu_cut)]
}

/// The first pixel the two runs differ at, as (x, y, device, CPU).
fn first_apart(size: [i32; 2], gpu: &[u32], cpu: &[u32]) -> Option<(i32, i32, u32, u32)> {
    let at = gpu.iter().zip(cpu).position(|(a, b)| a != b)? as i32;
    Some((at % size[0], at / size[0], gpu[at as usize], cpu[at as usize]))
}

fn assert_alike(name: &str, given: &Given, source: &str) -> Result<(), Cut> {
    let [(gpu, gpu_cut), (cpu, cpu_cut)] = both(source, given);
    assert_eq!(gpu_cut, cpu_cut, "{name}: cut on one run alone");
    // A cut run's words are no picture — the host keeps none of them — and
    // an invocation that enters once the run is cut is handed no share
    // (prelude `anicel_host_enter`, Q19 ③), so what each drew before the
    // cut reached it is the order the two ran their invocations in.
    if gpu_cut.is_ok() {
        assert_eq!(first_apart(given.size, &gpu, &cpu), None, "{name}: (x, y, device, CPU)");
    }
    gpu_cut
}

#[test]
fn every_fixture_draws_on_the_device_what_the_cpu_draws() {
    // 37 × 23 leaves every workgroup shape a part group at the right and
    // the bottom; the blur's reach is its value's radius.
    for (name, source, given) in &fixtures([37, 23]) {
        assert_eq!(assert_alike(name, given, source), Ok(()), "{name}: not cut");
    }
}

/// A plugin's group is any shape of 256 invocations (fx_wgsl's check), so
/// the tallest is one across and 256 down — which the device the engine
/// opens gives a group for it (`used`, in `device.rs`: the engine's own
/// groups go 16 down).
#[test]
fn a_group_one_across_and_256_down_draws_on_the_device_what_the_cpu_draws() {
    let source = "@compute @workgroup_size(1, 256)\nfn anicel_render(@builtin(global_invocation_id) at: vec3<u32>) {\n\
                  let here = anicel_here();\nanicel_out(anicel_in(here.x, here.y) ^ u32(here.x * 31 + here.y));\n}\n\
                  fn anicel_reach() -> u32 { return 0u; }";
    assert_eq!(assert_alike("one across, 256 down", &Given::new([3, 300], 0, &[]), source), Ok(()));
}

#[test]
fn an_endless_plugin_is_cut_on_the_device_where_the_cpu_cuts_it() {
    let mut given = Given::new([19, 7], 0, &[]);
    given.fuel = 5_000;
    assert_eq!(assert_alike("endless", &given, ENDLESS), Err(Cut));
}

#[test]
fn a_pixel_the_plugin_does_not_write_keeps_its_word_on_the_device() {
    let source = "@compute @workgroup_size(8, 8)\nfn anicel_render(@builtin(global_invocation_id) at: vec3<u32>) {\n\
                  let here = anicel_here();\nif ((here.x & 1) == 0) { anicel_out(anicel_in(here.x, here.y)); }\n}\n\
                  fn anicel_reach() -> u32 { return 0u; }";
    let given = Given::new([13, 9], 0, &[]);
    let [(gpu, _), (cpu, _)] = both(source, &given);
    let start = hashed(13 * 9, 3);
    assert_eq!(first_apart(given.size, &gpu, &cpu), None);
    assert_eq!(gpu[1], start[1], "an odd pixel keeps the word it started with");
    assert_eq!(gpu[0], given.input[0], "an even one is the input's");
}

#[test]
fn a_blur_given_no_values_binds_them_all_the_same() {
    // No value at all: the values' binding still holds a value's words,
    // none of them read — `anicel_value` answers 0 past the count.
    assert_eq!(assert_alike("blur, no values", &Given::new([9, 9], 0, &[]), BLUR), Ok(()));
}

#[test]
fn an_empty_output_runs_nothing_on_either() {
    assert_eq!(assert_alike("empty", &Given::new([0, 5], 0, &[]), INVERT), Ok(()));
}

#[test]
fn the_devices_integers_are_wgsls_as_the_cpu_computes_them() {
    // A row a family of operations, each pixel its own operands: where a
    // backend lowers one apart from WGSL — a division by zero, the most
    // negative over -1, a shift past 31, an index past an array's end, a
    // field past a word's end, an unsigned pack inside a wider expression
    // (fx_wgsl count.rs's 🔧) — the row and the column say which.
    let source = "\
fn op(row: i32, x: i32, y: i32, wide: i32) -> u32 {
  let low = anicel_value(0, 2);
  let minus = anicel_value(0, 1);
  let d = y - 2;
  let w = u32(wide);
  var table = array<u32, 5>(11u, 22u, 33u, 44u, 55u);
  var r = 0u;
  switch row {
    case 0: { r = u32(x / d) ^ ((w / u32(d)) << 7u); }
    case 1: { r = u32(x % d) ^ ((w % u32(d)) << 9u); }
    case 2: {
      r = u32(select(x, low, (x & 1) == 0) / select(d, minus, (x & 2) == 0))
        ^ u32(select(x, low, (x & 4) == 0) % minus);
    }
    case 3: { r = (w << u32(x + 16)) ^ u32(wide >> u32(x + 20)) ^ (w >> u32(x + 24)); }
    case 4: {
      table[u32(x)] = 99u;
      r = table[u32(x - 3)] ^ (table[4] << 8u) ^ (table[w % 9u] << 16u);
    }
    case 5: {
      r = countOneBits(w) ^ (u32(countLeadingZeros(wide)) << 6u) ^ (countTrailingZeros(w) << 12u)
        ^ (u32(firstLeadingBit(wide)) << 18u) ^ (firstTrailingBit(w) << 24u) ^ reverseBits(u32(x));
    }
    case 6: {
      r = u32(extractBits(wide, u32(x + 20), u32(y * 9))) ^ extractBits(w, u32(x + 25), 12u)
        ^ insertBits(w, u32(x), u32(y * 7), u32(x + 22));
    }
    case 7: {
      r = pack4xI8Clamp(vec4<i32>(x * 40, -wide, wide, y)) ^ pack4xU8Clamp(vec4<u32>(u32(x * 30), w, 3u, 0u))
        ^ u32(dot4I8Packed(w, u32(x) * 16843009u)) ^ dot4U8Packed(w, 0x01ff7f80u)
        ^ u32(dot(unpack4xI8(w), vec4<i32>(1, -2, 3, -4)));
    }
    case 8: {
      r = u32(abs(select(wide, low, (x & 1) == 0))) ^ u32(sign(wide)) ^ u32(-select(wide, low, (x & 2) == 0))
        ^ u32(clamp(wide, -x * 1000, x * 1000)) ^ u32(min(wide, x) + max(wide, y));
    }
    case 9: {
      let v = vec4<u32>(u32(x * 30), w, 3u, w >> 24u);
      r = (pack4xU8(v) + 1u) ^ (pack4xU8Clamp(v) << 3u) ^ u32(pack4xU8(v) == w) ^ (pack4xI8(vec4<i32>(v)) * 3u)
        ^ dot(unpack4xU8(w) + vec4<u32>(1u), vec4<u32>(1u, 2u, 3u, 4u));
    }
    default: { r = u32(wide * 1103515245 + 12345) ^ (u32(x) - w); }
  }
  return r;
}

@compute @workgroup_size(16, 4)
fn anicel_render(@builtin(global_invocation_id) at: vec3<u32>) {
  let here = anicel_here();
  let x = here.x - 10 - 20;
  let y = (here.y - 20) / 11;
  let wide = i32((u32(x) ^ (u32(y) << 16u)) * 2654435761u);
  anicel_out(op((here.y - 20) % 11, x, y, wide));
}

fn anicel_reach() -> u32 { return 0u; }";
    let given = Given::new([40, 55], 0, &[[0, -1, i32::MIN, 33]]);
    assert_eq!(assert_alike("integers", &given, source), Ok(()));
}

#[test]
fn what_the_device_will_not_compile_comes_back_as_why() {
    let why = pipeline_or_why(first_engine(), &["@compute @workgroup_size(1) fn main() { let x: u32 = 1.5; }"], "main")
        .expect_err("refused");
    assert!(!why.is_empty());
}

#[test]
fn a_foreign_shader_reads_no_word_a_workgroup_before_it_left() {
    // 🔬256 words over 64 workgroups read clean with the zeroing off on the
    // RTX 4080; the whole 16 KiB over 4096 reddens every run (2026-11-09).
    const LEFT_OVER: &str = "
        @group(0) @binding(0) var<storage, read_write> seen: array<u32>;
        var<workgroup> left: array<u32, 4096>;
        @compute @workgroup_size(1)
        fn main(@builtin(global_invocation_id) at: vec3<u32>) {
            var any = 0u;
            for (var i = 0u; i < 4096u; i++) {
                any |= left[i];
                left[i] = (at.x + 1u) * 0x01010101u + i;
            }
            seen[at.x] = any;
        }";
    const GROUPS: u32 = 4096;
    let engine = first_engine();
    let pipeline = pipeline_or_why(engine, &[LEFT_OVER], "main").expect("compiled");
    let size = u64::from(GROUPS) * 4;
    let seen = engine.device().create_buffer(&wgpu::BufferDescriptor {
        label: None,
        size,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    });
    encode(engine, &[Encoded { pipeline: &pipeline, bound: whole(&[(0, &seen)]), groups: (GROUPS, 1, 1) }]);
    assert_eq!(crate::testing::read_buffer(engine, &seen), vec![0u8; size as usize]);
}


#[test]
fn a_big_plugin_compiles_whatever_thread_asks() {
    // 🔬One of 12 thousand IR expressions and 20 loops overflowed a 1 MiB
    // stack in D3D12's compiler (release, 2026-11-08) — Windows' main
    // thread has 1 MiB. Asked from such a thread, it compiles on its own.
    let mut body = String::from("let here = anicel_here();\nvar a = u32(here.x);\nvar b = u32(here.y);\n");
    for i in 0..1000 {
        if i % 50 == 0 {
            body.push_str(&format!("for (var i{i} = 0u; i{i} < b % 3u; i{i}++) {{ a = a ^ (b >> {}u); }}\n", i % 31));
        } else {
            body.push_str(&format!("a = a * {}u + (b ^ {}u);\nb = (b << {}u) ^ a;\n", 2 * i + 3, i, i % 31));
        }
    }
    let source = format!(
        "@compute @workgroup_size(16, 16)\nfn anicel_render(@builtin(global_invocation_id) at: vec3<u32>) {{\n{body}\
         anicel_out(a ^ b);\n}}\nfn anicel_reach() -> u32 {{ return 0u; }}"
    );
    let kernel = open(&source).unwrap_or_else(|refusal| panic!("refused: {refusal}"));
    let small = std::thread::Builder::new().stack_size(1 << 20);
    let opened = small.spawn(move || Plugin::open(first_engine(), kernel).map(|_| ())).expect("a thread").join();
    assert_eq!(opened.expect("the asking thread lived"), Ok(()));
}

/// The fixtures, each with what it is handed over `size`.
fn fixtures(size: [i32; 2]) -> [(&'static str, &'static str, Given); 6] {
    [
        ("invert", INVERT, Given::new(size, 0, &[])),
        ("blur", BLUR, Given::new(size, 3, &[[3 << 16, 0, 0, 0]])),
        ("layer", LAYER, Given::new(size, 0, &[[1, 0, 0, 0]])),
        ("row blur", ROW_BLUR, Given::new(size, 0, &[])),
        ("histogram", HISTOGRAM, Given::new(size, 0, &[])),
        ("group sum", GROUP_SUM, Given::new(size, 0, &[])),
    ]
}

/// Every pixel's ids, as one dispatch of the whole would hand them.
const IDS: &str = "@compute @workgroup_size(4, 2)\n\
fn anicel_render(@builtin(global_invocation_id) at: vec3<u32>, @builtin(workgroup_id) group: vec3<u32>,\n\
                 @builtin(num_workgroups) groups: vec3<u32>, @builtin(local_invocation_id) inside: vec3<u32>) {\n\
  anicel_out(at.x | at.y << 6u | group.x << 12u | group.y << 16u | groups.x << 20u | groups.y << 24u\n\
             | inside.x << 28u | inside.y << 30u);\n\
}\n\
fn anicel_reach() -> u32 { return 0u; }";

/// `source`'s picture and cut from the device in chunks of `most`
/// workgroups and from the CPU.
fn both_in_chunks(source: &str, given: &Given, most: u64) -> [(Vec<u32>, Result<(), Cut>); 2] {
    both_of(open(source).unwrap_or_else(|refusal| panic!("refused: {refusal}")), given, most)
}

/// [`both_in_chunks`] of a kernel opened already.
fn both_of(kernel: Kernel, given: &Given, most: u64) -> [(Vec<u32>, Result<(), Cut>); 2] {
    let engine = first_engine();
    let frame = given.frame();
    let start = hashed((given.size[0] * given.size[1]) as usize, 3);
    let mut cpu = start.clone();
    let cpu_cut = kernel.render(&frame, &mut cpu);
    let plugin = Plugin::open(engine, kernel).unwrap_or_else(|why| panic!("the device refused: {why}"));
    let mut gpu = start;
    let gpu_cut = plugin.run(engine, &frame, &mut gpu, most, Batches::default()).expect("the device ran it");
    [(gpu, gpu_cut), (cpu, cpu_cut)]
}

#[test]
fn a_plugin_opened_uncut_draws_on_the_device_what_the_cpu_draws() {
    // 🗣️-Q18 「끊지 않음」: the device's text has no charge, the CPU's
    // module its count — a plugin that ends draws the same on both.
    for (name, source, given) in &fixtures([37, 23]) {
        let kernel = open_uncut(source).unwrap_or_else(|refusal| panic!("{name}: refused: {refusal}"));
        let [(gpu, gpu_cut), (cpu, cpu_cut)] = both_of(kernel, given, 2);
        assert_eq!((gpu_cut, cpu_cut), (Ok(()), Ok(())), "{name}");
        assert_eq!(first_apart(given.size, &gpu, &cpu), None, "{name}: (x, y, device, CPU)");
    }
}

#[test]
fn a_run_in_chunks_draws_what_the_cpu_draws_in_one() {
    // 37 × 23 is 3 × 2 groups of 16 × 16 (and 5 × 6 of 8 × 4): one group a
    // chunk, a part of a row, a row and a part, and rows.
    for most in [1, 2, 4, 7] {
        for (name, source, given) in &fixtures([37, 23]) {
            let [(gpu, gpu_cut), (cpu, cpu_cut)] = both_in_chunks(source, given, most);
            assert_eq!((gpu_cut, cpu_cut), (Ok(()), Ok(())), "{name} in chunks of {most}");
            assert_eq!(first_apart(given.size, &gpu, &cpu), None, "{name} in chunks of {most}: (x, y, device, CPU)");
        }
    }
}

#[test]
fn a_run_in_chunks_hands_the_render_the_ids_of_one_dispatch() {
    // 13 × 7 is 4 × 4 groups of 4 × 2, the last of each a part one; 12 × 6
    // is 3 × 3 whole ones.
    for (size, groups) in [([13, 7], 4 | 4 << 4), ([12, 6], 3 | 3 << 4)] {
        let given = Given::new(size, 0, &[]);
        let last = (size[0] * size[1] - 1) as usize;
        for most in [1, 3, 5, 16] {
            let [(gpu, _), (cpu, _)] = both_in_chunks(IDS, &given, most);
            assert_eq!(first_apart(given.size, &gpu, &cpu), None, "{size:?} in chunks of {most}: (x, y, device, CPU)");
            assert_eq!(gpu[last] >> 20 & 0xff, groups, "the run's groups, {size:?} in chunks of {most}");
        }
    }
}

#[test]
fn an_endless_plugin_in_chunks_is_cut() {
    let mut given = Given::new([19, 7], 0, &[]);
    given.fuel = 5_000;
    for most in [1, 2] {
        let [(_, gpu_cut), (_, cpu_cut)] = both_in_chunks(ENDLESS, &given, most);
        assert_eq!((gpu_cut, cpu_cut), (Err(Cut), Err(Cut)), "in chunks of {most}");
    }
}

#[test]
fn every_group_lies_in_one_chunk_of_no_more_than_the_most() {
    for groups in [[1, 1], [3, 2], [5, 6], [240, 135]] {
        for most in [1, 2, 3, 5, 7, 240, 241, 500, u64::MAX] {
            let mut covered = vec![0; (groups[0] * groups[1]) as usize];
            for ([left, top], [wide, high]) in super::chunks(groups, most) {
                assert!(u64::from(wide * high) <= most.max(1), "{groups:?} by {most}: {wide} × {high}");
                for y in top..top + high {
                    for x in left..left + wide {
                        covered[(y * groups[0] + x) as usize] += 1;
                    }
                }
            }
            assert!(covered.iter().all(|&times| times == 1), "{groups:?} by {most}: {covered:?}");
        }
    }
    assert!(super::chunks([0, 4], 3).is_empty());
}

#[test]
fn a_chunk_holds_what_finishes_within_the_budget_at_the_whole_share() {
    // 🔬The Surface Pro 11's pace (11-11 11:22): 6.4 ns a charge on a lane
    // alone, 2.5 ps over a pixel of a full device; groups of 16 × 16.
    let pace = Pace::new(6.4e-9, 2.5e-12);
    assert_eq!(pace.chunk(10_000, 256), 15_625, "0.1 s over 10⁴ × 2.5 ps × 256");
    assert_eq!(pace.chunk(1_000_000, 256), 156, "the default share");
    assert_eq!(pace.chunk(100_000_000, 256), 10, "a lane alone takes 0.64 s: as many as finish with it");
    assert_eq!(pace.chunk(0, 256), pace.chunk(1, 256), "a share of none is spent as one");
    assert_eq!(Pace::new(1.0, 1.0).chunk(u32::MAX, 256), 1, "one group at the least");
}

#[test]
fn a_batch_doubles_while_its_chunks_come_back_quick_and_halves_when_slow() {
    use super::pace::{CHUNK_BUDGET, MOST_IN_A_BATCH};
    let mut batches = Batches::default();
    assert_eq!(batches.size(), 1, "one chunk at first");
    let mut after = |took: Duration| {
        batches.took(took);
        batches.size()
    };
    let quick: Vec<_> = (0..6).map(|_| after(CHUNK_BUDGET / 2)).collect();
    assert_eq!(quick, [2, 4, 8, 16, 16, 16], "doubled up to the most");
    assert_eq!(MOST_IN_A_BATCH, 16);
    assert_eq!(after(CHUNK_BUDGET), 16, "within a chunk's budget but not half: as it was");
    assert_eq!(after(CHUNK_BUDGET + Duration::from_micros(1)), 8, "past it: halved");
    let slow: Vec<_> = (0..5).map(|_| after(3 * CHUNK_BUDGET)).collect();
    assert_eq!(slow, [4, 2, 1, 1, 1], "one at the least");
    let mut held = Batches::within(Duration::from_secs(1));
    held.took(Duration::from_millis(400));
    assert_eq!(held.size(), 2, "held to its own budget, not a chunk's");
    held.took(Duration::from_millis(600));
    assert_eq!(held.size(), 2, "within it but not half: as it was");
    held.took(Duration::from_millis(1001));
    assert_eq!(held.size(), 1);
}

#[test]
fn a_quick_run_in_many_chunks_waits_for_the_device_a_batch_at_a_time() {
    // 64 × 64 is 16 × 32 of IDS' groups of 4 × 2: 512 chunks of one.
    let given = Given::new([64, 64], 0, &[]);
    let engine = first_engine();
    let plugin = Plugin::open(engine, open(IDS).expect("opened")).expect("compiled");
    let mut output = hashed(64 * 64, 3);
    // Held to a budget no wait passes, however loaded the machine: the
    // waits are the batches' alone.
    let quick = Batches::within(Duration::MAX);
    let waits = gpu_engine_waits_here();
    let run = plugin.run(engine, &given.frame(), &mut output, 1, quick).expect("the device ran it");
    let waited = gpu_engine_waits_here() - waits;
    assert_eq!(run, Ok(()));
    // Batches of 1, 2, 4 and 8, then 31 of 16 and the last one, and the
    // output read — 513 were it a wait a chunk.
    assert_eq!(waited, 4 + 31 + 1 + 1, "waits for 512 chunks");
    // Held to one no batch keeps: a wait a chunk, as before batches.
    let none = Batches::within(Duration::ZERO);
    let waits = gpu_engine_waits_here();
    plugin.run(engine, &given.frame(), &mut output, 1, none).expect("the device ran it").expect("not cut");
    assert_eq!(gpu_engine_waits_here() - waits, 512 + 1, "a wait a chunk");
}

#[test]
fn the_engines_pace_is_measured_once() {
    let engine = first_engine();
    let pace = Pace::of(engine).expect("measured");
    assert!(pace.chunk(1_000_000, 256) >= 1);
    assert_eq!(engine.plugin_pace.get(), Some(&pace), "kept on the engine");
    assert_eq!(Pace::of(engine), Some(pace));
}

/// A probe's runs as the 512² probe's ran (🔬main PC, 11-18): `own` of
/// their own — the quicker of two jumping by 2 ms every other size — and
/// `turn` a turn beside it; and the turns each was given.
fn probe_runs(
    own: f64,
    turn: f64,
) -> (impl FnMut(u32) -> Option<f64>, std::rc::Rc<std::cell::RefCell<Vec<u32>>>) {
    let asked = std::rc::Rc::new(std::cell::RefCell::new(Vec::new()));
    let seen = asked.clone();
    let runs = move |turns: u32| {
        let jump = if seen.borrow().len() % 2 == 1 { 0.002 } else { 0.0 };
        seen.borrow_mut().push(turns);
        Some(own + jump + f64::from(turns) * turn)
    };
    (runs, asked)
}

#[test]
fn a_probe_is_paced_by_what_its_turns_add_not_by_its_runs_own_cost() {
    use super::pace::turn_time_of;
    let turn = 1e-6;
    let (runs, asked) = probe_runs(0.010, turn);
    let paced = turn_time_of(runs, 256).expect("measured");
    // ↩️Stopped once a run passed 10 ms, a doubling's 2 ms jump over 512
    // turns: 4.9 µs a turn.
    assert!((paced / turn - 1.0).abs() < 0.25, "{paced:e} s a turn, for {turn:e}");
    assert_eq!(*asked.borrow(), [256, 256, 1024, 4096, 16384], "grown fourfold till they added 10 ms");
    // What the last growth added, 4,096 → 16,384 turns, the 2 ms its runs'
    // own cost fell by in it — not what every growth since the first did.
    let last = (12_288.0 * turn - 0.002) / 12_288.0;
    assert!((paced - last).abs() < 1e-12, "{paced:e} s a turn, the last growth's {last:e}");
}

#[test]
fn a_probe_whose_turns_never_add_enough_is_paced_at_the_most_turns() {
    use super::pace::{MOST_TURNS, turn_time_of};
    let (runs, asked) = probe_runs(0.010, 0.0);
    let paced = turn_time_of(runs, 1 << 12).expect("measured");
    assert_eq!(asked.borrow().last(), Some(&MOST_TURNS));
    assert_eq!(paced, 0.012 / f64::from(MOST_TURNS), "the whole run over its turns: slower, never quicker");
    let failed = turn_time_of(|_| None, 1 << 12);
    assert_eq!(failed, None, "a run the device did not make measures nothing");
}

/// `words`, a picture over `whole` — (left, top, right, bottom) — at
/// `at`'s (left, top, width, height), row after row: clear past `whole`.
fn cropped(words: &[u32], [left, top, right, bottom]: [i32; 4], [x0, y0, width, height]: [i32; 4]) -> Vec<u32> {
    let mut out = Vec::with_capacity((width * height).max(0) as usize);
    for y in y0..y0 + height {
        for x in x0..x0 + width {
            let inside = (left..right).contains(&x) && (top..bottom).contains(&y);
            out.push(if inside { words[((y - top) * (right - left) + (x - left)) as usize] } else { 0 });
        }
    }
    out
}

/// A chain's tiles over `rect`, each pixel its place hashed by `seed`, and
/// those words row after row over the tiles' pixels.
fn chain_tiles(engine: &crate::device::Engine, rect: TileRect, seed: u32) -> (wgpu::Buffer, Vec<u32>, [i32; 4]) {
    let side = TILE as i32;
    let whole = [rect.x0 * side, rect.y0 * side, (rect.x0 + rect.columns as i32) * side, (rect.y0 + rect.rows as i32) * side];
    let words = hashed(((whole[2] - whole[0]) * (whole[3] - whole[1])) as usize, seed);
    let tiles = put_over(engine, rect, whole, &le_bytes(&words)).expect("laid");
    (tiles, words, whole)
}

#[test]
fn a_run_over_a_chains_tiles_lays_on_them_what_the_cpu_draws() {
    // The CPU's run over the very pixels the tiles hold at the input's
    // place, what it drew put as a chain puts it — a pixel no alpha shows
    // zeroed (hashed words leave some at alpha 0, with colour). Past the
    // tiles the input reads clear: the second rectangle ends at x = 128,
    // inside the picture, and is two tiles high — a word past a row of
    // tiles' right edge is the next row's, so only the check makes it
    // clear (one row high, the word lay past the buffer, which this device
    // reads as 0). The second tells the plug-in a place 6 right of and 4
    // above where it lies on the tiles: the paper is not at the canvas's
    // origin.
    let engine = first_engine();
    let rects = [
        (TileRect { x0: -1, y0: 0, columns: 2, rows: 1 }, None, [0, 0]),
        (TileRect { x0: 0, y0: 0, columns: 1, rows: 2 }, Some([116, 16]), [-6, 4]),
    ];
    for (rect, origin, at) in rects {
        for (name, source, given) in &fixtures([37, 23]) {
            let base = given.frame();
            let [x, y] = origin.unwrap_or(base.in_origin);
            let reach = given.reach;
            let frame = Frame { in_origin: [x, y], out_origin: [x + reach, y + reach], ..base };
            let read = [x + at[0], y + at[1], frame.in_size[0], frame.in_size[1]];
            let (input, input_words, whole) = chain_tiles(engine, rect, 7);
            let layers: Vec<_> = (0..2).map(|slot| chain_tiles(engine, rect, 11 + slot)).collect();
            let cpu_input = cropped(&input_words, whole, read);
            let cpu_rows: Vec<u32> = layers.iter().flat_map(|(_, words, _)| cropped(words, whole, read)).collect();
            let kernel = open(source).unwrap_or_else(|refusal| panic!("refused: {refusal}"));
            let mut drawn = vec![0; (given.size[0] * given.size[1]) as usize];
            let cpu_cut = kernel.render(&Frame { input: &cpu_input, rows: &cpu_rows, ..frame }, &mut drawn);
            assert_eq!(cpu_cut, Ok(()), "{name}");
            for word in &mut drawn {
                if *word >> 24 == 0 {
                    *word = 0;
                }
            }
            let [left, top] = frame.out_origin;
            let [left, top] = [left + at[0], top + at[1]];
            let put = [left, top, left + given.size[0], top + given.size[1]];
            let expected = put_over(engine, rect, put, &le_bytes(&drawn)).expect("put");
            let plugin = Plugin::open(engine, kernel).unwrap_or_else(|why| panic!("the device refused: {why}"));
            let rows: Vec<_> = layers.iter().map(|(tiles, _, _)| Tiled { tiles, rect }).collect();
            let made = plugin
                .render_tiled(engine, &frame, at, Tiled { tiles: &input, rect }, &rows)
                .expect("the device ran it")
                .unwrap_or_else(|Cut| panic!("{name}: cut"));
            let (made, expected) = (engine.read_buffer(&made).expect("read"), engine.read_buffer(&expected).expect("read"));
            let apart = made.chunks(4).zip(expected.chunks(4)).position(|(a, b)| a != b);
            assert_eq!(apart, None, "{name} over {rect:?}: the first word apart, tile after tile");
        }
    }
}
