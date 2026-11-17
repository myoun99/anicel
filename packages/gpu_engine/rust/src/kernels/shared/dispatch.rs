//! What every pass of a kernel takes the same way: the words it reads, the
//! planes it puts, whether the device's bindings and dispatches reach them,
//! and its dispatches encoded in order. ⛔ONE COPY (CLAUDE.md 절대명령 1):
//! the blurs held these until the mask passes came as a second kind of
//! kernel to need them (11-05) — a kernel's own module adds its bindings,
//! never its own plumbing.

use std::ops::Range;


use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::TILE_BYTES;

/// A buffer a pass reads or puts, of `bytes` — nothing at first: wgpu
/// zeroes a new buffer.
pub(crate) fn plane(engine: &Engine, label: &str, bytes: u64) -> wgpu::Buffer {
    engine.device().create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: bytes,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    })
}

/// `words` as a buffer a pass reads them from, `usage` its kind.
pub(crate) fn words_buffer(
    engine: &Engine,
    label: &str,
    words: &[u32],
    usage: wgpu::BufferUsages,
) -> wgpu::Buffer {
    engine.filled(label, &le_bytes(words), usage)
}

/// `words` as a buffer holds them: little-endian, one after another.
pub(crate) fn le_bytes(words: &[u32]) -> Vec<u8> {
    words.iter().flat_map(|word| word.to_le_bytes()).collect()
}

/// The words a buffer's `bytes` hold — [`le_bytes`] read back.
pub(crate) fn le_words(bytes: &[u8]) -> Vec<u32> {
    bytes.chunks_exact(4).map(|four| u32::from_le_bytes([four[0], four[1], four[2], four[3]])).collect()
}

/// The bytes one binding holds on this device: no more than a buffer does.
pub(crate) fn room(engine: &Engine) -> u64 {
    let limits = engine.device().limits();
    u64::from(limits.max_storage_buffer_binding_size).min(limits.max_buffer_size)
}

/// The most tiles a pass takes on this device, a workgroup each, with
/// `per_tile` bytes each in a binding past `fixed` of its own: as many as a
/// dispatch reaches and the binding holds. Fails where one tile's do not
/// fit. ⛔ONE COUNT: the composite, the blur dabs, the cel pixel verbs and
/// the lift each worked it out (11-06, rule of three).
pub(crate) fn tiles_a_pass(engine: &Engine, per_tile: u64, fixed: u64) -> Option<usize> {
    let reach = u64::from(engine.device().limits().max_compute_workgroups_per_dimension);
    let held = room(engine).saturating_sub(fixed).checked_div(per_tile);
    match held.unwrap_or(reach).min(reach) {
        0 => fail(format!("one tile's {per_tile} bytes exceed a binding")),
        most => Some(most as usize),
    }
}

/// The most tiles a page takes on this device: as many as a pass takes and
/// a slot names — a u16 (`TileAt`). ⛔ONE COUNT: a gathered row's page, a
/// chained row's, a stamp's and the letters' each worked it out, and a kept
/// picture's was to be the fifth (11-08). ⚠️No test reaches the u16: a
/// page past it is a binding of 4 GiB, past every device here (mutant M13,
/// 11-08).
pub(crate) fn tiles_a_page(engine: &Engine) -> Option<usize> {
    Some(tiles_a_pass(engine, TILE_BYTES, 0)?.min(usize::from(u16::MAX)))
}

/// The most rows of a plane, `row_bytes` each, one binding of `room` bytes
/// holds wherever they start: a binding begins on a multiple of `step` —
/// the device's `min_storage_buffer_offset_alignment` — up to a step short
/// of its first row ([`words_bound`]); any number of rows of nothing (an
/// empty mask's). Fails where one row does not fit.
///
/// Board the-engine-binds-a-plane-past-the-device-limit (2026-11-17): a
/// plane read whole was bound whole, and a binding holds 128 MiB on
/// lavapipe — a stamp's picture of 7,988² past it at a wgpu validation
/// error. A plane read a part at a time is read as rows, these many a
/// part.
pub(crate) fn rows_a_binding(room: u64, step: u64, row_bytes: u64) -> Option<u64> {
    match room.saturating_sub(step).checked_div(row_bytes) {
        None => Some(u64::MAX),
        Some(0) => fail(format!("a row of {row_bytes} bytes exceeds a binding of {room}")),
        Some(rows) => Some(rows),
    }
}

/// The `words` of `buffer` as one binding a device takes — from the
/// multiple of `step` at or before their first, through their last or the
/// buffer's end — and the word it begins on, which a pass's indices count
/// from.
pub(crate) fn words_bound(
    buffer: &wgpu::Buffer,
    words: Range<u64>,
    step: u64,
) -> (wgpu::BindingResource<'_>, u64) {
    let start = words.start * 4 / step * step;
    let end = (words.end * 4).min(buffer.size());
    (range(buffer, start..end), start / 4)
}

/// `rows` of a pass's invocations in bands, each as many `unit`s of rows —
/// a workgroup's — as one binding of `room` bytes, begun on a multiple of
/// `step`, holds of every plane the band binds: `planes` the words each
/// lies on for a band of rows, as [`words_bound`] binds them. None, with
/// why, where one unit's do not fit.
///
/// 🚨ONE LAW FOR HOW MANY ROWS A BAND TAKES (board
/// conversions-bind-a-frame-past-the-device-limit, 2026-11-17): a band
/// grows while what it would bind fits — each pass says only which words
/// its rows lie on. ↩️The lay and the clear bits counted their rows by sums
/// of their own, one proved apart from the other's.
pub(crate) fn bands(
    rows: Range<u32>,
    unit: u32,
    (room, step): (u64, u64),
    planes: impl Fn(Range<u32>) -> Vec<Range<u64>>,
) -> Option<Vec<Range<u32>>> {
    // An empty plane is bound a word, as a binding holds something.
    let binds = |words: &Range<u64>| words.end.max(words.start + 1) * 4 - words.start * 4 / step * step;
    let held = |band: Range<u32>| planes(band).iter().map(binds).max().unwrap_or(0);
    let next = |end: u32| end.saturating_add(unit).min(rows.end);
    let mut bands = Vec::new();
    let mut start = rows.start;
    while start < rows.end {
        let mut end = next(start);
        let first = held(start..end);
        if first > room {
            let rows = if unit == 1 { "a row of a pass binds".to_owned() } else { format!("{unit} rows of a pass bind") };
            return fail(format!("{rows} {first} bytes, past a binding of {room}"));
        }
        while end < rows.end && held(start..next(end)) <= room {
            end = next(end);
        }
        bands.push(start..end);
        start = end;
    }
    Some(bands)
}

/// Whether the device makes a buffer of `bytes` — none, with why, where
/// not. A plane only made, copied or bound a part at a time asks this,
/// not [`fits`]: a buffer holds more than one binding of it does (board
/// the-engine-binds-a-plane-past-the-device-limit, 2026-11-17).
pub(crate) fn buffer_holds(engine: &Engine, bytes: u64) -> Option<()> {
    let most = engine.device().limits().max_buffer_size;
    if bytes > most {
        return fail(format!("a plane of {bytes} bytes exceeds a buffer of {most}"));
    }
    Some(())
}

/// Whether a binding holds each of `planes` (bytes) and a dispatch reaches
/// each of `groups`.
pub(crate) fn fits(
    engine: &Engine,
    planes: &[u64],
    mut groups: impl Iterator<Item = (u32, u32)>,
) -> Option<()> {
    let limits = engine.device().limits();
    let room = room(engine);
    if let Some(plane) = planes.iter().find(|&&plane| plane > room) {
        return fail(format!("a plane of {plane} bytes exceeds a binding of {room}"));
    }
    let most = limits.max_compute_workgroups_per_dimension;
    if groups.any(|(across, down)| across > most || down > most) {
        return fail("a pass has more workgroups than a dispatch reaches");
    }
    Some(())
}

/// One dispatch as it is encoded: its pipeline, what it binds — a buffer
/// whole or a range of one, a texture's view, a kernel's pages — and its
/// workgroups, across, down and deep.
pub(crate) struct Encoded<'a> {
    pub(crate) pipeline: &'a wgpu::ComputePipeline,
    pub(crate) bound: Vec<wgpu::BindGroupEntry<'a>>,
    pub(crate) groups: (u32, u32, u32),
}

/// `bound`, each buffer whole at its binding — what most passes bind.
pub(crate) fn whole<'a>(bound: &[(u32, &'a wgpu::Buffer)]) -> Vec<wgpu::BindGroupEntry<'a>> {
    bound
        .iter()
        .map(|&(binding, buffer)| wgpu::BindGroupEntry {
            binding,
            resource: buffer.as_entire_binding(),
        })
        .collect()
}

/// Where the next part of a plane whose parts so far are `bytes` may start
/// as a binding of its own: `bytes` padded with zeros to a multiple of
/// `align` — a device's `min_storage_buffer_offset_alignment` — and that
/// place. ⚠️The frame grid's tiles and the waves laid over them, each
/// dispatch's words and stream a part ([`range`]); the dabs place their
/// dispatches' uniforms on their plan in words, apart (dab/mod.rs, blur.rs).
pub(crate) fn aligned(bytes: &mut Vec<u8>, align: usize) -> u64 {
    bytes.resize(bytes.len().next_multiple_of(align), 0);
    bytes.len() as u64
}

/// `bytes` of `buffer` as a binding — a pass's part of a plane its passes
/// share. ⛔ONE: the blur's cel passes and its dispatches' words, the
/// pile's passes' words, the cel pixel verbs and the lift each wrote it,
/// and the write path came as another (11-06).
pub(crate) fn range(buffer: &wgpu::Buffer, bytes: Range<u64>) -> wgpu::BindingResource<'_> {
    wgpu::BindingResource::Buffer(wgpu::BufferBinding {
        buffer,
        offset: bytes.start,
        size: wgpu::BufferSize::new(bytes.end - bytes.start),
    })
}

/// Workgroups across and down, one deep — a pass over a plane.
pub(crate) fn flat((across, down): (u32, u32)) -> (u32, u32, u32) {
    (across, down, 1)
}

/// 🚨What write-only storage bindings of `target` have written so far lands
/// before what is encoded after this touches it, between two passes. wgpu's
/// DX12 puts a UAV barrier between two uses of a texture only when the first
/// was read-write (wgpu-hal 30.0.1, `transition_textures`), so dispatches
/// writing one pixel through write-only bindings overlap on the GPU and
/// either may land last. 🔬11-09, RTX 4080, a clear and a tile on each pixel:
/// a fifth of the pixels cleared away in one pass (38,683 of 204,800), none
/// of 163,840 in two. ⚠️Two passes held with or without this call there, and
/// D3D12 does not promise it: within one submission a later command list may
/// start before an earlier one has finished (`ExecuteCommandLists`' Remarks).
/// Leaving read-write for the next dispatch's write-only is what makes the
/// barrier, and no texture needs a usage more for it.
pub(crate) fn land_storage_writes(encoder: &mut wgpu::CommandEncoder, target: &wgpu::Texture) {
    encoder.transition_resources(
        std::iter::empty(),
        std::iter::once(wgpu::TextureTransition {
            texture: target,
            selector: None,
            state: wgpu::TextureUses::STORAGE_READ_WRITE,
        }),
    );
}

/// Encodes `dispatches` in order on `encoder`, in one compute pass — each
/// dispatch sees what the ones before it put in a buffer or a read-write
/// binding, not a write-only one's ([`land_storage_writes`]; wgpu orders a pass's
/// dispatches as it would passes). Submitting is the caller's: a kernel
/// that copies between its dispatches, or times the GPU's work alone,
/// submits where it does now. The crate's one compute pass: `one_pass.rs`
/// holds the copies left, on a ledger.
pub(crate) fn encode_on(
    engine: &Engine,
    encoder: &mut wgpu::CommandEncoder,
    dispatches: &[Encoded],
) {
    let bind_groups: Vec<wgpu::BindGroup> = dispatches
        .iter()
        .map(|dispatch| {
            engine.device().create_bind_group(&wgpu::BindGroupDescriptor {
                label: None,
                layout: &dispatch.pipeline.get_bind_group_layout(0),
                entries: &dispatch.bound,
            })
        })
        .collect();
    let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
    for (dispatch, bind_group) in dispatches.iter().zip(&bind_groups) {
        let (across, down, deep) = dispatch.groups;
        compute.set_pipeline(dispatch.pipeline);
        compute.set_bind_group(0, bind_group, &[]);
        compute.dispatch_workgroups(across, down, deep);
    }
}

/// Encodes `dispatches` in order and submits them; the caller waits.
pub(crate) fn encode(engine: &Engine, dispatches: &[Encoded]) {
    let mut encoder = engine
        .device()
        .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
    encode_on(engine, &mut encoder, dispatches);
    engine.queue.submit([encoder.finish()]);
}
