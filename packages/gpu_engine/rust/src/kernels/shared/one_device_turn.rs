//! A test's own device is opened under the tests' turn for one
//! (`testing::a_device_of_its_own` has why: several devices up at once,
//! each compiling and binding, end the process). A test of behaviour
//! passes a test that opens one out of turn — the process dies of it once
//! in forty runs —, so this one reads the sources: each function that
//! opens a device takes the turn, or is on the ledger with why it does
//! not.

use std::cell::RefCell;
use std::collections::BTreeSet;
use std::sync::{RwLock, mpsc};
use std::time::Duration;

use super::source_scan::files_where;
use crate::testing::{a_device_of_its_own, first_engine, turn_of};

/// How a function's body names the opening of a device: the engine's own
/// ways (`open`, `open_sole`, `open_first`, `on`) and the C ABI's.
const OPENS: [&str; 5] =
    ["open_first", "open_sole", "Engine::open(", "Engine::on(", "gpu_engine_open("];

/// The turn, as a body takes it.
const TURN: &str = "a_device_of_its_own(";

/// The functions that open a device with no turn, each with why.
const OUT_OF_TURN: [(&str, &str); 5] = [
    ("gpu_engine_open", "the C ABI's: the app's own device"),
    ("gpu_engine_open_sole", "the C ABI's: the app's own device"),
    ("gpu_engine_open_first", "the C ABI's: `flutter test`'s own device"),
    ("first_engine", "the device every test shares, opened once for the process"),
    ("engine", "`DeviceTurn::engine`: handed to nothing but a turn a test holds"),
];

/// Where `line` — its indent taken off — names the function it begins:
/// after `fn `, with nothing before it but what a signature opens with.
fn begins(line: &str) -> Option<&str> {
    let at = line.find("fn ")?;
    let opens_with = |c: char| c.is_alphanumeric() || " ()\"_".contains(c);
    line[..at].chars().all(opens_with).then(|| &line[at + "fn ".len()..])
}

/// The functions `text` defines, each by its name with its body: the lines
/// from its `fn` to the brace that closes it at the indent it began at —
/// the one line, where it closes on that.
fn functions(text: &str) -> Vec<(String, String)> {
    let lines: Vec<&str> = text.lines().collect();
    let function = |at: usize| {
        let line = lines[at];
        let indent = line.len() - line.trim_start().len();
        let after = begins(&line[indent..])?;
        let named = after.find(|c: char| !(c.is_alphanumeric() || c == '_')).unwrap_or(after.len());
        if line.trim_end().ends_with('}') {
            return Some((after[..named].to_owned(), after[named..].to_owned()));
        }
        let closes = format!("{}}}", " ".repeat(indent));
        let length = lines[at..].iter().position(|line| *line == closes)?;
        Some((after[..named].to_owned(), lines[at + 1..at + length].join("\n")))
    };
    (0..lines.len()).filter_map(function).collect()
}

/// Every function of the sources whose body opens a device, by its name,
/// with whether it takes the turn.
fn openers() -> Vec<(String, bool)> {
    let found = RefCell::new(Vec::new());
    files_where("rs", |text| {
        let opens = |body: &str| OPENS.iter().any(|open| body.contains(open));
        let opening = functions(text).into_iter().filter(|(_, body)| opens(body));
        found.borrow_mut().extend(opening.map(|(name, body)| (name, body.contains(TURN))));
        false
    });
    found.into_inner()
}

#[test]
fn the_turn_is_one_tests_at_a_time_and_outlives_a_test_that_failed_with_it() {
    // A turn of its own, taken as the tests' is (`turn_of`). On the tests'
    // own, each test that opens a device waits as well, and one of them
    // may take it where it is let go, again and again — a lock is no
    // queue: once the door's tests came to take it (21 in device.rs),
    // the land gate's release run went red so, the second thread taking
    // it past the minute this waits (11-14, the-ui-thread-never-enters-
    // the-driver 1a).
    static TURN: RwLock<()> = RwLock::new(());
    let turn = turn_of(&TURN);
    let (took, taken) = mpsc::channel();
    std::thread::scope(|scope| {
        let failing = scope.spawn(move || {
            let _turn = turn_of(&TURN);
            let _ = took.send(());
            panic!("a test that fails with the turn in hand");
        });
        let early = taken.recv_timeout(Duration::from_millis(300));
        assert!(early.is_err(), "a second test took the turn while the first held it");
        drop(turn);
        assert!(taken.recv_timeout(Duration::from_secs(60)).is_ok(), "the turn let go of is taken");
        assert!(failing.join().is_err(), "LIVENESS — the test that took it failed");
    });
    drop(turn_of(&TURN));
}

// The turn is the GPU's (`testing::a_device_of_its_own` has why): while
// a test's own device is up the shared device submits nothing, and what
// it is asked meanwhile goes in once the turn is let go.
#[test]
fn the_shared_device_submits_nothing_while_a_tests_own_is_up() {
    let engine = first_engine();
    let turn = a_device_of_its_own();
    let (went, gone) = mpsc::channel();
    std::thread::scope(|scope| {
        scope.spawn(move || {
            engine.queue.submit([]);
            let _ = went.send(());
        });
        let early = gone.recv_timeout(Duration::from_millis(300));
        assert!(early.is_err(), "the shared device submitted while a test's own was up");
        drop(turn);
        let late = gone.recv_timeout(Duration::from_secs(60));
        assert!(late.is_ok(), "LIVENESS — it submits once the turn is let go");
    });
}

// A test's own device comes up once the shared one is through with what it
// was handed: none of that work runs beside it. Its queue is empty as the
// turn is given — and no submit of its goes in under the turn, so a poll
// that waits for nothing reads it so.
#[test]
fn the_turn_is_given_once_the_shared_device_is_through_with_its_work() {
    let engine = first_engine();
    // Work to be under way still as the turn is asked for: 64 MiB copied
    // sixteen times.
    let size = 64 << 20;
    let buffer = |usage| {
        engine.device().create_buffer(&wgpu::BufferDescriptor {
            label: Some("the shared device's work"),
            size,
            usage,
            mapped_at_creation: false,
        })
    };
    let (from, to) = (buffer(wgpu::BufferUsages::COPY_SRC), buffer(wgpu::BufferUsages::COPY_DST));
    let mut encoder = engine.device().create_command_encoder(&Default::default());
    for _ in 0..16 {
        encoder.copy_buffer_to_buffer(&from, 0, &to, 0, size);
    }
    engine.queue.submit([encoder.finish()]);
    let _turn = a_device_of_its_own();
    let status = engine.device().poll(wgpu::PollType::Poll).expect("poll");
    assert!(status.is_queue_empty(), "the turn was given with the shared device at work");
}

#[test]
fn a_function_reads_as_its_name_and_its_body() {
    let text = "/// Not a fn here.\nimpl Kept {\n    pub(crate) fn first() -> Option<Self> {\n        \
                Self::of(a, b)\n    }\n}\n\n#[test]\nfn a_test() {\n    let made = taken(Kept::first);\n}\n\
                fn one_line() { Kept::of(7) }\n";
    let read = functions(text);
    let names: Vec<&str> = read.iter().map(|(name, _)| name.as_str()).collect();
    assert_eq!(names, ["first", "a_test", "one_line"]);
    assert_eq!(read[0].1, "        Self::of(a, b)");
    assert_eq!(read[1].1, "    let made = taken(Kept::first);");
    assert!(read[2].1.contains("Kept::of(7)"));
}

#[test]
fn a_tests_own_device_is_opened_under_the_turn_or_is_on_the_ledger() {
    let openers = openers();
    let named = |name: &str| openers.iter().any(|(opener, _)| opener == name);
    assert!(named("first_engine"), "LIVENESS — the scan finds the functions that open a device");
    assert!(
        openers.iter().any(|(_, turn)| *turn),
        "LIVENESS — the scan finds a function that takes the turn"
    );
    let stays = |name: &str| OUT_OF_TURN.iter().any(|(stays, _)| *stays == name);
    let off: BTreeSet<&str> = openers
        .iter()
        .filter(|(name, turn)| !turn && !stays(name))
        .map(|(name, _)| name.as_str())
        .collect();
    assert!(
        off.is_empty(),
        "a device opened out of turn — take `testing::a_device_of_its_own()` first, and open \
         it by the turn's `engine()` where an engine is all it needs: {off:?}"
    );
    for (name, why) in OUT_OF_TURN {
        // One function by the name: a second would pass under the first's why.
        let so_named = openers.iter().filter(|(opener, _)| opener == name).count();
        assert_eq!(so_named, 1, "{name} is on the ledger for one function that opens a device ({why})");
    }
}
