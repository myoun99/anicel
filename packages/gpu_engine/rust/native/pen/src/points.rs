//! THE POINTS THE OS SAW (H56) — every point a platform saw of a contact,
//! each with its own time, written down BEFORE Flutter hears of the message
//! that carries the newest of them, and read where that message's pointer
//! datum comes into the app (lib/src/native/qa_pen_points.dart).
//!
//! An embedder hands Flutter one point a message: the newest. The points
//! the OS merged into that message while the thread that takes the messages
//! was busy — Windows' pointer history and the mouse's move points, AppKit's
//! coalescing, UIKit's coalesced touches, Android's historical samples,
//! GDK's motion compression — none of the five embedders asks for (Flutter
//! 3.47.4), so a stroke drawn from the messages joined what was left with
//! long straight steps whenever the UI's thread was slow (🗣️유저 2026-11-14,
//! H56: 「점이 들어오는 길이 이상하지 않냐」 → 「플랫폼 구분없이
//! 통합해결」).
//!
//! One book for every platform, and no platform in it: a platform's reader
//! writes each message's points as one batch, the newest last, with the
//! point the embedder hands Flutter for that message; the app pairs a
//! pointer datum with the batch that ends where the datum is. Its cases run
//! on every host.
//!
//! Why FFI and not a channel: as the pen ledger's (ledger.rs) — a channel
//! message and a pointer event travel two queues with no order between
//! them, and a batch written before its message reaches Flutter, read while
//! its datum is handled, cannot arrive late.

use std::collections::VecDeque;
use std::sync::{Mutex, MutexGuard, PoisonError};

/// One point of a contact, as the OS saw it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct Point {
    /// Where, in the view's physical pixels, as finely as the OS says it.
    pub(crate) x: f64,
    pub(crate) y: f64,
    /// When the OS saw it, in microseconds on the clock Flutter stamps that
    /// platform's pointer data by.
    pub(crate) micros: i64,
    /// What a pointer datum carries of the pen, in a datum's own units —
    /// the pressure as a part of the device's range, 0..1; the tilt from
    /// upright and the orientation, in radians — and NaN where the reader
    /// gives none: the message's own datum says it then, as it did.
    pub(crate) pressure: f64,
    pub(crate) tilt: f64,
    pub(crate) orientation: f64,
    /// The tablet DRIVER's pressure, 0..1, of the packet that put the pen
    /// at the point (wintab.rs `Heard::at`) — where the point is the pen's
    /// or a mouse's (a pen the OS hands over as a mouse) and a Wintab
    /// context is open; NaN elsewhere.
    pub(crate) driven: f64,
}

/// The numbers a point is handed to the app as ([`Point::words`]).
pub(crate) const POINT_WORDS: usize = 7;

impl Point {
    /// A point the OS says nothing of but where and when.
    #[cfg_attr(target_os = "linux", allow(dead_code))]
    pub(crate) fn at(x: f64, y: f64, micros: i64) -> Self {
        Self { x, y, micros, pressure: f64::NAN, tilt: f64::NAN, orientation: f64::NAN, driven: f64::NAN }
    }

    /// The point as the app reads it (`qa_pen_points_take`): x, y, its time
    /// in microseconds — whole, below 2⁵³ for 285 years of a clock — the
    /// pressure, the tilt, the orientation and the driver's pressure.
    pub(crate) fn words(&self) -> [f64; POINT_WORDS] {
        [self.x, self.y, self.micros as f64, self.pressure, self.tilt, self.orientation, self.driven]
    }
}

/// 🚨WHAT MADE A CONTACT, AS ITS EMBEDDER NAMES A DATUM'S KIND TO FLUTTER
/// (H61): a datum's batch is one a contact of ITS OWN kind wrote
/// ([`Book::take`]) — a pen's two ends one kind, as the app reads them.
///
/// 🗣️유저 2026-11-18: 「정기적으로 일정구간에서 스트로크가 2개
/// 겹쳐지는거같은데」. Windows hands a pen over twice: its pointer messages,
/// and the moves of the cursor that follows it, which carry no pen's
/// signature and come in as a mouse (F-400) — the two ending on the same
/// pixel. The book paired by the pixel alone, and a mouse move hands the
/// cursor's NEWEST place however many of the pen's messages still wait
/// behind it, so a pen's datum could take the cursor's batch: the cursor's
/// history, every place the pen had gone since the cursor's last move —
/// and the stroke drew that stretch over again. ⚠️Read off the code and the
/// embedder (flutter_window.cc), not yet seen with a pen.
///
/// The number each is handed across the FFI by is its own.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i32)]
pub(crate) enum Kind {
    Touch = 0,
    Mouse = 1,
    Pen = 2,
    Trackpad = 3,
    Unknown = 4,
}

impl Kind {
    const ALL: [Self; 5] = [Self::Touch, Self::Mouse, Self::Pen, Self::Trackpad, Self::Unknown];

    /// The kind the app names a datum by (`qa_pen_points_take`) — none for
    /// a number no kind has.
    pub(crate) fn named(number: i32) -> Option<Self> {
        Self::ALL.into_iter().find(|kind| *kind as i32 == number)
    }

    /// A Windows pointer's, by its `POINTER_INFO.pointerType`, as
    /// flutter_window.cc names the datum (Flutter 3.47.4): a finger, a pen
    /// and a touchpad by theirs, every other a mouse. The mouse's own moves
    /// are a mouse's.
    #[cfg_attr(not(windows), allow(dead_code))]
    pub(crate) fn of_windows_pointer(pointer_type: i32) -> Self {
        match pointer_type {
            2 => Self::Touch,    // PT_TOUCH
            3 => Self::Pen,      // PT_PEN
            5 => Self::Trackpad, // PT_TOUCHPAD
            _ => Self::Mouse,
        }
    }

    /// A `UITouch`'s, by its `type`, as FlutterViewController.mm names the
    /// datum (`DeviceKindFromTouchType`): a finger direct or not a touch,
    /// the Pencil a pen, a pointer a mouse, any other a touch.
    #[cfg_attr(not(target_os = "ios"), allow(dead_code))]
    pub(crate) fn of_uikit_touch(touch_type: isize) -> Self {
        match touch_type {
            2 => Self::Pen,   // UITouchTypePencil
            3 => Self::Mouse, // UITouchTypeIndirectPointer
            _ => Self::Touch,
        }
    }

    /// An Android pointer's, by `MotionEvent.getToolType`, as
    /// AndroidTouchProcessor.java names the datum
    /// (`getPointerDeviceTypeForToolType`): the eraser a pen's other end,
    /// a tool it does not know unknown.
    #[cfg_attr(not(target_os = "android"), allow(dead_code))]
    pub(crate) fn of_android_tool(tool: i32) -> Self {
        match tool {
            1 => Self::Touch,     // TOOL_TYPE_FINGER
            2 | 4 => Self::Pen,   // TOOL_TYPE_STYLUS · TOOL_TYPE_ERASER
            3 => Self::Mouse,     // TOOL_TYPE_MOUSE
            _ => Self::Unknown,
        }
    }
}

/// A message's points, the newest last, and where the embedder hands
/// Flutter its point — in the shape the embedder hands it (Windows: the
/// message's whole screen pixels, put in the view; iOS: `locationInView`,
/// not the finer place; Android: `getX`/`getY`): the key a datum is paired
/// with its batch by, compared exactly, among its [`Kind`]'s. And the OS's
/// own name of the contact (a pointer's id; the mouse's one): what a
/// pairing passes by is the earlier messages of that contact alone.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Batch {
    pub(crate) contact: u64,
    pub(crate) kind: Kind,
    pub(crate) handed: (f64, f64),
    pub(crate) points: Vec<Point>,
}

/// Far more messages than Flutter is ever behind by: a batch waits only
/// from its message's reading to its datum's.
pub(crate) const MOST_BATCHES: usize = 256;

/// 🚨WHY A MESSAGE'S POINTS DID NOT ALL REACH THE BOOK (H59 법 A — counted
/// first, before anything is done of them, card
/// pen-points-are-taken-off-the-ui-thread): each a message whose line has
/// a stretch the OS saw and no stroke got, read loud beside the batches
/// [`Book::passed`] by ([`Book::lost`]). Counted where the reader knows it
/// — one count a way, in this order. The book itself keeps every point a
/// reader writes ([`Book::write`]).
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) enum Lost {
    /// The OS kept no more before them: Windows' mouse history full
    /// (`GetMouseMovePointsEx`'s 64), every move in it newer than the
    /// one written last.
    Full,
    /// The history could not be read — the message's own point alone. A
    /// mouse move Windows made and keeps none of reads so too.
    Unread,
}

/// How many ways a message's points are lost ([`Lost`]).
pub(crate) const LOSSES: usize = 2;

pub(crate) struct Book {
    batches: VecDeque<Batch>,
    /// The points a Runner has handed of a message it has not ended
    /// ([`Book::point`]).
    #[cfg_attr(not(target_os = "android"), allow(dead_code))]
    gathered: Vec<Point>,
    /// Batches no datum was paired with, passed by for a later one's — or
    /// pushed out for room. The app reads it loud: each is a message whose
    /// points the stroke did not get.
    passed: u64,
    /// The messages whose points did not all reach the book, by why
    /// ([`Lost`]).
    lost: [u64; LOSSES],
}

static BOOK: Mutex<Book> = Mutex::new(Book::EMPTY);

/// The app's book.
pub(crate) fn book() -> MutexGuard<'static, Book> {
    BOOK.lock().unwrap_or_else(PoisonError::into_inner)
}

impl Book {
    pub(crate) const EMPTY: Self = Self {
        batches: VecDeque::new(),
        gathered: Vec::new(),
        passed: 0,
        lost: [0; LOSSES],
    };

    /// A point of the message a Runner is handing over a point at a time:
    /// Android's, which JNI hands numbers.
    #[cfg_attr(not(target_os = "android"), allow(dead_code))]
    pub(crate) fn point(&mut self, point: Point) {
        self.gathered.push(point);
    }

    /// The end of that message: what was gathered, as its batch.
    #[cfg_attr(not(target_os = "android"), allow(dead_code))]
    pub(crate) fn end(&mut self, contact: u64, kind: Kind, handed: (f64, f64)) {
        let points = std::mem::take(&mut self.gathered);
        self.write(Batch { contact, kind, handed, points });
    }

    /// Writes a message's batch, every point of it.
    ///
    /// ↩️A batch kept its newest 512 points till 11-17 — H56's guess at a
    /// stall of two seconds of a 240 Hz pen — and the rest was counted lost
    /// (`Lost::Cut`): no one asked for the cut (H59 법 A, card
    /// pen-points-are-taken-off-the-ui-thread).
    pub(crate) fn write(&mut self, batch: Batch) {
        if self.batches.len() == MOST_BATCHES {
            self.batches.pop_front();
            self.passed += 1;
        }
        self.batches.push_back(batch);
    }

    /// The points of the datum of `kind` Flutter was handed at `handed`: the
    /// first batch of that kind, from the oldest unread, that ends there —
    /// every earlier batch of its contact passed by; another contact's wait
    /// for their own datums, which a platform may hand in another order
    /// (UIKit's set of touches, the cursor that follows a pen on Windows:
    /// [`Kind`]). None where none ends there, and nothing is read: the
    /// datum's own point is all there is of it (a message no reader wrote).
    pub(crate) fn take(&mut self, kind: Kind, handed: (f64, f64)) -> Option<Vec<Point>> {
        let at =
            self.batches.iter().position(|batch| batch.kind == kind && batch.handed == handed)?;
        let batch = self.batches.remove(at)?;
        let before = self.batches.len();
        let mut index = 0;
        self.batches.retain(|other| {
            let earlier = index < at;
            index += 1;
            !(earlier && other.contact == batch.contact)
        });
        self.passed += (before - self.batches.len()) as u64;
        Some(batch.points)
    }

    /// How many batches were passed by ([`Book::passed`]).
    pub(crate) fn passed(&self) -> u64 {
        self.passed
    }

    /// A message whose points did not all reach the book, for `why`.
    pub(crate) fn lose(&mut self, why: Lost) {
        self.lost[why as usize] += 1;
    }

    /// How many messages' points did not all reach the book, by why, in
    /// [`Lost`]'s order.
    pub(crate) fn lost(&self) -> [u64; LOSSES] {
        self.lost
    }
}
