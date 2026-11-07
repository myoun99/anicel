//! Apple's word on each pen sample, written into the ledger (ledger.rs)
//! before Flutter hears of it.
//!
//! iOS — UIKit's word on Apple Pencil force and altitude. Either can be an
//! ESTIMATE when a sample is taken (`estimatedProperties`), one UIKit will
//! correct (`estimatedPropertiesExpectingUpdates`) or one it calls final,
//! and a correction comes later through `touchesEstimatedPropertiesUpdated`,
//! which Flutter's engine does not implement. The Runner's view controller
//! hands both to +[QaPenLedger noteTouches:] and +[QaPenLedger
//! updateTouches:] ahead of its super calls. (Location can be estimated
//! too; the brush does not wait on position, so it is not kept.)
//!
//! macOS — the tablet pressure and tilt Flutter's embedder drops. A local
//! event monitor (`qa_pen_ledger_start`) sees every left-mouse event before
//! the window does and writes both, or that it is not a tablet event.
//!
//! Everything is asked of the objects by message, so nothing here links
//! UIKit or AppKit: the app has them loaded, and the tests hand in objects
//! that answer the same messages. Both readers are built for every Apple
//! target, each called on its own, so the Mac's tests run the iPad's too.

#[cfg_attr(not(target_os = "ios"), allow(dead_code))]
pub(crate) mod touches {
    use objc2::rc::{Retained, autoreleasepool};
    use objc2::runtime::{AnyObject, NSObject};
    use objc2::{define_class, msg_send};

    use crate::ledger::{self, Sample, UNREPORTED, state_of};

    /// UITouchTypePencil.
    const PENCIL: isize = 2;
    /// UITouchPropertyForce and UITouchPropertyAltitude.
    const FORCE: isize = 1 << 0;
    const ALTITUDE: isize = 1 << 2;

    /// Each object of the NSSet `set`.
    fn each(set: &AnyObject, mut visit: impl FnMut(&AnyObject)) {
        autoreleasepool(|_| {
            // SAFETY: NSSet's allObjects, and NSArray's count and
            // objectAtIndex:.
            unsafe {
                let all: Retained<AnyObject> = msg_send![set, allObjects];
                let count: usize = msg_send![&*all, count];
                for at in 0..count {
                    let object: Retained<AnyObject> = msg_send![&*all, objectAtIndex: at];
                    visit(&object);
                }
            }
        });
    }

    /// UIKit's number for the samples of `touch` it will update, if any.
    fn update_index(touch: &AnyObject) -> Option<i64> {
        // SAFETY: UITouch's estimationUpdateIndex, an NSNumber or nil.
        unsafe {
            let index: Option<Retained<AnyObject>> = msg_send![touch, estimationUpdateIndex];
            index.map(|index| msg_send![&*index, longLongValue])
        }
    }

    /// The Pencil's samples among `touches` (an NSSet of UITouch), into the
    /// ledger.
    pub(crate) fn note(touches: &AnyObject) {
        each(touches, |touch| {
            // SAFETY: UITouch's properties.
            unsafe {
                let kind: isize = msg_send![touch, type];
                if kind != PENCIL {
                    return;
                }
                let estimated: isize = msg_send![touch, estimatedProperties];
                let awaited: isize = msg_send![touch, estimatedPropertiesExpectingUpdates];
                let timestamp: f64 = msg_send![touch, timestamp];
                let sample = Sample {
                    micros: ledger::micros(timestamp),
                    update_index: update_index(touch),
                    value: msg_send![touch, force],
                    state: state_of(estimated, awaited, FORCE),
                    altitude: msg_send![touch, altitudeAngle],
                    altitude_state: state_of(estimated, awaited, ALTITUDE),
                    // The lean's direction rides the pointer on iOS.
                    tilt: (0.0, 0.0),
                    tilt_state: UNREPORTED,
                };
                ledger::ledger().record(sample);
            }
        });
    }

    /// UIKit's later word on `touches` (an NSSet of UITouch): what it no
    /// longer means to update replaces the estimate the ledger holds.
    pub(crate) fn update(touches: &AnyObject) {
        each(touches, |touch| {
            let Some(key) = update_index(touch) else {
                return;
            };
            // SAFETY: UITouch's properties.
            unsafe {
                let awaited: isize = msg_send![touch, estimatedPropertiesExpectingUpdates];
                let force = (awaited & FORCE == 0).then(|| msg_send![touch, force]);
                let altitude =
                    (awaited & ALTITUDE == 0).then(|| msg_send![touch, altitudeAngle]);
                ledger::ledger().update(key, force, altitude);
            }
        });
    }

    define_class!(
        // SAFETY: NSObject has no subclassing requirements, and this has no
        // Drop.
        #[unsafe(super(NSObject))]
        #[name = "QaPenLedger"]
        pub(crate) struct PenLedger;

        impl PenLedger {
            #[unsafe(method(noteTouches:))]
            fn note_touches(touches: Option<&AnyObject>) {
                if let Some(touches) = touches {
                    note(touches);
                }
            }

            #[unsafe(method(updateTouches:))]
            fn update_touches(touches: Option<&AnyObject>) {
                if let Some(touches) = touches {
                    update(touches);
                }
            }
        }
    );

    // The Runner looks the class up by name at each touch until it finds it
    // (AppDelegate's penLedger), so the class is the image's from its load
    // — an initializer registers it, on every Apple target, and the Mac's
    // tests reach it by name as the Runner does. The image is the GPU
    // engine's library, which Dart loads at its first call into it
    // (gpu_engine's lib.rs holds that it is registered there). Two classes
    // of one name abort the load: the C's left the app in the round that
    // linked this one (connection-round-checklist H, 2026-11-08).
    #[used]
    #[unsafe(link_section = "__DATA,__mod_init_func,mod_init_funcs")]
    static REGISTER: extern "C" fn() = register;

    extern "C" fn register() {
        let _ = <PenLedger as objc2::ClassType>::class();
    }
}

#[cfg_attr(not(target_os = "macos"), allow(dead_code))]
pub(crate) mod events {
    use std::sync::atomic::{AtomicPtr, Ordering};

    use block2::RcBlock;
    use objc2::rc::Retained;
    use objc2::runtime::{AnyClass, AnyObject};
    use objc2::{Encode, Encoding, msg_send};

    use crate::ledger::{self, MEASURED, NO_PRESSURE, Sample, UNREPORTED};

    /// NSPoint — CGPoint, by its name and layout.
    #[repr(C)]
    #[derive(Clone, Copy, Debug, Default, PartialEq)]
    pub(crate) struct Point {
        pub(crate) x: f64,
        pub(crate) y: f64,
    }

    // SAFETY: CGPoint's own encoding.
    unsafe impl Encode for Point {
        const ENCODING: Encoding = Encoding::Struct("CGPoint", &[f64::ENCODING, f64::ENCODING]);
    }

    /// NSEventTypeTabletPoint, and NSEventSubtypeTabletPoint.
    pub(crate) const TABLET_POINT: usize = 23;
    pub(crate) const SUBTYPE_TABLET_POINT: i16 = 1;

    /// One left-mouse or tablet event, into the ledger: its pressure and
    /// tilt, or that it is not a tablet's.
    pub(crate) fn note(event: &AnyObject) {
        // SAFETY: NSEvent's properties; its subtype is asked of a mouse
        // event alone, which has one.
        unsafe {
            let kind: usize = msg_send![event, type];
            let tablet = kind == TABLET_POINT || {
                let subtype: i16 = msg_send![event, subtype];
                subtype == SUBTYPE_TABLET_POINT
            };
            // `tilt` is valid for exactly these events (AppKit's own words).
            let tilt: Point = if tablet { msg_send![event, tilt] } else { Point::default() };
            let pressure: f32 = if tablet { msg_send![event, pressure] } else { 0.0 };
            let timestamp: f64 = msg_send![event, timestamp];
            ledger::ledger().record(Sample {
                micros: ledger::micros(timestamp),
                update_index: None,
                value: f64::from(pressure),
                state: if tablet { MEASURED } else { NO_PRESSURE },
                altitude: 0.0,
                altitude_state: UNREPORTED,
                tilt: (tilt.x, tilt.y),
                tilt_state: if tablet { MEASURED } else { UNREPORTED },
            });
        }
    }

    /// The left mouse's down, up and drag, and the tablet's point.
    pub(crate) const MASK: u64 = 1 << 1 | 1 << 2 | 1 << 6 | 1 << TABLET_POINT;

    static MONITOR: AtomicPtr<AnyObject> = AtomicPtr::new(std::ptr::null_mut());

    /// The local event monitor, once — on the main thread, where AppKit
    /// calls it.
    pub(crate) fn install() {
        if !MONITOR.load(Ordering::SeqCst).is_null() {
            return;
        }
        let Some(events) = AnyClass::get(c"NSEvent") else {
            return;
        };
        let handler = RcBlock::new(|event: *mut AnyObject| -> *mut AnyObject {
            // SAFETY: the event AppKit hands the monitor, or nil.
            if let Some(event) = unsafe { event.as_ref() } {
                note(event);
            }
            event
        });
        // SAFETY: +[NSEvent addLocalMonitorForEventsMatchingMask:handler:].
        let monitor: Option<Retained<AnyObject>> = unsafe {
            msg_send![events, addLocalMonitorForEventsMatchingMask: MASK, handler: &*handler]
        };
        if let Some(monitor) = monitor {
            MONITOR.store(Retained::into_raw(monitor), Ordering::SeqCst);
        }
    }
}

/// Starts whatever the platform needs to keep the ledger: the event monitor
/// on macOS (installed on the main thread, where AppKit calls it); nothing
/// on iOS, where the Runner writes. Safe to call again.
pub(crate) fn start() {
    #[cfg(target_os = "macos")]
    if objc2::MainThreadMarker::new().is_some() {
        events::install();
    } else {
        dispatch2::DispatchQueue::main().exec_async(events::install);
    }
}
