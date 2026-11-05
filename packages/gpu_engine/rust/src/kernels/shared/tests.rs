//! The shared functions on a real GPU. R1 is checked against the ledger
//! and cases worked out by hand from the spec — never a CPU copy of it
//! (`kernels/mod.rs` has why). The wide integers are checked against the
//! machine's own i64 and i128: their contract is "the exact two's
//! complement result", and the machine's integer operators ARE that
//! definition, not a second spelling of any kernel's formula.

use std::sync::{OnceLock, mpsc};

use wgpu::util::DeviceExt;

use super::{RESAMPLE_WGSL, ResampleMap, ResampleMode, WIDE_WGSL};
use crate::device::Engine;
use crate::testing::{assert_pinned, first_engine};

// cases.wgsl's ids.
const ADD: u32 = 0;
const SUB: u32 = 1;
const MUL_I32: u32 = 2;
const MUL_U32: u32 = 3;
const MUL: u32 = 4;
const MUL128: u32 = 5;
const SHR: u32 = 6;
const SHL: u32 = 7;
const ROUND: u32 = 8;
const ROUND128: u32 = 9;
const POW2_OVER: u32 = 10;
const DIVR: u32 = 11;
const LESS: u32 = 12;
const FITS: u32 = 13;
const SAMPLES: u32 = 14;
const SUBSAMPLE: u32 = 15;

/// The device and the compiled cases every test here runs on.
struct Rig {
    engine: &'static Engine,
    wide: wgpu::ComputePipeline,
    window: wgpu::ComputePipeline,
}

/// One compile for the whole test process, on the tests' one device
/// (blend's rig has the crash that taught both).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        let source = [WIDE_WGSL, RESAMPLE_WGSL, include_str!("cases.wgsl")].join("\n");
        let module = engine
            .device
            .create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some("shared cases"),
                source: wgpu::ShaderSource::Wgsl(source.into()),
            });
        let pipeline = |entry: &str| {
            engine
                .device
                .create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                    label: Some(entry),
                    layout: None,
                    module: &module,
                    entry_point: Some(entry),
                    compilation_options: Default::default(),
                    cache: None,
                })
        };
        let wide = pipeline("run_wide");
        let window = pipeline("run_window");
        Rig {
            engine,
            wide,
            window,
        }
    })
}

fn storage(engine: &Engine, words: &[u32]) -> wgpu::Buffer {
    let bytes: Vec<u8> = words.iter().flat_map(|word| word.to_le_bytes()).collect();
    engine
        .device
        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("shared cases"),
            contents: &bytes,
            usage: wgpu::BufferUsages::STORAGE,
        })
}

/// Runs `pipeline` over `groups` with `buffers` at their bindings and
/// returns the `words` words of the last.
fn dispatch(
    pipeline: &wgpu::ComputePipeline,
    buffers: &[(u32, &wgpu::Buffer)],
    groups: (u32, u32),
    words: usize,
) -> Vec<u32> {
    let engine = rig().engine;
    let size = (words.max(1) * 4) as u64;
    let results = engine.device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("shared results"),
        size,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    });
    let readback = engine.device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("shared readback"),
        size,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let mut entries: Vec<_> = buffers
        .iter()
        .map(|&(binding, buffer)| wgpu::BindGroupEntry {
            binding,
            resource: buffer.as_entire_binding(),
        })
        .collect();
    entries.push(wgpu::BindGroupEntry {
        binding: 2,
        resource: results.as_entire_binding(),
    });
    let bind_group = engine.device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("shared cases"),
        layout: &pipeline.get_bind_group_layout(0),
        entries: &entries,
    });
    let mut encoder = engine
        .device
        .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
    {
        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
        pass.set_pipeline(pipeline);
        pass.set_bind_group(0, &bind_group, &[]);
        pass.dispatch_workgroups(groups.0, groups.1, 1);
    }
    encoder.copy_buffer_to_buffer(&results, 0, &readback, 0, size);
    engine.queue.submit([encoder.finish()]);
    let (sender, receiver) = mpsc::channel();
    readback.map_async(wgpu::MapMode::Read, .., move |result| {
        let _ = sender.send(result);
    });
    engine.wait().expect("wait for the GPU");
    receiver.recv().expect("map_async answered").expect("map");
    let mapped = readback.get_mapped_range(..).expect("mapped range");
    mapped
        .chunks_exact(4)
        .take(words)
        .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
        .collect()
}

// ---- The wide integers ----

/// Runs each `(run, a, b, k)` and returns its four words as one i128.
fn wide(cases: &[(u32, i64, i64, u32)]) -> Vec<i128> {
    let Rig { engine, wide, .. } = rig();
    let words: Vec<u32> = cases
        .iter()
        .flat_map(|&(run, a, b, k)| {
            let (a, b) = (a as u64, b as u64);
            [run, a as u32, (a >> 32) as u32, b as u32, (b >> 32) as u32, k]
        })
        .collect();
    let job = storage(engine, &words);
    let groups = (cases.len() as u32).div_ceil(64);
    let out = dispatch(wide, &[(0, &job)], (groups, 1), cases.len() * 4);
    out.chunks_exact(4)
        .map(|w| {
            let unsigned = u128::from(w[0])
                | u128::from(w[1]) << 32
                | u128::from(w[2]) << 64
                | u128::from(w[3]) << 96;
            unsigned as i128
        })
        .collect()
}

/// A run of i64s that reaches every width and both signs, after the ones
/// at the edges (splitmix64, from `seed`).
fn operands(seed: u64, count: usize) -> Vec<i64> {
    let mut edges = vec![
        0,
        1,
        -1,
        2,
        i64::from(i32::MAX),
        i64::from(i32::MIN),
        1 << 31,
        -(1 << 31) - 1,
        (1 << 32) - 1,
        1 << 32,
        -(1 << 32),
        0xffff,
        0x1_0000,
        1 << 62,
        -(1 << 62),
        i64::MAX,
        i64::MIN,
    ];
    let mut state = seed;
    while edges.len() < count {
        state = state.wrapping_add(0x9e37_79b9_7f4a_7c15);
        let mut z = state;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        z ^= z >> 31;
        // Its low six bits pick how far to narrow it.
        edges.push((z as i64) >> (z & 63));
    }
    edges
}

/// Every operand against every other, through `run` with count `k`.
fn pairs(run: u32, k: impl Fn(usize) -> u32) -> Vec<(u32, i64, i64, u32)> {
    let a = operands(1, 48);
    let b = operands(2, 48);
    let mut cases = Vec::new();
    for (i, &x) in a.iter().enumerate() {
        for &y in &b {
            cases.push((run, x, y, k(i)));
        }
    }
    cases
}

fn check(cases: &[(u32, i64, i64, u32)], expect: impl Fn(i64, i64, u32) -> i128) {
    for (&(run, a, b, k), got) in cases.iter().zip(wide(cases)) {
        assert_eq!(got, expect(a, b, k), "run {run} a {a} b {b} k {k}");
    }
}

/// The low 64 bits, as the GPU leaves the rest of the case's words 0.
fn low(v: i64) -> i128 {
    i128::from(v as u64)
}

#[test]
fn sums_and_products_are_the_machines() {
    check(&pairs(ADD, |_| 0), |a, b, _| low(a.wrapping_add(b)));
    check(&pairs(SUB, |_| 0), |a, b, _| low(a.wrapping_sub(b)));
    check(&pairs(MUL_I32, |_| 0), |a, b, _| {
        low(i64::from(a as i32) * i64::from(b as i32))
    });
    check(&pairs(MUL_U32, |_| 0), |a, b, _| {
        low((u64::from(a as u32) * u64::from(b as u32)) as i64)
    });
    check(&pairs(MUL, |_| 0), |a, b, _| low(a.wrapping_mul(b)));
    check(&pairs(MUL128, |_| 0), |a, b, _| i128::from(a) * i128::from(b));
    // The one carry no random pair reached (11-05 mutant): 2·0x55555555 +
    // 0x55555555 fills the third column, and the second carries into it.
    let (a, b) = (0x2_ffff_ffff_i64, 0x5555_5555_ffff_ffff_i64);
    let cases = [(MUL128, a, b, 0), (MUL128, -a, b, 0), (MUL128, b, a, 0)];
    check(&cases, |a, b, _| i128::from(a) * i128::from(b));
}

#[test]
fn shifts_and_roundings_are_the_machines() {
    let k = |i: usize| (i % 64) as u32;
    check(&pairs(SHR, k), |a, _, k| low(a >> k));
    check(&pairs(SHL, k), |a, _, k| low(((a as u64) << k) as i64));
    let k = |i: usize| (i % 63) as u32 + 1;
    check(&pairs(ROUND, k), |a, _, k| low(a.wrapping_add(1 << (k - 1)) >> k));
    // rnd(a · b, k) as an i128; the case's third word says whether it fits.
    check(&pairs(ROUND128, k), |a, b, k| {
        let rounded = (i128::from(a) * i128::from(b) + (1 << (k - 1))) >> k;
        low(rounded as i64) | i128::from(i64::try_from(rounded).is_ok()) << 64
    });
}

#[test]
fn comparisons_are_the_machines() {
    check(&pairs(LESS, |_| 0), |a, b, _| {
        i128::from(a < b) | i128::from((a as u64) < (b as u64)) << 32
    });
    check(&pairs(FITS, |_| 0), |a, _, _| {
        let fits = i32::try_from(a).is_ok();
        i128::from(fits) | i128::from(fits && a != i64::from(i32::MIN)) << 32
    });
}

#[test]
fn divisions_are_the_machines() {
    // ⌊2^e / d⌋ wherever the quotient fits in 63 bits.
    let mut cases = Vec::new();
    for (i, &d) in operands(3, 200).iter().enumerate() {
        let d = d.unsigned_abs() as i64;
        let e = (i * 37 % 101) as u32;
        if d > 0 && (1i128 << e) / i128::from(d) < 1 << 63 {
            cases.push((POW2_OVER, d, 0, e));
        }
    }
    // R1's own: 1/w in Q.37 at both ends of w's range.
    cases.push((POW2_OVER, (1 << 25) + 1, 0, 74));
    cases.push((POW2_OVER, 1 << 37, 0, 74));
    check(&cases, |d, _, e| (1i128 << e) / i128::from(d));

    // divr(n, d) wherever its quotient and 2d · 2^(bits-1) fit.
    let mut cases = Vec::new();
    for (&n, &d) in operands(4, 300).iter().zip(operands(5, 300).iter()) {
        let (n, d) = (n.unsigned_abs() >> 2, d.unsigned_abs() >> 2);
        if d == 0 {
            continue;
        }
        let quotient = (2 * u128::from(n) + u128::from(d)) / (2 * u128::from(d));
        let bits = (128 - quotient.leading_zeros()).max(1);
        if bits <= 32 && (2 * u128::from(d)) << (bits - 1) < 1 << 64 {
            cases.push((DIVR, n as i64, d as i64, bits));
        }
    }
    assert!(cases.len() > 100, "{} divr cases", cases.len());
    check(&cases, |n, d, _| {
        i128::from(((2 * n as u128 + d as u128) / (2 * d as u128)) as u32)
    });
}

// ---- R1's own pieces, by hand ----

#[test]
fn a_step_sets_how_many_subsamples_an_axis_takes() {
    // n of 8..16 is the least with step² <= (n/2)²: steps of 4, 4.5 and
    // 7.5 px sit on 8, 9 and 15; one Q.16 past each is the next.
    let px = |x: f64| (x * 65536.0) as i64;
    let cases = [
        (0, 0, 8),
        (px(4.0), 0, 8),
        (px(4.0) + 1, 0, 9),
        (px(4.5), 0, 9),
        (px(4.5) + 1, 0, 10),
        (px(7.5), 0, 15),
        (px(7.5) + 1, 0, 16),
        (px(16.0), px(16.0), 16),
        // 3-4-5: the two components make a step of 5.
        (px(3.0), px(4.0), 10),
        (px(4.0), px(3.0) + 1, 11),
    ];
    let runs: Vec<_> = cases.iter().map(|&(along, across, _)| (SAMPLES, along, across, 0)).collect();
    let got: Vec<_> = wide(&runs).iter().map(|&n| n as u32).collect();
    let want: Vec<_> = cases.iter().map(|&(_, _, n)| n).collect();
    assert_eq!(got, want);
}

#[test]
fn a_subsample_sits_at_its_cell_centre_from_the_pixel_centre() {
    // divr((2s+1) · 2^15, n) − 2^15: thirds round to the nearest Q.16.
    let cases = [(0, 1, 0), (0, 2, -16384), (1, 2, 16384), (0, 3, -21845), (1, 3, 0), (2, 3, 21845), (15, 16, 30720)];
    let runs: Vec<_> = cases.iter().map(|&(s, n, _)| (SUBSAMPLE, s, 0, n)).collect();
    let got: Vec<_> = wide(&runs).iter().map(|&o| o as u32 as i32).collect();
    let want: Vec<_> = cases.iter().map(|&(_, _, o)| o).collect();
    assert_eq!(got, want);
}

// ---- R1 on pictures ----

/// A straight RGBA8 picture, row after row.
struct Picture {
    width: u32,
    height: u32,
    pixels: Vec<u32>,
}

impl Picture {
    fn filled(width: u32, height: u32, word: u32) -> Self {
        Picture {
            width,
            height,
            pixels: vec![word; (width * height) as usize],
        }
    }

    fn put(&mut self, x: u32, y: u32, word: u32) {
        self.pixels[(y * self.width + x) as usize] = word;
    }

    fn rect(&mut self, x0: u32, y0: u32, x1: u32, y1: u32, word: u32) {
        for y in y0..y1 {
            for x in x0..x1 {
                self.put(x, y, word);
            }
        }
    }
}

/// The picture every scene resamples: paper, ink, a half-clear red over
/// both, a clear corner, one-pixel lines either way and a patch of noise
/// with more words than Pick's sixteen slots.
fn fixture() -> Picture {
    let mut picture = Picture::filled(64, 48, 0xfff4_f0e8);
    picture.rect(8, 6, 28, 22, 0xff18_2030);
    picture.rect(20, 14, 44, 34, 0x80e0_4020);
    picture.rect(44, 0, 64, 16, 0);
    for t in 0..20 {
        picture.put(4 + t, 44 - t, 0xff00_00ff);
    }
    for y in 20..48 {
        picture.put(50, y, 0xff00_ff00);
    }
    let mut state = 0x2545_f491u32;
    for y in 30..46 {
        for x in 30..46 {
            // xorshift32
            state ^= state << 13;
            state ^= state >> 17;
            state ^= state << 5;
            // Its top byte is its alpha; under 32, nothing (a stored pixel
            // holds no colour without alpha).
            picture.put(x, y, if state >> 24 < 32 { 0 } else { state });
        }
    }
    picture
}

/// The window of `size` at `clip` in an output the map was made for.
fn window(map: &ResampleMap, picture: &Picture, size: (u32, u32), clip: (i32, i32)) -> Vec<u32> {
    let Rig { engine, window, .. } = rig();
    let mut job = map.words().to_vec();
    job.extend([picture.width, picture.height, size.0, size.1, clip.0 as u32, clip.1 as u32]);
    let job = storage(engine, &job);
    let pixels = storage(engine, &picture.pixels);
    let groups = (size.0.div_ceil(8), size.1.div_ceil(8));
    dispatch(window, &[(0, &job), (1, &pixels)], groups, (size.0 * size.1) as usize)
}

/// A scene: an inverse map over an output of `size`.
struct Scene {
    name: &'static str,
    inverse: [f64; 9],
    size: (u32, u32),
}

fn affine(a: f64, b: f64, c: f64, d: f64, e: f64, f: f64) -> [f64; 9] {
    [a, b, c, d, e, f, 0.0, 0.0, 1.0]
}

/// Every route through R1 the fixture can reach. Every entry is a double
/// the literal names exactly or rounds to by IEEE alone — no sin or cos,
/// whose last bit is the device's (the spec's 대조 필요 ①).
fn scenes() -> Vec<Scene> {
    vec![
        // 2.5 times larger: Pick's exact path, Blend under its floor.
        Scene { name: "enlarge", inverse: affine(0.4, 0.0, 17.3, 0.0, 0.4, 9.6), size: (48, 40) },
        // 1.37 times smaller, past every edge.
        Scene { name: "reduce", inverse: affine(1.37, 0.0, 0.4, 0.0, 1.37, -0.6), size: (48, 40) },
        // A 3-4-5 turn, 1.3 times larger: Pick subsamples.
        Scene { name: "turn", inverse: affine(0.8 / 1.3, -0.6 / 1.3, 24.0, 0.6 / 1.3, 0.8 / 1.3, 2.0), size: (48, 40) },
        // A quarter turn: exact Pick with the axes swapped.
        Scene { name: "quarter", inverse: affine(0.0, -0.75, 47.5, 0.75, 0.0, 3.25), size: (40, 40) },
        // Near ten times smaller: wide exact Pick, a wide tent.
        Scene { name: "squeeze", inverse: affine(9.5, 0.0, 1.0, 0.0, 7.25, -2.0), size: (8, 8) },
        // Past the 16 px ceiling: Pick subsamples an axis-aligned map.
        Scene { name: "far", inverse: affine(20.0, 0.0, -3.0, 0.0, 18.0, 1.0), size: (4, 4) },
        // A shear: subsampled Pick, an elongated tent.
        Scene { name: "shear", inverse: affine(1.0, 0.7, -5.0, 0.3, 1.2, 2.0), size: (40, 32) },
        // A quarter and a half pixel off: ties on the halves.
        Scene { name: "nudge", inverse: affine(1.0, 0.0, 0.25, 0.0, 1.0, -0.5), size: (40, 32) },
        // A gentle homography.
        Scene {
            name: "perspective",
            inverse: [1.1, -0.3, 14.0, 0.05, 1.2, 1.0, 0.004, -0.002, 1.0],
            size: (48, 40),
        },
        // A homography six times smaller, whose Jacobian's columns and
        // rows give the subsample counts apart.
        Scene {
            name: "dive",
            inverse: [6.0, 3.0, -20.0, 0.5, 6.0, -25.0, 0.004, 0.003, 1.0],
            size: (10, 8),
        },
        // A 3-4-5 turn six times smaller: twelve subsamples an axis.
        Scene { name: "spin", inverse: affine(4.8, -3.6, 20.0, 3.6, 4.8, -30.0), size: (10, 10) },
        // A strong one, shrinking 2.4 times towards its far side.
        Scene {
            name: "tilt",
            inverse: [0.9, 0.1, 1.0, -0.05, 0.8, 3.0, -0.012, 0.001, 1.0],
            size: (48, 40),
        },
    ]
}

const MODES: [(ResampleMode, &str); 2] = [(ResampleMode::Blend, "blend"), (ResampleMode::Pick, "pick")];

fn map_of(scene: &Scene, mode: ResampleMode) -> ResampleMap {
    ResampleMap::new(scene.inverse, 1.0, mode, scene.size.0, scene.size.1).expect("a map that lands")
}

fn bytes(words: &[u32]) -> Vec<u8> {
    words.iter().flat_map(|word| word.to_le_bytes()).collect()
}

#[test]
fn every_device_resamples_the_pinned_scenes() {
    let picture = fixture();
    for scene in scenes() {
        for (mode, mode_name) in MODES {
            let out = window(&map_of(&scene, mode), &picture, scene.size, (0, 0));
            assert_pinned(&format!("resample/{}-{mode_name}", scene.name), &bytes(&out));
        }
    }
    // A whole-pixel move copies, in either mode.
    let moved = ResampleMap::new(affine(1.0, 0.0, -7.0, 0.0, 1.0, 5.0), 1.0, ResampleMode::Blend, 48, 40);
    let out = window(&moved.unwrap(), &picture, (48, 40), (0, 0));
    assert_pinned("resample/move", &bytes(&out));
}

#[test]
fn a_window_is_that_window_of_the_whole() {
    // The spec's ✅: whole integers add in any order, so a window keeps the
    // whole's grid and its pixels to the bit, wherever it is cut.
    let picture = fixture();
    for scene in scenes() {
        for (mode, mode_name) in MODES {
            let map = map_of(&scene, mode);
            let (columns, rows) = scene.size;
            let whole = window(&map, &picture, scene.size, (0, 0));
            let (cut_x, cut_y) = (columns * 5 / 9, rows * 2 / 7);
            for (x0, y0, x1, y1) in [(0, 0, cut_x, cut_y), (cut_x, 0, columns, cut_y), (0, cut_y, cut_x, rows), (cut_x, cut_y, columns, rows)] {
                let part = window(&map, &picture, (x1 - x0, y1 - y0), (x0 as i32, y0 as i32));
                for y in y0..y1 {
                    for x in x0..x1 {
                        assert_eq!(
                            part[((y - y0) * (x1 - x0) + x - x0) as usize],
                            whole[(y * columns + x) as usize],
                            "{}-{mode_name} at ({x}, {y})",
                            scene.name,
                        );
                    }
                }
            }
        }
    }
}

// ---- R1 by hand ----

fn one_map(inverse: [f64; 9], mode: ResampleMode, size: (u32, u32)) -> ResampleMap {
    ResampleMap::new(inverse, 1.0, mode, size.0, size.1).expect("a map that lands")
}

#[test]
fn a_whole_pixel_move_copies_words_even_with_no_alpha() {
    let mut picture = Picture::filled(4, 2, 0xff00_0000);
    // A colour under no alpha: a copy keeps it, a blend could not.
    picture.put(1, 0, 0x00ab_cdef);
    picture.put(2, 1, 0x7f12_3456);
    for (mode, _) in MODES {
        let map = one_map(affine(1.0, 0.0, 1.0, 0.0, 1.0, -1.0), mode, (4, 3));
        // Pixel (x, y) is the source's (x + 1, y − 1).
        let out = window(&map, &picture, (4, 3), (0, 0));
        assert_eq!(out[0..4], [0, 0, 0, 0]);
        assert_eq!(out[4..8], [0x00ab_cdef, 0xff00_0000, 0xff00_0000, 0]);
        assert_eq!(out[8..12], [0xff00_0000, 0x7f12_3456, 0xff00_0000, 0]);
    }
}

#[test]
fn one_word_everywhere_resamples_to_that_word() {
    let word = 0x80c0_4020;
    let picture = Picture::filled(40, 40, word);
    for scene in [affine(0.8 / 1.3, -0.6 / 1.3, 18.0, 0.6 / 1.3, 0.8 / 1.3, 6.0), affine(2.5, 0.0, 4.0, 0.0, 2.5, 4.0)] {
        for (mode, mode_name) in MODES {
            let out = window(&one_map(scene, mode, (12, 12)), &picture, (12, 12), (0, 0));
            assert!(out.iter().all(|&w| w == word), "{mode_name}: {out:x?}");
        }
    }
}

#[test]
fn a_tent_weighs_by_distance_and_by_alpha() {
    // Shifted a quarter pixel: u = 0.25, so source 0 is 0.25 px away and
    // source 1 0.75 — weights rnd((1 − 0.25) · 2^8) = 192 and 64, rows
    // 256 and 0. Red opaque, blue at alpha 51:
    //   α   = (255·192 + 51·64) / 256          = 204
    //   red = 255·255·192 / (255·192 + 51·64)  = 239.06 → 239
    //   blue = 255·51·64 / 52224               = 15.94  → 16
    let mut picture = Picture::filled(2, 1, 0xff00_00ff);
    picture.put(1, 0, 0x33ff_0000);
    let map = one_map(affine(1.0, 0.0, 0.25, 0.0, 1.0, 0.0), ResampleMode::Blend, (1, 1));
    assert_eq!(window(&map, &picture, (1, 1), (0, 0)), [0xcc10_00ef]);
    // Both opaque: red 255·192/256 = 191.25 → 191, blue 63.75 → 64.
    picture.put(1, 0, 0xffff_0000);
    assert_eq!(window(&map, &picture, (1, 1), (0, 0)), [0xff40_00bf]);
}

#[test]
fn words_with_no_alpha_blend_to_nothing() {
    // A checkerboard of two, so no reach is one word and the tent runs.
    let mut picture = Picture::filled(6, 6, 0x0011_2233);
    for y in 0..6 {
        for x in (y % 2..6).step_by(2) {
            picture.put(x, y, 0x0044_5566);
        }
    }
    let map = one_map(affine(0.5, 0.0, 1.0, 0.0, 0.5, 1.0), ResampleMode::Blend, (6, 6));
    assert!(window(&map, &picture, (6, 6), (0, 0)).iter().all(|&w| w == 0));
}

#[test]
fn pick_takes_the_word_covering_most_and_the_first_met_on_a_tie() {
    // Halving: output (0, 0) is source 0..2 × 0..2, each pixel a quarter.
    let (a, b, c) = (0xff00_00ffu32, 0xff00_ff00u32, 0xffff_0000u32);
    let halve = one_map(affine(2.0, 0.0, 0.0, 0.0, 2.0, 0.0), ResampleMode::Pick, (1, 1));
    let block = |words: [u32; 4]| {
        let mut picture = Picture::filled(2, 2, 0);
        picture.pixels.copy_from_slice(&words);
        window(&halve, &picture, (1, 1), (0, 0))[0]
    };
    assert_eq!(block([a, a, a, b]), a);
    assert_eq!(block([b, a, a, a]), a);
    assert_eq!(block([a, b, c, c]), c);
    // Two and two: the one met first, row by row.
    assert_eq!(block([b, a, a, b]), b);
    assert_eq!(block([a, b, b, a]), a);
}

#[test]
fn a_homography_at_its_horizon_is_outside() {
    // w = (63x − 31) / 2048: 1 at the right edge of 33 columns, exactly
    // 2^-12 at pixel 0's centre, where W = 2^25 — outside, though the
    // point it would map to, (2047.5, 0.5), is in the source and its tent
    // all one word. Pixel 1 is in. The second row is the third, so v stays
    // at 0.5.
    let word = 0xff20_4080;
    let picture = Picture::filled(2100, 3, word);
    let (g, i) = (63.0 / 2048.0, -31.0 / 2048.0);
    let map = one_map([1.0, 0.0, 0.0, g, 0.0, i, g, 0.0, i], ResampleMode::Blend, (33, 1));
    assert_eq!(window(&map, &picture, (2, 1), (0, 0)), [0, word]);
}

#[test]
fn a_projection_past_an_i64_is_outside() {
    // w = (23x − 11) / 1024 over 45 columns is 2^-11 at pixel 0, inside,
    // but c = 2^40 px puts its point at 2^51 px: rnd(N · r, 42) is
    // 2^67 + 2^26, past an i64. Its low 64 bits alone would be 2^26 —
    // (1023.5, 0.5), a point in the source.
    let word = 0xff20_4080;
    let picture = Picture::filled(2100, 3, word);
    let (g, i) = (23.0 / 1024.0, -11.0 / 1024.0);
    let far = (1u64 << 40) as f64;
    let map = one_map([1.0, 0.0, far, g, 0.0, i, g, 0.0, i], ResampleMode::Blend, (45, 1));
    assert_eq!(window(&map, &picture, (1, 1), (0, 0)), [0]);
}

#[test]
fn a_subsample_past_2_to_the_31_votes_for_nothing() {
    // w = (11x − 5) / 512 over 47 columns is 2^-10 at pixel 0, where
    // a = 128 and c = −64 make u = −0.5 and du/dx = 128 · 1024 = 2^17 px:
    // the sixteen columns of subsamples land 4096 px apart, from −61440 to
    // 61440. Four land in the source (4096 … 28672), four more past −2^15
    // px — nothing, though their low 32 bits would wrap into the source
    // and tie the vote. With dv/dy = 0 the rows take 8: 32 of 128 for the
    // word, so nothing wins.
    let word = 0xff20_4080;
    let picture = Picture::filled(32768, 2, word);
    let (g, i) = (11.0 / 512.0, -5.0 / 512.0);
    let map = one_map([128.0, 0.0, -64.0, g, 0.0, i, g, 0.0, i], ResampleMode::Pick, (47, 1));
    assert_eq!(window(&map, &picture, (1, 1), (0, 0)), [0]);
}

#[test]
fn a_half_pixel_move_is_not_a_copy() {
    // c = 0.5: the tent sits on the edge between the two, 128 each —
    // red 255·128/256 = 127.5 rounds up. The same down the rows with f.
    let (red, blue) = (0xff00_00ffu32, 0xffff_0000u32);
    let mut across = Picture::filled(2, 1, red);
    across.put(1, 0, blue);
    let map = one_map(affine(1.0, 0.0, 0.5, 0.0, 1.0, 0.0), ResampleMode::Blend, (1, 1));
    assert_eq!(window(&map, &across, (1, 1), (0, 0)), [0xff80_0080]);
    let mut down = Picture::filled(1, 2, red);
    down.put(0, 1, blue);
    let map = one_map(affine(1.0, 0.0, 0.0, 0.0, 1.0, 0.5), ResampleMode::Blend, (1, 1));
    assert_eq!(window(&map, &down, (1, 1), (0, 0)), [0xff80_0080]);
}

#[test]
fn a_tent_weight_on_a_half_rounds_up() {
    // f = 2^-9 px puts v at 128 in Q.16: rows weigh rnd(65408, 8) = 256
    // and rnd(128, 8) = 1, both halves. Red over blue:
    //   red 255·256/257 = 254.0, blue 255/257 = 0.99 → 1.
    let (red, blue) = (0xff00_00ffu32, 0xffff_0000u32);
    let mut down = Picture::filled(1, 2, red);
    down.put(0, 1, blue);
    let nudge = 1.0 / 512.0;
    let map = one_map(affine(1.0, 0.0, 0.0, 0.0, 1.0, nudge), ResampleMode::Blend, (1, 1));
    assert_eq!(window(&map, &down, (1, 1), (0, 0)), [0xff01_00fe]);
    let mut across = Picture::filled(2, 1, red);
    across.put(1, 0, blue);
    let map = one_map(affine(1.0, 0.0, nudge, 0.0, 1.0, 0.0), ResampleMode::Blend, (1, 1));
    assert_eq!(window(&map, &across, (1, 1), (0, 0)), [0xff01_00fe]);
}

/// Opaque word `n` of a run no two of which match.
fn token(n: u32) -> u32 {
    0xff00_0000 | (n * 0x0010_3050)
}

#[test]
fn sixteen_words_fill_the_slots_and_a_seventeenth_evicts() {
    // A quarter of four by four, every word once: sixteen slots hold them
    // all, the tie goes to the one met first.
    let mut picture = Picture::filled(4, 4, 0);
    for n in 0..16 {
        picture.put(n % 4, n / 4, token(n + 1));
    }
    let quarter = one_map(affine(4.0, 0.0, 0.0, 0.0, 4.0, 0.0), ResampleMode::Pick, (1, 1));
    assert_eq!(window(&quarter, &picture, (1, 1), (0, 0)), [token(1)]);
    // Four by five, row by row: sixteen words, then the seventeenth three
    // times and the first again. The seventeenth takes the lightest slot
    // (the first, lowest index), the first comes back in the next; the
    // recount gives 3, 2 and 1s.
    let mut picture = Picture::filled(4, 5, 0);
    let order = (1..=16).chain([17, 17, 17, 1]);
    for (n, word) in order.enumerate() {
        picture.put(n as u32 % 4, n as u32 / 4, token(word));
    }
    let map = one_map(affine(4.0, 0.0, 0.0, 0.0, 5.0, 0.0), ResampleMode::Pick, (1, 1));
    assert_eq!(window(&map, &picture, (1, 1), (0, 0)), [token(17)]);
    // Six by three: sixteen words, then the sixteenth and the fifteenth
    // again. The sixteenth has a slot of its own, so nothing is evicted and
    // the tie of two goes to the fifteenth, met first.
    let mut picture = Picture::filled(6, 3, 0);
    let order = (1..=16).chain([16, 15]);
    for (n, word) in order.enumerate() {
        picture.put(n as u32 % 6, n as u32 / 6, token(word));
    }
    let map = one_map(affine(6.0, 0.0, 0.0, 0.0, 3.0, 0.0), ResampleMode::Pick, (1, 1));
    assert_eq!(window(&map, &picture, (1, 1), (0, 0)), [token(15)]);
}

#[test]
fn a_sixteen_times_reduction_weighs_areas_not_subsamples() {
    // 16 px is the exact path's widest. The preimage [−0.25, 15.75] across
    // covers column 0 by 0.75 and column 16 by 0.25: A (column 0) has 0.75,
    // B (columns 1 and 16) 1.25 — B. Subsampled, columns 0 … 15 would get
    // 16 votes each and the tie go to A, met first. The same on its side.
    let (a, b) = (token(1), token(2));
    let mut picture = Picture::filled(17, 17, 0);
    for y in 0..17 {
        for x in 0..17 {
            let word = match x {
                0 => a,
                1 | 16 => b,
                _ => token(x + 1),
            };
            picture.put(x, y, word);
        }
    }
    let across = one_map(affine(16.0, 0.0, 0.25, 0.0, 16.0, 0.0), ResampleMode::Pick, (1, 1));
    assert_eq!(window(&across, &picture, (1, 1), (0, 0)), [b]);
    // A quarter turn: u follows y, v follows x — still axis-aligned.
    let turned = one_map(affine(0.0, 16.0, 0.25, 16.0, 0.0, 0.0), ResampleMode::Pick, (1, 1));
    assert_eq!(window(&turned, &picture, (1, 1), (0, 0)), [b]);
}

#[test]
fn each_axis_steps_by_its_own_column_of_the_map() {
    // Seventeen times along x, past the exact path: x steps 16 px (capped)
    // and takes sixteen subsamples, landing on columns ⌊17(2k+1)/32⌋ — all
    // but 8. Eight would land on the odd ones, ⌊17(2k+1)/16⌋. A on 1, 3, 5,
    // 7 and 9, B elsewhere: sixteen give B 11 to 5, eight would give A 5 to
    // 3. y steps 1 px and takes eight, all on the one row.
    let (a, b) = (token(1), token(2));
    let stripe = |k: u32| if k < 10 && k % 2 == 1 { a } else { b };
    let mut across = Picture::filled(17, 1, 0);
    for x in 0..17 {
        across.put(x, 0, stripe(x));
    }
    let map = one_map(affine(17.0, 0.0, 0.0, 0.0, 1.0, 0.0), ResampleMode::Pick, (1, 1));
    assert_eq!(window(&map, &across, (1, 1), (0, 0)), [b]);
    // A homography whose x runs down the rows: x's step is dv/dx = 17, and
    // du/dy = 1/4 is y's. g = 2^-30 keeps it off the affine path while its
    // Jacobian rounds to the affine one's.
    let mut down = Picture::filled(1, 17, 0);
    for y in 0..17 {
        down.put(0, y, stripe(y));
    }
    let g = 1.0 / (1u64 << 30) as f64;
    let map = one_map([0.0, 0.25, 0.375, 17.0, 0.0, 0.0, g, 0.0, 1.0], ResampleMode::Pick, (1, 1));
    assert_eq!(window(&map, &down, (1, 1), (0, 0)), [b]);
}

#[test]
fn a_preimage_under_a_pixel_still_votes() {
    // Along x the source runs (0.35, −0.35), along y barely (0.01, 0.01): a
    // sliver centred at (1.01, 1.08), just right of and below the corner of
    // four words — in the bottom right one. Eight by eight subsamples: the
    // four left of the middle land bottom left, the next two bottom right,
    // the last two top right, so bottom left wins 32 to 16 and 16. The
    // probe still looks one ring out, where the words differ.
    let mut picture = Picture::filled(2, 2, 0);
    picture.pixels.copy_from_slice(&[token(1), token(2), token(3), token(4)]);
    let sliver = one_map(affine(0.35, 0.01, 0.83, -0.35, 0.01, 1.25), ResampleMode::Pick, (1, 1));
    assert_eq!(window(&sliver, &picture, (1, 1), (0, 0)), [token(3)]);
}
