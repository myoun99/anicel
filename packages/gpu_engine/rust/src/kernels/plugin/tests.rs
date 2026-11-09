//! The device's run of a plugin held to the CPU's, pixel for pixel and cut
//! for cut. That is no CPU copy of a kernel's formula (kernels/mod.rs): a
//! plugin's formula is written once, by its author, and both runs run the
//! same counted module — the CPU's is the run the chain's plan asks the
//! reach of anyway (fx_wgsl's run.rs), and what it computes is WGSL's.

use fx_wgsl::{Cut, Frame, open};

use super::Plugin;
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
fn hashed(count: usize, seed: u32) -> Vec<u32> {
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
    assert_eq!(first_apart(given.size, &gpu, &cpu), None, "{name}: (x, y, device, CPU)");
    gpu_cut
}

#[test]
fn every_fixture_draws_on_the_device_what_the_cpu_draws() {
    // 37 × 23 leaves every workgroup shape a part group at the right and
    // the bottom; the blur's reach is its value's radius.
    let size = [37, 23];
    let fixtures: [(&str, &str, Given); 6] = [
        ("invert", INVERT, Given::new(size, 0, &[])),
        ("blur", BLUR, Given::new(size, 3, &[[3 << 16, 0, 0, 0]])),
        ("layer", LAYER, Given::new(size, 0, &[[1, 0, 0, 0]])),
        ("row blur", ROW_BLUR, Given::new(size, 0, &[])),
        ("histogram", HISTOGRAM, Given::new(size, 0, &[])),
        ("group sum", GROUP_SUM, Given::new(size, 0, &[])),
    ];
    for (name, source, given) in &fixtures {
        assert_eq!(assert_alike(name, given, source), Ok(()), "{name}: not cut");
    }
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
    let seen = engine.device.create_buffer(&wgpu::BufferDescriptor {
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
