//! The ledger's ring and what it answers, on answers worked out here: the
//! C (qa_pen_ledger_apple.m) is compiled into the Apple app alone, never
//! beside the engine, so there is no C to hold it to.

use crate::ledger::{
    ESTIMATED, ESTIMATED_FINAL, Ledger, MEASURED, NO_PRESSURE, RING, Sample, UNREPORTED, micros,
    state_of,
};

/// UITouchPropertyForce and UITouchPropertyAltitude.
const FORCE: isize = 1 << 0;
const ALTITUDE: isize = 1 << 2;

fn empty() -> Box<Ledger> {
    Box::new(Ledger::EMPTY)
}

/// A sample Flutter stamped `micros`, whose force `value` reads as `state`.
fn force(micros: i64, value: f64, state: i32) -> Sample {
    Sample {
        micros,
        value,
        state,
        altitude_state: UNREPORTED,
        tilt_state: UNREPORTED,
        ..Sample::default()
    }
}

/// A sample UIKit numbered `key`: force 0.33 read as `state`, altitude 0.2
/// read as `altitude_state`.
fn numbered(micros: i64, key: Option<i64>, state: i32, altitude_state: i32) -> Sample {
    Sample {
        micros,
        update_index: key,
        value: 0.33,
        state,
        altitude: 0.2,
        altitude_state,
        tilt_state: UNREPORTED,
        ..Sample::default()
    }
}

#[test]
fn a_timestamp_is_keyed_as_flutter_stamps_it_truncated_to_the_microsecond() {
    assert_eq!(micros(1.5), 1_500_000);
    assert_eq!(micros(1001.25), 1_001_250_000);
    // 2000000.9 microseconds: cut, not rounded.
    assert_eq!(micros(2.0000009), 2_000_000);
}

#[test]
fn uikit_says_each_property_is_measured_awaited_or_a_final_estimate() {
    assert_eq!(state_of(0, 0, FORCE), MEASURED);
    assert_eq!(state_of(FORCE, FORCE, FORCE), ESTIMATED);
    assert_eq!(state_of(0, FORCE, FORCE), ESTIMATED, "an update coming is an estimate");
    // H43: an estimate no update will correct is still no measurement.
    assert_eq!(state_of(FORCE, 0, FORCE), ESTIMATED_FINAL);
    // Another property's word is not this one's.
    assert_eq!(state_of(ALTITUDE, ALTITUDE, FORCE), MEASURED);
    assert_eq!(state_of(FORCE | ALTITUDE, ALTITUDE, FORCE), ESTIMATED_FINAL);
    assert_eq!(state_of(FORCE | ALTITUDE, ALTITUDE, ALTITUDE), ESTIMATED);
}

#[test]
fn the_force_reads_as_its_value_or_why_there_is_none() {
    let mut ledger = empty();
    assert_eq!(ledger.value(1), -1.0, "an empty ledger");
    ledger.record(force(1, 0.75, MEASURED));
    ledger.record(force(2, 0.75, ESTIMATED));
    ledger.record(force(3, 0.75, NO_PRESSURE));
    ledger.record(force(4, 0.75, ESTIMATED_FINAL));
    ledger.record(force(5, 0.75, UNREPORTED));
    assert_eq!(ledger.value(1), 0.75);
    assert_eq!(ledger.value(2), -2.0);
    assert_eq!(ledger.value(3), -3.0);
    assert_eq!(ledger.value(4), -4.0);
    // Any other word reads the value, as the C's did.
    assert_eq!(ledger.value(5), 0.75);
    assert_eq!(ledger.value(6), -1.0, "a stamp it never heard");
}

#[test]
fn the_altitude_reads_as_its_radians_or_why_there_are_none() {
    let mut ledger = empty();
    assert_eq!(ledger.altitude(1), -1.0, "an empty ledger");
    let states = [MEASURED, ESTIMATED, ESTIMATED_FINAL, UNREPORTED, NO_PRESSURE];
    for (micros, state) in (1..).zip(states) {
        let sample = force(micros, 0.5, MEASURED);
        ledger.record(Sample { altitude: 1.25, altitude_state: state, ..sample });
    }
    assert_eq!(ledger.altitude(1), 1.25);
    assert_eq!(ledger.altitude(2), -2.0);
    assert_eq!(ledger.altitude(3), -4.0);
    // A platform that reports none, and a word the altitude never takes.
    assert_eq!(ledger.altitude(4), -1.0);
    assert_eq!(ledger.altitude(5), -1.0);
    assert_eq!(ledger.altitude(6), -1.0, "a stamp it never heard");
}

#[test]
fn a_tilt_is_read_only_as_appkit_measured_it() {
    let mut ledger = empty();
    assert_eq!(ledger.tilt(1), None, "an empty ledger");
    let leaning = |micros, state| Sample {
        tilt: (0.25, -0.5),
        tilt_state: state,
        ..force(micros, 0.5, MEASURED)
    };
    ledger.record(leaning(1, MEASURED));
    ledger.record(leaning(2, UNREPORTED));
    ledger.record(leaning(3, ESTIMATED));
    assert_eq!(ledger.tilt(1), Some((0.25, -0.5)));
    assert_eq!(ledger.tilt(2), None);
    assert_eq!(ledger.tilt(3), None);
    assert_eq!(ledger.tilt(4), None, "a stamp it never heard");
}

#[test]
fn of_two_records_of_one_stamp_the_newer_answers() {
    let mut ledger = empty();
    ledger.record(force(99, 0.1, MEASURED));
    ledger.record(force(99, 0.2, MEASURED));
    assert_eq!(ledger.value(99), 0.2);
}

#[test]
fn the_ring_keeps_its_newest_512_and_forgets_the_rest() {
    let mut ledger = empty();
    for micros in 0..=RING as i64 {
        ledger.record(force(micros, micros as f64 / 1000.0, MEASURED));
    }
    assert_eq!(ledger.value(0), -1.0, "the 513th record took the first one's place");
    assert_eq!(ledger.value(1), 0.001);
    assert_eq!(ledger.value(512), 0.512);
}

#[test]
fn the_newer_answers_across_the_rings_seam() {
    // The oldest record sits where the next one goes, and shares the
    // newest's stamp.
    let mut ledger = empty();
    ledger.record(force(99, 0.1, MEASURED));
    for micros in 1..RING as i64 - 1 {
        ledger.record(force(1000 + micros, 0.5, MEASURED));
    }
    ledger.record(force(99, 0.2, MEASURED));
    assert_eq!(ledger.value(99), 0.2);
    // One more: the newest is in the ring's first place, the next older at
    // its end.
    ledger.record(force(99, 0.3, MEASURED));
    assert_eq!(ledger.value(99), 0.3);
}

#[test]
fn uikits_later_word_replaces_the_estimates_it_numbered() {
    let mut ledger = empty();
    ledger.record(numbered(1, Some(7), ESTIMATED, ESTIMATED));
    ledger.update(7, Some(0.9), Some(1.1));
    assert_eq!(ledger.value(1), 0.9);
    assert_eq!(ledger.altitude(1), 1.1);
}

#[test]
fn a_property_still_awaited_keeps_its_estimate() {
    let mut ledger = empty();
    ledger.record(numbered(1, Some(7), ESTIMATED, ESTIMATED));
    ledger.update(7, Some(0.9), None);
    assert_eq!((ledger.value(1), ledger.altitude(1)), (0.9, -2.0));
    let mut ledger = empty();
    ledger.record(numbered(1, Some(7), ESTIMATED, ESTIMATED));
    ledger.update(7, None, Some(1.1));
    assert_eq!((ledger.value(1), ledger.altitude(1)), (-2.0, 1.1));
}

#[test]
fn only_an_estimate_awaiting_its_update_is_replaced() {
    let mut ledger = empty();
    ledger.record(numbered(1, Some(7), MEASURED, MEASURED));
    ledger.record(numbered(2, Some(7), ESTIMATED_FINAL, ESTIMATED_FINAL));
    ledger.update(7, Some(0.9), Some(1.1));
    assert_eq!((ledger.value(1), ledger.altitude(1)), (0.33, 0.2));
    assert_eq!((ledger.value(2), ledger.altitude(2)), (-4.0, -4.0));
}

#[test]
fn every_record_of_the_number_is_updated_and_no_other() {
    let mut ledger = empty();
    ledger.record(numbered(1, Some(7), ESTIMATED, ESTIMATED));
    ledger.record(numbered(2, Some(7), ESTIMATED, ESTIMATED));
    ledger.record(numbered(3, Some(8), ESTIMATED, ESTIMATED));
    ledger.record(numbered(4, None, ESTIMATED, ESTIMATED));
    ledger.update(7, Some(0.9), Some(1.1));
    assert_eq!((ledger.value(1), ledger.altitude(1)), (0.9, 1.1));
    assert_eq!((ledger.value(2), ledger.altitude(2)), (0.9, 1.1));
    assert_eq!((ledger.value(3), ledger.altitude(3)), (-2.0, -2.0));
    // A sample UIKit gave no number is no other's. (The C kept -1 for none,
    // and an update UIKit numbered -1 would have reached it.)
    ledger.update(-1, Some(0.9), Some(1.1));
    assert_eq!((ledger.value(4), ledger.altitude(4)), (-2.0, -2.0));
}
