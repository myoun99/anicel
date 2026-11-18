//! The book of the points the OS saw, and how a datum is paired with its
//! batch, on answers worked out here.

use crate::points::{Batch, Book, Driven, Kind, LOSSES, Lost, MOST_BATCHES, POINT_WORDS, Point, book};

/// A message's batch: its points at `xs` along y 0, one microsecond apart
/// from `from`, handed to Flutter at the last of them — of contact 1, a pen.
fn batch(from: i64, xs: &[f64]) -> Batch {
    of((1, Kind::Pen), from, xs)
}

/// [`batch`], of `contact` of a kind.
fn of((contact, kind): (u64, Kind), from: i64, xs: &[f64]) -> Batch {
    let points: Vec<_> =
        xs.iter().enumerate().map(|(at, &x)| Point::at(x, 0.0, from + at as i64)).collect();
    Batch { contact, kind, handed: (*xs.last().expect("a point"), 0.0), points }
}

fn xs(points: &[Point]) -> Vec<f64> {
    points.iter().map(|point| point.x).collect()
}

#[test]
fn a_datum_is_handed_the_points_of_the_batch_that_ends_where_it_is_oldest_first() {
    let mut book = Book::EMPTY;
    book.write(batch(0, &[1.0, 2.0, 3.0]));
    book.write(batch(10, &[4.0, 5.0]));
    let first = book.take(Kind::Pen, (3.0, 0.0)).expect("the first batch ends at 3");
    assert_eq!(xs(&first), [1.0, 2.0, 3.0]);
    assert_eq!(first.iter().map(|point| point.micros).collect::<Vec<_>>(), [0, 1, 2]);
    assert_eq!(xs(&book.take(Kind::Pen, (5.0, 0.0)).expect("then the second")), [4.0, 5.0]);
    assert_eq!(book.passed(), 0);
}

#[test]
fn a_datum_no_batch_ends_at_reads_nothing_and_its_own_point_is_all_there_is() {
    let mut book = Book::EMPTY;
    book.write(batch(0, &[1.0, 2.0]));
    assert_eq!(book.take(Kind::Pen, (7.0, 0.0)), None);
    assert_eq!(xs(&book.take(Kind::Pen, (2.0, 0.0)).expect("still there")), [1.0, 2.0]);
    assert_eq!(book.passed(), 0);
}

#[test]
fn the_batches_before_a_datum_s_are_passed_by_and_counted() {
    let mut book = Book::EMPTY;
    book.write(batch(0, &[1.0]));
    book.write(batch(1, &[2.0]));
    book.write(batch(2, &[3.0]));
    assert_eq!(xs(&book.take(Kind::Pen, (3.0, 0.0)).expect("the third")), [3.0]);
    assert_eq!(book.passed(), 2, "each a message whose points the stroke did not get");
    assert_eq!(book.take(Kind::Pen, (1.0, 0.0)), None, "a passed batch is gone");
}

#[test]
fn a_message_handed_a_point_at_a_time_is_one_batch_at_its_end() {
    let mut book = Book::EMPTY;
    book.point(Point::at(1.0, 0.0, 0));
    book.point(Point::at(2.0, 0.0, 1));
    book.end(3, Kind::Pen, (2.0, 0.0));
    book.point(Point::at(5.0, 0.0, 2));
    book.end(3, Kind::Pen, (5.0, 0.0));
    assert_eq!(xs(&book.take(Kind::Pen, (2.0, 0.0)).expect("the first message")), [1.0, 2.0]);
    assert_eq!(xs(&book.take(Kind::Pen, (5.0, 0.0)).expect("the second, alone")), [5.0]);
}

#[test]
fn another_contact_s_batch_waits_for_its_own_datum() {
    // Two fingers in one UIKit set, handed in another order than written.
    let mut book = Book::EMPTY;
    book.write(of((1, Kind::Touch), 0, &[1.0, 2.0]));
    book.write(of((2, Kind::Touch), 0, &[7.0, 8.0]));
    let second = book.take(Kind::Touch, (8.0, 0.0)).expect("the second finger's");
    assert_eq!(xs(&second), [7.0, 8.0]);
    let first = book.take(Kind::Touch, (2.0, 0.0)).expect("the first's, kept");
    assert_eq!(xs(&first), [1.0, 2.0]);
    assert_eq!(book.passed(), 0);
}

// 🗣️H61 (유저 2026-11-18): 「정기적으로 일정구간에서 스트로크가 2개
// 겹쳐지는거같은데」. On Windows the cursor follows the pen: its move came
// in ahead of the pen's message that got there, on the same pixel, with
// the cursor's history since its last move — places the pen's batches had
// already handed the stroke.
#[test]
fn a_pen_s_datum_takes_the_pen_s_batch_not_the_cursor_s_that_ends_alike() {
    let mut book = Book::EMPTY;
    book.write(of((1, Kind::Pen), 0, &[1.0, 2.0]));
    book.write(of((u64::MAX, Kind::Mouse), 0, &[1.0, 2.0, 3.0, 4.0]));
    book.write(of((1, Kind::Pen), 3, &[3.0, 4.0]));
    assert_eq!(xs(&book.take(Kind::Pen, (2.0, 0.0)).expect("the pen's first")), [1.0, 2.0]);
    let pen = book.take(Kind::Pen, (4.0, 0.0)).expect("the pen's own");
    assert_eq!(xs(&pen), [3.0, 4.0], "not the cursor's way back over 1 and 2");
    let cursor = book.take(Kind::Mouse, (4.0, 0.0)).expect("the cursor's, for its own datum");
    assert_eq!(xs(&cursor), [1.0, 2.0, 3.0, 4.0]);
    assert_eq!(book.passed(), 0, "each read by its own");
}

#[test]
fn a_datum_of_a_kind_no_batch_there_is_of_reads_nothing() {
    let mut book = Book::EMPTY;
    book.write(of((1, Kind::Pen), 0, &[1.0, 2.0]));
    for kind in [Kind::Touch, Kind::Mouse, Kind::Trackpad, Kind::Unknown] {
        assert_eq!(book.take(kind, (2.0, 0.0)), None, "{kind:?}");
    }
    assert_eq!(book.passed(), 0, "and passes none by");
    assert!(book.take(Kind::Pen, (2.0, 0.0)).is_some(), "still the pen's");
}

#[test]
fn each_kind_is_named_by_its_own_number_and_no_other() {
    for kind in [Kind::Touch, Kind::Mouse, Kind::Pen, Kind::Trackpad, Kind::Unknown] {
        assert_eq!(Kind::named(kind as i32), Some(kind));
    }
    assert_eq!(Kind::named(-1), None);
    assert_eq!(Kind::named(5), None);
}

#[test]
fn the_app_s_number_of_a_kind_no_batch_has_takes_nothing() {
    // A place no other case hands at: the book is the app's one.
    let handed = (-1357.5, 2468.25);
    book().write(Batch { contact: 8, kind: Kind::Pen, handed, points: vec![] });
    assert_eq!(crate::qa_pen_points_take(Kind::Mouse as i32, handed.0, handed.1), -1);
    assert_eq!(crate::qa_pen_points_take(99, handed.0, handed.1), -1);
    // Read past the FFI: what it takes it holds for one other case to read.
    assert_eq!(book().take(Kind::Pen, handed), Some(vec![]), "still there");
}

/// Each reader names its contact's kind as its embedder names the datum's
/// to Flutter (3.47.4): flutter_window.cc's `pointerType` switch,
/// FlutterViewController.mm's `DeviceKindFromTouchType` and
/// AndroidTouchProcessor.java's `getPointerDeviceTypeForToolType`.
#[test]
fn each_reader_names_a_kind_as_its_embedder_names_the_datum_s() {
    // PT_POINTER 1 · PT_TOUCH 2 · PT_PEN 3 · PT_MOUSE 4 · PT_TOUCHPAD 5
    let windows: Vec<Kind> = (1..=5).map(Kind::of_windows_pointer).collect();
    assert_eq!(windows, [Kind::Mouse, Kind::Touch, Kind::Pen, Kind::Mouse, Kind::Trackpad]);
    // UITouchType: direct · indirect · pencil · indirectPointer · past them
    let uikit: Vec<Kind> = (0..=4).map(Kind::of_uikit_touch).collect();
    assert_eq!(uikit, [Kind::Touch, Kind::Touch, Kind::Pen, Kind::Mouse, Kind::Touch]);
    // TOOL_TYPE_: UNKNOWN 0 · FINGER 1 · STYLUS 2 · MOUSE 3 · ERASER 4
    let android: Vec<Kind> = (0..=4).map(Kind::of_android_tool).collect();
    assert_eq!(android, [Kind::Unknown, Kind::Touch, Kind::Pen, Kind::Mouse, Kind::Pen]);
}

#[test]
fn of_two_batches_that_end_alike_the_older_is_the_datum_s() {
    // A pen held still: message after message ends on the same pixel.
    let mut book = Book::EMPTY;
    book.write(batch(0, &[1.0, 2.0]));
    book.write(batch(10, &[3.0, 2.0]));
    assert_eq!(xs(&book.take(Kind::Pen, (2.0, 0.0)).expect("the older")), [1.0, 2.0]);
    assert_eq!(xs(&book.take(Kind::Pen, (2.0, 0.0)).expect("then the newer")), [3.0, 2.0]);
}

// A stall of eight seconds of a 240 Hz pen: the book cut a batch to its
// newest 512 till 11-17, which no one asked for.
#[test]
fn a_batch_keeps_every_point_however_long_the_stall() {
    let mut book = Book::EMPTY;
    let many: Vec<f64> = (0..2000).map(|x| x as f64).collect();
    book.write(batch(0, &many));
    let kept = book.take(Kind::Pen, (*many.last().expect("many"), 0.0)).expect("kept");
    assert_eq!(xs(&kept), many);
    assert_eq!(book.lost(), [0; LOSSES], "nothing lost");
}

#[test]
fn the_app_reads_every_point_of_a_batch_it_takes_however_many() {
    // A place no other case hands at: the book is the app's one.
    let handed = (-4321.25, 9876.5);
    let mut last: Vec<_> = (0..1500).map(|at| Point::at(at as f64, handed.1, at)).collect();
    last.push(Point::at(handed.0, handed.1, 1500));
    book().write(Batch { contact: 7, kind: Kind::Pen, handed, points: last.clone() });

    let count = crate::qa_pen_points_take(Kind::Pen as i32, handed.0, handed.1);
    let mut out = vec![0.0; POINT_WORDS * count as usize];
    // SAFETY: room for `count` points.
    let read = unsafe { crate::qa_pen_points_taken(out.as_mut_ptr(), count as usize) };

    assert_eq!(count, 1501);
    assert_eq!(read, 1501);
    // Bit for bit: a point the OS says nothing more of reads NaN.
    let bits = |words: &[f64]| words.iter().map(|word| word.to_bits()).collect::<Vec<_>>();
    let words: Vec<f64> = last.iter().flat_map(|point| point.words()).collect();
    assert_eq!(bits(&out), bits(&words));
    let mut again = vec![0.0; POINT_WORDS];
    // SAFETY: room for one point.
    let after = unsafe { crate::qa_pen_points_taken(again.as_mut_ptr(), 1) };
    assert_eq!(after, 0, "read once, let go of");
}

#[test]
fn a_loss_is_counted_by_its_why() {
    let mut book = Book::EMPTY;
    book.lose(Lost::Full);
    book.lose(Lost::Full);
    book.lose(Lost::Unread);
    assert_eq!(book.lost(), [2, 1]);
}

#[test]
fn a_full_book_pushes_its_oldest_batch_out_and_counts_it() {
    let mut book = Book::EMPTY;
    for at in 0..=MOST_BATCHES {
        book.write(batch(at as i64, &[at as f64]));
    }
    assert_eq!(book.passed(), 1);
    assert_eq!(book.take(Kind::Pen, (0.0, 0.0)), None, "the oldest is gone");
    assert!(book.take(Kind::Pen, (1.0, 0.0)).is_some());
}

#[test]
fn a_point_the_os_says_nothing_more_of_reads_none_for_the_pen() {
    let words = Point::at(1.0, 2.0, 3).words();
    assert_eq!(words[..3], [1.0, 2.0, 3.0]);
    assert!(words[3..].iter().all(|word| word.is_nan()));
}

#[test]
fn a_point_is_handed_to_the_app_where_when_and_as_the_pen_read() {
    let driven = Driven { pressure: 0.75, lean: Some((90.0, 0.5)), twist: Some(270.0) };
    let point = Point { pressure: 0.5, tilt: 0.25, orientation: -1.5, driven: Some(driven), ..Point::at(1.5, 2.25, 7) };
    assert_eq!(point.words(), [1.5, 2.25, 7.0, 0.5, 0.25, -1.5, 0.75, 90.0, 0.5, 270.0]);
    // The packet of a device that declares no orientation and no twist.
    let bare = Point { driven: Some(Driven { lean: None, twist: None, ..driven }), ..point };
    assert_eq!(bare.words()[..7], point.words()[..7]);
    assert!(bare.words()[7..].iter().all(|word| word.is_nan()), "no lean and no twist read");
    // A performance counter's microseconds a day after boot stay whole.
    assert_eq!(Point::at(0.0, 0.0, 86_400_000_001).words()[2], 86_400_000_001.0);
}

#[test]
fn the_app_reads_a_point_in_as_many_numbers_as_it_is_handed() {
    let dart = include_str!("../../../../../../../lib/src/native/qa_pen_points.dart");
    let declared = "static const int _words = ";
    let line = dart.lines().map(str::trim_start).find(|line| line.starts_with(declared)).expect(declared);
    let words: usize = line[declared.len()..].trim_end_matches(';').parse().expect(line);
    assert_eq!(words, POINT_WORDS, "qa_pen_points.dart reads a point as the book writes it");
}

#[test]
fn the_app_names_each_kind_by_the_book_s_own_number() {
    let dart = include_str!("../../../../../../../lib/src/native/qa_pen_points.dart");
    let mut named: Vec<(&str, i32)> = dart
        .lines()
        .map(str::trim)
        .filter(|line| line.starts_with("PointerDeviceKind."))
        .filter_map(|line| line.trim_end_matches(',').split_once(" => "))
        .flat_map(|(kinds, number)| {
            let number: i32 = number.parse().expect(number);
            kinds.split(" || ").map(move |kind| (kind.trim_start_matches("PointerDeviceKind."), number))
        })
        .collect();
    named.sort_unstable();
    let mut book = vec![
        ("touch", Kind::Touch as i32),
        ("mouse", Kind::Mouse as i32),
        ("stylus", Kind::Pen as i32),
        ("invertedStylus", Kind::Pen as i32),
        ("trackpad", Kind::Trackpad as i32),
        ("unknown", Kind::Unknown as i32),
    ];
    book.sort_unstable();
    assert_eq!(named, book, "qa_pen_points.dart names a datum's kind as the book reads it");
}
