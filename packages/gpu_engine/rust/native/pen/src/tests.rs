//! The pen held to answers worked out here and to what the C it replaced
//! (qa_tablet_win.c and qa_penraw_win.c) was measured to answer, so a reader
//! that changes its answer fails: the HID axis law on the C's own test's
//! cases (qa_pen_hid_axis_test.c); the Wintab half on packets from a driver
//! of its own (wintab_fake); the Raw Input half on its life without a report
//! — a report comes from a digitizer alone, which no test has — and its
//! reading of one on the HID parser's answers made up here. The ledger and
//! Apple's readers are held to answers worked out here.

#[cfg(target_vendor = "apple")]
mod apple;
mod hid_axis;
mod ledger;
#[cfg(windows)]
mod mouse_kept;
mod points;
#[cfg(windows)]
mod points_win;
#[cfg(windows)]
mod raw;
#[cfg(windows)]
mod receiver;
mod report;
#[cfg(windows)]
mod wintab;

/// The ABI the app's bridge asks a reader for, as it declares `name`
/// (lib/src/native/qa_tablet_bridge.dart) — the number each half must say.
#[cfg(windows)]
fn bridge_asks(name: &str) -> i32 {
    let dart = include_str!("../../../../../../lib/src/native/qa_tablet_bridge.dart");
    let declared = format!("static const int {name} = ");
    let line = dart.lines().map(str::trim_start).find(|line| line.starts_with(&declared)).expect(name);
    line.trim_end_matches(';').rsplit(' ').next().and_then(|value| value.parse().ok()).expect(line)
}

/// The number the app's bridge reads for `qat_open`'s answer `name`, as its
/// `QaTabletOpen` declares it (lib/src/native/qa_tablet_bridge.dart).
#[cfg(windows)]
fn bridge_reads(name: &str) -> i32 {
    let dart = include_str!("../../../../../../lib/src/native/qa_tablet_bridge.dart");
    let declared = format!("{name}(");
    let line = dart.lines().map(str::trim_start).find(|line| line.starts_with(&declared)).expect(name);
    line[declared.len()..].split(')').next().and_then(|value| value.parse().ok()).expect(line)
}
