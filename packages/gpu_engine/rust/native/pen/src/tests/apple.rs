//! Apple's readers on objects that answer as UITouch and NSEvent do, read
//! back through the ledger's exports, on answers worked out here: the C
//! (qa_pen_ledger_apple.m) is compiled into the app alone. The iPad's reader
//! is reached as the Runner reaches it, by the class's name — nothing here
//! registers it. The event monitor itself needs a running AppKit app, which
//! no test has.

use std::cell::Cell;

use objc2::rc::Retained;
use objc2::runtime::{AnyClass, AnyObject, NSObject};
use objc2::{AnyThread, DefinedClass, define_class, msg_send};

use crate::apple::events::{self, MASK, Point, SUBTYPE_TABLET_POINT, TABLET_POINT};
use crate::{qa_pen_ledger_altitude, qa_pen_ledger_tilt, qa_pen_ledger_value};

// NSSet and NSNumber, which the app has loaded and a test binary does not.
#[link(name = "Foundation", kind = "framework")]
unsafe extern "C" {}

/// UITouchTypeDirect, UITouchTypeIndirect, UITouchTypePencil and
/// UITouchTypeIndirectPointer.
const FINGER: isize = 0;
const INDIRECT: isize = 1;
const PENCIL: isize = 2;
const POINTER: isize = 3;
/// UITouchPropertyForce and UITouchPropertyAltitude.
const FORCE: isize = 1 << 0;
const ALTITUDE: isize = 1 << 2;

fn class(name: &std::ffi::CStr) -> &'static AnyClass {
    AnyClass::get(name).unwrap_or_else(|| panic!("no class {name:?}"))
}

/// An NSSet of `objects`.
fn set(objects: &[&AnyObject]) -> Retained<AnyObject> {
    // SAFETY: +[NSMutableSet new] and -addObject:.
    unsafe {
        let set: Retained<AnyObject> = msg_send![class(c"NSMutableSet"), new];
        for object in objects {
            let _: () = msg_send![&*set, addObject: *object];
        }
        set
    }
}

/// What the Runner's view controller does with touches: hands them to the
/// class it found by name.
fn note_touches(touches: &[&AnyObject]) {
    // SAFETY: +[QaPenLedger noteTouches:], with an NSSet.
    unsafe { msg_send![class(c"QaPenLedger"), noteTouches: &*set(touches)] }
}

fn update_touches(touches: &[&AnyObject]) {
    // SAFETY: +[QaPenLedger updateTouches:], with an NSSet.
    unsafe { msg_send![class(c"QaPenLedger"), updateTouches: &*set(touches)] }
}

/// What the ledger answers for `micros`: force, altitude, and tilt.
fn read(micros: i64) -> (f64, f64, Option<(f64, f64)>) {
    let mut xy = [f64::NAN; 2];
    // SAFETY: two writable f64s.
    let tilted = unsafe { qa_pen_ledger_tilt(micros, xy.as_mut_ptr()) };
    let tilt = match tilted {
        0 => {
            assert!(xy.iter().all(|v| v.is_nan()), "no tilt, but {xy:?} written");
            None
        }
        _ => Some((xy[0], xy[1])),
    };
    (qa_pen_ledger_value(micros), qa_pen_ledger_altitude(micros), tilt)
}

struct Touch {
    kind: isize,
    estimated: isize,
    awaited: isize,
    timestamp: f64,
    force: f64,
    altitude: f64,
    index: Option<i64>,
}

const PENCIL_TOUCH: Touch = Touch {
    kind: PENCIL,
    estimated: 0,
    awaited: 0,
    timestamp: 0.0,
    force: 0.0,
    altitude: 0.0,
    index: None,
};

define_class!(
    // SAFETY: NSObject has no subclassing requirements, and this has no
    // Drop.
    #[unsafe(super(NSObject))]
    #[name = "PenTestTouch"]
    #[ivars = Touch]
    struct FakeTouch;

    impl FakeTouch {
        #[unsafe(method(type))]
        fn kind(&self) -> isize {
            self.ivars().kind
        }

        #[unsafe(method(estimatedProperties))]
        fn estimated(&self) -> isize {
            self.ivars().estimated
        }

        #[unsafe(method(estimatedPropertiesExpectingUpdates))]
        fn awaited(&self) -> isize {
            self.ivars().awaited
        }

        #[unsafe(method(timestamp))]
        fn timestamp(&self) -> f64 {
            self.ivars().timestamp
        }

        #[unsafe(method(force))]
        fn force(&self) -> f64 {
            self.ivars().force
        }

        #[unsafe(method(altitudeAngle))]
        fn altitude(&self) -> f64 {
            self.ivars().altitude
        }

        #[unsafe(method_id(estimationUpdateIndex))]
        fn index(&self) -> Option<Retained<AnyObject>> {
            // SAFETY: +[NSNumber numberWithLongLong:].
            self.ivars()
                .index
                .map(|index| unsafe { msg_send![class(c"NSNumber"), numberWithLongLong: index] })
        }
    }
);

impl FakeTouch {
    fn new(touch: Touch) -> Retained<Self> {
        let this = Self::alloc().set_ivars(touch);
        // SAFETY: NSObject's init.
        unsafe { msg_send![super(this), init] }
    }
}

#[test]
fn the_pencils_sample_is_written_by_its_stamp() {
    let touch = FakeTouch::new(Touch {
        timestamp: 1001.25,
        force: 2.5,
        altitude: 0.75,
        ..PENCIL_TOUCH
    });
    note_touches(&[&touch]);
    // The lean's direction rides the pointer on iOS.
    assert_eq!(read(1_001_250_000), (2.5, 0.75, None));
}

#[test]
fn a_finger_or_a_pointer_is_not_the_pencils() {
    let touch =
        |kind| FakeTouch::new(Touch { kind, timestamp: 1002.25, force: 2.5, ..PENCIL_TOUCH });
    note_touches(&[&touch(FINGER), &touch(INDIRECT), &touch(POINTER)]);
    assert_eq!(read(1_002_250_000), (-1.0, -1.0, None));
}

#[test]
fn each_of_several_touches_is_written() {
    let touch = |timestamp: f64| {
        FakeTouch::new(Touch { timestamp, force: timestamp - 1000.0, ..PENCIL_TOUCH })
    };
    note_touches(&[&touch(1003.25), &touch(1003.5)]);
    assert_eq!(read(1_003_250_000).0, 3.25);
    assert_eq!(read(1_003_500_000).0, 3.5);
}

#[test]
fn an_estimate_is_kept_as_uikit_names_it() {
    let touch = FakeTouch::new(Touch {
        estimated: FORCE | ALTITUDE,
        awaited: FORCE,
        timestamp: 1004.25,
        force: 0.33,
        altitude: 0.75,
        index: Some(4101),
        ..PENCIL_TOUCH
    });
    note_touches(&[&touch]);
    assert_eq!(read(1_004_250_000), (-2.0, -4.0, None));
}

#[test]
fn uikits_later_word_replaces_what_it_no_longer_awaits() {
    let noted = FakeTouch::new(Touch {
        estimated: FORCE | ALTITUDE,
        awaited: FORCE | ALTITUDE,
        timestamp: 1005.25,
        force: 0.33,
        altitude: 0.75,
        index: Some(4102),
        ..PENCIL_TOUCH
    });
    note_touches(&[&noted]);
    assert_eq!(read(1_005_250_000), (-2.0, -2.0, None));
    // The altitude still awaited; the force final.
    let later = |awaited| {
        let index = Some(4102);
        FakeTouch::new(Touch { awaited, force: 1.5, altitude: 1.25, index, ..PENCIL_TOUCH })
    };
    update_touches(&[&later(ALTITUDE)]);
    assert_eq!(read(1_005_250_000), (1.5, -2.0, None));
    update_touches(&[&later(0)]);
    assert_eq!(read(1_005_250_000), (1.5, 1.25, None));
}

#[test]
fn a_later_word_is_for_the_number_it_carries() {
    let noted = FakeTouch::new(Touch {
        awaited: FORCE | ALTITUDE,
        timestamp: 1006.25,
        index: Some(4103),
        ..PENCIL_TOUCH
    });
    note_touches(&[&noted]);
    let unnumbered = FakeTouch::new(Touch { force: 1.5, altitude: 1.25, ..PENCIL_TOUCH });
    let another = FakeTouch::new(Touch { index: Some(4104), ..PENCIL_TOUCH });
    update_touches(&[&unnumbered, &another]);
    assert_eq!(read(1_006_250_000), (-2.0, -2.0, None));
}

/// What a fake event was asked, beyond its type and timestamp.
const SUBTYPE: u8 = 1 << 0;
const TILT: u8 = 1 << 1;
const PRESSURE: u8 = 1 << 2;

struct Event {
    kind: usize,
    subtype: i16,
    tilt: Point,
    pressure: f32,
    timestamp: f64,
    asked: Cell<u8>,
}

/// NSEventTypeLeftMouseDown and NSEventTypeLeftMouseDragged;
/// NSEventSubtypeMouseEvent and NSEventSubtypeTabletProximity.
const MOUSE_DOWN: usize = 1;
const MOUSE_DRAGGED: usize = 6;
const SUBTYPE_MOUSE: i16 = 0;
const SUBTYPE_PROXIMITY: i16 = 2;

define_class!(
    // SAFETY: NSObject has no subclassing requirements, and this has no
    // Drop.
    #[unsafe(super(NSObject))]
    #[name = "PenTestEvent"]
    #[ivars = Event]
    struct FakeEvent;

    impl FakeEvent {
        #[unsafe(method(type))]
        fn kind(&self) -> usize {
            self.ivars().kind
        }

        #[unsafe(method(subtype))]
        fn subtype(&self) -> i16 {
            self.ask(SUBTYPE);
            self.ivars().subtype
        }

        #[unsafe(method(tilt))]
        fn tilt(&self) -> Point {
            self.ask(TILT);
            self.ivars().tilt
        }

        #[unsafe(method(pressure))]
        fn pressure(&self) -> f32 {
            self.ask(PRESSURE);
            self.ivars().pressure
        }

        #[unsafe(method(timestamp))]
        fn timestamp(&self) -> f64 {
            self.ivars().timestamp
        }
    }
);

impl FakeEvent {
    fn new(kind: usize, subtype: i16, timestamp: f64) -> Retained<Self> {
        let this = Self::alloc().set_ivars(Event {
            kind,
            subtype,
            tilt: Point { x: 0.5, y: -0.25 },
            pressure: 0.75,
            timestamp,
            asked: Cell::new(0),
        });
        // SAFETY: NSObject's init.
        unsafe { msg_send![super(this), init] }
    }

    fn ask(&self, what: u8) {
        self.ivars().asked.set(self.ivars().asked.get() | what);
    }

    /// Noted, and what it was asked.
    fn noted(&self) -> u8 {
        events::note(self);
        self.ivars().asked.get()
    }
}

#[test]
fn a_tablet_point_is_read_whole_and_never_asked_its_subtype() {
    let event = FakeEvent::new(TABLET_POINT, SUBTYPE_MOUSE, 2001.25);
    assert_eq!(event.noted(), TILT | PRESSURE);
    assert_eq!(read(2_001_250_000), (0.75, -1.0, Some((0.5, -0.25))));
}

#[test]
fn a_mouse_event_the_tablet_sent_is_read_whole() {
    let event = FakeEvent::new(MOUSE_DRAGGED, SUBTYPE_TABLET_POINT, 2002.25);
    assert_eq!(event.noted(), SUBTYPE | TILT | PRESSURE);
    assert_eq!(read(2_002_250_000), (0.75, -1.0, Some((0.5, -0.25))));
}

#[test]
fn a_mouses_event_carries_no_pressure_and_is_asked_none() {
    for (subtype, timestamp, micros) in
        [(SUBTYPE_MOUSE, 2003.25, 2_003_250_000), (SUBTYPE_PROXIMITY, 2003.5, 2_003_500_000)]
    {
        let event = FakeEvent::new(MOUSE_DOWN, subtype, timestamp);
        assert_eq!(event.noted(), SUBTYPE, "tilt is valid for a tablet's events alone");
        assert_eq!(read(micros), (-3.0, -1.0, None));
    }
}

#[test]
fn the_monitor_sees_the_left_mouse_and_the_tablet() {
    // NSEventMaskLeftMouseDown, -LeftMouseUp, -LeftMouseDragged and
    // -TabletPoint.
    assert_eq!(MASK, 0x0080_0046);
}
