//! Whether a frame is opaque, so its PDF picture goes without alpha
//! (gpu-export-path ①d) — `opaque.wgsl` has the law.

use super::{Dispatch, Picture, Pipelines, Shown, convert};
use crate::device::Engine;
use crate::kernels::composite::TILE;
use crate::kernels::shared::words_buffer;

/// The opaque pass.
pub(crate) struct Opaque {
    pub(super) pipelines: Pipelines,
}

impl Opaque {
    pub(crate) const fn new() -> Self {
        Self {
            pipelines: Pipelines::new(&[include_str!("opaque.wgsl")], "opaque_pass"),
        }
    }

    /// Asks whether every pixel of the picture in `frame` is opaque, and
    /// submits the work; the caller waits. Returns the buffer of the
    /// answer, one little-endian u32: 255 when every pixel is, less when
    /// one is not.
    pub(crate) fn run(&self, engine: &Engine, frame: &Shown, picture: Picture) -> Option<wgpu::Buffer> {
        picture.check()?;
        frame.holds(picture)?;
        let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
        let answer = words_buffer(engine, "opaque answer", &[255], usage);
        // A workgroup a tile: a row of them is a row of tiles, the picture's
        // rows it covers whole across.
        let (across, tile_rows) = picture.tiles();
        let (width, side) = (u64::from(picture.width), u64::from(TILE));
        let pixels = |rows: std::ops::Range<u32>| {
            let bottom = (u64::from(rows.end) * side).min(u64::from(picture.height));
            u64::from(rows.start) * side * width..bottom * width
        };
        convert(
            engine,
            self.pipelines.of(engine, frame),
            (&frame.rows, &answer),
            Dispatch { rows: tile_rows, unit: 1, across },
            |rows| [frame.words(picture, pixels(rows)), 0..1],
            |first_row, [frame_base, _]| {
                // Inside u32: a word of a frame the shader indexes.
                let frame_base = frame_base as u32;
                vec![frame.stride, picture.width, picture.height, frame_base, first_row, 0, 0, 0]
            },
        )?;
        Some(answer)
    }
}
