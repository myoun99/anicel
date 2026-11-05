//! Reading the pool's pages — the stored tiles, a page a storage buffer —
//! in a pass: which pages it binds and how a pixel's word is read from one
//! (gpu-canonical-store 23:52). The composite reads its rows so, and every
//! kernel that reads a stored tile reads it the same way.
//!
//! A device binds few storage buffers a stage — 4 on GLES — so a pass binds
//! as many pages as are left past the kernel's own buffers, and a table
//! tells it which binding holds each page of the pool.

use crate::device::Engine;
use crate::fail;

/// The most pages one pass binds, whatever the device allows: each is a
/// case of `page_word`.
const MOST_PAGES: usize = 16;

/// In a pass's table, a page of the pool the pass binds none of.
pub(crate) const NO_PAGE: u32 = u32::MAX;

/// How a kernel binds pages: as many as a pass can on this device, from
/// one binding on, and a blank one wherever a pass has fewer.
pub(crate) struct Pages {
    first: u32,
    per_pass: usize,
    blank: wgpu::Buffer,
}

impl Pages {
    /// For a kernel with `own` storage buffers besides its pages, whose
    /// pages begin at binding `first` — or nothing, where the device leaves
    /// it no page to bind.
    pub(crate) fn new(engine: &Engine, own: u32, first: u32) -> Option<Pages> {
        let limit = engine.device.limits().max_storage_buffers_per_shader_stage;
        if limit <= own {
            return fail(format!("{limit} storage buffers a stage leave no page to bind"));
        }
        let blank = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("blank page"),
            size: 16,
            usage: wgpu::BufferUsages::STORAGE,
            mapped_at_creation: false,
        });
        let per_pass = ((limit - own) as usize).min(MOST_PAGES);
        Some(Pages { first, per_pass, blank })
    }

    /// How many pages a pass binds.
    pub(crate) fn per_pass(&self) -> usize {
        self.per_pass
    }

    /// The binding past the pages.
    pub(crate) fn end(&self) -> u32 {
        self.first + self.per_pass as u32
    }

    /// The WGSL that binds the pages and reads them: `page_word(k, index)`.
    pub(crate) fn source(&self) -> String {
        let bindings: String = (0..self.per_pass)
            .map(|k| {
                format!(
                    "@group(0) @binding({}) var<storage, read> page{k}: array<u32>;\n",
                    self.first as usize + k
                )
            })
            .collect();
        let reads: String = (0..self.per_pass)
            .map(|k| format!("case {k}u: {{\n      return page{k}[index];\n    }}\n    "))
            .collect();
        include_str!("pages.wgsl")
            .replace("//__PAGES__", &bindings)
            .replace("//__READS__", &reads)
    }

    /// The bindings of a pass's `bound` pages, in order, the blank one past
    /// them.
    pub(crate) fn entries<'a>(
        &'a self,
        bound: impl IntoIterator<Item = &'a wgpu::Buffer>,
    ) -> Vec<wgpu::BindGroupEntry<'a>> {
        let mut bound = bound.into_iter();
        (0..self.per_pass)
            .map(|k| wgpu::BindGroupEntry {
                binding: self.first + k as u32,
                resource: bound.next().unwrap_or(&self.blank).as_entire_binding(),
            })
            .collect()
    }
}

/// A pass's table of pages: for each of the pool's `pool` pages, the k of
/// the binding among `bound` that holds it, or NO_PAGE.
pub(crate) fn page_table(bound: &[u16], pool: usize) -> impl Iterator<Item = u32> + '_ {
    (0..pool).map(move |page| {
        bound
            .iter()
            .position(|&each| usize::from(each) == page)
            .map_or(NO_PAGE, |k| k as u32)
    })
}
