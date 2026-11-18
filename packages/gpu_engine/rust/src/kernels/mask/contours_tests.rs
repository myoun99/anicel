//! The outline walk the selection's ants and a held fill's mark share
//! ([`walked`]), pinned by the exact points it gives: the order is the law
//! — a contour starts where the scan first met it, so the dashes stay put.
//! ↩️These were the Dart walk's pins (`pixel_run_contours_test.dart`), the
//! same points expected, now counted from the box.

use super::{laid_count, runs_hold, walked};

/// `rows` — each row's starts and ends in turn — as the runs the walk
/// reads: the rows' offsets and their ends.
fn runs_of(rows: &[Vec<u32>]) -> (Vec<u32>, Vec<u32>) {
    let mut offsets = vec![0];
    let mut ends = Vec::new();
    for row in rows {
        ends.extend(row);
        offsets.push(ends.len() as u32);
    }
    (offsets, ends)
}

/// The contours of `rows` in a box `width` wide, each a list of points.
fn walk(rows: &[Vec<u32>], width: u32) -> Vec<Vec<(i32, i32)>> {
    let (offsets, ends) = runs_of(rows);
    let contours = walked(&offsets, &ends, width);
    contours
        .starts
        .windows(2)
        .map(|contour| {
            let points = &contours.points[2 * contour[0] as usize..2 * contour[1] as usize];
            points.chunks_exact(2).map(|point| (point[0], point[1])).collect()
        })
        .collect()
}

/// The runs of the pixels `covered` says, in a box `width` × `height`.
fn rows_of(covered: impl Fn(u32, u32) -> bool, width: u32, height: u32) -> Vec<Vec<u32>> {
    (0..height)
        .map(|y| (0..=width).filter(|&x| (x < width && covered(x, y)) != (x > 0 && covered(x - 1, y))).collect())
        .collect()
}

#[test]
fn a_block_is_its_four_corners_from_its_top_left_going_right() {
    assert_eq!(walk(&[vec![0, 3], vec![0, 3]], 3), [vec![(0, 0), (3, 0), (3, 2), (0, 2)]]);
}

#[test]
fn two_pixels_that_meet_only_at_a_corner_are_one_walk_through_it_its_later_edge_first() {
    assert_eq!(
        walk(&[vec![0, 1], vec![1, 2]], 2),
        [vec![(0, 0), (1, 0), (1, 1), (2, 1), (2, 2), (1, 2), (1, 1), (0, 1)]],
    );
}

#[test]
fn two_runs_that_meet_only_at_a_corner_each_of_its_own_length_are_walked_through_it_a_run_each() {
    assert_eq!(
        walk(&[vec![0, 3], vec![3, 6]], 6),
        [vec![(0, 0), (3, 0), (3, 1), (6, 1), (6, 2), (3, 2), (3, 1), (0, 1)]],
    );
}

#[test]
fn a_hole_wider_than_a_pixel_starts_at_its_top_left_corner_going_down() {
    let hole = |x: u32, y: u32| (2..5).contains(&x) && (1..3).contains(&y);
    assert_eq!(
        walk(&rows_of(|x, y| !hole(x, y), 7, 5), 7),
        [vec![(0, 0), (7, 0), (7, 5), (0, 5)], vec![(2, 1), (2, 3), (5, 3), (5, 1)]],
    );
}

#[test]
fn a_straight_side_is_laid_as_an_edge_or_two_not_a_pixels_each() {
    // A 1000-pixel run three rows deep: its top one edge, its bottom two
    // (its first pixel's own, then the rest), its sides one a row.
    let (offsets, ends) = runs_of(&[vec![0, 1000], vec![0, 1000], vec![0, 1000]]);
    assert_eq!(laid_count(&offsets, &ends), 9);
}

#[test]
fn holes_come_after_the_outline_that_holds_them_in_the_order_the_scan_meets_them() {
    let hole = |x: u32, y: u32| x % 4 == 1 && y % 4 == 1 && x < 60 && y < 60;
    let mut expected = vec![vec![(0, 0), (64, 0), (64, 64), (0, 64)]];
    for y in (1..60).step_by(4) {
        for x in (1..60).step_by(4) {
            expected.push(vec![(x + 1, y), (x, y), (x, y + 1), (x + 1, y + 1)]);
        }
    }
    assert_eq!(walk(&rows_of(|x, y| !hole(x, y), 64, 64), 64), expected);
}

#[test]
fn nothing_held_is_no_contour() {
    assert!(walk(&[vec![], vec![]], 4).is_empty());
    assert!(walk(&[], 4).is_empty());
    assert!(walk(&[vec![0, 1]], 0).is_empty());
}

#[test]
fn runs_hold_only_where_each_rows_are_in_order_and_within_the_box() {
    assert!(runs_hold(&[0, 2, 4], &[0, 3, 1, 4], 4));
    assert!(runs_hold(&[0], &[], 0));
    assert!(!runs_hold(&[0, 2], &[0, 5], 4), "past the box");
    assert!(!runs_hold(&[0, 2], &[3, 3], 4), "an empty run");
    assert!(!runs_hold(&[0, 4], &[2, 3, 0, 1], 4), "out of order");
    assert!(!runs_hold(&[2, 0], &[0, 1], 4), "rows out of order");
    assert!(!runs_hold(&[0, 3], &[0, 1], 4), "past the ends");
}

#[test]
fn the_door_hands_the_walk_over_and_refuses_runs_of_no_such_box() {
    use super::super::abi::{gpu_engine_run_contours, gpu_engine_run_contours_free, gpu_engine_run_contours_read};
    use crate::testing::last_error;
    let (offsets, ends) = runs_of(&[vec![0, 3], vec![0, 3]]);
    let mut counts = [0usize; 2];
    // SAFETY: each offsets holds a word more than its rows, each ends as
    // many as given, and counts two; the contours are read and freed once.
    unsafe {
        let contours = gpu_engine_run_contours(offsets.as_ptr(), 2, ends.as_ptr(), ends.len(), 3, counts.as_mut_ptr());
        assert!(!contours.is_null(), "{}", last_error());
        assert_eq!(counts, [1, 4], "a contour of four points");
        let (mut starts, mut points) = (vec![0u32; 2], vec![0i32; 8]);
        gpu_engine_run_contours_read(contours, starts.as_mut_ptr(), points.as_mut_ptr());
        assert_eq!((starts, points), (vec![0, 4], vec![0, 0, 3, 0, 3, 2, 0, 2]));
        gpu_engine_run_contours_free(contours);
        let past = [0u32, 5];
        let refused = gpu_engine_run_contours(offsets.as_ptr(), 1, past.as_ptr(), 2, 3, counts.as_mut_ptr());
        assert!(refused.is_null(), "a run past the box");
        assert!(last_error().contains("none of a box 3 wide"), "{}", last_error());
    }
}
