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
    let bytes: Vec<u8> = words.iter().flat_map(|word| word.to_le_bytes()).collect();
    engine
        .device
        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some(label),
            contents: &bytes,
            usage,
        })
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

/// One dispatch as it is encoded: its pipeline, each buffer at the binding
/// it is bound to, and its workgroups.
pub(crate) struct Encoded<'a> {
    pub(crate) pipeline: &'a wgpu::ComputePipeline,
    pub(crate) bound: Vec<(u32, &'a wgpu::Buffer)>,
    pub(crate) groups: (u32, u32),
}

/// Encodes `dispatches` in order and submits them; the caller waits.
pub(crate) fn encode(engine: &Engine, dispatches: &[Encoded]) {
    let mut encoder = engine
        .device
        .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
    for dispatch in dispatches {
        let entries: Vec<wgpu::BindGroupEntry> = dispatch
            .bound
            .iter()
            .map(|&(binding, buffer)| wgpu::BindGroupEntry {
                binding,
                resource: buffer.as_entire_binding(),
            })
            .collect();
        let bind_group = engine.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: None,
            layout: &dispatch.pipeline.get_bind_group_layout(0),
            entries: &entries,
        });
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
        compute.set_pipeline(dispatch.pipeline);
        compute.set_bind_group(0, &bind_group, &[]);
        compute.dispatch_workgroups(dispatch.groups.0, dispatch.groups.1, 1);
    }
    engine.queue.submit([encoder.finish()]);
}
