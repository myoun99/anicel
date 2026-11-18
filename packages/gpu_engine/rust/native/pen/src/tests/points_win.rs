//! What a mouse message hands on of the moves `GetMouseMovePointsEx` keeps,
//! on answers worked out here (I-110 · F-600).

use crate::points::Lost;
use crate::points_win::{Move, mouse_lost, moves_since};

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

#[test]
fn a_full_history_handed_on_whole_lost_the_moves_before_it() {
    let written = Some((0, 0, 1));
    assert_eq!(mouse_lost(64, 64, written), Some(Lost::Full));
    assert_eq!(mouse_lost(64, 63, written), None, "the move written was in it");
    assert_eq!(mouse_lost(12, 12, written), None, "a history not full kept them all");
}

#[test]
fn a_history_unread_lost_what_came_before_the_message() {
    assert_eq!(mouse_lost(-1, 1, Some((0, 0, 1))), Some(Lost::Unread));
}

#[test]
fn the_first_move_of_all_loses_nothing() {
    assert_eq!(mouse_lost(64, 64, None), None);
    assert_eq!(mouse_lost(-1, 1, None), None);
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
