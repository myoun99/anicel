//! What every pass of a kernel takes the same way: the words it reads, the
//! planes it puts, whether the device's bindings and dispatches reach them,
//! and its dispatches encoded in order. ⛔ONE COPY (CLAUDE.md 절대명령 1):
//! the blurs held these until the mask passes came as a second kind of
//! kernel to need them (11-05) — a kernel's own module adds its bindings,
//! never its own plumbing.

use wgpu::util::DeviceExt;

use crate::device::Engine;
use crate::fail;

/// A buffer a pass reads or puts, of `bytes` — nothing at first: wgpu
/// zeroes a new buffer.
pub(crate) fn plane(engine: &Engine, label: &str, bytes: u64) -> wgpu::Buffer {
    engine.device.create_buffer(&wgpu::BufferDescriptor {
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
    engine
        .device
        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some(label),
            contents: &le_bytes(words),
            usage,
        })
}

/// `words` as a buffer holds them: little-endian, one after another.
pub(crate) fn le_bytes(words: &[u32]) -> Vec<u8> {
    words.iter().flat_map(|word| word.to_le_bytes()).collect()
}

/// Whether a binding holds each of `planes` (bytes) and a dispatch reaches
/// each of `groups`.
pub(crate) fn fits(
    engine: &Engine,
    planes: &[u64],
    mut groups: impl Iterator<Item = (u32, u32)>,
) -> Option<()> {
    let limits = engine.device.limits();
    let room = u64::from(limits.max_storage_buffer_binding_size).min(limits.max_buffer_size);
    if let Some(plane) = planes.iter().find(|&&plane| plane > room) {
        return fail(format!(
            "a plane of {plane} bytes exceeds a binding of {room} — a picture this large \
             waits for the round that cuts it into bands"
        ));
    }
    let most = limits.max_compute_workgroups_per_dimension;
    if groups.any(|(across, down)| across > most || down > most) {
        return fail("a pass has more workgroups than a dispatch reaches");
    }
    Some(())
}

//// One dispatch as it is encoded: its pipeline, what it binds — a buffer
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

/// Workgroups across and down, one deep — a pass over a plane.
pub(crate) fn flat((across, down): (u32, u32)) -> (u32, u32, u32) {
    (across, down, 1)
}

/// Encodes `dispatches` in order on `encoder`, in one compute pass — each
/// dispatch sees what the ones before it put (wgpu orders a pass's
/// dispatches as it would passes). Submitting is the caller's: a kernel
/// that copies between its dispatches, or times the GPU's work alone,
/// submits where it does now.
pub(crate) fn encode_on(
    engine: &Engine,
    encoder: &mut wgpu::CommandEncoder,
    dispatches: &[Encoded],
) {
    let bind_groups: Vec<wgpu::BindGroup> = dispatches
        .iter()
        .map(|dispatch| {
            engine.device.create_bind_group(&wgpu::BindGroupDescriptor {
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
        .device
        .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
    encode_on(engine, &mut encoder, dispatches);
    engine.queue.submit([encoder.finish()]);
}
