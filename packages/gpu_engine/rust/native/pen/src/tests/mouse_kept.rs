//! The mouse's history kept off the UI's thread (mouse_kept.rs): what a
//! read keeps and loses, when each move it keeps was made, and what a
//! message takes of it — on histories made up here as Windows hands them,
//! the newest first.

use windows::Win32::Foundation::WPARAM;
use windows::Win32::UI::WindowsAndMessaging::{
    WM_CAPTURECHANGED, WM_LBUTTONDOWN, WM_LBUTTONUP, WM_MOUSEMOVE, WM_RBUTTONDBLCLK, WM_RBUTTONUP,
    WM_XBUTTONDOWN,
};

use crate::mouse_kept::{Kept, Told, history_for, keeping_after};
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
fn moves(from: i32, to: i32) -> Vec<Move> {
    (from..=to).map(moved).collect()
}

/// What `kept` keeps, without when.
fn kept_moves(kept: &Kept) -> Vec<Move> {
    kept.moves.iter().map(|&(at, _)| at).collect()
}

#[test]
fn a_read_keeps_the_moves_past_the_newest_kept_the_oldest_first() {
    let mut kept = Kept::from(moved(0), 0);
    assert_eq!(kept.hear(&history_at(3), 4, 30), None);
    assert_eq!((kept_moves(&kept), kept.newest), (moves(1, 3), moved(3)));
    assert_eq!(kept.hear(&history_at(5), 6, 50), None);
    assert_eq!((kept_moves(&kept), kept.newest), (moves(1, 5), moved(5)));
    assert_eq!(kept.hear(&history_at(5), 6, 60), None);
    assert_eq!(kept_moves(&kept), moves(1, 5), "nothing past the newest kept");
}

// 🚨The history's clock steps 15.6 ms: a move kept is at a time of its own —
// among those heard with it, evenly, since the read before, the newest at
// the read — never on its millisecond (the steadied line stands still on a
// time that does not go on).
#[test]
fn a_move_kept_is_timed_evenly_since_the_read_before_the_newest_at_the_read() {
    let mut kept = Kept::from(moved(0), 1_000);
    kept.hear(&history_at(4), 5, 5_000);
    kept.hear(&history_at(4), 5, 6_000);
    kept.hear(&history_at(6), 7, 8_000);
    let times: Vec<i64> = kept.moves.iter().map(|&(_, at)| at).collect();
    assert_eq!(times, [2_000, 3_000, 4_000, 5_000, 7_000, 8_000], "none heard at 6 000: made after it");
}

#[test]
fn a_read_refused_keeps_nothing_loses_nothing_and_says_nothing_of_when() {
    let mut kept = Kept::from(moved(0), 1_000);
    assert_eq!(kept.hear(&[], -1, 5_000), None, "the next read is a moment away");
    assert_eq!(kept, Kept::from(moved(0), 1_000));
    kept.hear(&history_at(2), 3, 9_000);
    assert_eq!(kept.moves.iter().map(|&(_, at)| at).collect::<Vec<_>>(), [5_000, 9_000]);
}

#[test]
fn the_press_told_a_pixel_off_is_the_move_kept_from() {
    let mut kept = Kept::from((0, 1, 1000), 0);
    assert_eq!(kept.hear(&history_at(3), 4, 30), None);
    assert_eq!(kept_moves(&kept), moves(1, 3));
}

#[test]
fn a_full_history_with_none_of_it_kept_lost_the_moves_before_it() {
    let mut kept = Kept::from(moved(0), 0);
    assert_eq!(kept.hear(&history_at(100), 64, 1_000), Some(Lost::Full));
    assert_eq!(kept_moves(&kept), moves(37, 100), "what there was, kept");
}

// 🔬Surface Pro 11, 11-19: a read 218 ms after the one before, at the
// cursor while moves came, found 63 — every one newer than the newest
// kept, and none counted lost.
#[test]
fn a_read_that_found_fewer_than_64_every_one_newer_lost_the_moves_before_it() {
    let mut kept = Kept::from(moved(0), 0);
    let behind_the_newest = &history_at(100)[1..];
    assert_eq!(kept.hear(behind_the_newest, 63, 1_000), Some(Lost::Full));
    assert_eq!(kept_moves(&kept), moves(37, 99), "what there was, kept");
}

#[test]
fn a_message_takes_the_moves_through_its_own_and_leaves_the_rest() {
    let mut kept = Kept::from(moved(0), 0);
    kept.hear(&history_at(5), 6, 50);
    let taken = |taken: Option<Vec<(Move, i64)>>| {
        taken.map(|moves| moves.into_iter().map(|(at, _)| at).collect::<Vec<_>>())
    };
    assert_eq!(taken(kept.take_through(moved(3))), Some(vec![moved(3), moved(2), moved(1)]));
    assert_eq!(kept_moves(&kept), moves(4, 5), "the next messages'");
    assert_eq!(taken(kept.take_through((5, 1, 1005))), Some(vec![moved(5), moved(4)]), "a pixel off");
    assert_eq!(kept.take_through(moved(9)), None, "not kept");
}

// 🚨The UI's thread stood for 200 moves, three times the 64 Windows keeps:
// read every 50 off it, the message hands every one of them on — each at a
// time of its own, going on.
#[test]
fn a_ui_that_stood_for_200_moves_hands_all_200_each_at_its_own_time() {
    let mut kept = Kept::from(moved(0), 0);
    for newest in [50, 100, 150, 200] {
        let history = history_at(newest);
        let found = history.len() as i32;
        assert_eq!(kept.hear(&history, found, i64::from(newest) * 1_000), None, "read at {newest}");
    }
    let Told::Kept(taken) = history_for(moved(200), Some(&mut kept), |_| panic!("the OS asked")) else {
        panic!("not what was kept");
    };
    let (history, times): (Vec<Move>, Vec<i64>) = taken.into_iter().rev().unzip();
    assert_eq!(history, moves(1, 200));
    assert!(times.windows(2).all(|two| two[0] < two[1]), "each later than the one before: {times:?}");
    assert_eq!((times[0], times[199]), (1_000, 200_000));
}

#[test]
fn a_message_whose_move_was_not_kept_reads_the_os_s_own() {
    let os = |own: Move| (history_at(own.0), 6);
    let mut kept = Kept::from(moved(0), 0);
    assert_eq!(history_for(moved(5), Some(&mut kept), os), Told::Read(history_at(5), 6));
    assert_eq!(history_for(moved(5), None, os), Told::Read(history_at(5), 6), "no button down");
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
