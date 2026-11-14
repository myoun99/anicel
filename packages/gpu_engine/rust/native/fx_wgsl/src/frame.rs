//! What the host hands one run of a kernel, as both runs bind it: the
//! device's (gpu_engine's kernels/plugin) and the CPU's (run.rs). Each
//! takes a binding's words, the dispatch's size and the bindings the
//! render reaches from here, so the two cannot lay a frame out apart.

use std::borrow::Cow;

use naga::{AddressSpace, StorageAccess};

use crate::Kernel;

/// The prelude's binding the run's picture is written to.
pub const OUTPUT: &str = "anicel_host_output";

/// The prelude's binding a cut run is marked in.
pub const CUT: &str = "anicel_host_cut";

/// The prelude's binding [`Frame`] is laid in.
pub const FRAME: &str = "anicel_host_frame";

/// Where in [`FRAME`]'s words the first group of the chunk a dispatch
/// runs lies, across then down — the prelude's `AnicelFrame.chunk`, 0 0
/// where a run is one dispatch.
pub const CHUNK_WORD: usize = 16;

/// The pictures, values and moment one run is handed — what the GPU's
/// bindings hold (prelude.wgsl's `AnicelFrame` and buffers). Places are
/// canvas pixels; a picture is one straight RGBA8 word a pixel, row by row.
#[derive(Clone, Copy, Debug)]
pub struct Frame<'a> {
    pub out_origin: [i32; 2],
    pub out_size: [i32; 2],
    pub in_origin: [i32; 2],
    pub in_size: [i32; 2],
    pub frame: i32,
    pub time_q16: i32,
    pub rate_q16: i32,
    pub scale_q16: i32,
    /// What each invocation may spend (Q5).
    pub fuel: u32,
    pub input: &'a [u32],
    /// The layer planes, each `in_size`, one after another.
    pub rows: &'a [u32],
    pub values: &'a [[i32; 4]],
}

/// The run spent its share somewhere and was cut.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Cut;

/// A buffer the host binds for the render, which reads or writes it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Bound<'k> {
    /// Its `@binding` in group 0.
    pub number: u32,
    /// Its name in the prelude, what [`Frame::bound`] answers.
    pub name: &'k str,
    /// A uniform buffer; a storage buffer otherwise.
    pub uniform: bool,
    /// Whether the run writes it — the picture and the cut, which the
    /// host reads back.
    pub written: bool,
}

impl<'a> Frame<'a> {
    /// The words the host binds as the prelude's `name`, as its buffer
    /// holds them — the output as the run starts it, the cut as not cut —,
    /// or none for a name the host binds nothing as.
    pub fn bound<'b>(&self, name: &str, output: &'b [u32]) -> Option<Cow<'b, [u32]>>
    where
        'a: 'b,
    {
        match name {
            FRAME => Some(Cow::Owned(self.words())),
            "anicel_host_input" => Some(Cow::Borrowed(self.input)),
            "anicel_host_rows" => Some(Cow::Borrowed(self.rows)),
            "anicel_host_values" => Some(Cow::Owned(self.values.iter().flatten().map(|&w| w as u32).collect())),
            OUTPUT => Some(Cow::Borrowed(output)),
            CUT => Some(Cow::Owned(vec![0])),
            _ => None,
        }
    }

    /// The prelude's `AnicelFrame`, member by member, a word each — as its
    /// uniform buffer holds it, no member padded (tests.rs holds the
    /// members and their offsets to the prelude's).
    fn words(&self) -> Vec<u32> {
        let plane = (self.in_size[0].max(0) * self.in_size[1].max(0)) as usize;
        let rows = if plane == 0 { 0 } else { self.rows.len() / plane };
        let [out_x, out_y] = self.out_origin;
        let [out_w, out_h] = self.out_size;
        let [in_x, in_y] = self.in_origin;
        let [in_w, in_h] = self.in_size;
        let signed = [
            out_x,
            out_y,
            out_w,
            out_h,
            in_x,
            in_y,
            in_w,
            in_h,
            rows as i32,
            self.values.len() as i32,
            self.frame,
            self.time_q16,
            self.rate_q16,
            self.scale_q16,
        ];
        signed.iter().map(|&w| w as u32).chain([self.fuel, 0, 0, 0]).collect()
    }
}

impl Kernel {
    /// The workgroups the render is dispatched over for `frame`: an
    /// invocation for each pixel of its output, across and down.
    pub fn groups(&self, frame: &Frame<'_>) -> [u32; 3] {
        let size = self.workgroup_size();
        [
            (frame.out_size[0].max(0) as u32).div_ceil(size[0]),
            (frame.out_size[1].max(0) as u32).div_ceil(size[1]),
            1,
        ]
    }

    /// The buffers the render reads or writes — the ones the device's
    /// layout for it holds, as wgpu derives one from the module —, by
    /// number.
    pub fn bindings(&self) -> Vec<Bound<'_>> {
        let uses = self.info.get_entry_point(self.render_index());
        let mut bindings: Vec<_> = self
            .module
            .global_variables
            .iter()
            .filter(|&(handle, _)| !uses[handle].is_empty())
            .filter_map(|(_, global)| {
                Some(Bound {
                    number: global.binding.as_ref()?.binding,
                    name: global.name.as_deref()?,
                    uniform: global.space == AddressSpace::Uniform,
                    written: written(global.space),
                })
            })
            .collect();
        bindings.sort_by_key(|bound| bound.number);
        bindings
    }
}

/// Whether a run writes a global of `space`'s, binding or not.
pub(crate) fn written(space: AddressSpace) -> bool {
    matches!(space, AddressSpace::Storage { access } if access.contains(StorageAccess::STORE))
}
