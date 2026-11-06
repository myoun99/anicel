//! The letters' covers, set in the app's own bundled faces — read from
//! `assets/fonts/`, the files `pubspec.yaml` ships.

use std::sync::OnceLock;

use zeno::{Command, Vector};

use super::glyphs::{Affine, Cluster, Faces, Family, Paint, Run, Shape, boxed, by_family, covered, letters};
use super::tests::at as pixel_of;
use super::{Pass, set};
use crate::kernels::composite::tests::rig;

const IDENTITY: Affine = Affine {
    a: 1.0,
    b: 0.0,
    c: 0.0,
    d: 1.0,
    e: 0.0,
    f: 0.0,
};

/// The app's canvas letters' families, in their order: BIZ UDPGothic,
/// 나눔고딕, Noto Sans SC (app_theme.dart; engine-canvas-letters-Q2).
fn faces() -> &'static Faces {
    static FACES: OnceLock<Faces> = OnceLock::new();
    FACES.get_or_init(|| {
        let dir = std::env::var("CARGO_MANIFEST_DIR").expect("cargo runs the test");
        let file = |name: &str| {
            let path = format!("{dir}/../../../assets/fonts/{name}");
            std::fs::read(&path).unwrap_or_else(|error| panic!("{path}: {error}"))
        };
        Faces::new(vec![
            Family::of_two(file("BIZUDPGothic-Regular.ttf"), file("BIZUDPGothic-Bold.ttf")).unwrap(),
            Family::of_two(file("NanumGothic-Regular.ttf"), file("NanumGothic-Bold.ttf")).unwrap(),
            Family::of_one_variable(file("NotoSansSC-Variable.ttf")).unwrap(),
        ])
        .unwrap()
    })
}

/// `text`, one cluster a letter `step` 64ths apart, at `size` 64ths, from
/// (`x`, `y`) 64ths.
fn run(text: &str, size: i32, (x, y): (i32, i32), step: i32) -> Run {
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
    covered(faces(), &shapes, Paint::Fill, to_grid).expect("a cover")
}

fn ink(cover: &super::Cover) -> u64 {
    cover.bytes.iter().map(|&byte| u64::from(byte)).sum()
}

#[test]
fn a_letter_goes_to_the_first_family_that_has_it() {
    let families = |text: &str| -> Vec<usize> {
        by_family(faces(), text, false).into_iter().map(|(family, _)| family).collect()
    };
    assert_eq!(families("A"), [0], "BIZ UDPGothic has Latin");
    assert_eq!(families("カ"), [0]);
    assert_eq!(families("셀"), [1], "나눔고딕 draws Hangul");
    // F-524-Q1: the bundled BIZ files lose the keyboard tilde.
    assert_eq!(families("~"), [1]);
    assert_eq!(families("业"), [2], "a simplified character neither has");
    assert_eq!(families("😊"), [0], "one none has: the first's empty box");
    assert_eq!(by_family(faces(), "A셀业", false), [(0, "A".into()), (1, "셀".into()), (2, "业".into())]);
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
        letters(faces(), &run(text, 64 * 64, (0, 100 * 64), 0), &mut letter);
        assert_eq!(wound(&letter), wound(&boxed_path), "{text}");
    }
}

#[test]
fn an_outline_reaches_half_its_width_past_the_fill() {
    let shapes = || vec![Shape::Rect([0, 0, 10 * 64, 10 * 64])];
    let stroked = covered(faces(), &shapes(), Paint::Stroke { width: 4 * 64 }, IDENTITY).expect("a cover");
    assert_eq!(stroked.at, [-2, -2, 12, 12]);
    let row = |y: i32| &stroked.bytes[((y + 2) * 14) as usize..((y + 3) * 14) as usize];
    // Across the middle: two pixels outside, two inside, nothing between.
    assert_eq!(row(5)[..4], [255, 255, 255, 255]);
    assert_eq!(row(5)[4..10], [0, 0, 0, 0, 0, 0]);
}

#[test]
fn a_placement_scales_the_outline_with_the_letters() {
    // Strokes first, then the transform: twice the grid, twice the width.
    let shapes = || vec![Shape::Rect([0, 0, 10 * 64, 10 * 64])];
    let twice = Affine { a: 2.0, d: 2.0, ..IDENTITY };
    let stroked = covered(faces(), &shapes(), Paint::Stroke { width: 2 * 64 }, twice).expect("a cover");
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
    assert!(covered(faces(), &[Shape::Letters(run(" ", 30 * 64, (0, 2000), 0))], Paint::Fill, IDENTITY).is_none());
    assert!(covered(faces(), &[], Paint::Fill, IDENTITY).is_none());
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
                shapes: shapes(),
            },
            Pass {
                colour: 0xFFFF_FFFF,
                hard: false,
                paint: Paint::Fill,
                shapes: shapes(),
            },
        ],
    )
    .expect("set");
    assert_eq!(pixel_of(&picture, -1, 5), 0xFF20_2020, "outside the fill, the outline");
    assert_eq!(pixel_of(&picture, 1, 5), 0xFFFF_FFFF, "over the outline, the fill");
    assert_eq!(pixel_of(&picture, 5, 5), 0xFFFF_FFFF);
    assert_eq!(pixel_of(&picture, -3, 5), 0, "past the outline, nothing");
}
