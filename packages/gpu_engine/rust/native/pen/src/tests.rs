//! The pen held to the C it replaces (qa_tablet_win.c and qa_penraw_win.c,
//! through qa_tablet beside the engine — native/oracle) and to answers
//! worked out here, so two readers that agree on a wrong answer still fail:
//! the HID axis law on the C's own test's cases (qa_pen_hid_axis_test.c);
//! the Wintab half on the same packets from one driver (wintab_fake); the
//! Raw Input half on its life without a report — a report comes from a
//! digitizer alone, which no test has — and its reading of one on the HID
//! parser's answers made up here. The ledger and Apple's readers have no C
//! beside the engine to be held to (qa_pen_ledger_apple.m is compiled into
//! the app alone): their answers are worked out here.

#[cfg(target_vendor = "apple")]
mod apple;
mod hid_axis;
mod ledger;
#[cfg(windows)]
mod raw;
mod report;
#[cfg(windows)]
mod wintab;
