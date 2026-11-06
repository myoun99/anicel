//! A sound's container, through the door the app takes a sound in by.
#![no_main]

libfuzzer_sys::fuzz_target!(|container: &[u8]| decoder_fuzz::audio_stream(container));
