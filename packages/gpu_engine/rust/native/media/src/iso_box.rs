//! 🚨★**A BOX OF AN ISO OR QUICKTIME FILE — ITS HEAD READ IN ONE PLACE.**
//!
//! A box's size is its first 32 bits — or, when those say 1, the 64 that
//! follow its type, and when they say 0, all the rest of what holds it
//! (ISO/IEC 14496-12, 4.2).
//!
//! ↩️Each walker read it for itself until 2026-11-10: the sound decoder's,
//! over a file (native/audio `start.rs`), and the export tests', over a
//! movie in memory (native/video `export/tests.rs` — which read the 32 bits
//! alone until 2026-11-07, and a MOV the Mac wrote stopped it at its first
//! box past `ftyp`: bundle GPU CI 42353590096). The third made them one:
//! the export's own, which writes its sound's edit list into the movie the
//! sink writer finished (native/video `export/edit_list.rs`).

/// A box's head: its type, how many bytes the head itself takes, and the
/// size it says.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Head {
    pub kind: [u8; 4],
    /// 8 — or 16, where a 64-bit size follows the type.
    pub bytes: usize,
    /// The size as the head says it. ⚠️Not the box's own where it
    /// [runs to the end](Head::runs_to_the_end): ask [Head::size_in].
    pub said: u64,
}

/// The head `bytes` open with — its first 16 are all that is read — or None
/// where they are too few for the head they start.
pub fn head(bytes: &[u8]) -> Option<Head> {
    let kind = bytes.get(4..8)?.try_into().ok()?;
    let short = u32::from_be_bytes(bytes.get(..4)?.try_into().ok()?);
    if short != 1 {
        return Some(Head { kind, bytes: 8, said: u64::from(short) });
    }
    let long = u64::from_be_bytes(bytes.get(8..16)?.try_into().ok()?);
    Some(Head { kind, bytes: 16, said: long })
}

impl Head {
    /// Whether the head says 「all the rest of what holds me」: 32 bits of 0.
    pub fn runs_to_the_end(&self) -> bool {
        self.bytes == 8 && self.said == 0
    }

    /// The whole box's size where `room` bytes are left to hold it, or None
    /// for a box that does not fit: shorter than its own head, or longer
    /// than the room.
    pub fn size_in(&self, room: u64) -> Option<u64> {
        let size = if self.runs_to_the_end() { room } else { self.said };
        (size >= self.bytes as u64 && size <= room).then_some(size)
    }
}

/// A box in a slice: its type, where it starts, where its body starts and
/// one past its end.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Atom {
    pub kind: [u8; 4],
    pub at: usize,
    pub body: usize,
    pub end: usize,
}

/// The box at `at` of `bytes`, when a whole one fits before `end`.
pub fn atom(bytes: &[u8], at: usize, end: usize) -> Option<Atom> {
    let held = bytes.get(at..end)?;
    let head = head(held)?;
    let size = usize::try_from(head.size_in(held.len() as u64)?).ok()?;
    Some(Atom { kind: head.kind, at, body: at + head.bytes, end: at + size })
}

/// The boxes directly in `bytes[start..end]`, up to the first that does not
/// fit.
pub fn atoms(bytes: &[u8], start: usize, end: usize) -> impl Iterator<Item = Atom> + '_ {
    let mut at = start;
    std::iter::from_fn(move || {
        let atom = atom(bytes, at, end)?;
        at = atom.end;
        Some(atom)
    })
}

/// The box `path` leads to under `bytes[start..end]`: the first of each
/// kind, each inside the one before.
pub fn find(bytes: &[u8], start: usize, end: usize, path: &[&[u8; 4]]) -> Option<Atom> {
    let (first, rest) = path.split_first()?;
    let atom = atoms(bytes, start, end).find(|atom| atom.kind == **first)?;
    if rest.is_empty() { Some(atom) } else { find(bytes, atom.body, atom.end, rest) }
}

/// Makes the box at `at` of `bytes` say it is `by` bytes longer, in the
/// form its head says its size — nothing to write where it runs to the end
/// of what holds it. None where no head is there, or its 32 bits cannot say
/// the new size.
pub fn grow(bytes: &mut [u8], at: usize, by: u64) -> Option<()> {
    let head = head(bytes.get(at..)?)?;
    if head.runs_to_the_end() {
        return Some(());
    }
    let size = head.said.checked_add(by)?;
    if head.bytes == 8 {
        bytes[at..at + 4].copy_from_slice(&u32::try_from(size).ok()?.to_be_bytes());
    } else {
        bytes[at + 8..at + 16].copy_from_slice(&size.to_be_bytes());
    }
    Some(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A plain box, one sized in 64 bits and one that runs to the end.
    fn each_form() -> Vec<u8> {
        let mut movie = vec![0, 0, 0, 12];
        movie.extend_from_slice(b"ftyp");
        movie.extend_from_slice(&[1, 2, 3, 4, 0, 0, 0, 1]);
        movie.extend_from_slice(b"free");
        movie.extend_from_slice(&20u64.to_be_bytes());
        movie.extend_from_slice(&[7, 7, 7, 7, 0, 0, 0, 0]);
        movie.extend_from_slice(b"mdat");
        movie.extend_from_slice(&[9; 6]);
        movie
    }

    // By hand, since no movie this machine writes has a box sized in 64
    // bits or one that runs to the end: a box of each after a plain one.
    // ↩️Held in native/video's export tests until the walkers became one
    // (2026-11-10).
    #[test]
    fn every_size_a_box_says_is_walked() {
        let movie = each_form();
        let spans: Vec<_> =
            atoms(&movie, 0, movie.len()).map(|atom| (atom.kind, atom.at, atom.body, atom.end)).collect();
        assert_eq!(spans, [(*b"ftyp", 0, 8, 12), (*b"free", 12, 28, 32), (*b"mdat", 32, 40, 46)]);
    }

    // Longer than what holds it, shorter than its own head — in 32 bits and
    // in 64 — and a head cut short.
    #[test]
    fn a_box_that_does_not_fit_is_no_box() {
        for size in [40, 5] {
            let unfit = [0, 0, 0, size, b'm', b'o', b'o', b'v', 0, 0, 0, 0];
            assert_eq!(atom(&unfit, 0, unfit.len()), None, "32 bits of {size}");
        }
        for size in [40u64, 15, 0] {
            let mut unfit = vec![0, 0, 0, 1];
            unfit.extend_from_slice(b"moov");
            unfit.extend_from_slice(&size.to_be_bytes());
            unfit.extend_from_slice(&[0; 8]);
            assert_eq!(atom(&unfit, 0, unfit.len()), None, "64 bits of {size}");
        }
        let cut = [0, 0, 0, 1, b'm', b'o', b'o', b'v', 0, 0, 0, 0];
        assert_eq!(head(&cut), None, "a 64-bit size that is not all there");
        assert_eq!(head(&cut[..7]), None, "a type that is not all there");
        assert_eq!(atom(&cut, 4, 2), None, "an end before the start");
    }

    #[test]
    fn a_path_leads_to_the_first_of_each_kind_inside_the_one_before() {
        // moov { free, trak { tkhd }, trak { tkhd, mdia } }
        let tkhd = [0, 0, 0, 8, b't', b'k', b'h', b'd'];
        let mdia = [0, 0, 0, 8, b'm', b'd', b'i', b'a'];
        let mut movie = vec![0, 0, 0, 56];
        movie.extend_from_slice(b"moov");
        movie.extend_from_slice(&[0, 0, 0, 8, b'f', b'r', b'e', b'e']);
        movie.extend_from_slice(&[0, 0, 0, 16, b't', b'r', b'a', b'k']);
        movie.extend_from_slice(&tkhd);
        movie.extend_from_slice(&[0, 0, 0, 24, b't', b'r', b'a', b'k']);
        movie.extend_from_slice(&tkhd);
        movie.extend_from_slice(&mdia);
        let found = |path: &[&[u8; 4]]| find(&movie, 0, movie.len(), path).map(|atom| (atom.at, atom.end));
        assert_eq!(found(&[b"moov"]), Some((0, 56)));
        assert_eq!(found(&[b"moov", b"trak"]), Some((16, 32)));
        assert_eq!(found(&[b"moov", b"trak", b"tkhd"]), Some((24, 32)));
        assert_eq!(found(&[b"moov", b"trak", b"mdia"]), None, "the first track has none, and only it is asked");
        assert_eq!(found(&[b"trak"]), None, "not directly inside");
        assert_eq!(found(&[]), None);
    }

    #[test]
    fn a_box_grows_in_the_form_its_head_says_its_size() {
        let mut movie = each_form();
        let before = movie.clone();
        assert_eq!(grow(&mut movie, 0, 36), Some(()));
        assert_eq!(movie[..4], [0, 0, 0, 48]);
        assert_eq!(grow(&mut movie, 12, 36), Some(()));
        assert_eq!(movie[20..28], 56u64.to_be_bytes());
        assert_eq!(grow(&mut movie, 32, 36), Some(()), "one that runs to the end has nothing to say");
        let changed: Vec<_> = (0..movie.len()).filter(|&at| movie[at] != before[at]).collect();
        assert_eq!(changed, [3, 27], "nothing but the two sizes");
        assert_eq!(grow(&mut movie, 0, u64::from(u32::MAX)), None, "32 bits cannot say it");
        assert_eq!(grow(&mut movie, 44, 36), None, "no head there");
    }
}
