//! Linux and anything else: no OS reader this app can lean on. The answer
//! is 「none」, and the window says 「no video decoder in this build」 rather
//! than failing as a corrupt file.

use std::ffi::CStr;

use super::{Opened, Why};

pub const SUPPORTED: bool = false;

/// Nothing ever opens, so nothing is held.
pub struct Reader;

impl Reader {
    pub fn open(_path: &CStr, _span: Option<(i64, i64, bool)>) -> Result<(Reader, Opened), Why> {
        Err("no video decoder in this build".into())
    }

    pub fn reposition(&mut self, _index: i64, _rate: (i32, i32)) -> Result<(), Why> {
        Err("no video decoder in this build".into())
    }

    pub fn read(&mut self, _index: i64, _rate: (i32, i32), _rgba: &mut [u8]) -> Result<(), Why> {
        Err("no video decoder in this build".into())
    }
}
