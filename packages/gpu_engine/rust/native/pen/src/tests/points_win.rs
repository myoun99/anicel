//! What a mouse message hands on of the moves `GetMouseMovePointsEx` keeps,
//! on answers worked out here (I-110 · F-600).

use crate::points::Lost;
use crate::points_win::{Move, handed_on, history_near, mouse_lost, moves_since, told_alike};

/// The message's own move: the newest of every history here.
const OWN: Move = (50, 0, 105);

#[test]
fn a_message_hands_the_moves_since_the_one_written_newest_first() {
    let history = [OWN, (40, 0, 104), (30, 0, 103), (20, 0, 102)];
    assert_eq!(moves_since(OWN, &history, Some((30, 0, 103))), [OWN, (40, 0, 104)]);
}

#[test]
fn a_history_that_does_not_keep_the_move_written_is_cut_at_its_time() {
    // I-110: the move written was one Windows made, kept by no history —
    // what lies past its time is the cursor's from seconds before.
    let history = [OWN, (40, 0, 104), (900, 700, 90), (910, 700, 80)];
    assert_eq!(moves_since(OWN, &history, Some((45, 3, 100))), [OWN, (40, 0, 104)]);
}

#[test]
fn the_first_move_of_all_hands_its_own_alone() {
    let history = [OWN, (40, 0, 104), (900, 700, 90)];
    assert_eq!(moves_since(OWN, &history, None), [OWN]);
}

// 🔬Release, 11-19: the kept-moves test run first of all handed its own
// move alone, 3 times in 60.
#[test]
fn the_first_message_of_all_hands_on_every_move_kept_since_the_press() {
    let kept = [OWN, (40, 0, 104), (30, 0, 103)];
    assert_eq!(handed_on(OWN, &kept, None, None), kept);
    assert_eq!(handed_on(OWN, &kept, Some(3), None), [OWN], "a history read, its own alone");
}

#[test]
fn what_was_kept_is_cut_at_the_move_written_as_a_history_is() {
    let kept = [OWN, (40, 0, 104), (30, 0, 103)];
    assert_eq!(handed_on(OWN, &kept, None, Some((40, 0, 104))), [OWN]);
    assert_eq!(handed_on(OWN, &kept, None, Some((20, 0, 102))), kept);
}

#[test]
fn a_move_where_the_mouse_stood_or_one_with_no_history_hands_its_own() {
    assert_eq!(moves_since(OWN, &[OWN, (40, 0, 104)], Some(OWN)), [OWN]);
    assert_eq!(moves_since(OWN, &[], Some((40, 0, 104))), [OWN]);
}

#[test]
fn a_move_of_the_written_ones_millisecond_before_it_is_newer() {
    // A mouse that reports faster than a millisecond keeps several there.
    let history = [(60, 0, 104), (50, 0, 103), (40, 0, 103), (30, 0, 103)];
    assert_eq!(
        moves_since((60, 0, 104), &history, Some((40, 0, 103))),
        [(60, 0, 104), (50, 0, 103)],
    );
}

/// The `found` moves along a row the OS hands back from the one asked, the
/// newest first at `newest` milliseconds and each a millisecond before.
fn found_back(newest: u32, found: u32) -> Vec<Move> {
    (0..found).map(|back| (newest as i32 - back as i32, 0, newest - back)).collect()
}

// 🔬Surface Pro 11, 11-19: asked at the cursor while moves come, the OS
// found 62–63 in most reads — the moves after the one asked are not handed
// back, and the move written is gone all the same.
#[test]
fn a_history_whose_every_move_found_is_newer_lost_the_moves_before_it() {
    let written = Some((0, 0, 1));
    assert_eq!(mouse_lost(&found_back(200, 64), 64, written), Some(Lost::Full));
    assert_eq!(mouse_lost(&found_back(200, 63), 63, written), Some(Lost::Full), "asked behind the newest");
    assert_eq!(mouse_lost(&found_back(200, 12), 12, written), Some(Lost::Full), "asked far behind it");
}

#[test]
fn a_history_that_reaches_the_move_written_lost_nothing() {
    let history = found_back(200, 64);
    assert_eq!(mouse_lost(&history, 64, Some(history[63])), None, "the move written was in it");
    assert_eq!(mouse_lost(&history[..12], 12, Some((0, 0, 190))), None, "one older than it was");
    assert_eq!(mouse_lost(&[OWN], 1, Some(OWN)), None, "the move written, found once more");
    assert_eq!(mouse_lost(&[], 0, Some(OWN)), None, "none found");
}

#[test]
fn a_history_unread_lost_what_came_before_the_message() {
    assert_eq!(mouse_lost(&[], -1, Some((0, 0, 1))), Some(Lost::Unread));
}

#[test]
fn the_first_move_of_all_loses_nothing() {
    assert_eq!(mouse_lost(&found_back(200, 64), 64, None), None);
    assert_eq!(mouse_lost(&[], -1, None), None);
}

#[test]
fn the_message_clock_wraps() {
    let near_the_end = u32::MAX - 1;
    let history = [(70, 0, 2), (60, 0, 0), (50, 0, near_the_end - 4)];
    assert_eq!(
        moves_since((70, 0, 2), &history, Some((55, 0, near_the_end))),
        [(70, 0, 2), (60, 0, 0)],
    );
}

#[test]
fn the_move_written_is_met_a_pixel_from_where_it_was_written() {
    // H61: the history tells the move written at (31, 1), rounded its own
    // way; the move before it of the same millisecond went on already.
    let history = [OWN, (40, 0, 104), (31, 1, 104), (20, 0, 104)];
    assert_eq!(moves_since(OWN, &history, Some((30, 0, 104))), [OWN, (40, 0, 104)]);
}

#[test]
fn a_move_two_pixels_from_the_written_one_is_another() {
    let history = [OWN, (32, 0, 104), (30, 0, 104)];
    assert_eq!(moves_since(OWN, &history, Some((30, 0, 104))), [OWN, (32, 0, 104)]);
    assert!(!told_alike((30, 0, 104), (30, 2, 104)));
    assert!(!told_alike((30, 0, 104), (31, 1, 105)), "another millisecond");
    assert!(told_alike((30, 0, 104), (29, 1, 104)));
}

#[test]
fn a_history_is_asked_at_its_own_point_first_then_a_pixel_round() {
    let mut asked = Vec::new();
    let found = history_near((50, 0, 105), |place| {
        asked.push(place);
        if place == (49, 1, 105) { 7 } else { -1 }
    });
    assert_eq!(found, 7);
    assert_eq!(asked.first(), Some(&(50, 0, 105)), "its own point first");
    assert_eq!(asked.last(), Some(&(49, 1, 105)), "and no more once found");
    assert!(asked.iter().all(|&place| told_alike(place, (50, 0, 105))));
}

#[test]
fn a_history_found_nowhere_round_its_point_is_refused() {
    let mut asks = 0;
    assert_eq!(history_near((50, 0, 105), |_| { asks += 1; -1 }), -1);
    assert_eq!(asks, 9, "its point and the eight a pixel round it");
}
