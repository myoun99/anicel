//! THE PEN LEDGER (H43) — what the platform said about each pen sample,
//! written down BEFORE Flutter hears of it, and read by the brush
//! synchronously, by the sample's own timestamp.
//!
//! Why a ledger and not a channel: a channel message and a pointer event
//! travel two queues with no order between them, and the brush has to know
//! about THIS sample while it handles THIS sample. A write that happens
//! before the event reaches Flutter, read through FFI while the event is
//! being handled, cannot arrive late.
//!
//! No platform in it: Apple's readers write it (apple.rs), and its cases
//! run on every host.

use std::sync::{Mutex, MutexGuard, PoisonError};

/// What the platform said of one property of a sample.
pub(crate) const MEASURED: i32 = 0;
pub(crate) const ESTIMATED: i32 = 1;
pub(crate) const NO_PRESSURE: i32 = 2;
/// The platform never reports this property.
pub(crate) const UNREPORTED: i32 = 3;
/// UIKit's estimate that no update will correct: `estimatedProperties`
/// names it and `estimatedPropertiesExpectingUpdates` does not, which Apple
/// calls final. Final, but nothing measured it (H43, build 1065).
pub(crate) const ESTIMATED_FINAL: i32 = 4;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub(crate) struct Sample {
    pub(crate) micros: i64,
    /// UIKit's estimationUpdateIndex; None when there is none.
    pub(crate) update_index: Option<i64>,
    /// Force (iOS) or pressure (macOS).
    pub(crate) value: f64,
    pub(crate) state: i32,
    /// Radians from the surface (iOS only).
    pub(crate) altitude: f64,
    pub(crate) altitude_state: i32,
    /// AppKit's scaled tilt, -1..1 each way (macOS only).
    pub(crate) tilt: (f64, f64),
    pub(crate) tilt_state: i32,
}

/// Far more samples than one stroke's wait can span: the brush asks about a
/// sample within milliseconds of recording it.
pub(crate) const RING: usize = 512;

pub(crate) struct Ledger {
    ring: [Option<Sample>; RING],
    next: usize,
}

static LEDGER: Mutex<Ledger> = Mutex::new(Ledger::EMPTY);

/// The app's ledger.
pub(crate) fn ledger() -> MutexGuard<'static, Ledger> {
    LEDGER.lock().unwrap_or_else(PoisonError::into_inner)
}

/// The key Flutter itself stamps the pointer event with: the platform
/// timestamp times 1000000, truncated into an integer (iOS:
/// FlutterViewController's dispatchTouches; macOS: the embedder's mouse
/// events). The same arithmetic here makes the two keys equal.
pub(crate) fn micros(timestamp: f64) -> i64 {
    (timestamp * 1_000_000.0) as i64
}

/// What UIKit says of `property` on one sample: an estimate it will send
/// the measured value for, an estimate it never will, or a measurement.
///
/// 🚨H43, build 1065: the ledger asked `estimatedPropertiesExpectingUpdates`
/// alone, so an estimate with no update coming read as MEASURED — and the
/// constant 0.33 the Pencil's first samples carry was painted as it always
/// had been. `estimatedProperties` is the set that says a value is an
/// estimate at all.
pub(crate) fn state_of(estimated: isize, awaited: isize, property: isize) -> i32 {
    if awaited & property != 0 {
        ESTIMATED
    } else if estimated & property != 0 {
        ESTIMATED_FINAL
    } else {
        MEASURED
    }
}

impl Ledger {
    pub(crate) const EMPTY: Self = Self { ring: [None; RING], next: 0 };

    pub(crate) fn record(&mut self, sample: Sample) {
        self.ring[self.next] = Some(sample);
        self.next = (self.next + 1) % RING;
    }

    /// The newest record Flutter stamped `micros`.
    fn find(&self, micros: i64) -> Option<&Sample> {
        (1..=RING)
            .filter_map(|back| self.ring[(self.next + RING - back) % RING].as_ref())
            .find(|sample| sample.micros == micros)
    }

    /// UIKit's later word on the samples it numbered `key`: a property it
    /// no longer means to update — `force` or `altitude` given — replaces
    /// an estimate of it.
    pub(crate) fn update(&mut self, key: i64, force: Option<f64>, altitude: Option<f64>) {
        for sample in self.ring.iter_mut().flatten() {
            if sample.update_index != Some(key) {
                continue;
            }
            if let Some(force) = force.filter(|_| sample.state == ESTIMATED) {
                sample.value = force;
                sample.state = MEASURED;
            }
            if let Some(altitude) = altitude.filter(|_| sample.altitude_state == ESTIMATED) {
                sample.altitude = altitude;
                sample.altitude_state = MEASURED;
            }
        }
    }

    /// What the ledger holds for the sample Flutter stamped `micros`,
    /// newest record first: -1 when it has none, -2 while UIKit's force is
    /// still an estimate, -4 when it is an estimate UIKit will never
    /// correct, -3 when the sample carries no pressure at all (a mouse on
    /// macOS); otherwise the value the platform reported — UIKit force on
    /// iOS, NSEvent pressure (0..1) on macOS.
    pub(crate) fn value(&self, micros: i64) -> f64 {
        self.find(micros).map_or(-1.0, |sample| match sample.state {
            ESTIMATED => -2.0,
            NO_PRESSURE => -3.0,
            ESTIMATED_FINAL => -4.0,
            _ => sample.value,
        })
    }

    /// The pen's altitude for the sample Flutter stamped `micros`, in
    /// radians from the surface (UIKit's altitudeAngle): -1 when the ledger
    /// has no record or the platform reports none, -2 while it is still
    /// UIKit's estimate, -4 when it is an estimate UIKit will never correct.
    pub(crate) fn altitude(&self, micros: i64) -> f64 {
        self.find(micros).map_or(-1.0, |sample| match sample.altitude_state {
            ESTIMATED => -2.0,
            ESTIMATED_FINAL => -4.0,
            MEASURED => sample.altitude,
            _ => -1.0,
        })
    }

    /// The pen's tilt for the sample Flutter stamped `micros`, as AppKit
    /// scaled it (NSEvent.tilt: -1..1 each way), when the record is a
    /// tablet event's — none for no record, a mouse, or iOS, where the lean
    /// rides the pointer itself.
    pub(crate) fn tilt(&self, micros: i64) -> Option<(f64, f64)> {
        self.find(micros).filter(|sample| sample.tilt_state == MEASURED).map(|sample| sample.tilt)
    }
}
