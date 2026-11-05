//! Reading the pool's pages — the stored tiles, a page a storage buffer —
//! in a pass: which pages it binds and how a pixel's word is read from one
//! (gpu-canonical-store 23:52). The composite reads its rows so, and every
//! kernel that reads a stored tile reads it the same way.
//!
//! A stroke's planes are kept on pages by the same law, a tile a slot of a
//! page, and the dab kernels read and put their words so (캔버스 베이스
//! 11-06 03:36): a binding holds 128 MB on some devices, less than a big
//! brush's one dab reaches.
//!
//! A device binds few storage buffers a stage — 4 on GLES — so a pass binds
//! as many pages as are left past the kernel's own buffers, and a table
//! tells it which binding holds each page of the pool.

use std::ops::Range;

use crate::device::Engine;
use crate::fail;

/// The most pages one pass binds, whatever the device allows: each is a
/// case of `page_word`.
const MOST_PAGES: usize = 16;

/// In a pass's table, a page of the pool the pass binds none of.
pub(crate) const NO_PAGE: u32 = u32::MAX;

/// How a kernel binds pages: as many as a pass can on this device, from
/// one binding on, and a blank one wherever a pass has fewer — to read, or
/// to read and put.
pub(crate) struct Pages {
    first: u32,
    per_pass: usize,
    writable: bool,
    blank: wgpu::Buffer,
}

impl Pages {
    /// For a kernel with `own` storage buffers besides its pages, whose
    /// pages begin at binding `first` and are only read — or nothing, where
    /// the device leaves it no page to bind.
    pub(crate) fn new(engine: &Engine, own: u32, first: u32) -> Option<Pages> {
        Self::bound(engine, (own, first), false, MOST_PAGES)
    }

    /// [`Pages::new`] for a kernel that puts words on its pages too
    /// (`page_put`), binding no more than `most` a pass: a kernel whose
    /// passes mostly bind one compiles itself for one apart, as each page a
    /// pass binds is a case of every read and put. The pages past the ones
    /// a pass binds are blank, so no test tells a pass of fewer from one of
    /// the device's most — only the time (mutant p04, 11-06).
    pub(crate) fn writable(engine: &Engine, own: u32, first: u32, most: usize) -> Option<Pages> {
        Self::bound(engine, (own, first), true, most)
    }

    fn bound(
        engine: &Engine,
        (own, first): (u32, u32),
        writable: bool,
        most: usize,
    ) -> Option<Pages> {
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
        let per_pass = ((limit - own) as usize).min(MOST_PAGES).min(most);
        Some(Pages { first, per_pass, writable, blank })
    }

    /// How many pages a pass binds.
    pub(crate) fn per_pass(&self) -> usize {
        self.per_pass
    }

    /// The binding past the pages.
    pub(crate) fn end(&self) -> u32 {
        self.first + self.per_pass as u32
    }

    /// The WGSL that binds the pages and reads them: `page_word(k, index)`,
    /// and where they are writable `page_put(k, index, word)`.
    pub(crate) fn source(&self) -> String {
        let access = if self.writable { "read_write" } else { "read" };
        let bindings: String = (0..self.per_pass)
            .map(|k| {
                format!(
                    "@group(0) @binding({}) var<storage, {access}> page{k}: array<u32>;\n",
                    self.first as usize + k
                )
            })
            .collect();
        let reads: String = (0..self.per_pass)
            .map(|k| format!("case {k}u: {{\n      return page{k}[index];\n    }}\n    "))
            .collect();
        let source = include_str!("pages.wgsl")
            .replace("//__PAGES__", &bindings)
            .replace("//__READS__", &reads);
        if !self.writable {
            return source;
        }
        let puts: String = (0..self.per_pass)
            .map(|k| format!("case {k}u: {{\n      page{k}[index] = word;\n    }}\n    "))
            .collect();
        source + "\n" + &include_str!("page_put.wgsl").replace("//__PUTS__", &puts)
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

/// Tiles in their order — each on the page `pages` names for it — cut into
/// the runs a kernel's passes take, each with the pages it binds in the
/// order they come (a page's k): a run ends where its next tile would
/// bring it past `per_pass` pages or `most` tiles. The tiles keep their
/// order, so a pass binds the range of a run in what it writes (dab/blur.rs:
/// the cel's passes).
///
/// The second greedy cut by the pages a pass binds — the executor's `cut`
/// (composite/mod.rs) is the first, which holds stack levels too: the two
/// stay apart until a third comes (rule of three, CLAUDE.md absolute
/// rule 1).
pub(crate) fn runs(
    pages: impl ExactSizeIterator<Item = u16>,
    per_pass: usize,
    most: usize,
) -> Vec<(Range<usize>, Vec<u16>)> {
    let count = pages.len();
    let mut runs = Vec::new();
    let mut first = 0;
    let mut bound: Vec<u16> = Vec::new();
    for (index, page) in pages.enumerate() {
        let fresh = !bound.contains(&page);
        if index - first == most || (fresh && bound.len() == per_pass) {
            runs.push((first..index, std::mem::take(&mut bound)));
            first = index;
        }
        if !bound.contains(&page) {
            bound.push(page);
        }
    }
    if first < count {
        runs.push((first..count, bound));
    }
    runs
}
