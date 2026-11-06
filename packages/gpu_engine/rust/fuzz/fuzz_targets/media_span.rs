//! A framed medium, through the door the app reads a project's media by.
#![no_main]

libfuzzer_sys::fuzz_target!(|blob: &[u8]| decoder_fuzz::media_span(blob));
