//! A frame's last picture on the engine (gpu-export-path ①⑵): a frame the
//! export makes ([`Shown::blank`]) and a picture laid over it at a
//! strength, under a cover where one is given — its ground, the cut's
//! picture cut at the canvas's edge, what is drawn over it, a track's
//! units and a fade. `lay.wgsl` has the law.

use super::{Picture, Pipelines, Read, Shown};
use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::BLEND_WGSL;
use crate::kernels::shared::{Encoded, ISQRT_WGSL, encode, fits, flat, plane, whole, words_buffer};

/// How much of what is laid each pixel of a frame takes: a byte each, four
/// a word, the low byte first — the canvas's edge as a view cuts it, which
/// the app rasters ([`Lay::run`]).
pub struct Cover {
    bytes: wgpu::Buffer,
    width: u32,
    height: u32,
}

impl Cover {
    /// `alpha`, a byte a pixel of `picture` row after row — none, with why,
    /// unless it holds as many.
    pub(crate) fn of(engine: &Engine, alpha: &[u8], picture: Picture) -> Option<Self> {
        picture.check()?;
        let pixels = picture.pixels();
        if alpha.len() as u64 != pixels {
            return fail(format!(
                "a {}x{} cover is {pixels} bytes, not {}",
                picture.width,
                picture.height,
                alpha.len()
            ));
        }
        let mut words = vec![0u32; alpha.len().div_ceil(4)];
        for (at, &byte) in alpha.iter().enumerate() {
            words[at / 4] |= u32::from(byte) << (at % 4 * 8);
        }
        fits(engine, &[words.len() as u64 * 4], std::iter::empty())?;
        Some(Self {
            bytes: words_buffer(engine, "export cover", &words, wgpu::BufferUsages::STORAGE),
            width: picture.width,
            height: picture.height,
        })
    }
}

impl Shown {
    /// A frame of `picture` the export makes, nothing laid on it yet — or
    /// none, with why.
    pub(crate) fn blank(engine: &Engine, picture: Picture) -> Option<Self> {
        picture.check()?;
        let bytes = picture.pixels() * 4;
        fits(engine, &[bytes], std::iter::empty())?;
        Some(Self::rgba(plane(engine, "export frame", bytes), picture))
    }

    /// `rgba`, a picture's premultiplied pixels four bytes each, red first,
    /// row after row — what the app rasters to lay over a frame — or none,
    /// with why, unless it holds `picture`'s.
    pub(crate) fn uploaded(engine: &Engine, rgba: &[u8], picture: Picture) -> Option<Self> {
        picture.check()?;
        let bytes = picture.pixels() * 4;
        if rgba.len() as u64 != bytes {
            return fail(format!(
                "a {}x{} picture is {bytes} bytes, not {}",
                picture.width,
                picture.height,
                rgba.len()
            ));
        }
        fits(engine, &[bytes], std::iter::empty())?;
        let words: Vec<u32> = rgba
            .chunks_exact(4)
            .map(|pixel| u32::from_le_bytes([pixel[0], pixel[1], pixel[2], pixel[3]]))
            .collect();
        let rows = words_buffer(engine, "export picture", &words, wgpu::BufferUsages::STORAGE);
        Some(Self::rgba(rows, picture))
    }

    /// A frame the export made as it lies — its premultiplied RGBA, row
    /// after row with nothing between — and its bytes, to read back: what a
    /// picture of a panel is made of. None, with why, for a frame the
    /// export did not make.
    pub(crate) fn laid_rows(&self) -> Option<(wgpu::Buffer, u64)> {
        if !self.rows.usage().contains(wgpu::BufferUsages::COPY_SRC) || self.stride != self.width {
            return fail("a frame is read back where the export made it".to_owned());
        }
        Some((self.rows.clone(), u64::from(self.width) * u64::from(self.height) * 4))
    }

    fn rgba(rows: wgpu::Buffer, Picture { width, height }: Picture) -> Self {
        Self { rows, stride: width, width, height, bgra: false }
    }
}

/// What is laid over a frame.
#[derive(Clone, Copy)]
pub(crate) enum Source<'a> {
    /// A frame's picture, its top-left at a pixel of the frame laid onto —
    /// past its edges where it lies past them.
    Frame { frame: &'a Shown, x: i32, y: i32 },
    /// One colour everywhere: straight, red the low byte.
    Solid(u32),
}

/// The lay pass.
pub(crate) struct Lay {
    pipelines: Pipelines,
}

impl Lay {
    pub(crate) const fn new() -> Self {
        Self {
            pipelines: Pipelines::new(&[ISQRT_WGSL, BLEND_WGSL, include_str!("lay.wgsl")], "lay_pass"),
        }
    }

    /// Compiles the pass for the frames the export makes and for frames
    /// shown on surfaces laid `bgra` or not, where it is first asked of a
    /// frame: a lay waits for no compile after.
    pub(crate) fn warm(&self, engine: &Engine, bgra: bool) {
        self.pipelines.reading(engine, Read::Shown { bgra: false });
        if bgra {
            self.pipelines.reading(engine, Read::Shown { bgra: true });
        }
    }

    /// Lays `source` over `onto` at `opacity`, each pixel taking of it what
    /// `cover` says where one is given — and only within the pixels
    /// `within`, [left, top, right, bottom), where those are — and submits
    /// the work — none, with why, where `onto` is not laid as the export
    /// lays a frame or `cover` is not its size.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        onto: &Shown,
        source: Source,
        opacity: u8,
        cover: Option<&Cover>,
        within: Option<[i32; 4]>,
    ) -> Option<()> {
        if onto.bgra {
            return fail("a frame is laid onto as the export lays one: RGBA, not BGRA".to_owned());
        }
        if let Some(cover) = cover
            && (cover.width, cover.height) != (onto.width, onto.height)
        {
            return fail(format!(
                "a {}x{} cover is not a {}x{} frame's",
                cover.width, cover.height, onto.width, onto.height
            ));
        }
        let (rows, read, stride, [x0, y0, width, height, sx, sy], solid, colour) = match source {
            Source::Frame { frame, x, y } => (
                Some(&frame.rows),
                Read::Shown { bgra: frame.bgra },
                frame.stride,
                overlap(region(onto, within), (frame.width, frame.height), (x, y)),
                0,
                0,
            ),
            Source::Solid(colour) => (
                None,
                Read::Shown { bgra: false },
                0,
                overlap(region(onto, within), (onto.width, onto.height), (0, 0)),
                1,
                colour,
            ),
        };
        if width == 0 || height == 0 {
            return Some(());
        }
        let groups = (width.div_ceil(64), height);
        fits(engine, &[], [groups].into_iter())?;
        let params = [
            stride,
            onto.stride,
            x0,
            y0,
            width,
            height,
            sx,
            sy,
            u32::from(opacity),
            solid,
            colour,
            u32::from(cover.is_some()),
            0,
            0,
            0,
            0,
        ];
        let params = words_buffer(engine, "export lay params", &params, wgpu::BufferUsages::UNIFORM);
        // A binding the pass reads nothing of where it lays a colour, or
        // takes no cover.
        let nothing = plane(engine, "export lay nothing", 4);
        encode(
            engine,
            &[Encoded {
                pipeline: self.pipelines.reading(engine, read),
                bound: whole(&[
                    (0, &params),
                    (1, rows.unwrap_or(&nothing)),
                    (2, &onto.rows),
                    (3, cover.map_or(&nothing, |cover| &cover.bytes)),
                ]),
                groups: flat(groups),
            }],
        );
        Some(())
    }
}

/// The pixels of `onto` a pass may lay — [left, top, right, bottom) — all
/// of it, cut to `within` where that is given.
fn region(onto: &Shown, within: Option<[i32; 4]>) -> [i64; 4] {
    let [left, top, right, bottom] =
        within.map_or([i64::MIN, i64::MIN, i64::MAX, i64::MAX], |edges| edges.map(i64::from));
    [left.max(0), top.max(0), right.min(i64::from(onto.width)), bottom.min(i64::from(onto.height))]
}

/// Where a picture of `width` x `height`, its top-left at (`x`, `y`),
/// meets `region`: the box's top-left, its size, and the picture's pixel
/// at its top-left — an empty box where they do not meet.
fn overlap([left, top, right, bottom]: [i64; 4], (width, height): (u32, u32), (x, y): (i32, i32)) -> [u32; 6] {
    let span = |at: i32, own: u32, low: i64, high: i64| {
        let at = i64::from(at);
        let start = at.max(low);
        let end = (at + i64::from(own)).min(high);
        if end <= start {
            return (0, 0, 0);
        }
        // Inside u32: the box lies in the frame laid onto, and what is
        // skipped of the picture is under its own size.
        (start as u32, (end - start) as u32, (start - at) as u32)
    };
    let (x0, width, sx) = span(x, width, left, right);
    let (y0, height, sy) = span(y, height, top, bottom);
    [x0, y0, width, height, sx, sy]
}
