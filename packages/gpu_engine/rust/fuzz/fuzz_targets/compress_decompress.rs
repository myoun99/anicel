//! zstd frames, through the door the app reads a cel by.
#![no_main]

libfuzzer_sys::fuzz_target!(|frame: &[u8]| decoder_fuzz::compress_decompress(frame));
