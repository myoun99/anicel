use windows::Win32::Media::MediaFoundation::{MF_E_SHUTDOWN, MFCreateMediaSession};

use super::up;

// ⚠️The only test in this crate, and it must stay so: its first half needs a
// process in which nothing has started Media Foundation yet.
#[test]
fn it_is_down_until_asked_then_stays_up() {
    // SAFETY: no pointers; a session made is dropped at once.
    let before = unsafe { MFCreateMediaSession(None) };
    assert_eq!(before.err().map(|error| error.code()), Some(MF_E_SHUTDOWN));
    assert!(up());
    assert!(unsafe { MFCreateMediaSession(None) }.is_ok(), "a session needs MF started");
    assert!(up(), "asked again, it is still up");
}
