//! The mouse's history kept off the UI's thread (mouse_kept.rs): what a
//! read keeps and loses, and what a message takes of it — on histories made
//! up here as Windows hands them, the newest first.

use std::collections::VecDeque;

use windows::Win32::Foundation::WPARAM;
use windows::Win32::UI::WindowsAndMessaging::{
    WM_CAPTURECHANGED, WM_LBUTTONDOWN, WM_LBUTTONUP, WM_MOUSEMOVE, WM_RBUTTONDBLCLK, WM_RBUTTONUP,
    WM_XBUTTONDOWN,
};

use crate::mouse_kept::{Kept, history_for, keeping_after};
use crate::points::Lost;
use crate::points_win::Move;

/// The mouse's `n`-th move along a row, a millisecond after the one before.
fn moved(n: i32) -> Move {
    (n, 0, 1000 + n as u32)
}

/// What Windows keeps once the mouse made its `newest` move: the 64 newest,
/// the newest first.
fn history_at(newest: i32) -> Vec<Move> {
    (0..=newest).rev().take(64).map(moved).collect()
}

/// The moves `from..=to`, the oldest first.
fn moves(from: i32, to: i32) -> VecDeque<Move> {
    (from..=to).map(moved).collect()
}

#[test]
fn a_read_keeps_the_moves_past_the_newest_kept_the_oldest_first() {
    let mut kept = Kept::from(moved(0));
    assert_eq!(kept.hear(&history_at(3), 4), None);
    assert_eq!((kept.moves.clone(), kept.newest), (moves(1, 3), moved(3)));
    assert_eq!(kept.hear(&history_at(5), 6), None);
    assert_eq!((kept.moves.clone(), kept.newest), (moves(1, 5), moved(5)));
    assert_eq!(kept.hear(&history_at(5), 6), None);
    assert_eq!(kept.moves, moves(1, 5), "nothing past the newest kept");
}

#[test]
fn the_press_told_a_pixel_off_is_the_move_kept_from() {
    let mut kept = Kept::from((0, 1, 1000));
    assert_eq!(kept.hear(&history_at(3), 4), None);
    assert_eq!(kept.moves, moves(1, 3));
}

#[test]
fn a_full_history_with_none_of_it_kept_lost_the_moves_before_it() {
    let mut kept = Kept::from(moved(0));
    assert_eq!(kept.hear(&history_at(100), 64), Some(Lost::Full));
    assert_eq!(kept.moves, moves(37, 100), "what there was, kept");
}

#[test]
fn a_read_refused_keeps_nothing_and_loses_nothing() {
    let mut kept = Kept::from(moved(0));
    assert_eq!(kept.hear(&[], -1), None, "the next read is a moment away");
    assert_eq!(kept, Kept::from(moved(0)));
}

#[test]
fn a_message_takes_the_moves_through_its_own_and_leaves_the_rest() {
    let mut kept = Kept::from(moved(0));
    kept.hear(&history_at(5), 6);
    assert_eq!(kept.take_through(moved(3)), Some(vec![moved(3), moved(2), moved(1)]));
    assert_eq!(kept.moves, moves(4, 5), "the next messages'");
    assert_eq!(kept.take_through((5, 1, 1005)), Some(vec![moved(5), moved(4)]), "a pixel off");
    assert_eq!(kept.take_through(moved(9)), None, "not kept");
}

// 🚨The UI's thread stood for 200 moves, three times the 64 Windows keeps:
// read every 50 off it, the message hands every one of them on.
#[test]
fn a_ui_that_stood_for_200_moves_hands_all_200() {
    let mut kept = Kept::from(moved(0));
    for newest in [50, 100, 150, 200] {
        let history = history_at(newest);
        assert_eq!(kept.hear(&history, history.len() as i32), None, "read at {newest}");
    }
    let (history, found) = history_for(moved(200), Some(&mut kept), |_| panic!("the OS asked"));
    assert_eq!(history, (1..=200).rev().map(moved).collect::<Vec<_>>());
    assert_eq!(found, None, "no read of the message's own to count");
}

#[test]
fn a_message_whose_move_was_not_kept_reads_the_os_s_own() {
    let os = |own: Move| (history_at(own.0), 6);
    let mut kept = Kept::from(moved(0));
    assert_eq!(history_for(moved(5), Some(&mut kept), os), (history_at(5), Some(6)));
    assert_eq!(history_for(moved(5), None, os), (history_at(5), Some(6)), "no button down");
}

#[test]
fn a_mouse_press_keeps_and_the_last_button_let_go_or_the_capture_lost_ends_it() {
    let none = WPARAM(0);
    assert_eq!(keeping_after(WM_LBUTTONDOWN, none, false), Some(true));
    assert_eq!(keeping_after(WM_RBUTTONDBLCLK, none, false), Some(true));
    assert_eq!(keeping_after(WM_XBUTTONDOWN, none, false), Some(true));
    assert_eq!(keeping_after(WM_LBUTTONDOWN, none, true), None, "a pen's or a finger's");
    assert_eq!(keeping_after(WM_RBUTTONUP, WPARAM(0x0001), false), None, "the left still down");
    assert_eq!(keeping_after(WM_LBUTTONUP, none, false), Some(false));
    assert_eq!(keeping_after(WM_CAPTURECHANGED, none, false), Some(false));
    assert_eq!(keeping_after(WM_MOUSEMOVE, none, false), None);
}
