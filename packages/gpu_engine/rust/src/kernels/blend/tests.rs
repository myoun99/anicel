//! The blend family on a real GPU, checked against the ledger and against
//! what the formulas give by hand — never against a CPU copy of them
//! (`kernels/mod.rs` has why).

use std::sync::OnceLock;

use wgpu::util::DeviceExt;

use super::BLEND_WGSL;
use crate::device::Engine;
use crate::kernels::shared::{ISQRT_WGSL, pipeline};
use crate::testing::{assert_pinned, first_engine, read_buffer};

// cases.wgsl's ids for one function each.
const ERASE: u32 = 100;
const MUL: u32 = 101;
const DIV: u32 = 102;
const TO8: u32 = 103;
const SQRT: u32 = 104;
const ATOP: u32 = 105;
const PACK: u32 = 106;
const UNPACK: u32 = 107;

const NORMAL: u32 = 28;

/// Every mode of blend.wgsl's table, with the name its ledger row carries.
const MODES: [(u32, &str); 29] = [
    (0, "behind"),
    (1, "add"),
    (2, "darken"),
    (3, "multiply"),
    (4, "color-burn"),
    (5, "lighten"),
    (6, "screen"),
    (7, "color-dodge"),
    (8, "overlay"),
    (9, "soft-light"),
    (10, "hard-light"),
    (11, "difference"),
    (12, "exclusion"),
    (13, "linear-burn"),
    (14, "subtract"),
    (15, "vivid-light"),
    (16, "linear-light"),
    (17, "pin-light"),
    (18, "hard-mix"),
    (19, "divide"),
    (20, "darker-color"),
    (21, "lighter-color"),
    (22, "hue"),
    (23, "saturation"),
    (24, "chroma"),
    (25, "luminosity"),
    (26, "glow-dodge"),
    (27, "glow-add"),
    (NORMAL, "normal"),
];

type Rgba = [u32; 4];

/// A byte on the 16-bit scale.
const fn wide(byte: u32) -> u32 {
    byte * 257
}

/// The device and the compiled cases every test here runs on.
struct Rig {
    engine: &'static Engine,
    pipeline: wgpu::ComputePipeline,
}

/// One rig for the whole test process, as the app opens one device: a
/// device and a compile per test put eighteen D3D12 devices up at once,
/// and the process died on a cold compile (exit 2173, RTX 4080,
/// 2026-11-05).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        let sources = [ISQRT_WGSL, BLEND_WGSL, include_str!("cases.wgsl")];
        let pipeline = pipeline(engine, &sources, "run_cases");
        Rig { engine, pipeline }
    })
}

/// Runs each `(run, src, dst)` on the GPU and returns what came out.
fn run(cases: &[(u32, Rgba, Rgba)]) -> Vec<Rgba> {
    let Rig { engine, pipeline } = rig();
    let words: Vec<u8> = cases
        .iter()
        .flat_map(|(run, src, dst)| std::iter::once(run).chain(src).chain(dst))
        .flat_map(|word| word.to_le_bytes())
        .collect();
    let input = engine
        .device
        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("blend cases"),
            contents: &words,
            usage: wgpu::BufferUsages::STORAGE,
        });
    let size = (cases.len() * 16) as u64;
    let results = engine.device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("blend results"),
        size,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    });
    let bind_group = engine.device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("blend cases"),
        layout: &pipeline.get_bind_group_layout(0),
        entries: &[
            wgpu::BindGroupEntry {
                binding: 0,
                resource: input.as_entire_binding(),
            },
            wgpu::BindGroupEntry {
                binding: 1,
                resource: results.as_entire_binding(),
            },
        ],
    });
    let mut encoder = engine
        .device
        .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
    {
        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
        pass.set_pipeline(&pipeline);
        pass.set_bind_group(0, &bind_group, &[]);
        pass.dispatch_workgroups((cases.len() as u32).div_ceil(64), 1, 1);
    }
    engine.queue.submit([encoder.finish()]);
    read_buffer(engine, &results)
        .chunks_exact(16)
        .map(|texel| {
            let word = |k: usize| u32::from_le_bytes(texel[k * 4..k * 4 + 4].try_into().unwrap());
            [word(0), word(1), word(2), word(3)]
        })
        .collect()
}

/// One function of two words — cases.wgsl's 101 onwards — on each pair.
fn each(function: u32, pairs: &[(u32, u32)]) -> Vec<u32> {
    let cases: Vec<_> = pairs
        .iter()
        .map(|&(a, b)| (function, [a, 0, 0, 0], [b, 0, 0, 0]))
        .collect();
    run(&cases).into_iter().map(|out| out[0]).collect()
}

fn composite(mode: u32, src: Rgba, dst: Rgba) -> Rgba {
    run(&[(mode, src, dst)])[0]
}

// ---- The ledger ----

/// Colours of every kind a blend meets: black, white, primaries, greys
/// either side of half, bytes near the ends, and three that no byte widens
/// to — the stroke's wide plane holds those. The last sits on the edges
/// where a mode changes branch: 32767 is the last channel under W_HALF and
/// 32768 the first over, 16383 the last that soft light cubes (at 16384 the
/// cube and the root agree, 32768 both). Without it the grid passed with
/// W_HALF moved by one (11-05 mutant).
const COLOURS: [[u32; 3]; 9] = [
    [0, 0, 0],
    [65535, 65535, 65535],
    [65535, 0, 0],
    [0, wide(128), 65535],
    [wide(64), wide(192), wide(32)],
    [wide(127), wide(128), wide(129)],
    [wide(1), wide(254), wide(200)],
    [12345, 40000, 777],
    [32767, 32768, 16383],
];

/// Alphas from none to whole, half either side, and one no byte gives.
const ALPHAS: [u32; 7] = [0, wide(1), 12345, wide(127), wide(128), wide(254), 65535];

fn grid() -> Vec<(Rgba, Rgba)> {
    let pixels: Vec<Rgba> = COLOURS
        .iter()
        .flat_map(|&[r, g, b]| ALPHAS.iter().map(move |&a| [r, g, b, a]))
        .collect();
    pixels
        .iter()
        .flat_map(|&src| pixels.iter().map(move |&dst| (src, dst)))
        .collect()
}

fn bytes(results: &[Rgba]) -> Vec<u8> {
    results.iter().flatten().flat_map(|word| word.to_le_bytes()).collect()
}

#[test]
fn every_device_composites_the_pinned_grid_in_every_mode() {
    let grid = grid();
    for (mode, name) in MODES {
        let cases: Vec<_> = grid.iter().map(|&(src, dst)| (mode, src, dst)).collect();
        let id = format!("blend/grid-{mode:02}-{name}");
        assert_pinned(&id, &bytes(&run(&cases)));
    }
    let cases: Vec<_> = grid.iter().map(|&(src, dst)| (ERASE, src, dst)).collect();
    assert_pinned("blend/grid-erase", &bytes(&run(&cases)));
    let cases: Vec<_> = grid.iter().map(|&(src, dst)| (ATOP, src, dst)).collect();
    assert_pinned("blend/grid-atop", &bytes(&run(&cases)));
}

// ---- By hand, from the formulas ----

// round(a·b / 65535): whole times x is x, nothing times x is nothing, and
// the halves round as they lie — 1·32767/65535 is just under a half, and
// 1·32768/65535 just over. 32896² / 65535 = 16512.502.
#[test]
fn a_product_is_rounded_over_65535() {
    let pairs = [
        (65535, 0),
        (65535, 777),
        (65535, 65535),
        (0, 40000),
        (32768, 65535),
        (1, 32767),
        (1, 32768),
        (32896, 32896),
    ];
    assert_eq!(
        each(MUL, &pairs),
        [0, 777, 65535, 0, 32768, 0, 1, 16513]
    );
}

// round(n·65535 / d): a whole is 65535, nothing is nothing, a half rounds
// up, a third is 65535/3 exactly.
#[test]
fn a_ratio_is_a_channel() {
    let pairs = [(1, 1), (2, 2), (300, 300), (65535, 65535), (0, 5), (1, 2), (1, 3)];
    assert_eq!(
        each(DIV, &pairs),
        [65535, 65535, 65535, 65535, 0, 32768, 21845]
    );
}

// round(w / 257) has no tie, so every byte widened comes back as itself;
// the step from 0 to 1 lies between 128 and 129.
#[test]
fn every_byte_widened_comes_back_as_itself() {
    let pairs: Vec<_> = (0..=255).map(|byte| (wide(byte), 0)).collect();
    assert_eq!(each(TO8, &pairs), (0..=255).collect::<Vec<_>>());
    assert_eq!(each(TO8, &[(128, 0), (129, 0)]), [0, 1]);
}

// round(√(x·65535)): √0 = 0; √(65535²) = 65535; √65535 = 255.998;
// √(16384·65535) = 32767.75.
#[test]
fn a_root_is_rounded() {
    let pairs = [(0, 0), (65535, 0), (1, 0), (16384, 0)];
    assert_eq!(each(SQRT, &pairs), [0, 65535, 256, 32768]);
}

const SOME: Rgba = [12345, 40000, 777, wide(128)];

// Over nothing, ad = 0: the destination's weights are 0 and the source's
// is its whole alpha, in every mode — a glow's too.
#[test]
fn over_nothing_every_mode_lands_the_source() {
    for (mode, name) in MODES {
        let out = composite(mode, SOME, [65535, 0, 32896, 0]);
        assert_eq!(out, SOME, "{name}");
    }
}

// as = 0: the alpha out is the destination's, and only cd has weight —
// a glow's B of nothing is the destination's own channel.
#[test]
fn a_clear_source_leaves_every_destination_as_it_was() {
    for (mode, name) in MODES {
        let out = composite(mode, [65535, 0, 32896, 0], SOME);
        assert_eq!(out, SOME, "{name}");
    }
}

// Nothing over nothing ends with no alpha, and so with no colour.
#[test]
fn nothing_over_nothing_is_nothing_whatever_it_held() {
    for (mode, name) in MODES {
        let out = composite(mode, [65535, 1, 2, 0], [3, 65535, 4, 0]);
        assert_eq!(out, [0, 0, 0, 0], "{name}");
    }
}

// ABI 40's rule by the formula: the three weights sum to the alpha out, so
// a colour over itself is itself at any pair of alphas.
#[test]
fn normal_over_its_own_colour_keeps_it_exactly() {
    for a_s in ALPHAS.into_iter().filter(|&a| a > 0) {
        for a_d in ALPHAS {
            let out = composite(NORMAL, [12345, 40000, 777, a_s], [12345, 40000, 777, a_d]);
            assert_eq!(out[..3], [12345, 40000, 777], "as {a_s} ad {a_d}");
        }
    }
}

// Half-opaque red over opaque blue: ad(1 - as) = round(65535·32639/65535)
// = 32639, so the alpha out is whole; red is 32896·65535/65535 and blue
// 32639·65535/65535 — bytes 128 and 127.
#[test]
fn half_red_over_opaque_blue() {
    let out = composite(NORMAL, [65535, 0, 0, wide(128)], [0, 0, 65535, 65535]);
    assert_eq!(out, [32896, 0, 32639, 65535]);
}

// Both opaque, the composite is B itself: 32896 times 32896 is 16513.
#[test]
fn multiply_of_two_opaque_greys_is_their_product() {
    let grey = [32896, 32896, 32896, 65535];
    assert_eq!(composite(3, grey, grey), [16513, 16513, 16513, 65535]);
}

// Byte pairs summing to 255 widen to exactly 65535 and go white; 254 is
// short and goes black.
#[test]
fn hard_mix_whitens_where_two_bytes_reach_255() {
    let src = [wide(128), wide(127), 0, 65535];
    let dst = [wide(127), wide(127), wide(255), 65535];
    assert_eq!(composite(18, src, dst), [65535, 0, 65535, 65535]);
}

// Equal channel totals are a tie, and a tie keeps what is there.
#[test]
fn darker_colour_keeps_the_destination_on_a_tie() {
    let src = [wide(100), wide(50), wide(150), 65535];
    let dst = [wide(150), wide(100), wide(50), 65535];
    assert_eq!(composite(20, src, dst), dst);
}

// A grey's luminosity is the grey (the weights sum to 65536), so a grey's
// luminosity laid on another grey is the first grey, unclipped.
#[test]
fn luminosity_of_a_grey_on_a_grey_is_that_grey() {
    let src = [40000, 40000, 40000, 65535];
    let dst = [777, 777, 777, 65535];
    assert_eq!(composite(25, src, dst), src);
}

// A grey has no saturation, so its hue on pure red is red's luminosity as
// a grey: (19661·65535 + 32768) >> 16 = 19661.
#[test]
fn a_grey_hue_on_red_is_reds_luminosity() {
    let src = [wide(90), wide(90), wide(90), 65535];
    let dst = [65535, 0, 0, 65535];
    assert_eq!(composite(22, src, dst), [19661, 19661, 19661, 65535]);
}

// The eraser takes alpha and leaves colour: 65535 times 65535 - 32896 is
// 32639. A whole eraser leaves nothing, colour included.
#[test]
fn the_eraser_takes_alpha_and_keeps_colour() {
    let dst = [12345, 40000, 777, 65535];
    assert_eq!(
        run(&[(ERASE, [0, 0, 0, wide(128)], dst), (ERASE, [0, 0, 0, 65535], dst)]),
        [[12345, 40000, 777, 32639], [0, 0, 0, 0]]
    );
}

// srcATop: the alpha out is the base's. On an opaque base it is normal
// over it (half red over blue as above); on a half base an opaque source
// is its own colour at the base's alpha; a clear source leaves the base;
// where there is no base there is nothing.
#[test]
fn a_clipped_source_lands_by_the_base_alpha() {
    let blue = [0, 0, 65535, 65535];
    let half_blue = [0, 0, 65535, wide(128)];
    let red = [65535, 0, 0, 65535];
    assert_eq!(
        run(&[
            (ATOP, [65535, 0, 0, wide(128)], blue),
            (ATOP, red, half_blue),
            (ATOP, [65535, 0, 0, 0], half_blue),
            (ATOP, red, [0, 0, 65535, 0]),
        ]),
        [
            [32896, 0, 32639, 65535],
            [65535, 0, 0, wide(128)],
            half_blue,
            [0, 0, 0, 0],
        ]
    );
}

// A stored pixel is RGBA8 with red in the low byte, each channel c·257 on
// the wide scale; packing rounds each once, and an alpha that rounds to no
// byte (128 does, 129 does not) takes the colour with it.
#[test]
fn a_pixel_is_stored_as_rgba8_and_read_back_wide() {
    assert_eq!(
        run(&[(UNPACK, [0x8040_2010, 0, 0, 0], [0; 4])]),
        [[wide(0x10), wide(0x20), wide(0x40), wide(0x80)]]
    );
    let packed: Vec<u32> = run(&[
        (PACK, [65535, 32896, 0, 65535], [0; 4]),
        (PACK, [65535, 65535, 65535, 128], [0; 4]),
        (PACK, [65535, 65535, 65535, 129], [0; 4]),
    ])
    .into_iter()
    .map(|out| out[0])
    .collect();
    assert_eq!(packed, [0xff00_80ff, 0, 0x01ff_ffff]);
}
