//! What a mask is laid under, as the app hands it ([`PaintOf`]): read from
//! its tag and the numbers that tag reads, and refused where one is none
//! the host knows. What a paint lays is the stamp's (`stamp_tests.rs`).

use super::super::stamp::Shape;
use super::{CIRCLE, COLOUR, GRADIENT, LINE, PaintOf};
use crate::testing::last_error;

fn read(numbers: &[f64]) -> Option<PaintOf> {
    // SAFETY: each paint here holds its tag and the numbers that tag reads.
    unsafe { PaintOf::read(numbers.as_ptr()) }
}

#[test]
fn a_colour_is_its_word_s_red_green_and_blue_its_alpha_unread() {
    let Some(PaintOf::Colour(colour)) = read(&[COLOUR, f64::from(0x80CC_6633u32)]) else {
        panic!("{}", last_error());
    };
    assert_eq!(colour, [0x33, 0x66, 0xCC]);
}

#[test]
fn a_gradient_is_its_shape_its_two_ends_and_their_colours_in_turn() {
    let start = f64::from(0xFF00_0000u32);
    let end = f64::from(0x0011_2233u32);
    let Some(PaintOf::Gradient(circle)) = read(&[GRADIENT, CIRCLE, 1.5, -2.0, 30.25, 4.0, start, end])
    else {
        panic!("{}", last_error());
    };
    assert!(matches!(circle.shape, Shape::Circle));
    assert_eq!((circle.from, circle.to), ((1.5, -2.0), (30.25, 4.0)));
    assert_eq!((circle.start, circle.end), ([0, 0, 0, 0xFF], [0x33, 0x22, 0x11, 0]));
    let Some(PaintOf::Gradient(line)) = read(&[GRADIENT, LINE, 0.0, 0.0, 1.0, 0.0, end, start]) else {
        panic!("{}", last_error());
    };
    assert!(matches!(line.shape, Shape::Line));
    assert_eq!((line.start, line.end), ([0x33, 0x22, 0x11, 0], [0, 0, 0, 0xFF]));
}

#[test]
fn a_paint_the_host_does_not_know_is_refused_and_says_so() {
    assert!(read(&[2.0]).is_none());
    assert!(last_error().contains("tagged 2"), "{}", last_error());
    assert!(read(&[GRADIENT, 2.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0]).is_none());
    assert!(last_error().contains("shape 2"), "{}", last_error());
    for word in [0.5, -1.0, f64::from(u32::MAX) + 1.0, f64::NAN] {
        assert!(read(&[COLOUR, word]).is_none(), "{word}");
        assert!(last_error().contains("no pixel's word"), "{word}: {}", last_error());
    }
    assert!(read(&[GRADIENT, LINE, 0.0, 0.0, 1.0, 0.0, 0.0, 0.25]).is_none());
    assert!(last_error().contains("no pixel's word"), "{}", last_error());
}
