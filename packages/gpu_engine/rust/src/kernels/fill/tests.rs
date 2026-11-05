//! The fill pass on a real GPU, checked against the ledger and against
//! what the formula gives by hand — never against a CPU copy of it
//! (`kernels/mod.rs` has why).

use super::Fill;
use crate::device::Engine;
use crate::testing::{assert_pinned, first_engine, storage_texture};

// 70 x 45: rows of 280 bytes are padded to 512 on readback, and neither
// side is a multiple of the 8 x 8 workgroup.
const WIDTH: u32 = 70;
const HEIGHT: u32 = 45;

const BGRA: wgpu::TextureFormat = wgpu::TextureFormat::Bgra8Unorm;
const RGBA: wgpu::TextureFormat = wgpu::TextureFormat::Rgba8Unorm;

fn filled(engine: &Engine, format: wgpu::TextureFormat, seed: u32) -> Vec<u8> {
    let texture = storage_texture(engine, WIDTH, HEIGHT, format);
    Fill::new(engine).run(engine, &texture, seed).expect("fill");
    engine.read_texture(&texture).expect("read back")
}

#[test]
fn every_device_writes_the_pinned_bytes() {
    let engine = first_engine();
    let storable = engine
        .device
        .features()
        .contains(wgpu::Features::BGRA8UNORM_STORAGE);
    assert!(storable, "this adapter cannot store to bgra8unorm");
    for (format, order) in [(BGRA, "bgra"), (RGBA, "rgba")] {
        for seed in [0, 7, u32::MAX] {
            let id = format!("fill/70x45-seed{seed}-{order}");
            assert_pinned(&id, &filled(&engine, format, seed));
        }
    }
}

// mix32(0) is 0 — every step of lowbias32 maps 0 to 0 — so for seed 0 the
// texel at (0, 0) packs to 0xff000000: opaque black, in either order.
#[test]
fn seed_zero_makes_the_first_texel_opaque_black() {
    let engine = first_engine();
    for format in [BGRA, RGBA] {
        assert_eq!(filled(&engine, format, 0)[..4], [0, 0, 0, 0xff], "{format:?}");
    }
}

// The shader ORs 0xff000000 into every texel.
#[test]
fn every_texel_is_opaque() {
    let engine = first_engine();
    let bytes = filled(&engine, RGBA, 7);
    assert!(bytes.chunks_exact(4).all(|texel| texel[3] == 0xff));
}

// The format moves where each channel sits, not what is stored: BGRA's
// bytes are RGBA's with red and blue swapped.
#[test]
fn the_two_orders_differ_only_by_red_and_blue() {
    let engine = first_engine();
    let swapped: Vec<u8> = filled(&engine, BGRA, 7)
        .chunks_exact(4)
        .flat_map(|texel| [texel[2], texel[1], texel[0], texel[3]])
        .collect();
    assert_eq!(swapped, filled(&engine, RGBA, 7));
}
