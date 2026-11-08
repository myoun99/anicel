//! The letters' covers: each pass's shapes — a run's glyphs where the
//! app's layout set them, a box, a line — as one path, rastered by zeno to
//! a byte a pixel of the grid (gpu-int-spec-word-bake 「규격 고침」 B–E).
//!
//! Where a letter stands is the app's to say: Flutter lays the text out
//! and hands each cluster's text and origin over, since it never says which
//! glyphs it drew (`dart:ui` `GlyphInfo`). Which face draws a letter and
//! which glyphs it takes are the engine's, by the app's law for bundled
//! faces (conte_pdf_writer.dart `_runsFor`) and HarfBuzz's own shaping —
//! and which of a family's files, and what of it is faked, Flutter's
//! engine's law for the faces handed to it ([`Family::of_files`]).
//!
//! Each shape is inked in its own space — a column's cell, a line drawn
//! wider ([`Placed`]) — and laid into the layout's, so an outline is as
//! wide as the style says before anything scales it, as Skia strokes in
//! the canvas's local space; the path is laid on the grid by zeno's
//! transform.

use std::sync::{Arc, Mutex, PoisonError};

use harfrust::{Buffer, Font, ShapeOptions, ShaperFont, shape};
use read_fonts::model::attribute::{Attributes, Style, Width};
use read_fonts::model::glyph::outline::{DrawMemory, DrawOptions, PathSink};
use read_fonts::types::{GlyphId, Tag};
use zeno::{Command, Fill, Join, Mask, Stroke, Transform, Vector, apply};

use super::Cover;

/// How far a lean slants a letter: its x moves by a quarter of its height
/// above the baseline — the lean Flutter's engine makes for a face with
/// none (canvas_letter_style.dart 「A LEAN IS THE ENGINE'S OWN」: the top
/// row of the ink 13 px right of the upright's at 64, on the device
/// 2026-10-18). 🔬A quarter here moves it 12–13 px at 64 in the three
/// bundled faces, Latin, kana and Hangul (measured 2026-11-07).
const LEAN: f64 = 0.25;

/// How much wider a letter whose face is not as bold as the run asks is
/// drawn: an outline that wide round it — a 24th of the size at 9 px and
/// under, a 32nd at 36 px and over, and along the line between them in
/// between (Skia `SkTextFormatParams.h` `kStdFakeBoldInterp…`, the width
/// `SkScalerContextRec::useStrokeForFakeBold` strokes and fills a filled
/// letter with, and adds to a stroked one's).
pub(super) fn bolder_by(size: f64) -> f64 {
    let along = ((size - 9.0) / 27.0).clamp(0.0, 1.0);
    size * (1.0 / 24.0 + (1.0 / 32.0 - 1.0 / 24.0) * along)
}

const WGHT: Tag = Tag::new(b"wght");

/// One file of a family: its first face, and what the file says it is —
/// how wide, how it slants, how heavy — as the OS/2 table says it
/// (read-fonts' `Attributes`), which is what Flutter's engine reads of a
/// face handed to it.
pub(super) struct Face {
    pub(super) font: Font,
    /// `usWidthClass`, 1 (ultra-condensed) to 9 (ultra-expanded).
    pub(super) width: i32,
    /// Upright 0, italic 1, oblique 2 — Skia's `SkFontStyle::Slant`.
    pub(super) slant: usize,
    pub(super) weight: i32,
}

impl Face {
    fn of(bytes: Vec<u8>) -> Option<Self> {
        let font = Font::new(bytes, 0)?;
        let Attributes { width, style, weight } = font.default_attributes();
        Some(Self {
            width: width_class(width),
            slant: match style {
                Style::Normal => 0,
                Style::Italic => 1,
                Style::Oblique(_) => 2,
            },
            weight: weight.value().round() as i32,
            font,
        })
    }

    /// How well the face answers a run asking for `weight` and `slant`, at
    /// the normal width — Skia's `SkFontStyleSet::matchStyleCSS3`, which
    /// Flutter matches the faces handed to it by
    /// (`TypefaceFontStyleSet::matchStyle`): the width first, then the
    /// slant, then the weight, each shifted past the next (read from
    /// google/skia `src/core/SkFontMgr.cpp`, 2026-11-08).
    ///
    /// ⚠️A weight's score runs to 1000 and a slant's step is 256, so the
    /// weight can outrank the slant: asked for an italic 400, an upright 400
    /// beats an oblique 1000. Kept, as the engine whose letters these are
    /// does it.
    pub(super) fn score(&self, weight: i32, slant: usize) -> i32 {
        const NORMAL: i32 = 5;
        // Over the normal width, the narrower the nearer.
        let width = if self.width <= NORMAL {
            10 - NORMAL + self.width
        } else {
            10 - self.width
        };
        // Asked for, rows; the face's, columns: upright, italic, oblique.
        const SLANT: [[i32; 3]; 3] = [[3, 1, 2], [1, 3, 2], [1, 2, 3]];
        let face = self.weight;
        let weight = match weight {
            _ if face == weight => 1000,
            // Under 400: lighter, the nearest first, then heavier.
            ..400 if face <= weight => 1000 - weight + face,
            ..400 => 1000 - face,
            // 400 to 500: heavier up to 500, then lighter, then heavier still.
            ..=500 if (weight..=500).contains(&face) => 1000 + weight - face,
            ..=500 if face <= weight => 500 + face,
            ..=500 => 1000 - face,
            // Past 500: heavier, the nearest first, then lighter.
            _ if face > weight => 1000 + weight - face,
            _ => face,
        };
        (((width << 8) + SLANT[slant][self.slant]) << 8) + weight
    }
}

/// The `usWidthClass` a width is read from (read-fonts `from_width_class`).
fn width_class(width: Width) -> i32 {
    [0.5, 0.625, 0.75, 0.875, 1.0, 1.125, 1.25, 1.5]
        .iter()
        .position(|&ratio| width.ratio() <= ratio)
        .map_or(9, |at| at as i32 + 1)
}

/// What a run is set in: its family's face for the weight and slant it
/// asks, and what of those the engine fakes. A clone shares its font.
#[derive(Clone)]
pub(super) struct Styled {
    /// The face's font, at the weight the run asks where the face varies
    /// by weight — Flutter sets its `wght` to the style's weight unasked
    /// (`ParagraphBuilderSkia::TxtToSkia`).
    pub(super) font: Font,
    /// Whether its letters are drawn bolder ([`bolder_by`]): the run asks
    /// for 600 or more, and 200 more than the face is — Skia's
    /// `OneLineShaper`, `fakeMissingFontStyles` being on.
    pub(super) bolder: bool,
    /// Whether its letters lean ([`LEAN`]): the run asks for italic and
    /// the face is not.
    pub(super) lean: bool,
}

/// A family's faces, as a run of each weight and slant is set in them.
pub(crate) struct Family {
    faces: Vec<Face>,
    /// Each weight and slant a run has asked for, and what it is set in —
    /// made the first time one asks (브러시/렌더링 11-08 17:07: a weight is
    /// any of `FontWeight`'s 1 to 1000, so there are too many to make
    /// first).
    styles: Mutex<Vec<((u16, bool), Styled)>>,
}

/// The weights a run may ask for: `FontWeight`'s, 1 to 1000
/// (dart:ui text.dart).
pub(crate) const WEIGHTS: std::ops::RangeInclusive<u16> = 1..=1000;

impl Family {
    /// The family of `files` — the app's own (BIZ UDPGothic's regular and
    /// bold, Noto Sans SC's one variable file) and a face a person brought
    /// alike: each file's first face, in the order the engine was handed
    /// them, which breaks a tie. A file that holds no face is passed over;
    /// `None` if none does.
    pub(crate) fn of_files(files: Vec<Vec<u8>>) -> Option<Self> {
        Self::of_faces(files.into_iter().filter_map(Face::of).collect())
    }

    pub(super) fn of_faces(faces: Vec<Face>) -> Option<Self> {
        if faces.is_empty() {
            return None;
        }
        Some(Self {
            faces,
            styles: Mutex::new(Vec::new()),
        })
    }

    /// What a run of `weight` — one of [`WEIGHTS`] — and `italic` is set
    /// in.
    pub(super) fn at(&self, weight: u16, italic: bool) -> Styled {
        let mut styles = self.styles.lock().unwrap_or_else(PoisonError::into_inner);
        if let Some((_, styled)) = styles.iter().find(|(asked, _)| *asked == (weight, italic)) {
            return styled.clone();
        }
        let styled = self.styled(i32::from(weight), italic);
        styles.push(((weight, italic), styled.clone()));
        styled
    }

    fn styled(&self, weight: i32, italic: bool) -> Styled {
        let slant = usize::from(italic);
        // The last of the best in reverse: the first of them in order.
        let face = self
            .faces
            .iter()
            .rev()
            .max_by_key(|face| face.score(weight, slant))
            .expect("a family holds a face");
        // How heavy the face is as it is set: a varying one at the weight
        // asked, as far as its axis reaches.
        let at = [(WGHT, weight as f32)];
        let (font, set) = match face.font.axes().get_by_tag(WGHT) {
            Some(_) => (
                face.font.instance_builder().variations(at).build(),
                Attributes::from_variations(&face.font, at).weight.value().round() as i32,
            ),
            None => (face.font.clone(), face.weight),
        };
        Styled {
            font,
            bolder: weight >= 600 && weight - set >= 200,
            lean: italic && face.slant != 1,
        }
    }
}

/// The families letters are set in, in the order a letter goes down them:
/// the first that has it draws it, and one none has is the first family's
/// empty box (`_runsFor`; 🗣️engine-canvas-letters-Q2, 유저 2026-11-07:
/// Noto Sans SC after the two).
pub(crate) struct Faces {
    families: Vec<Arc<Family>>,
}

impl Faces {
    pub(crate) fn new(families: Vec<Family>) -> Option<Self> {
        Self::of_shared(families.into_iter().map(Arc::new).collect())
    }

    fn of_shared(families: Vec<Arc<Family>>) -> Option<Self> {
        if families.is_empty() {
            return crate::fail("letters are set in a face — none was given");
        }
        Some(Self { families })
    }

    /// These families in the order `order` names them, each by where it
    /// stands in this one — the UI's order, which a Chinese UI begins with
    /// Noto Sans SC (`fallbackFor`) — sharing their files and what each has
    /// set: ⚠️the app's are 31 MB, read once.
    pub(crate) fn ordered(&self, order: &[u32]) -> Option<Self> {
        let mut families = Vec::with_capacity(order.len());
        for &at in order {
            let Some(family) = self.families.get(at as usize) else {
                return crate::fail(format!(
                    "an order of faces names family {at} — there are {}",
                    self.families.len()
                ));
            };
            families.push(Arc::clone(family));
        }
        Self::of_shared(families)
    }

    /// The family that draws `letter` in a run of that weight and slant:
    /// the first whose face for it has it, or the first of all.
    fn of(&self, letter: char, weight: u16, italic: bool) -> usize {
        self.families
            .iter()
            .position(|family| family.at(weight, italic).font.charmap().map_unicode(letter).is_some())
            .unwrap_or(0)
    }
}

/// A run of letters in one style, as the app's layout set it.
pub(crate) struct Run {
    /// The letters' size, 1/64 px of the layout.
    pub(crate) size: i32,
    /// One of [`WEIGHTS`]: Flutter matches a face by it and sets a varying
    /// one's `wght` to it.
    pub(crate) weight: u16,
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

/// A shape, and where its own space stands in the layout's — what the
/// app's canvas was transformed by round the painter that drew it: a
/// column's cell turned, moved and fitted into its place
/// (`paintVerticalTextCell`), letters drawn wider than they were set
/// (`CelTextContent.letterWidth`). Which cell turns and how is the app's
/// one table's (`vertical_writing.dart`) — the engine is handed where the
/// cell landed, and keeps no copy of why.
pub(crate) struct Placed {
    pub(crate) at: Affine,
    pub(crate) shape: Shape,
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

impl Affine {
    fn transform(self) -> Transform {
        Transform::new(self.a, self.b, self.c, self.d, self.e, self.f)
    }
}

/// `shapes` painted by `paint`, laid on the grid by `to_grid`: the cover,
/// or `None` where they reach no pixel.
pub(crate) fn covered(faces: &Faces, shapes: &[Placed], paint: Paint, to_grid: Affine) -> Option<Cover> {
    let mut path = Vec::new();
    for placed in shapes {
        match &placed.shape {
            Shape::Letters(run) => letters(faces, run, paint, placed.at, &mut path),
            Shape::Rect(rect) => {
                let mut outline = Vec::new();
                boxed(rect, &mut outline);
                laid(&outline, Inked::of(paint, 0.0), placed.at, &mut path);
            }
        }
    }
    let mut mask = Mask::new(&path[..]);
    mask.transform(Some(to_grid.transform()));
    mask.style(Fill::NonZero);
    let (bytes, at) = mask.render();
    if at.width == 0 || at.height == 0 {
        return None;
    }
    Some(Cover {
        at: [at.left, at.top, at.left + at.width as i32, at.top + at.height as i32],
        bytes,
    })
}


/// How a piece is inked.
#[derive(Clone, Copy)]
enum Inked {
    Filled,
    /// Filled, grown this many px on every side ([`grown`]).
    Grown(f64),
    /// Outlined this wide, joined so.
    Outlined(f32, Join),
}

impl Inked {
    /// What `paint` inks of a piece drawn `bolder` px bolder ([`bolder_by`]):
    /// a filled one is filled and outlined that wide — grown by half of it
    /// — and a stroked one's outline is that much wider, joined as it was.
    fn of(paint: Paint, bolder: f64) -> Self {
        match paint {
            Paint::Fill if bolder > 0.0 => Self::Grown(bolder / 2.0),
            Paint::Fill => Self::Filled,
            Paint::Stroke { width } => Self::Outlined((f64::from(width) / 64.0 + bolder) as f32, Join::Round),
        }
    }
}

/// `outline` — a letter's contours, a box — inked in its own space and
/// laid into the layout's by `at`, wound as a box is.
fn laid(outline: &[Command], inked: Inked, at: Affine, path: &mut Vec<Command>) {
    let at = Some(at.transform());
    let mut piece = Vec::new();
    match inked {
        Inked::Filled => {
            apply(outline, Fill::NonZero, at, &mut piece);
        }
        Inked::Grown(by) => {
            apply(&grown(outline, by)[..], Fill::NonZero, at, &mut piece);
        }
        Inked::Outlined(width, join) => {
            let mut stroke = Stroke::new(width);
            stroke.join(join);
            apply(outline, stroke, at, &mut piece);
        }
    }
    wound_as_a_box(&piece, path);
}

/// How far past `by` a mitre may reach before its corner is cut flat: 4
/// times, a default paint's (Skia `SkPaintDefaults_MiterLimit`) — the
/// join a letter's faked bolder outline takes (`useStrokeForFakeBold`).
const MITRE_LIMIT: f64 = 4.0;

/// `outline` grown `by` px on every side: what Skia's stroke-and-fill of a
/// letter covers with an outline `2·by` wide, mitred — each contour's
/// corners moved out along its edges' normals to where the moved edges
/// meet, a corner whose mitre would reach past [`MITRE_LIMIT`] cut flat
/// (one turning in as sharply left where it is). Curves are cut into
/// lines first, none a 128th of a px off them.
///
/// 🔬ONE REGION, NEVER A FILL UNDER AN OUTLINE: zeno sums the covers of a
/// pixel's pieces and clamps only the sum, so the outline's inner half
/// over the fill counts those pixels twice — measured on the device
/// (Windows GLES, 2026-11-07): BIZ UDPGothic's regular alone at 9 px, made
/// bold, the app's letters carried 1.50 times the ink of the upright ones
/// and the fill-and-outline 1.92.
pub(super) fn grown(outline: &[Command], by: f64) -> Vec<Command> {
    // Out is away from the fill: to the left of a contour wound as a box
    // is, and to the right of one wound the other way.
    let out = if twice_the_area(outline) < 0.0 { -by } else { by };
    let mut path = Vec::new();
    for contour in outline.split_inclusive(|command| matches!(command, Command::Close)) {
        let corners = flattened(contour);
        let count = corners.len();
        if count < 3 {
            continue;
        }
        // Each edge's normal, out, `by` long.
        let normals: Vec<(f64, f64)> = (0..count)
            .map(|edge| {
                let ((x0, y0), (x1, y1)) = (corners[edge], corners[(edge + 1) % count]);
                let length = (x1 - x0).hypot(y1 - y0);
                ((y1 - y0) / length * out, (x0 - x1) / length * out)
            })
            .collect();
        for (corner, &(x, y)) in corners.iter().enumerate() {
            let (before, after) = (normals[(corner + count - 1) % count], normals[corner]);
            let dot = (before.0 * after.0 + before.1 * after.1) / (by * by);
            let turns_out = (before.0 * after.1 - before.1 * after.0) * out > 0.0;
            let sin_half = ((1.0 + dot) / 2.0).max(0.0).sqrt();
            let mut to = |(dx, dy): (f64, f64)| {
                let at = Vector::new((x + dx) as f32, (y + dy) as f32);
                path.push(if path.last().is_none_or(|last| matches!(last, Command::Close)) {
                    Command::MoveTo(at)
                } else {
                    Command::LineTo(at)
                });
            };
            if sin_half >= 1.0 / MITRE_LIMIT {
                let reach = 1.0 / (1.0 + dot);
                to(((before.0 + after.0) * reach, (before.1 + after.1) * reach));
            } else if turns_out {
                to(before);
                to(after);
            } else {
                // A corner turning in as sharply: the moved edges would meet
                // far past it, or cross where they are too short to — it
                // stays where it was, a notch filled a little less.
                to((0.0, 0.0));
            }
        }
        path.push(Command::Close);
    }
    path
}

/// `contour`'s corners, its curves cut into lines none a 128th of a px off
/// them, without a corner repeated.
fn flattened(contour: &[Command]) -> Vec<(f64, f64)> {
    const OFF: f64 = 1.0 / 128.0;
    // Nearer than this, two corners are one: a contour closed a rounding
    // short of where it began does not turn back on itself.
    const SAME: f64 = 1e-4;
    let xy = |point: Vector| (f64::from(point.x), f64::from(point.y));
    let mut corners: Vec<(f64, f64)> = Vec::new();
    let mut add = |corner: (f64, f64)| {
        if corners.last().is_none_or(|&(x, y)| (x - corner.0).hypot(y - corner.1) > SAME) {
            corners.push(corner);
        }
    };
    let mut last = (0.0, 0.0);
    for command in contour {
        match *command {
            Command::MoveTo(to) | Command::LineTo(to) => {
                last = xy(to);
                add(last);
            }
            Command::QuadTo(control, to) => {
                let (p0, c, p1) = (last, xy(control), xy(to));
                // A quadratic is off its chord by a quarter of its bend over the steps squared.
                let bend = (p0.0 - 2.0 * c.0 + p1.0).hypot(p0.1 - 2.0 * c.1 + p1.1);
                let steps = (bend / 4.0 / OFF).sqrt().ceil().max(1.0) as usize;
                for step in 1..=steps {
                    let t = step as f64 / steps as f64;
                    let (a, b, d) = ((1.0 - t) * (1.0 - t), 2.0 * t * (1.0 - t), t * t);
                    add((a * p0.0 + b * c.0 + d * p1.0, a * p0.1 + b * c.1 + d * p1.1));
                }
                last = p1;
            }
            Command::CurveTo(first, second, to) => {
                let (p0, c0, c1, p1) = (last, xy(first), xy(second), xy(to));
                // A cubic, by three quarters of its larger bend.
                let bend = (p0.0 - 2.0 * c0.0 + c1.0)
                    .hypot(p0.1 - 2.0 * c0.1 + c1.1)
                    .max((c0.0 - 2.0 * c1.0 + p1.0).hypot(c0.1 - 2.0 * c1.1 + p1.1));
                let steps = (0.75 * bend / OFF).sqrt().ceil().max(1.0) as usize;
                for step in 1..=steps {
                    let t = step as f64 / steps as f64;
                    let u = 1.0 - t;
                    let (a, b, c, d) = (u * u * u, 3.0 * u * u * t, 3.0 * u * t * t, t * t * t);
                    add((
                        a * p0.0 + b * c0.0 + c * c1.0 + d * p1.0,
                        a * p0.1 + b * c0.1 + c * c1.1 + d * p1.1,
                    ));
                }
                last = p1;
            }
            Command::Close => {}
        }
    }
    if corners.len() > 1 && corners.first().zip(corners.last()).is_some_and(|(a, b)| (a.0 - b.0).hypot(a.1 - b.1) <= SAME) {
        corners.pop();
    }
    corners
}


/// `piece` onto `path`, every contour of it run backwards if it winds
/// against a box ([`boxed`]). The pass is one path filled by its winding,
/// so two pieces wound against each other would leave a hole where they
/// cross: a CFF face's contours run against a TrueType face's, and a
/// letter's outline against its fill as the stroker happens to lay it
/// (Skia turns a letter it strokes and fills the same way,
/// `SkStroke::strokePath`).
fn wound_as_a_box(piece: &[Command], path: &mut Vec<Command>) {
    if twice_the_area(piece) >= 0.0 {
        path.extend_from_slice(piece);
        return;
    }
    for contour in piece.split_inclusive(|command| matches!(command, Command::Close)) {
        backwards(contour, path);
    }
}

/// Twice the area `piece`'s contours enclose, each closed back to where it
/// began and a curve taken by its control points: a box's is more than
/// nothing, and a piece wound the other way less.
pub(super) fn twice_the_area(piece: &[Command]) -> f64 {
    let edge = |from: Vector, to: Vector| f64::from(from.x) * f64::from(to.y) - f64::from(to.x) * f64::from(from.y);
    let (mut twice, mut start, mut last) = (0.0, Vector::ZERO, Vector::ZERO);
    for command in piece {
        match *command {
            Command::MoveTo(to) => {
                twice += edge(last, start);
                (start, last) = (to, to);
            }
            Command::LineTo(to) => {
                twice += edge(last, to);
                last = to;
            }
            Command::QuadTo(control, to) => {
                twice += edge(last, control) + edge(control, to);
                last = to;
            }
            Command::CurveTo(first, second, to) => {
                twice += edge(last, first) + edge(first, second) + edge(second, to);
                last = to;
            }
            Command::Close => {
                twice += edge(last, start);
                last = start;
            }
        }
    }
    twice + edge(last, start)
}

/// `contour` — a move and what follows it, to its close — run backwards.
pub(super) fn backwards(contour: &[Command], path: &mut Vec<Command>) {
    let ends: Vec<Vector> = contour
        .iter()
        .filter_map(|command| match *command {
            Command::MoveTo(to) | Command::LineTo(to) | Command::QuadTo(_, to) | Command::CurveTo(_, _, to) => {
                Some(to)
            }
            Command::Close => None,
        })
        .collect();
    let Some(&last) = ends.last() else {
        return;
    };
    path.push(Command::MoveTo(last));
    for (index, command) in contour.iter().enumerate().skip(1).rev() {
        let to = ends[index - 1];
        path.push(match *command {
            Command::QuadTo(control, _) => Command::QuadTo(control, to),
            Command::CurveTo(first, second, _) => Command::CurveTo(second, first, to),
            Command::LineTo(_) => Command::LineTo(to),
            Command::MoveTo(_) | Command::Close => continue,
        });
    }
    if matches!(contour.last(), Some(Command::Close)) {
        path.push(Command::Close);
    }
}

/// `rect` as a closed path, wound as the bundled faces' outer contours land
/// in the layout — the way every piece of a pass is wound
/// ([`wound_as_a_box`]): zeno reads a part cover one byte under one way
/// round (raster.rs `coverage`: `!coverage`, so half is 127, the other way
/// 128), and the hard cut is at 128 — so a box's edge is cut as a letter's
/// is.
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

/// `run`'s glyphs, inked as `paint` inks them and laid by `at`: each line
/// of its clusters (those on one baseline, one after another) shaped
/// whole — so letters the face joins are joined, as the app's layout joins
/// them (🔬"fi" and "fl" are one glyph in BIZ UDPGothic, drawn so on the
/// device 2026-11-07) — and each glyph set from the origin of the cluster
/// it belongs to, after the glyphs before it there. A glyph is a piece of
/// its own, wound on its own ([`wound_as_a_box`]).
pub(super) fn letters(faces: &Faces, run: &Run, paint: Paint, at: Affine, path: &mut Vec<Command>) {
    let size = f64::from(run.size) / 64.0;
    for line in run.clusters.chunk_by(|a, b| a.origin[1] == b.origin[1]) {
        let baseline = f64::from(line[0].origin[1]) / 64.0;
        for glyph in shaped(faces, line, (run.weight, run.italic), size) {
            let styled = faces.families[glyph.family].at(run.weight, run.italic);
            let place = Place {
                x: glyph.x,
                y: baseline - glyph.up,
                scale: size / f64::from(styled.font.units_per_em()),
                lean: styled.lean,
            };
            let Some(outline) = styled.font.outline_glyphs().get(glyph.id) else {
                continue;
            };
            let mut contours = Vec::new();
            let mut sink = Sink {
                place,
                path: &mut contours,
            };
            let _ = outline.draw(&DrawOptions::default(), DrawMemory::Scratch, &mut sink);
            let bolder = if styled.bolder { bolder_by(size) } else { 0.0 };
            laid(&contours, Inked::of(paint, bolder), at, path);
        }
    }
}

/// A glyph of a line, where it is set: its family's, `x` across the
/// layout and `up` above the baseline, in pixels of the layout.
pub(super) struct Set {
    pub(super) family: usize,
    pub(super) id: GlyphId,
    pub(super) x: f64,
    pub(super) up: f64,
}

/// `line`'s glyphs at `size` px, in a run of that weight and slant
/// (`weight`, `italic`): its text cut into runs of the family that draws
/// each, each run shaped whole, and each glyph set from the origin of the
/// cluster holding its first letter, after the glyphs before it there — a
/// glyph of letters joined across clusters standing at the first one's.
pub(super) fn shaped(faces: &Faces, line: &[Cluster], (weight, italic): (u16, bool), size: f64) -> Vec<Set> {
    let text: String = line.iter().map(|cluster| cluster.text.as_str()).collect();
    let starts: Vec<usize> = line
        .iter()
        .scan(0, |at, cluster| {
            let start = *at;
            *at += cluster.text.len();
            Some(start)
        })
        .collect();
    let mut pens: Vec<f64> = line.iter().map(|cluster| f64::from(cluster.origin[0]) / 64.0).collect();
    let mut set = Vec::new();
    let mut from = 0;
    for (family, letters) in by_family(faces, &text, (weight, italic)) {
        let styled = faces.families[family].at(weight, italic);
        let font = &styled.font;
        let scale = size / f64::from(font.units_per_em());
        let mut buffer = Buffer::new();
        buffer.push_str(&letters);
        buffer.guess_segment_properties();
        // harfrust refuses only a misuse (shape.rs: a buffer already
        // shaped, no direction, a plan of another), and a fresh buffer
        // whose direction was guessed is none — the guess falls back to
        // left to right (buffer.rs `guess_segment_properties`).
        shape(&ShaperFont::new(font), &mut buffer, ShapeOptions::new())
            .expect("a fresh buffer, its direction guessed, shapes");
        for (glyph, position) in buffer.glyph_infos().iter().zip(buffer.glyph_positions()) {
            let cluster = starts.partition_point(|&start| start <= from + glyph.cluster as usize) - 1;
            set.push(Set {
                family,
                id: GlyphId::new(glyph.glyph_id),
                x: pens[cluster] + f64::from(position.x_offset) * scale,
                up: f64::from(position.y_offset) * scale,
            });
            pens[cluster] += f64::from(position.x_advance) * scale;
        }
        from += letters.len();
    }
    set
}

/// `text` cut where the family that draws it changes, in a run of that
/// weight and slant — `_runsFor`.
pub(super) fn by_family(faces: &Faces, text: &str, (weight, italic): (u16, bool)) -> Vec<(usize, String)> {
    let mut runs: Vec<(usize, String)> = Vec::new();
    for letter in text.chars() {
        let family = faces.of(letter, weight, italic);
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
