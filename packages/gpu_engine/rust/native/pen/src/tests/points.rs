//! The book of the points the OS saw, and how a datum is paired with its
//! batch, on answers worked out here.

use crate::points::{Batch, Book, MOST_BATCHES, MOST_POINTS, Point};

/// A message's batch: its points at `xs` along y 0, one microsecond apart
/// from `from`, handed to Flutter at the last of them — of contact 1.
fn batch(from: i64, xs: &[f64]) -> Batch {
    of(1, from, xs)
}

/// [`batch`], of `contact`.
fn of(contact: u64, from: i64, xs: &[f64]) -> Batch {
    let points: Vec<_> =
        xs.iter().enumerate().map(|(at, &x)| Point::at(x, 0.0, from + at as i64)).collect();
    Batch { contact, handed: (*xs.last().expect("a point"), 0.0), points }
}

fn xs(points: &[Point]) -> Vec<f64> {
    points.iter().map(|point| point.x).collect()
}

#[test]
fn a_datum_is_handed_the_points_of_the_batch_that_ends_where_it_is_oldest_first() {
    let mut book = Book::EMPTY;
    book.write(batch(0, &[1.0, 2.0, 3.0]));
    book.write(batch(10, &[4.0, 5.0]));
    let first = book.take((3.0, 0.0)).expect("the first batch ends at 3");
    assert_eq!(xs(&first), [1.0, 2.0, 3.0]);
    assert_eq!(first.iter().map(|point| point.micros).collect::<Vec<_>>(), [0, 1, 2]);
    assert_eq!(xs(&book.take((5.0, 0.0)).expect("then the second")), [4.0, 5.0]);
    assert_eq!(book.passed(), 0);
}

#[test]
fn a_datum_no_batch_ends_at_reads_nothing_and_its_own_point_is_all_there_is() {
    let mut book = Book::EMPTY;
    book.write(batch(0, &[1.0, 2.0]));
    assert_eq!(book.take((7.0, 0.0)), None);
    assert_eq!(xs(&book.take((2.0, 0.0)).expect("still there")), [1.0, 2.0]);
    assert_eq!(book.passed(), 0);
}

#[test]
fn the_batches_before_a_datum_s_are_passed_by_and_counted() {
    let mut book = Book::EMPTY;
    book.write(batch(0, &[1.0]));
    book.write(batch(1, &[2.0]));
    book.write(batch(2, &[3.0]));
    assert_eq!(xs(&book.take((3.0, 0.0)).expect("the third")), [3.0]);
    assert_eq!(book.passed(), 2, "each a message whose points the stroke did not get");
    assert_eq!(book.take((1.0, 0.0)), None, "a passed batch is gone");
}

#[test]
fn a_message_handed_a_point_at_a_time_is_one_batch_at_its_end() {
    let mut book = Book::EMPTY;
    book.point(Point::at(1.0, 0.0, 0));
    book.point(Point::at(2.0, 0.0, 1));
    book.end(3, (2.0, 0.0));
    book.point(Point::at(5.0, 0.0, 2));
    book.end(3, (5.0, 0.0));
    assert_eq!(xs(&book.take((2.0, 0.0)).expect("the first message")), [1.0, 2.0]);
    assert_eq!(xs(&book.take((5.0, 0.0)).expect("the second, alone")), [5.0]);
}

#[test]
fn another_contact_s_batch_waits_for_its_own_datum() {
    // Two fingers in one UIKit set, handed in another order than written.
    let mut book = Book::EMPTY;
    book.write(of(1, 0, &[1.0, 2.0]));
    book.write(of(2, 0, &[7.0, 8.0]));
    assert_eq!(xs(&book.take((8.0, 0.0)).expect("the second finger's")), [7.0, 8.0]);
    assert_eq!(xs(&book.take((2.0, 0.0)).expect("the first's, kept")), [1.0, 2.0]);
    assert_eq!(book.passed(), 0);
}

#[test]
fn of_two_batches_that_end_alike_the_older_is_the_datum_s() {
    // A pen held still: message after message ends on the same pixel.
    let mut book = Book::EMPTY;
    book.write(batch(0, &[1.0, 2.0]));
    book.write(batch(10, &[3.0, 2.0]));
    assert_eq!(xs(&book.take((2.0, 0.0)).expect("the older")), [1.0, 2.0]);
    assert_eq!(xs(&book.take((2.0, 0.0)).expect("then the newer")), [3.0, 2.0]);
}

#[test]
fn a_batch_keeps_its_newest_points() {
    let mut book = Book::EMPTY;
    let many: Vec<f64> = (0..MOST_POINTS + 3).map(|x| x as f64).collect();
    book.write(batch(0, &many));
    let kept = book.take((*many.last().expect("many"), 0.0)).expect("kept");
    assert_eq!(kept.len(), MOST_POINTS);
    assert_eq!(kept[0].x, 3.0, "the oldest three left out");
}

#[test]
fn a_full_book_pushes_its_oldest_batch_out_and_counts_it() {
    let mut book = Book::EMPTY;
    for at in 0..=MOST_BATCHES {
        book.write(batch(at as i64, &[at as f64]));
    }
    assert_eq!(book.passed(), 1);
    assert_eq!(book.take((0.0, 0.0)), None, "the oldest is gone");
    assert!(book.take((1.0, 0.0)).is_some());
}

#[test]
fn a_point_the_os_says_nothing_more_of_reads_none_for_the_pen() {
    let words = Point::at(1.0, 2.0, 3).words();
    assert_eq!(words[..3], [1.0, 2.0, 3.0]);
    assert!(words[3..].iter().all(|word| word.is_nan()));
}

#[test]
fn a_point_is_handed_to_the_app_where_when_and_as_the_pen_read() {
    let point = Point { pressure: 0.5, tilt: 0.25, orientation: -1.5, ..Point::at(1.5, 2.25, 7) };
    assert_eq!(point.words(), [1.5, 2.25, 7.0, 0.5, 0.25, -1.5]);
    // A performance counter's microseconds a day after boot stay whole.
    assert_eq!(Point::at(0.0, 0.0, 86_400_000_001).words()[2], 86_400_000_001.0);
}
