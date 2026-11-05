//! The canvas's warps on the GPU (gpu-census 변형 리샘플 · R3;
//! gpu-canonical-store 11-06 07:05): a selection's picture — a box of
//! straight RGBA8, the lift's (cel_pixel/lift.rs) or a stamp's — through R1
//! into a window of the output, each pixel by one map (an affine's or a
//! quad's: the app's `_resampleIntoWindow`) or by the map of the mesh
//! triangle that owns it (R3: `transformStampDabMesh`). warp.wgsl has the
//! pass; R1 is shared's.
//!
//! The window is a new stamp: laying it on a cel is the stamp's path
//! (kernels/dab), not here.

// ⏳Nothing outside the tests runs it until the app's bridge round
// (gpu-canonical-store ⑧).
#![cfg_attr(not(test), allow(dead_code))]

#[cfg(test)]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::mesh::{MeshGrid, MeshOwners, affines};
use crate::kernels::shared::{
    Encoded, RESAMPLE_WGSL, ResampleMap, ResampleMode, WIDE_WGSL, encode, fits, flat, pipeline,
    plane, whole, words_buffer,
};

/// warp.wgsl's workgroup side.
const GROUP: u32 = 8;

/// A picture a warp reads: straight RGBA8 words row after row, `size`
/// across and down.
pub(crate) struct Boxed<'a> {
    pub(crate) pixels: &'a wgpu::Buffer,
    pub(crate) size: (u32, u32),
}

/// The pixels a warp puts: `size` across and down from `at` in the output
/// its maps measure from.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Window {
    pub(crate) at: (i32, i32),
    pub(crate) size: (u32, u32),
}

/// The warp, and the mesh's owners it reads, compiled once.
pub(crate) struct Warp {
    window: wgpu::ComputePipeline,
    owners: MeshOwners,
}

impl Warp {
    pub(crate) fn new(engine: &Engine) -> Self {
        let sources = [WIDE_WGSL, RESAMPLE_WGSL, include_str!("warp.wgsl")];
        Self {
            window: pipeline(engine, &sources, "warp_window"),
            owners: MeshOwners::new(engine),
        }
    }

    /// `window` of `picture` through `map`: every pixel by it, and nothing
    /// where there is none — a map past R1's ranges lands nothing. Submits
    /// the work; the caller waits.
    pub(crate) fn one(
        &self,
        engine: &Engine,
        picture: &Boxed,
        map: Option<&ResampleMap>,
        window: Window,
    ) -> Option<wgpu::Buffer> {
        self.run(engine, picture, &[map.copied()], None, window)
    }

    /// `window` of the canvas from `mesh`'s warp of `picture`, whose top-left
    /// pixel is at `source_at` on the canvas: each pixel by the map of the
    /// triangle that paints it ([`MeshOwners`], [`affines`]), with
    /// `radius_floor` and `mode`, and nothing where none does. Submits the
    /// work; the caller waits.
    pub(crate) fn mesh(
        &self,
        engine: &Engine,
        mesh: &MeshGrid,
        picture: &Boxed,
        source_at: (f64, f64),
        window: Window,
        radius_floor: f64,
        mode: ResampleMode,
    ) -> Option<wgpu::Buffer> {
        let maps = affines(mesh, source_at, radius_floor, mode)?;
        let owners = self.owners.owners(engine, mesh, window.at, window.size)?;
        self.run(engine, picture, &maps, Some(&owners), window)
    }

    /// `window` of `picture`, each pixel by the one of `maps` that `owners`
    /// names for it, or by the first where there are none.
    fn run(
        &self,
        engine: &Engine,
        picture: &Boxed,
        maps: &[Option<ResampleMap>],
        owners: Option<&wgpu::Buffer>,
        Window { at: (left, top), size: (columns, rows) }: Window,
    ) -> Option<wgpu::Buffer> {
        let (width, height) = picture.size;
        let held = u64::from(width) * u64::from(height) * 4;
        if picture.pixels.size() < held {
            return fail(format!("{} bytes hold no {width}x{height} box", picture.pixels.size()));
        }
        if columns == 0 || rows == 0 {
            return fail(format!("a window of {columns}x{rows}"));
        }
        let bytes = u64::from(columns) * u64::from(rows) * 4;
        if let Some(owners) = owners
            && owners.size() < bytes
        {
            return fail(format!("{} bytes of owners for a window of {bytes}", owners.size()));
        }
        let table: Vec<u32> = maps
            .iter()
            .flat_map(|map| {
                let (words, lands) =
                    map.as_ref().map_or(([0; ResampleMap::WORDS], 0), |map| (map.words(), 1));
                words.into_iter().chain([lands])
            })
            .collect();
        let groups = (columns.div_ceil(GROUP), rows.div_ceil(GROUP));
        fits(engine, &[bytes, table.len() as u64 * 4, held], [groups].into_iter())?;
        let warped = plane(engine, "warped", bytes);
        let owned = u32::from(owners.is_some());
        let uniform = [width, height, columns, rows, left as u32, top as u32, owned];
        let uniform = words_buffer(engine, "warp", &uniform, wgpu::BufferUsages::UNIFORM);
        let table = words_buffer(engine, "warp maps", &table, wgpu::BufferUsages::STORAGE);
        // A binding holds something, where every pixel takes the first map.
        let none = plane(engine, "no owners", 4);
        let bound = whole(&[
            (0, &uniform),
            (1, &table),
            (2, owners.unwrap_or(&none)),
            (3, picture.pixels),
            (4, &warped),
        ]);
        encode(engine, &[Encoded { pipeline: &self.window, bound, groups: flat(groups) }]);
        Some(warped)
    }
}
