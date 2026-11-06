//! A family's faces as Flutter's engine sets a run in them — which file,
//! at what weight, and what of it is faked — and where each shape of a
//! pass stands: the files are the app's bundled ones, said to be whatever
//! face a test needs.

use harfrust::Font;
use zeno::{Command, Vector};

use super::glyphs::{
    Affine, Face, Faces, Family, Paint, Placed, Shape, backwards, bolder_by, by_family, covered, grown, twice_the_area,
};
use super::glyphs_tests::{IDENTITY, faces, file, here, run};

/// A file's first face, said to be `width`, `slant` and `weight`.
fn said(name: &str, (width, slant, weight): (i32, usize, i32)) -> Face {
    Face {
        font: Font::new(file(name), 0).expect("a face"),
        width,
        slant,
        weight,
    }
}

/// Which of two faces a run of `bold` and `italic` is set in — BIZ
/// UDPGothic's regular file said to be `first`, 나눔고딕's said to be
/// `second` — told by whether its face has Hangul.
fn picked(first: (i32, usize, i32), second: (i32, usize, i32), (bold, italic): (bool, bool)) -> &'static str {
    let family = Family::of_faces(vec![
        said("BIZUDPGothic-Regular.ttf", first),
        said("NanumGothic-Regular.ttf", second),
    ])
    .expect("a family");
    match family.at(bold, italic).font.charmap().map_unicode('셀') {
        Some(_) => "second",
        None => "first",
    }
}

const UPRIGHT: (bool, bool) = (false, false);
const ITALIC: (bool, bool) = (false, true);
const BOLD: (bool, bool) = (true, false);

#[test]
fn a_regular_run_takes_400_then_up_to_500_then_lighter_then_heavier() {
    let face = |weight: i32| (5, 0, weight);
    assert_eq!(picked(face(400), face(500), UPRIGHT), "first");
    assert_eq!(picked(face(500), face(450), UPRIGHT), "second", "the nearer of the heavier up to 500");
    assert_eq!(picked(face(500), face(300), UPRIGHT), "first");
    assert_eq!(picked(face(300), face(350), UPRIGHT), "second", "the nearer of the lighter");
    assert_eq!(picked(face(300), face(600), UPRIGHT), "first", "lighter before heavier past 500");
    assert_eq!(picked(face(900), face(600), UPRIGHT), "second");
}

#[test]
fn a_bold_run_takes_700_then_heavier_then_lighter() {
    let face = |weight: i32| (5, 0, weight);
    assert_eq!(picked(face(800), face(700), BOLD), "second");
    assert_eq!(picked(face(800), face(900), BOLD), "first", "the nearer of the heavier");
    assert_eq!(picked(face(600), face(900), BOLD), "second", "any heavier before a lighter");
    assert_eq!(picked(face(400), face(600), BOLD), "second", "the heavier of the lighter");
}

#[test]
fn a_slant_counts_after_the_width_and_before_most_of_the_weight() {
    // Upright 0, italic 1, oblique 2.
    assert_eq!(picked((5, 0, 400), (5, 1, 400), ITALIC), "second");
    assert_eq!(picked((5, 0, 400), (5, 2, 400), ITALIC), "second", "oblique before upright");
    assert_eq!(picked((5, 1, 400), (5, 2, 400), UPRIGHT), "second", "oblique before italic");
    assert_eq!(picked((5, 0, 400), (5, 1, 400), UPRIGHT), "first");
    // A weight's score runs to 1000, a slant's step is 256: an upright
    // 400 outranks an oblique 1000 for an italic run, as in Skia.
    assert_eq!(picked((5, 0, 400), (5, 2, 1000), ITALIC), "first");
    // The width before either: the normal one, then the narrower.
    assert_eq!(picked((4, 1, 400), (5, 0, 400), ITALIC), "second");
    assert_eq!(picked((6, 0, 400), (4, 0, 400), UPRIGHT), "second");
}

#[test]
fn of_two_faces_alike_the_first_handed_over_is_taken() {
    assert_eq!(picked((5, 0, 400), (5, 0, 400), UPRIGHT), "first");
}

#[test]
fn a_run_bolder_than_its_face_by_200_and_at_least_600_is_drawn_bolder() {
    let alone = |weight: i32| Family::of_faces(vec![said("BIZUDPGothic-Regular.ttf", (5, 0, weight))]).unwrap();
    for (weight, bold, bolder) in [
        (400, true, true),
        (500, true, true),
        (600, true, false),
        (700, true, false),
        (300, false, false),
        (100, false, false),
    ] {
        assert_eq!(alone(weight).at(bold, false).bolder, bolder, "a face of {weight}, bold {bold}");
    }
}

#[test]
fn a_run_leans_where_its_face_is_not_italic() {
    let alone = |slant: usize| Family::of_faces(vec![said("BIZUDPGothic-Regular.ttf", (5, slant, 400))]).unwrap();
    assert!(alone(0).at(false, true).lean);
    assert!(!alone(1).at(false, true).lean, "an italic face leans of itself");
    assert!(alone(2).at(false, true).lean, "an oblique face is leaned again");
    assert!(!alone(0).at(false, false).lean);
    assert!(!alone(1).at(true, false).lean, "an upright run never leans");
}

#[test]
fn a_variable_face_is_set_at_the_runs_weight_and_not_drawn_bolder() {
    let noto = Family::of_files(vec![file("NotoSansSC-Variable.ttf")]).unwrap();
    assert!(!noto.at(true, false).bolder, "its wght is 700, not its file's 400");
    let only_regular = Family::of_files(vec![file("BIZUDPGothic-Regular.ttf")]).unwrap();
    assert!(only_regular.at(true, false).bolder);
}

#[test]
fn a_file_that_holds_no_face_is_passed_over() {
    assert!(Family::of_files(vec![b"not a font".to_vec()]).is_none());
    assert!(Family::of_files(vec![b"not a font".to_vec(), file("NanumGothic-Regular.ttf")]).is_some());
}

#[test]
fn a_letter_goes_to_the_family_whose_face_for_the_run_has_it() {
    // A family whose italic face is 나눔고딕's, then 나눔고딕: Hangul set
    // upright goes past the first, set italic stays in it.
    let first = Family::of_faces(vec![
        said("BIZUDPGothic-Regular.ttf", (5, 0, 400)),
        said("NanumGothic-Regular.ttf", (5, 1, 400)),
    ])
    .unwrap();
    let second = Family::of_files(vec![file("NanumGothic-Regular.ttf")]).unwrap();
    let faces = Faces::new(vec![first, second]).unwrap();
    assert_eq!(by_family(&faces, "셀", (false, false)), [(1, "셀".into())]);
    assert_eq!(by_family(&faces, "셀", (false, true)), [(0, "셀".into())]);
}

/// How many pixels of ink the middle row of an "I" holds — the width of
/// its stem — set `px` px in BIZ UDPGothic's regular file alone, `bold`.
fn stem(px: f64, bold: bool, paint: Paint) -> f64 {
    let alone = Faces::new(vec![Family::of_files(vec![file("BIZUDPGothic-Regular.ttf")]).unwrap()]).unwrap();
    let mut letters = run("I", (px * 64.0) as i32, (19, 200 * 64), 0);
    letters.bold = bold;
    let cover = covered(&alone, &here(vec![Shape::Letters(letters)]), paint, IDENTITY).expect("a cover");
    let [left, top, right, bottom] = cover.at;
    let width = (right - left) as usize;
    let middle = ((bottom - top) / 2) as usize;
    let row = &cover.bytes[middle * width..(middle + 1) * width];
    // A stem filled through: nothing part-covered but its two edges.
    if matches!(paint, Paint::Fill) {
        let inked: Vec<usize> = (0..width).filter(|&x| row[x] > 0).collect();
        let inside = row.get(inked[0] + 1..inked[inked.len() - 1]).unwrap_or_default();
        assert!(inside.iter().all(|&byte| byte == 255), "{px} px: {row:?}");
    }
    row.iter().map(|&byte| f64::from(byte)).sum::<f64>() / 255.0
}

#[test]
fn a_bolder_letter_reaches_out_by_its_size_over_24_to_over_32() {
    // 9 px and under a 24th, 36 and over a 32nd, between them the line.
    assert!((bolder_by(9.0) - 9.0 / 24.0).abs() < 1e-9);
    assert!((bolder_by(4.0) - 4.0 / 24.0).abs() < 1e-9);
    assert!((bolder_by(36.0) - 36.0 / 32.0).abs() < 1e-9);
    assert!((bolder_by(72.0) - 72.0 / 32.0).abs() < 1e-9);
    assert!((bolder_by(22.5) - 22.5 * (1.0 / 24.0 + 1.0 / 32.0) / 2.0).abs() < 1e-9);
    // Grown by half of it on each side, the stem is that much wider, and
    // no pixel of it is counted twice.
    for px in [9.0, 22.5, 36.0, 48.0] {
        let grown = stem(px, true, Paint::Fill) - stem(px, false, Paint::Fill);
        assert!((grown - bolder_by(px)).abs() < 0.03, "{px} px: grown {grown}, {}", bolder_by(px));
    }
}

#[test]
fn a_bolder_letters_outline_is_wider_by_as_much() {
    // A pixel's outline round the stem: a pixel across each edge, and
    // bolder by as much again at each.
    let outline = Paint::Stroke { width: 64 };
    let grown = stem(36.0, true, outline) - stem(36.0, false, outline);
    assert!((grown - 2.0 * bolder_by(36.0)).abs() < 0.05, "grown {grown}");
}

#[test]
fn a_placed_shape_is_outlined_in_its_own_space() {
    // Twice as wide, so its outline is twice as wide across and as it
    // was down: [-1, 11) each way, then x twice.
    let wider = Affine { a: 2.0, ..IDENTITY };
    let placed = [Placed {
        at: wider,
        shape: Shape::Rect([0, 0, 10 * 64, 10 * 64]),
    }];
    let cover = covered(faces(), &placed, Paint::Stroke { width: 2 * 64 }, IDENTITY).expect("a cover");
    assert_eq!(cover.at, [-2, -1, 22, 11]);
}

#[test]
fn each_shape_stands_where_its_own_placement_puts_it() {
    // A cell turned a quarter and moved 20 right — x' = 20 - y, y' = x —
    // beside one that stands as it is.
    let turned = Affine {
        a: 0.0,
        b: 1.0,
        c: -1.0,
        d: 0.0,
        e: 20.0,
        f: 0.0,
    };
    let placed = [
        Placed {
            at: turned,
            shape: Shape::Rect([0, 0, 4 * 64, 64]),
        },
        Placed {
            at: IDENTITY,
            shape: Shape::Rect([0, 0, 64, 64]),
        },
    ];
    let cover = covered(faces(), &placed, Paint::Fill, Affine { f: 1.0, ..IDENTITY }).expect("a cover");
    assert_eq!(cover.at, [0, 1, 20, 5]);
    let at = |x: i32, y: i32| cover.bytes[((y - 1) * 20 + x) as usize];
    assert_eq!((at(19, 1), at(19, 4), at(0, 1)), (255, 255, 255));
    assert_eq!((at(18, 1), at(0, 2), at(10, 3)), (0, 0, 0));
}

#[test]
fn pieces_wound_either_way_cover_once_where_they_cross() {
    // A box mirrored into place — x' = 6 - x — winds against one that is
    // not: laid as they came, the two would cancel where they cross, as a
    // CFF letter would under a line.
    let mirrored = Affine { a: -1.0, e: 6.0, ..IDENTITY };
    let placed = [
        Placed {
            at: IDENTITY,
            shape: Shape::Rect([0, 0, 4 * 64, 64]),
        },
        Placed {
            at: mirrored,
            shape: Shape::Rect([0, 0, 4 * 64, 64]),
        },
    ];
    let cover = covered(faces(), &placed, Paint::Fill, IDENTITY).expect("a cover");
    assert_eq!(cover.at, [0, 0, 6, 1]);
    assert_eq!(cover.bytes, [255; 6]);
}

#[test]
fn a_contour_run_backwards_is_the_same_contour_wound_the_other_way() {
    let at = |x: f32, y: f32| Vector::new(x, y);
    let contour = vec![
        Command::MoveTo(at(0.0, 0.0)),
        Command::LineTo(at(4.0, 0.0)),
        Command::CurveTo(at(6.0, 1.0), at(5.0, 3.0), at(4.0, 4.0)),
        Command::QuadTo(at(2.0, 6.0), at(0.0, 4.0)),
        Command::Close,
    ];
    let mut back = Vec::new();
    backwards(&contour, &mut back);
    assert_eq!(
        back,
        [
            Command::MoveTo(at(0.0, 4.0)),
            Command::QuadTo(at(2.0, 6.0), at(4.0, 4.0)),
            Command::CurveTo(at(5.0, 3.0), at(6.0, 1.0), at(4.0, 0.0)),
            Command::LineTo(at(0.0, 0.0)),
            Command::Close,
        ]
    );
    // Its corners and control points, closed: twice 24.5.
    assert_eq!(twice_the_area(&contour), 49.0);
    assert_eq!(twice_the_area(&back), -twice_the_area(&contour));
}

/// Each contour's corners of `path`, in order.
fn contours_of(path: &[Command]) -> Vec<Vec<(f32, f32)>> {
    path.split_inclusive(|command| matches!(command, Command::Close))
        .map(|contour| {
            contour
                .iter()
                .filter_map(|command| match *command {
                    Command::MoveTo(to) | Command::LineTo(to) => Some((to.x, to.y)),
                    _ => None,
                })
                .collect()
        })
        .collect()
}

/// A closed polygon through `corners`, px.
fn polygon(corners: &[(f32, f32)]) -> Vec<Command> {
    let mut path: Vec<Command> = corners
        .iter()
        .enumerate()
        .map(|(index, &(x, y))| match index {
            0 => Command::MoveTo(Vector::new(x, y)),
            _ => Command::LineTo(Vector::new(x, y)),
        })
        .collect();
    path.push(Command::Close);
    path
}

#[test]
fn a_grown_box_is_as_much_larger_on_every_side_wound_either_way() {
    let square = polygon(&[(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0)]);
    assert_eq!(contours_of(&grown(&square, 1.0)), [[(-1.0, -1.0), (11.0, -1.0), (11.0, 11.0), (-1.0, 11.0)]]);
    // Wound the other way — a CFF face's — it grows out all the same.
    let mut against = Vec::new();
    backwards(&square, &mut against);
    assert_eq!(contours_of(&grown(&against, 1.0)), [[(-1.0, 11.0), (11.0, 11.0), (11.0, -1.0), (-1.0, -1.0)]]);
}

#[test]
fn a_hole_shrinks_and_an_inner_corner_moves_in() {
    let mut holed = polygon(&[(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0)]);
    holed.extend(polygon(&[(3.0, 3.0), (3.0, 7.0), (7.0, 7.0), (7.0, 3.0)]));
    let grown_holed = contours_of(&grown(&holed, 1.0));
    assert_eq!(grown_holed[1], [(4.0, 4.0), (4.0, 6.0), (6.0, 6.0), (6.0, 4.0)]);
    let ell = polygon(&[(0.0, 0.0), (10.0, 0.0), (10.0, 4.0), (4.0, 4.0), (4.0, 10.0), (0.0, 10.0)]);
    let grown_ell = &contours_of(&grown(&ell, 1.0))[0];
    assert_eq!(grown_ell.len(), 6, "no corner of an L is cut");
    assert_eq!(grown_ell[3], (5.0, 5.0), "the inner corner, where the moved edges meet");
}

#[test]
fn a_corner_sharper_than_the_mitre_limit_is_cut_flat() {
    // A tip of 90°: its mitre reaches √2 out — under 4, so one corner.
    let right = contours_of(&grown(&polygon(&[(0.0, -10.0), (10.0, 0.0), (0.0, 10.0)]), 1.0)).remove(0);
    assert_eq!(right.len(), 3);
    let (x, y) = right[1];
    assert!((x - (10.0 + 2f32.sqrt())).abs() < 1e-5 && y.abs() < 1e-5, "{:?}", right[1]);
    // A tip of 11.4°: its mitre would reach 10 out — cut, two corners.
    let sharp = contours_of(&grown(&polygon(&[(0.0, -1.0), (10.0, 0.0), (0.0, 1.0)]), 1.0)).remove(0);
    assert_eq!(sharp.len(), 4);
    assert!(sharp.iter().all(|&(x, _)| x <= 11.0), "{sharp:?}");
}

#[test]
fn a_curve_grows_as_the_curve_does() {
    // A circle 10 px round, of four cubics and of sixteen quadratics: grown
    // 1 px, every corner stands 11 px from its middle.
    let k = 10.0 * 0.552_284_8;
    let at = |x: f32, y: f32| Vector::new(x, y);
    let cubics = vec![
        Command::MoveTo(at(10.0, 0.0)),
        Command::CurveTo(at(10.0, k), at(k, 10.0), at(0.0, 10.0)),
        Command::CurveTo(at(-k, 10.0), at(-10.0, k), at(-10.0, 0.0)),
        Command::CurveTo(at(-10.0, -k), at(-k, -10.0), at(0.0, -10.0)),
        Command::CurveTo(at(k, -10.0), at(10.0, -k), at(10.0, 0.0)),
        Command::Close,
    ];
    let mut quadratics = vec![Command::MoveTo(at(10.0, 0.0))];
    let (step, reach) = (std::f32::consts::PI / 8.0, 10.0 / (std::f32::consts::PI / 16.0).cos());
    for sixteenth in 0..16 {
        let (middle, end) = ((sixteenth as f32 + 0.5) * step, (sixteenth + 1) as f32 * step);
        quadratics.push(Command::QuadTo(
            at(reach * middle.cos(), reach * middle.sin()),
            at(10.0 * end.cos(), 10.0 * end.sin()),
        ));
    }
    quadratics.push(Command::Close);
    for circle in [cubics, quadratics] {
        let corners = contours_of(&grown(&circle, 1.0)).remove(0);
        assert!(corners.len() > 16, "cut into lines: {}", corners.len());
        for (x, y) in corners {
            let from_middle = x.hypot(y);
            assert!((from_middle - 11.0).abs() < 0.02, "{from_middle}");
        }
    }
}

#[test]
fn a_corner_turning_in_too_sharply_stays_where_it_was() {
    // A notch 9 px deep and 0.4 px wide up into a square: its tip turns in
    // at 2.5°, and the moved edges would meet 18 px past it.
    let notched = polygon(&[(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (5.2, 10.0), (5.0, 1.0), (4.8, 10.0), (0.0, 10.0)]);
    let corners = contours_of(&grown(&notched, 1.0)).remove(0);
    assert!(corners.contains(&(5.0, 1.0)), "{corners:?}");
    assert!(corners.iter().all(|&(x, y)| (-1.5..=11.5).contains(&x) && (-1.5..=11.5).contains(&y)), "{corners:?}");
}

/// The cover of `text` set 40 px in a run of `bold` and `italic`, in the
/// families `faces`.
fn set_in(faces: &Faces, text: &str, (bold, italic): (bool, bool)) -> super::Cover {
    let mut letters = run(text, 40 * 64, (0, 100 * 64), 0);
    (letters.bold, letters.italic) = (bold, italic);
    covered(faces, &here(vec![Shape::Letters(letters)]), Paint::Fill, IDENTITY).expect("a cover")
}

#[test]
fn a_face_as_bold_and_as_italic_as_the_run_is_drawn_as_it_is() {
    // BIZ UDPGothic's bold file alone answers a regular run: a run asking
    // for bold is drawn in it no bolder.
    let bold_alone = Faces::new(vec![Family::of_files(vec![file("BIZUDPGothic-Bold.ttf")]).unwrap()]).unwrap();
    let (regular, bold) = (set_in(&bold_alone, "I", UPRIGHT), set_in(&bold_alone, "I", BOLD));
    assert_eq!((regular.at, regular.bytes), (bold.at, bold.bytes));
    // A face said to be italic is not leaned again.
    let italic_alone = || Family::of_faces(vec![said("BIZUDPGothic-Regular.ttf", (5, 1, 400))]).unwrap();
    let italic_alone = Faces::new(vec![italic_alone()]).unwrap();
    let (upright, italic) = (set_in(&italic_alone, "I", UPRIGHT), set_in(&italic_alone, "I", ITALIC));
    assert_eq!((upright.at, upright.bytes), (italic.at, italic.bytes));
}

#[test]
fn a_run_is_shaped_in_the_face_it_is_drawn_in() {
    // Hangul set italic in a family whose italic face is 나눔고딕's — and
    // whose upright face, BIZ UDPGothic's, has none — is 나눔고딕's own.
    let mixed = Family::of_faces(vec![
        said("BIZUDPGothic-Regular.ttf", (5, 0, 400)),
        said("NanumGothic-Regular.ttf", (5, 1, 400)),
    ])
    .unwrap();
    let alone = Family::of_faces(vec![said("NanumGothic-Regular.ttf", (5, 1, 400))]).unwrap();
    let (mixed, alone) = (Faces::new(vec![mixed]).unwrap(), Faces::new(vec![alone]).unwrap());
    let (ours, its_own) = (set_in(&mixed, "셀", ITALIC), set_in(&alone, "셀", ITALIC));
    assert_eq!((ours.at, ours.bytes), (its_own.at, its_own.bytes));
}
