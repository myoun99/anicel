//! A pass over a run of tiles on the pool's pages ([`runs`]), as the
//! kernels that give each pass its own words bind it: its uniform at 0,
//! what it is given at 1, the kernel's own two at 2 and 3, the run's pages
//! after them, and a workgroup a tile. ⛔ONE SHAPE: the cel pixel verbs and
//! the lift each built it, and the write path came as a third (11-06, rule
//! of three).

use std::ops::Range;

use super::{Encoded, Pages, fits, le_bytes, whole, words_buffer};
use crate::device::Engine;
use crate::fail;

/// A pass: its run of the tiles, and the pages it binds — a page's k its
/// place among them ([`runs`]).
pub(crate) type Run = (Range<usize>, Vec<u16>);

/// Fails unless a pass binds 1 to the `pages`' pages and takes a tile.
pub(crate) fn cut_by(pages: &Pages, (per_pass, most): (usize, usize)) -> Option<()> {
    if per_pass == 0 || per_pass > pages.per_pass() || most == 0 {
        return fail(format!(
            "{per_pass} pages and {most} tiles a pass; this device binds 1 to {} pages",
            pages.per_pass()
        ));
    }
    Some(())
}

/// What a pass is given — its tiles' words, then the kernel's, then any
/// bytes copied after them — and its uniform.
pub(crate) struct Given {
    pub(crate) words: wgpu::Buffer,
    pub(crate) uniform: wgpu::Buffer,
}

impl Given {
    /// [`given`] `words` and `band`, and `uniform`.
    pub(crate) fn new(
        engine: &Engine,
        encoder: &mut wgpu::CommandEncoder,
        words: &[u32],
        band: Option<(&wgpu::Buffer, Range<u64>)>,
        uniform: &[u32],
    ) -> Option<Given> {
        Some(Given {
            words: given(engine, encoder, words, band)?,
            uniform: words_buffer(engine, "pass uniform", uniform, wgpu::BufferUsages::UNIFORM),
        })
    }
}

/// What a pass is given: `words`, and `band`'s bytes of its buffer after
/// them — a selection's rows, copied there on `encoder`, before the passes
/// that read them. The blur's cel passes, shaped apart, are given theirs by
/// it too.
pub(crate) fn given(
    engine: &Engine,
    encoder: &mut wgpu::CommandEncoder,
    words: &[u32],
    band: Option<(&wgpu::Buffer, Range<u64>)>,
) -> Option<wgpu::Buffer> {
    let copied = band.as_ref().map_or(0, |(_, bytes)| bytes.end - bytes.start);
    let size = words.len() as u64 * 4 + copied;
    fits(engine, &[size], std::iter::empty())?;
    let given = engine.device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("pass given"),
        size,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    engine.queue.write_buffer(&given, 0, &le_bytes(words));
    if let Some((from, bytes)) = band {
        encoder.copy_buffer_to_buffer(from, bytes.start, &given, size - copied, copied);
    }
    Some(given)
}

/// `pipeline` over `pass`, given `given`, its tiles a workgroup each: what
/// the kernel puts bound at 2 and 3 as `own` has it, and the pass's pages
/// among `pages` — the pool's `pool`.
pub(crate) fn encoded<'a>(
    pages: &'a Pages,
    pipeline: &'a wgpu::ComputePipeline,
    pool: &'a [wgpu::Buffer],
    (run, bound): &Run,
    given: &'a Given,
    own: [Option<wgpu::BindingResource<'a>>; 2],
) -> Encoded<'a> {
    let mut entries = whole(&[(0, &given.uniform), (1, &given.words)]);
    for (binding, resource) in (2..).zip(own) {
        if let Some(resource) = resource {
            entries.push(wgpu::BindGroupEntry { binding, resource });
        }
    }
    entries.extend(pages.entries(bound.iter().map(|&page| &pool[usize::from(page)])));
    Encoded { pipeline, bound: entries, groups: (run.len() as u32, 1, 1) }
}
