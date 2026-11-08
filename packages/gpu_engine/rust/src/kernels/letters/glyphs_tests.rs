//! The letters' covers, set in the app's own bundled faces — read from
//! `assets/fonts/`, the files `pubspec.yaml` ships.

use std::sync::OnceLock;

use zeno::{Command, Vector};

use super::glyphs::{
    Affine, Cluster, Faces, Family, Paint, Placed, Run, Shape, boxed, by_family, covered, letters, shaped,
};
use super::tests::at as pixel_of;
use super::{Pass, set};
use crate::kernels::composite::tests::rig;

pub(super) const IDENTITY: Affine = Affine {
    a: 1.0,
    b: 0.0,
    c: 0.0,
    d: 1.0,
    e: 0.0,
    f: 0.0,
};

/// `shapes`, each standing in the layout as it is.
pub(super) fn here(shapes: Vec<Shape>) -> Vec<Placed> {
    shapes.into_iter().map(|shape| Placed { at: IDENTITY, shape }).collect()
}

pub(crate) fn file(name: &str) -> Vec<u8> {
    let dir = std::env::var("CARGO_MANIFEST_DIR").expect("cargo runs the test");
    let path = format!("{dir}/../../../assets/fonts/{name}");
    std::fs::read(&path).unwrap_or_else(|error| panic!("{path}: {error}"))
}

/// The app's canvas letters' families, in their order: BIZ UDPGothic,
/// 나눔고딕, Noto Sans SC (app_theme.dart; engine-canvas-letters-Q2).
pub(super) fn faces() -> &'static Faces {
    static FACES: OnceLock<Faces> = OnceLock::new();
    FACES.get_or_init(|| {
        Faces::new(vec![
            Family::of_files(vec![file("BIZUDPGothic-Regular.ttf"), file("BIZUDPGothic-Bold.ttf")]).unwrap(),
            Family::of_files(vec![file("NanumGothic-Regular.ttf"), file("NanumGothic-Bold.ttf")]).unwrap(),
            Family::of_files(vec![file("NotoSansSC-Variable.ttf")]).unwrap(),
        ])
        .unwrap()
    })
}

/// `text`, one cluster a letter `step` 64ths apart, at `size` 64ths, from
/// (`x`, `y`) 64ths.
pub(super) fn run(text: &str, size: i32, (x, y): (i32, i32), step: i32) -> Run {
    Run {
        size,
        bold: false,
        italic: false,
        clusters: text
            .chars()
            .enumerate()
            .map(|(i, letter)| Cluster {
                text: letter.to_string(),
                origin: [x + i as i32 * step, y],
            })
            .collect(),
    }
}

fn filled(shapes: Vec<Shape>, to_grid: Affine) -> super::Cover {
    covered(faces(), &here(shapes), Paint::Fill, to_grid).expect("a cover")
}

pub(super) fn ink(cover: &super::Cover) -> u64 {
    cover.bytes.iter().map(|&byte| u64::from(byte)).sum()
}

#[test]
fn a_letter_goes_to_the_first_family_that_has_it() {
    let families = |text: &str| -> Vec<usize> {
        by_family(faces(), text, (false, false)).into_iter().map(|(family, _)| family).collect()
    };
    assert_eq!(families("A"), [0], "BIZ UDPGothic has Latin");
    assert_eq!(families("カ"), [0]);
    assert_eq!(families("셀"), [1], "나눔고딕 draws Hangul");
    // F-524-Q1: the bundled BIZ files lose the keyboard tilde.
    assert_eq!(families("~"), [1]);
    assert_eq!(families("业"), [2], "a simplified character neither has");
    assert_eq!(families("😊"), [0], "one none has: the first's empty box");
    // A family's letters are one run, shaped together.
    assert_eq!(by_family(faces(), "AB셀业", (false, false)), [(0, "AB".into()), (1, "셀".into()), (2, "业".into())]);
}

#[test]
fn letters_are_set_in_some_face() {
    assert!(Faces::new(Vec::new()).is_none());
}

#[test]
fn a_letter_is_its_glyphs_units_at_the_size() {
    // BIZ UDPGothic's H, of 2048 units: from 199 right of its origin, 1282
    // wide, from 1608 above the baseline, 1659 tall. At 100 px from (0,
    // 200): 9.72 to 72.32 across, 121.48 to 202.49 down.
    let cover = filled(vec![Shape::Letters(run("H", 100 * 64, (0, 200 * 64), 0))], IDENTITY);
    assert_eq!(cover.at, [9, 121, 73, 203]);
}

#[test]
fn a_clusters_letters_follow_one_another() {
    // One cluster of two: the second at the first's advance, not over it.
    let one = ink(&filled(vec![Shape::Letters(run("I", 40 * 64, (0, 3000), 0))], IDENTITY));
    let mut two = run("I", 40 * 64, (0, 3000), 0);
    two.clusters[0].text = "II".into();
    let two = ink(&filled(vec![Shape::Letters(two)], IDENTITY));
    assert!(two > one * 19 / 10, "two {two}, one {one}");
}

#[test]
fn letters_a_face_joins_are_joined_across_clusters() {
    // The app hands "f" and "i" over as two clusters, and BIZ UDPGothic
    // sets them as one glyph, at the "f"'s origin.
    let path_of = |clusters: &[(&str, i32, i32)]| {
        let mut path = Vec::new();
        let clusters = clusters
            .iter()
            .map(|&(text, x, y)| Cluster {
                text: text.into(),
                origin: [x, y],
            })
            .collect();
        letters(faces(), &Run { size: 40 * 64, bold: false, italic: false, clusters }, Paint::Fill, IDENTITY, &mut path);
        path
    };
    let joined = path_of(&[("fi", 640, 3200)]);
    assert_eq!(path_of(&[("f", 640, 3200), ("i", 1573, 3200)]), joined);
    // On two lines they are two letters, each where it stands.
    let (f, i) = (path_of(&[("f", 640, 3200)]), path_of(&[("i", 640, 6400)]));
    assert_ne!(f, joined);
    assert_eq!(path_of(&[("f", 640, 3200), ("i", 640, 6400)]), [f, i].concat());
    // A cluster stands where the app put it, not where the advance ends:
    // letters spaced out (6 px a letter in the app, on the device) come
    // over with the room in their origins.
    let (a, one) = (path_of(&[("A", 0, 3200)]), path_of(&[("1", 64 * 50, 3200)]));
    assert_eq!(path_of(&[("A", 0, 3200), ("1", 64 * 50, 3200)]), [a, one].concat());
}

/// 🚨THE ENGINE'S HALF OF `test/fixtures/canvas_letter_clusters.json`
/// (the app's: the_app_sets_letters_where_the_engines_shaping_does_test.dart):
/// each line set by harfrust's own advances from its start lays every glyph
/// where the app's lefts lay it — kerning and joined letters with it — to
/// the 64th of a pixel a cluster's origin is handed over in.
#[test]
fn harfrusts_advances_meet_the_apps_clusters() {
    let dir = std::env::var("CARGO_MANIFEST_DIR").expect("cargo runs the test");
    let path = format!("{dir}/../../../test/fixtures/canvas_letter_clusters.json");
    let text = std::fs::read_to_string(&path).unwrap_or_else(|error| panic!("{path}: {error}"));
    let fixture: serde_json::Value = serde_json::from_str(&text).unwrap_or_else(|error| panic!("{path}: {error}"));
    for line in fixture["lines"].as_array().expect("lines") {
        let texts: Vec<&str> = line["clusters"].as_array().unwrap().iter().map(|c| c.as_str().unwrap()).collect();
        let lefts: Vec<f64> = line["lefts"].as_array().unwrap().iter().map(|l| l.as_f64().unwrap()).collect();
        let (size, bold) = (line["size"].as_f64().unwrap(), line["bold"].as_bool().unwrap());
        let whole = [Cluster {
            text: texts.concat(),
            origin: [0, 0],
        }];
        let split: Vec<Cluster> = texts
            .iter()
            .zip(&lefts)
            .map(|(text, left)| Cluster {
                text: (*text).into(),
                origin: [(left * 64.0).round() as i32, 0],
            })
            .collect();
        let (ours, apps) = (shaped(faces(), &whole, (bold, false), size), shaped(faces(), &split, (bold, false), size));
        let ids = |set: &[super::glyphs::Set]| set.iter().map(|glyph| glyph.id.to_u32()).collect::<Vec<_>>();
        assert_eq!(ids(&ours), ids(&apps));
        for (glyph, (ours, apps)) in ours.iter().zip(&apps).enumerate() {
            let off = (ours.x - apps.x).abs();
            assert!(off <= 1.0 / 64.0, "{}: glyph {glyph} at {} by harfrust, {} by the app", texts.concat(), ours.x, apps.x);
        }
    }
}

#[test]
fn marks_stand_where_the_face_puts_them() {
    // BIZ UDPGothic sets an acute back over the x (-1162 units), and a
    // second one above the first (368).
    let cover = |text: &str| {
        let mut letters = run("x", 64 * 64, (0, 100 * 64), 0);
        letters.clusters[0].text = text.into();
        filled(vec![Shape::Letters(letters)], IDENTITY)
    };
    let (x, acute, two) = (cover("x"), cover("x\u{301}"), cover("x\u{301}\u{301}"));
    assert!(acute.at[2] <= x.at[2], "the acute over the x, not after it");
    assert!(two.at[1] <= acute.at[1] - 10, "a second acute above the first");
}

#[test]
fn a_turn_of_the_grid_turns_the_cover() {
    // A quarter turn: x' = -y, y' = x.
    let turned = Affine { a: 0.0, b: 1.0, c: -1.0, d: 0.0, ..IDENTITY };
    let cover = filled(vec![Shape::Rect([0, 0, 4 * 64, 64])], turned);
    assert_eq!(cover.at, [-1, 0, 0, 4]);
    assert_eq!(cover.bytes, [255; 4]);
}

#[test]
fn shapes_of_one_pass_that_overlap_cover_once() {
    // A line through letters, as an underline crosses them: no hole.
    let cover = filled(vec![Shape::Rect([0, 0, 4 * 64, 64]), Shape::Rect([2 * 64, 0, 6 * 64, 64])], IDENTITY);
    assert_eq!(cover.at, [0, 0, 6, 1]);
    assert_eq!(cover.bytes, [255; 6]);
}

#[test]
fn a_letters_contours_are_closed_and_keep_their_curves() {
    for text in ["O", "셀", "业"] {
        let mut path = Vec::new();
        letters(faces(), &run(text, 64 * 64, (0, 100 * 64), 0), Paint::Fill, IDENTITY, &mut path);
        let count = |of: fn(&Command) -> bool| path.iter().filter(|command| of(command)).count();
        let (moves, closes) = (count(|c| matches!(c, Command::MoveTo(_))), count(|c| matches!(c, Command::Close)));
        assert!(moves > 0 && moves == closes, "{text}: {moves} contours, {closes} closed");
        assert!(count(|c| matches!(c, Command::QuadTo(..))) > 0, "{text}: no curve");
    }
}

#[test]
fn the_same_letters_raster_to_the_same_bytes() {
    let once = filled(vec![Shape::Letters(run("A12タロウ셀业", 34 * 64, (100, 3000), 2200))], IDENTITY);
    let again = filled(vec![Shape::Letters(run("A12タロウ셀业", 34 * 64, (100, 3000), 2200))], IDENTITY);
    assert_eq!(once.at, again.at);
    assert_eq!(once.bytes, again.bytes);
}

#[test]
fn a_whole_pixel_move_moves_the_cover_whole() {
    let here = filled(vec![Shape::Letters(run("A셀", 30 * 64, (37, 2000), 2000))], IDENTITY);
    // The origin a pixel right, and the grid three pixels down.
    let moved = filled(
        vec![Shape::Letters(run("A셀", 30 * 64, (37 + 64, 2000), 2000))],
        Affine { f: 3.0, ..IDENTITY },
    );
    let [left, top, right, bottom] = here.at;
    assert_eq!(moved.at, [left + 1, top + 3, right + 1, bottom + 3]);
    assert_eq!(moved.bytes, here.bytes);
}

#[test]
fn a_rect_covers_its_pixels_and_a_half_pixel_by_a_byte_under_half() {
    // The winding the letters take reads a half as 127: under the hard cut.
    let cover = filled(vec![Shape::Rect([0, 0, 3 * 64 + 32, 64])], IDENTITY);
    assert_eq!(cover.at, [0, 0, 4, 1]);
    assert_eq!(cover.bytes, [255, 255, 255, 127]);
}

#[test]
fn a_box_winds_as_a_letters_outer_contour_does() {
    // Twice the area a path's corners enclose: its sign is its winding.
    let wound = |path: &[Command]| {
        let corners: Vec<Vector> = path
            .iter()
            .filter_map(|command| match *command {
                Command::MoveTo(to) | Command::LineTo(to) | Command::QuadTo(_, to) | Command::CurveTo(_, _, to) => {
                    Some(to)
                }
                Command::Close => None,
            })
            .collect();
        let area: f32 = corners
            .iter()
            .zip(corners.iter().cycle().skip(1))
            .map(|(from, to)| from.x * to.y - to.x * from.y)
            .sum();
        area.signum()
    };
    let mut boxed_path = Vec::new();
    boxed(&[0, 0, 640, 640], &mut boxed_path);
    // One contour each, in the two families' faces that set Latin and
    // Hangul — "I", and "ㅣ".
    for text in ["I", "ㅣ"] {
        let mut letter = Vec::new();
        letters(faces(), &run(text, 64 * 64, (0, 100 * 64), 0), Paint::Fill, IDENTITY, &mut letter);
        assert_eq!(wound(&letter), wound(&boxed_path), "{text}");
    }
}

#[test]
fn an_outline_reaches_half_its_width_past_the_fill() {
    let shapes = || vec![Shape::Rect([0, 0, 10 * 64, 10 * 64])];
    let stroked = covered(faces(), &here(shapes()), Paint::Stroke { width: 4 * 64 }, IDENTITY).expect("a cover");
    assert_eq!(stroked.at, [-2, -2, 12, 12]);
    let row = |y: i32| &stroked.bytes[((y + 2) * 14) as usize..((y + 3) * 14) as usize];
    // Across the middle: two pixels outside, two inside, nothing between.
    assert_eq!(row(5)[..4], [255, 255, 255, 255]);
    assert_eq!(row(5)[4..10], [0, 0, 0, 0, 0, 0]);
    // A round join: the corner pixel holds the quarter circle of radius 2
    // past (1, 1) of it, 0.315 of the pixel by hand — 80 of 255, and zeno's
    // arc of curves lands 74. A mitre would fill it whole, a bevel leave it
    // empty.
    let corner = row(-2)[0];
    assert!((60..=100).contains(&corner), "the corner pixel holds {corner}");
}

#[test]
fn a_placement_scales_the_outline_with_the_letters() {
    // Strokes first, then the transform: twice the grid, twice the width.
    let shapes = || vec![Shape::Rect([0, 0, 10 * 64, 10 * 64])];
    let twice = Affine { a: 2.0, d: 2.0, ..IDENTITY };
    let stroked = covered(faces(), &here(shapes()), Paint::Stroke { width: 2 * 64 }, twice).expect("a cover");
    assert_eq!(stroked.at, [-2, -2, 22, 22]);
}

#[test]
fn bold_letters_carry_more_ink() {
    for text in ["A", "셀", "业"] {
        let mut letters = run(text, 40 * 64, (0, 3000), 0);
        let regular = ink(&filled(vec![Shape::Letters(letters)], IDENTITY));
        letters = run(text, 40 * 64, (0, 3000), 0);
        letters.bold = true;
        let bold = ink(&filled(vec![Shape::Letters(letters)], IDENTITY));
        assert!(bold > regular * 11 / 10, "{text}: bold {bold}, regular {regular}");
    }
}

#[test]
fn a_lean_moves_a_letters_top_right_by_a_quarter_of_its_height() {
    let baseline = 100;
    let upright = filled(vec![Shape::Letters(run("I", 64 * 64, (0, baseline * 64), 0))], IDENTITY);
    let mut leaning = run("I", 64 * 64, (0, baseline * 64), 0);
    leaning.italic = true;
    let leaning = filled(vec![Shape::Letters(leaning)], IDENTITY);
    // The first pixel the stem covers by half or more, top row first.
    let first = |cover: &super::Cover| {
        let width = cover.at[2] - cover.at[0];
        let index = cover.bytes.iter().position(|&byte| byte >= 128).expect("ink") as i32;
        (cover.at[0] + index % width, cover.at[1] + index / width)
    };
    let ((upright_x, top), (leaning_x, leaning_top)) = (first(&upright), first(&leaning));
    assert_eq!(leaning_top, top, "a lean moves no letter up or down");
    let height = f64::from(baseline - top);
    let moved = f64::from(leaning_x - upright_x);
    assert!((moved - height / 4.0).abs() <= 1.0, "moved {moved} for a height of {height}");
}

#[test]
fn a_letter_no_family_has_draws_the_first_familys_box() {
    assert!(ink(&filled(vec![Shape::Letters(run("😊", 30 * 64, (0, 2000), 0))], IDENTITY)) > 0);
}

#[test]
fn nothing_to_draw_is_no_cover() {
    assert!(covered(faces(), &here(vec![Shape::Letters(run(" ", 30 * 64, (0, 2000), 0))]), Paint::Fill, IDENTITY).is_none());
    assert!(covered(faces(), &[], Paint::Fill, IDENTITY).is_none());
    assert!(covered(faces(), &here(vec![Shape::Rect([320, 320, 320, 320])]), Paint::Fill, IDENTITY).is_none());
}

#[test]
fn passes_are_set_outline_under_fill_on_the_gpu() {
    let rig = rig();
    let shapes = || vec![Shape::Rect([0, 0, 10 * 64, 10 * 64])];
    let picture = set(
        rig.engine,
        &rig.composite,
        faces(),
        IDENTITY,
        &[
            Pass {
                colour: 0xFF20_2020,
                hard: false,
                paint: Paint::Stroke { width: 4 * 64 },
                shapes: here(shapes()),
            },
            Pass {
                colour: 0xFFFF_FFFF,
                hard: false,
                paint: Paint::Fill,
                shapes: here(shapes()),
            },
        ],
    )
    .flatten()
    .expect("set");
    assert_eq!(pixel_of(&picture, -1, 5), 0xFF20_2020, "outside the fill, the outline");
    assert_eq!(pixel_of(&picture, 1, 5), 0xFFFF_FFFF, "over the outline, the fill");
    assert_eq!(pixel_of(&picture, 5, 5), 0xFFFF_FFFF);
    assert_eq!(pixel_of(&picture, -3, 5), 0, "past the outline, nothing");
}

#[test]
fn a_hard_pass_is_cut_on_the_gpu() {
    // Three and a half pixels: the half is 127, under the cut.
    let rig = rig();
    let pass = |hard: bool| Pass {
        colour: 0xFF20_30D0,
        hard,
        paint: Paint::Fill,
        shapes: here(vec![Shape::Rect([0, 0, 3 * 64 + 32, 64])]),
    };
    let smooth = set(rig.engine, &rig.composite, faces(), IDENTITY, &[pass(false)]).flatten().expect("set");
    let hard = set(rig.engine, &rig.composite, faces(), IDENTITY, &[pass(true)]).flatten().expect("set");
    assert_eq!(pixel_of(&smooth, 3, 0), 127 << 24 | 0x0020_30D0);
    assert_eq!(pixel_of(&hard, 3, 0), 0);
    assert_eq!(pixel_of(&hard, 2, 0), 0xFF20_30D0);
}
