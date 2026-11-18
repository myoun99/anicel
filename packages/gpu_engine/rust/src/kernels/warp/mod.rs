//! The canvas's warps on the GPU (gpu-census 변형 리샘플 · R3;
//! gpu-canonical-store 11-06 07:05): a selection's picture — a box of
//! straight RGBA8, the lift's (cel_pixel/lift.rs) or a stamp's — through R1
//! into a window of the output, each pixel by one map (an affine's or a
//! quad's: the app's `_resampleIntoWindow`) or by the map of the mesh
//! triangle that owns it (R3: `transformStampDabMesh`). warp.wgsl has the
//! pass; R1 is shared's.
//!
//! The window is a new stamp: laying it on a cel is the stamp's path
//! (`dab::stamp`'s picture), not here.

// A stamp's landing carries a picture by them (`dab::stamp`'s `carried` and
// `meshed`): one map's for a posed row (gpu-canonical-store ⑪ 2026-11-11)
// and a box's affine or quad, a mesh's for its mesh (float-warp-resamples-
// in-the-c-engine, 2026-11-11).

#[cfg(test)]
mod tests;

use std::ops::Range;

use crate::device::Engine;
use crate::fail;
use crate::kernels::mesh::{MeshGrid, MeshOwners, affines};
use crate::kernels::shared::{
    Encoded, Own, Pages, RESAMPLE_WGSL, ResampleMap, ResampleMode, WIDE_WGSL, bands, buffer_holds,
    encode, fits, flat, pipeline, plane, room, whole, words_bound, words_buffer,
};

/// warp.wgsl's workgroup side.
const GROUP: u32 = 8;

/// The buffers the warp binds besides its picture's pages: its maps, its
/// owners and what it puts, and its uniform.
const OWN: Own = Own { storage: 3, uniform: 1 };

/// A picture a warp reads, and a stamp lays: straight RGBA8 words row
/// after row, `size` across and down.
pub(crate) struct Boxed<'a> {
    pub(crate) pixels: &'a wgpu::Buffer,
    pub(crate) size: (u32, u32),
}

impl Boxed<'_> {
    /// The bytes its box holds.
    pub(crate) fn bytes(&self) -> u64 {
        u64::from(self.size.0) * u64::from(self.size.1) * 4
    }

    /// Fails where its buffer holds less than its box.
    pub(crate) fn checked(&self) -> Option<()> {
        if self.pixels.size() < self.bytes() {
            let (width, height) = self.size;
            return fail(format!("{} bytes hold no {width}x{height} box", self.pixels.size()));
        }
        Some(())
    }
}

/// The pixels a warp puts: `size` across and down from `at` in the output
/// its maps measure from.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Window {
    pub(crate) at: (i32, i32),
    pub(crate) size: (u32, u32),
}

/// The warp, compiled once. A mesh's owners are the mesh's own pass
/// (`kernels::mesh`), which a mesh's warp is handed: a stamp's landing
/// compiles both as the app launches (`StampLanding`).
pub(crate) struct Warp {
    window: wgpu::ComputePipeline,
    pictures: Pages,
}

impl Warp {
    /// Compiled for as many of a picture's pages as one of the device's
    /// largest takes — one where a binding holds a buffer, so a read
    /// chooses among none — or nothing, where the device binds too few
    /// storage buffers a stage for one.
    pub(crate) fn new(engine: &Engine) -> Option<Self> {
        let largest = engine.device().limits().max_buffer_size;
        let most = largest.div_ceil(page_bytes(engine)).max(1);
        let most = usize::try_from(most).unwrap_or(usize::MAX);
        let pictures = Pages::reading(engine, OWN, OWN.storage + OWN.uniform, most)?.named("picture");
        let read = pictures.source();
        let sources = [WIDE_WGSL, RESAMPLE_WGSL, &read, include_str!("warp.wgsl")];
        Some(Self { window: pipeline(engine, &sources, "warp_window"), pictures })
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
    /// triangle that paints it (`owners`', [`affines`]), with `radius_floor`
    /// and `mode`, and nothing where none does. Submits the work; the caller
    /// waits.
    pub(crate) fn mesh(
        &self,
        engine: &Engine,
        (owners, mesh): (&MeshOwners, &MeshGrid),
        picture: &Boxed,
        source_at: (f64, f64),
        window: Window,
        radius_floor: f64,
        mode: ResampleMode,
    ) -> Option<wgpu::Buffer> {
        let maps = affines(mesh, source_at, radius_floor, mode)?;
        let owners = owners.owners(engine, mesh, window.at, window.size)?;
        self.run(engine, picture, &maps, Some(&owners), window)
    }

    /// `window` of `picture`, each pixel by the one of `maps` that `owners`
    /// names for it, or by the first where there are none.
    ///
    /// 🚨A PASS BINDS THE ROWS OF THE WINDOW IT PUTS AND THE PICTURE ON ITS
    /// PAGES, NOT EITHER WHOLE (board
    /// conversions-bind-a-frame-past-the-device-limit, 2026-11-17): both
    /// were bound whole and refused past a binding — 128 MiB on lavapipe,
    /// less than a selection of the user's 7751×4396 canvas. The window's
    /// rows go in bands as the lay's and the export's do ([`bands`]); the
    /// picture's cannot, as a map reads any of them for a row of the window.
    fn run(
        &self,
        engine: &Engine,
        picture: &Boxed,
        maps: &[Option<ResampleMap>],
        owners: Option<&wgpu::Buffer>,
        Window { at: (left, top), size: (columns, rows) }: Window,
    ) -> Option<wgpu::Buffer> {
        picture.checked()?;
        let (width, height) = picture.size;
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
        let page = page_bytes(engine);
        let pages = self.pictures.cut(picture.pixels, picture.bytes(), page)?;
        let step = u64::from(engine.device().limits().min_storage_buffer_offset_alignment);
        // The words a band of the window's rows lies on, in what it puts
        // and in its owners alike.
        let words = |band: Range<u32>| {
            u64::from(band.start) * u64::from(columns)..u64::from(band.end) * u64::from(columns)
        };
        let bands = bands(0..rows, GROUP, (room(engine), step), |band| vec![words(band)])?;
        let groups = |band: &Range<u32>| (columns.div_ceil(GROUP), (band.end - band.start).div_ceil(GROUP));
        fits(engine, &[table.len() as u64 * 4], bands.iter().map(groups))?;
        buffer_holds(engine, bytes)?;
        let warped = plane(engine, "warped", bytes);
        let table = words_buffer(engine, "warp maps", &table, wgpu::BufferUsages::STORAGE);
        // A binding holds something, where every pixel takes the first map.
        let none = plane(engine, "no owners", 4);
        let owned = u32::from(owners.is_some());
        let mut uniforms = Vec::new();
        let mut bound = Vec::new();
        for band in &bands {
            let (warped_given, warped_base) = words_bound(&warped, words(band.clone()), step);
            let (owners_given, owners_base) = match owners {
                Some(owners) => words_bound(owners, words(band.clone()), step),
                None => (none.as_entire_binding(), 0),
            };
            let uniform = [
                width,
                height,
                columns,
                band.end - band.start,
                left as u32,
                top as u32,
                owned,
                (page / 4) as u32,
                band.start,
                owners_base as u32,
                warped_base as u32,
                0,
            ];
            uniforms.push(words_buffer(engine, "warp", &uniform, wgpu::BufferUsages::UNIFORM));
            bound.push([(2, owners_given), (3, warped_given)]);
        }
        let passes: Vec<Encoded> = uniforms
            .iter()
            .zip(bound)
            .zip(&bands)
            .map(|((uniform, given), band)| {
                let mut entries = whole(&[(0, uniform), (1, &table)]);
                entries.extend(given.map(|(binding, resource)| wgpu::BindGroupEntry { binding, resource }));
                entries.extend(pages.iter().cloned());
                Encoded { pipeline: &self.window, bound: entries, groups: flat(groups(band)) }
            })
            .collect();
        encode(engine, &passes);
        Some(warped)
    }
}

/// The bytes of a picture one of its pages holds: as many as a binding
/// does, begun on a multiple of the device's offset step — and no more
/// than 4 GiB, as warp.wgsl counts a page's words in a u32 (a picture's
/// words are counted so too).
fn page_bytes(engine: &Engine) -> u64 {
    let step = u64::from(engine.device().limits().min_storage_buffer_offset_alignment);
    (room(engine).min(1 << 32) / step * step).max(step)
}
