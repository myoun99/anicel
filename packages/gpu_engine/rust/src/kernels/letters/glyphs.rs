//! The letters' covers: each pass's shapes — a run's glyphs where the
//! app's layout set them, a box, a line — as one path, rastered by zeno to
//! a byte a pixel of the grid (gpu-int-spec-word-bake 「규격 고침」 B–E).
//!
//! Where a letter stands is the app's to say: Flutter lays the text out
//! and hands each cluster's text and origin over, since it never says which
//! glyphs it drew (`dart:ui` `GlyphInfo`). Which face draws a letter and
//! which glyphs it takes are the engine's, by the app's law for bundled
//! faces (conte_pdf_writer.dart `_runsFor`) and HarfBuzz's own shaping.
//!
//! The path is built in the layout's space and laid on the grid by zeno's
//! transform, which strokes first and transforms after — an outline is as
//! wide as the style says before a placement scales it, as Skia strokes in
//! the canvas's local space.

use harfrust::{Buffer, Font, ShapeOptions, ShaperFont, shape};
use read_fonts::model::glyph::outline::{DrawMemory, DrawOptions, PathSink};
use read_fonts::types::GlyphId;
use zeno::{Command, Fill, Join, Mask, Stroke, Transform, Vector};

use super::Cover;

/// How far a lean slants a letter: its x moves by a quarter of its height
/// above the baseline — the lean Flutter's engine makes for a face with
/// none (canvas_letter_style.dart 「A LEAN IS THE ENGINE'S OWN」: the top
/// row of the ink 13 px right of the upright's at 64, on the device
/// 2026-10-18). 🔬A quarter here moves it 12–13 px at 64 in the three
/// bundled faces, Latin, kana and Hangul (measured 2026-11-07).
const LEAN: f64 = 0.25;

/// One family's two weights: what a run that is not bold (400) and one
/// that is (700) are set in (`canvasLetterTextStyle`).
pub(crate) struct Family {
    regular: Font,
    bold: Font,
}

impl Family {
    /// A family of two files, its regular and its bold (BIZ UDPGothic,
    /// 나눔고딕). `None` if either holds no face.
    pub(crate) fn of_two(regular: Vec<u8>, bold: Vec<u8>) -> Option<Self> {
        Some(Self {
            regular: Font::new(regular, 0)?,
            bold: Font::new(bold, 0)?,
        })
    }

    /// A family of one variable file whose `wght` axis sets both weights,
    /// as Flutter sets it (Noto Sans SC — app_theme.dart: 「variable, its
    /// weight set by the style's」).
    pub(crate) fn of_one_variable(bytes: Vec<u8>) -> Option<Self> {
        let font = Font::new(bytes, 0)?;
        let at = |weight: f32| font.instance_builder().variations([("wght", weight)]).build();
        Some(Self {
            regular: at(400.0),
            bold: at(700.0),
        })
    }

    fn at(&self, bold: bool) -> &Font {
        if bold { &self.bold } else { &self.regular }
    }
}

/// The families letters are set in, in the order a letter goes down them:
/// the first that has it draws it, and one none has is the first family's
/// empty box (`_runsFor`; 🗣️engine-canvas-letters-Q2, 유저 2026-11-07:
/// Noto Sans SC after the two).
pub(crate) struct Faces {
    families: Vec<Family>,
}

impl Faces {
    pub(crate) fn new(families: Vec<Family>) -> Option<Self> {
        if families.is_empty() {
            return crate::fail("letters are set in a face — none was given");
        }
        Some(Self { families })
    }

    /// The family that draws `letter`: the first whose face has it, or the
    /// first of all.
    fn of(&self, letter: char, bold: bool) -> usize {
        self.families
            .iter()
            .position(|family| family.at(bold).charmap().map_unicode(letter).is_some())
            .unwrap_or(0)
    }
}

/// A run of letters in one style, as the app's layout set it.
pub(crate) struct Run {
    /// The letters' size, 1/64 px of the layout.
    pub(crate) size: i32,
    pub(crate) bold: bool,
    pub(crate) italic: bool,
    pub(crate) clusters: Vec<Cluster>,
}

/// A grapheme cluster: its text, and where the layout put it — its box's
/// left and its line's baseline, 1/64 px.
pub(crate) struct Cluster {
    pub(crate) text: String,
    pub(crate) origin: [i32; 2],
}

/// What one pass paints.
pub(crate) enum Shape {
    Letters(Run),
    /// A box or a line: [left, top, right, bottom), 1/64 px of the layout.
    Rect([i32; 4]),
}

/// How a pass paints its shapes.
#[derive(Clone, Copy)]
pub(crate) enum Paint {
    Fill,
    /// An outline `width` wide, 1/64 px of the layout, joined round
    /// (`canvasLetterOutlinePaint`).
    Stroke { width: i32 },
}

/// The layout's space to the grid's: x' = a·x + c·y + e, y' = b·x + d·y + f
/// — a placement times where the letters stand.
#[derive(Clone, Copy)]
pub(crate) struct Affine {
    pub(crate) a: f32,
    pub(crate) b: f32,
    pub(crate) c: f32,
    pub(crate) d: f32,
    pub(crate) e: f32,
    pub(crate) f: f32,
}

/// `shapes` painted by `paint`, laid on the grid by `to_grid`: the cover,
/// or `None` where they reach no pixel.
pub(crate) fn covered(faces: &Faces, shapes: &[Shape], paint: Paint, to_grid: Affine) -> Option<Cover> {
    let mut path = Vec::new();
    for shape in shapes {
        match shape {
            Shape::Letters(run) => letters(faces, run, &mut path),
            Shape::Rect(rect) => boxed(rect, &mut path),
        }
    }
    let mut mask = Mask::new(&path[..]);
    let transform = Transform::new(to_grid.a, to_grid.b, to_grid.c, to_grid.d, to_grid.e, to_grid.f);
    mask.transform(Some(transform));
    match paint {
        Paint::Fill => {
            mask.style(Fill::NonZero);
        }
        Paint::Stroke { width } => {
            let mut stroke = Stroke::new(width as f32 / 64.0);
            stroke.join(Join::Round);
            mask.style(stroke);
        }
    }
    let (bytes, at) = mask.render();
    if at.width == 0 || at.height == 0 {
        return None;
    }
    Some(Cover {
        at: [at.left, at.top, at.left + at.width as i32, at.top + at.height as i32],
        bytes,
    })
}

/// `rect` as a closed path, wound as the bundled faces' outer contours land
/// in the layout: zeno reads a part cover one byte under one way round
/// (raster.rs `coverage`: `!coverage`, so half is 127, the other way 128),
/// and the hard cut is at 128 — so a box's edge is cut as a letter's is.
pub(super) fn boxed(&[left, top, right, bottom]: &[i32; 4], path: &mut Vec<Command>) {
    let at = |x: i32, y: i32| Vector::new(x as f32 / 64.0, y as f32 / 64.0);
    path.extend([
        Command::MoveTo(at(left, top)),
        Command::LineTo(at(right, top)),
        Command::LineTo(at(right, bottom)),
        Command::LineTo(at(left, bottom)),
        Command::Close,
    ]);
}

/// `run`'s glyphs, each cluster from its origin: its letters cut into runs
/// of the family that draws each, each shaped and set one after another.
pub(super) fn letters(faces: &Faces, run: &Run, path: &mut Vec<Command>) {
    let size = f64::from(run.size) / 64.0;
    for cluster in &run.clusters {
        let mut pen = f64::from(cluster.origin[0]) / 64.0;
        let baseline = f64::from(cluster.origin[1]) / 64.0;
        for (family, text) in by_family(faces, &cluster.text, run.bold) {
            let font = faces.families[family].at(run.bold);
            let scale = size / f64::from(font.units_per_em());
            let mut buffer = Buffer::new();
            buffer.push_str(&text);
            buffer.guess_segment_properties();
            // harfrust refuses only a misuse (shape.rs: a buffer already
            // shaped, no direction, a plan of another), and a fresh buffer
            // whose direction was guessed is none — the guess falls back
            // to left to right (buffer.rs `guess_segment_properties`).
            shape(&ShaperFont::new(font), &mut buffer, ShapeOptions::new())
                .expect("a fresh buffer, its direction guessed, shapes");
            for (glyph, position) in buffer.glyph_infos().iter().zip(buffer.glyph_positions()) {
                let place = Place {
                    x: pen + f64::from(position.x_offset) * scale,
                    y: baseline - f64::from(position.y_offset) * scale,
                    scale,
                    lean: run.italic,
                };
                if let Some(outline) = font.outline_glyphs().get(GlyphId::new(glyph.glyph_id)) {
                    let mut sink = Sink { place, path };
                    let _ = outline.draw(&DrawOptions::default(), DrawMemory::Scratch, &mut sink);
                }
                pen += f64::from(position.x_advance) * scale;
            }
        }
    }
}

/// `text` cut where the family that draws it changes — `_runsFor`.
pub(super) fn by_family(faces: &Faces, text: &str, bold: bool) -> Vec<(usize, String)> {
    let mut runs: Vec<(usize, String)> = Vec::new();
    for letter in text.chars() {
        let family = faces.of(letter, bold);
        match runs.last_mut() {
            Some((last, run)) if *last == family => run.push(letter),
            _ => runs.push((family, letter.to_string())),
        }
    }
    runs
}

/// Where a glyph's font units land in the layout: from its origin, y up
/// in the font and down in the layout, leaning if the run leans.
#[derive(Clone, Copy)]
struct Place {
    x: f64,
    y: f64,
    scale: f64,
    lean: bool,
}

impl Place {
    fn at(&self, x: f32, y: f32) -> Vector {
        let up = f64::from(y) * self.scale;
        let lean = if self.lean { up * LEAN } else { 0.0 };
        Vector::new(
            (self.x + f64::from(x) * self.scale + lean) as f32,
            (self.y - up) as f32,
        )
    }
}

struct Sink<'a> {
    place: Place,
    path: &'a mut Vec<Command>,
}

impl PathSink for Sink<'_> {
    fn move_to(&mut self, x: f32, y: f32) {
        self.path.push(Command::MoveTo(self.place.at(x, y)));
    }

    fn line_to(&mut self, x: f32, y: f32) {
        self.path.push(Command::LineTo(self.place.at(x, y)));
    }

    fn quad_to(&mut self, cx0: f32, cy0: f32, x: f32, y: f32) {
        self.path.push(Command::QuadTo(self.place.at(cx0, cy0), self.place.at(x, y)));
    }

    fn curve_to(&mut self, cx0: f32, cy0: f32, cx1: f32, cy1: f32, x: f32, y: f32) {
        let (c0, c1, to) = (self.place.at(cx0, cy0), self.place.at(cx1, cy1), self.place.at(x, y));
        self.path.push(Command::CurveTo(c0, c1, to));
    }

    fn close(&mut self) {
        self.path.push(Command::Close);
    }
}
