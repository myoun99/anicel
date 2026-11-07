//! The container a sound is in: a span of a file, read through the one span
//! reader (`media::span`), which also reads a span the save FRAMED.
//!
//! ⚠️Positions are RELATIVE TO THE CONTAINER, never to the file. A decoder
//! that seeks to 0 must land on the container's first byte, not the
//! archive's — which for a carried sound is thousands of bytes earlier, and
//! reads as a corrupt file rather than as the arithmetic bug it is. The span
//! reader is where that arithmetic lives, once.

use std::ffi::{CStr, CString};
use std::io::{self, Read, Seek, SeekFrom};
use std::sync::{Arc, Mutex, PoisonError};

use media::span::Span;
use symphonia::core::io::MediaSource;

/// Where a container is stored: `[offset, offset + length)` of `path`, as it
/// is or framed.
struct Stored {
    path: CString,
    offset: i64,
    length: i64,
    framed: bool,
}

impl Stored {
    fn open(&self) -> Option<Span> {
        Span::open(&self.path, self.offset, self.length, self.framed)
    }
}

/// The container, shared: a decoder reads it through a cursor of its own
/// while the stream reads its boxes, to learn where the sound starts.
#[derive(Clone)]
pub(crate) struct Container {
    span: Arc<Mutex<Span>>,
    size: i64,
    stored: Arc<Stored>,
}

impl Container {
    /// The container stored in `[offset, offset + length)` of `path`, or
    /// None when the span is not inside the file ([Span::open]).
    pub(crate) fn open(path: &CStr, offset: i64, length: i64, framed: bool) -> Option<Container> {
        let stored = Stored { path: path.to_owned(), offset, length, framed };
        let span = stored.open()?;
        let size = span.size();
        Some(Container { span: Arc::new(Mutex::new(span)), size, stored: Arc::new(stored) })
    }

    /// The container's span opened once more, for a decoder that reads it
    /// on threads of its own (the OS stage's): its own file handle and
    /// position, never this container's.
    #[cfg(windows)]
    pub(crate) fn span_again(&self) -> Option<Span> {
        self.stored.open()
    }

    /// How many bytes the container has — for a framed span, decoded.
    pub(crate) fn size(&self) -> i64 {
        self.size
    }

    /// Up to `out.len()` bytes from `at` into `out`: how many — short at
    /// the end, and 0 past it or where the span would not read, which every
    /// reader here takes as the end.
    pub(crate) fn read_at(&self, at: i64, out: &mut [u8]) -> usize {
        self.span.lock().unwrap_or_else(PoisonError::into_inner).read(at, out).unwrap_or(0)
    }

    /// Whether all of `out` reads from `at`.
    pub(crate) fn read_all_at(&self, at: i64, out: &mut [u8]) -> bool {
        self.read_at(at, out) == out.len()
    }

    /// The container's first eight bytes — zeros past what reads.
    pub(crate) fn head(&self) -> [u8; 8] {
        let mut head = [0u8; 8];
        self.read_at(0, &mut head);
        head
    }
}

/// The container from `origin` on, as a decoder reads it: its position
/// counted from `origin`.
pub(crate) struct Cursor {
    container: Container,
    origin: i64,
    position: i64,
    seekable: bool,
}

impl Cursor {
    /// ⚠️`seekable` is what the source tells the decoder, not what the span
    /// can do — the MP3 reader is told no (see `bundled::open_mp3`).
    pub(crate) fn new(container: &Container, origin: i64, seekable: bool) -> Cursor {
        Cursor { container: container.clone(), origin, position: 0, seekable }
    }

    fn length(&self) -> i64 {
        self.container.size - self.origin
    }
}

impl Read for Cursor {
    fn read(&mut self, out: &mut [u8]) -> io::Result<usize> {
        if self.position >= self.length() {
            return Ok(0);
        }
        let read = self.container.read_at(self.origin + self.position, out);
        self.position += read as i64;
        Ok(read)
    }
}

impl Seek for Cursor {
    /// ⚠️Seeking exactly TO the end is legal (a decoder measuring the
    /// container does it); past it is not.
    fn seek(&mut self, to: SeekFrom) -> io::Result<u64> {
        let target = match to {
            SeekFrom::Start(offset) => i64::try_from(offset).ok(),
            SeekFrom::Current(offset) => self.position.checked_add(offset),
            SeekFrom::End(offset) => self.length().checked_add(offset),
        };
        match target {
            Some(target) if (0..=self.length()).contains(&target) => {
                self.position = target;
                Ok(target as u64)
            }
            _ => Err(io::Error::new(io::ErrorKind::InvalidInput, "a seek outside the container")),
        }
    }
}

impl MediaSource for Cursor {
    fn is_seekable(&self) -> bool {
        self.seekable
    }

    fn byte_len(&self) -> Option<u64> {
        Some(self.length() as u64)
    }
}
