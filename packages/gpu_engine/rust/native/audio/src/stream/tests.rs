use std::ffi::CString;

use super::{Decode, Opened, Stream};
use crate::FORMAT_OS;
use crate::container::Container;
use crate::start::Start;
use crate::tests::TempFile;

/// A decoder that says its shape only once it has handed a block back, as
/// the NDK's MediaCodec does by its output format.
struct SaysItLater {
    blocks: usize,
    handed: bool,
}

impl Decode for SaysItLater {
    fn next(&mut self, block: &mut Vec<f32>) -> usize {
        if self.blocks == 0 {
            return 0;
        }
        self.blocks -= 1;
        self.handed = true;
        block.clear();
        block.extend([0.25; 10]);
        10
    }

    fn shape(&self) -> Option<(i32, i32)> {
        self.handed.then_some((1, 8000))
    }
}

fn opened(blocks: usize) -> Opened {
    Opened {
        decoder: Box::new(SaysItLater { blocks, handed: false }),
        format: FORMAT_OS,
        channels: 2,
        sample_rate: 44_100,
        start: Start::default(),
    }
}

#[test]
fn the_first_block_fixes_the_shape_a_decoder_says_only_then() {
    let file = TempFile::new("shape.bin", &[0u8; 64]);
    let path = CString::new(file.path().to_str().expect("UTF-8")).expect("no NUL");
    let container = Container::open(&path, 0, 64, false).expect("a span");
    let mut stream = Stream::begin(&container, opened(2)).expect("a block came");
    assert_eq!((stream.channels(), stream.sample_rate()), (1, 8000), "what it said after the block, not as it opened");
    let mut out = [0f32; 20];
    assert_eq!(stream.pass(Some(&mut out), 20), 20, "both blocks, one channel each frame");
    // One that hands back nothing says nothing: the next decoder is asked.
    assert!(Stream::begin(&container, opened(0)).is_none());
}
