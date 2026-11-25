//! A surface's texels moved by whole pixels ([`Composite::moved`]): what a
//! screen panned by them still holds of the frame drawn on it last, put
//! where the pan takes it — the walk then draws what it uncovers alone
//! (the app's `EngineStackScreen.show`).
//!
//! 🗣️유저 2026-11-23, build 1099 on a Galaxy Tab (card
//! the-galaxy-tab-canvas-went-slow-on-build-1095): 「처음은 100미만 팬,줌」 —
//! the first of three slow things photographed. 🔬Every frame a pan under
//! 100 % stepped past the margin its screen spares (the app's
//! `_screenMargin`) drew every texel of its target again — 3584 × 2560,
//! each a blend of some 5 × 5 of the canvas's at × 0.63 —, 43 ms of that
//! tablet's GPU (the engine's stages, the same photographs). A pan moves
//! every texel it keeps by the same whole pixels, so the frame drawn last
//! holds them all but those it uncovers.
//!
//! 🚨WORD FOR WORD: a texel moved is the one the surface held, its bytes as
//! they lay — copied out as the surface stores them and stored back so
//! (moved.wgsl), the camera that drew them the one the pan's frame is drawn
//! through, moved by whole pixels (`EngineStackScreen.show` makes it so).
//!
//! 🚨A BAND AT A TIME, the band the move goes away from first: a band is
//! copied out whole before any of it is stored, and stored onto rows the
//! bands after it do not read — down, the rows below are stored first.
//! Through one buffer of [`BAND_BYTES`] at most, one of the engine's spares
//! ([`spares`](super::spares)): kept while a hand is at work, let go once
//! it rests.

use super::Composite;
use crate::device::Engine;
use crate::fail;
use crate::kernels::shared::{
    Encoded, bands, encode_on, flat, kept_or_made, land_storage_writes, pipeline, room, storage_format,
    whole, words_buffer,
};

/// moved.wgsl's workgroup side.
const GROUP: u32 = 8;

/// The most bytes a band of a move holds ([`Composite::moved`]).
///
/// 🔢브러시/렌더링's (2026-11-23; no rule of the user's): what a band costs
/// is the buffer kept for it while a hand is at work, and a band more is a
/// copy and a dispatch more — a Galaxy Tab's screen (3584 × 2560, 35 MiB)
/// moves in five bands, a 4K one's some 500 rows a band. How many rows
/// that holds is the engine's one law for it ([`bands`]).
const BAND_BYTES: u64 = 8 << 20;

/// The move pass for a surface stored in the WGSL format `token`
/// ([`storage_format`]).
pub(super) fn compile(engine: &Engine, token: &'static str) -> wgpu::ComputePipeline {
    let source = include_str!("moved.wgsl").replace("__FORMAT__", token);
    pipeline(engine, &[&source], "moved_store")
}

/// What stays on a side of `side` texels of what moves `by` along it:
/// where it lies before the move, [from, to) — none where all of it goes
/// off.
pub(super) fn staying(by: i32, side: u32) -> Option<(u32, u32)> {
    let side = i64::from(side);
    let from = (-i64::from(by)).max(0);
    let to = (side - i64::from(by)).min(side);
    // Both within [0, side], a u32's.
    (from < to).then(|| (from as u32, to as u32))
}

impl Composite {
    /// Moves the texels of `surface` by `by` — the one at (x, y) to
    /// (x + dx, y + dy) — and leaves those the move uncovers as they were;
    /// submits the work and waits for none of it, as [`Composite::show`]
    /// does.
    pub(crate) fn moved(&self, engine: &Engine, surface: &wgpu::Texture, by: (i32, i32)) -> Option<()> {
        let Some(token) = storage_format(surface.format()) else {
            return fail(format!("the composite cannot move texels of {:?}", surface.format()));
        };
        let (dx, dy) = by;
        let (Some((left, right)), Some((top, bottom))) =
            (staying(dx, surface.width()), staying(dy, surface.height()))
        else {
            return Some(());
        };
        let columns = right - left;
        let stride = (columns * 4).next_multiple_of(wgpu::COPY_BYTES_PER_ROW_ALIGNMENT);
        // A band's copy lies from the buffer's first word.
        let step = u64::from(engine.device().limits().min_storage_buffer_offset_alignment);
        let words_a_row = u64::from(stride / 4);
        let mut cut = bands(top..bottom, 1, (BAND_BYTES.min(room(engine)), step), |band| {
            vec![0..band.len() as u64 * words_a_row]
        })?;
        if dy > 0 {
            cut.reverse();
        }
        let most = cut.iter().map(|band| band.len() as u64).max().unwrap_or(0);
        let pass = kept_or_made(&self.moves.cell(Some(token)), || compile(engine, token)).clone();
        let copied = engine.spares.of(engine, u64::from(stride) * most);
        let view = surface.create_view(&wgpu::TextureViewDescriptor::default());
        let mut encoder = engine.device().create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        for band in cut {
            let (from, rows) = (band.start, band.end - band.start);
            encoder.copy_texture_to_buffer(
                wgpu::TexelCopyTextureInfo {
                    texture: surface,
                    mip_level: 0,
                    origin: wgpu::Origin3d { x: left, y: from, z: 0 },
                    aspect: wgpu::TextureAspect::All,
                },
                wgpu::TexelCopyBufferInfo {
                    buffer: copied.buffer(),
                    layout: wgpu::TexelCopyBufferLayout {
                        offset: 0,
                        bytes_per_row: Some(stride),
                        rows_per_image: Some(rows),
                    },
                },
                wgpu::Extent3d { width: columns, height: rows, depth_or_array_layers: 1 },
            );
            // Within the surface: what stays lands on it.
            let onto = |at: u32, by: i32| (i64::from(at) + i64::from(by)) as u32;
            let words = [onto(left, dx), onto(from, dy), columns, rows, stride / 4];
            let record = words_buffer(engine, "moved", &words, wgpu::BufferUsages::STORAGE);
            let mut bound = whole(&[(0, &record), (1, copied.buffer())]);
            bound.push(wgpu::BindGroupEntry { binding: 2, resource: wgpu::BindingResource::TextureView(&view) });
            let groups = flat((columns.div_ceil(GROUP), rows.div_ceil(GROUP)));
            encode_on(engine, &mut encoder, &[Encoded { pipeline: &pass, bound, groups }]);
        }
        // What is drawn after the move — the tiles changed since, over texels
        // it moved — lands after its stores ([`land_storage_writes`]'s 🚨).
        // Its bands need none between them: a band's copy is a use of its
        // own, and no band stores where another does.
        land_storage_writes(&mut encoder, surface);
        engine.queue.submit([encoder.finish()]);
        Some(())
    }
}
