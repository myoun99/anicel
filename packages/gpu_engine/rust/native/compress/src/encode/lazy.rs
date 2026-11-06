//! The lazy parser at depth 2 (`ZSTD_compressBlock_lazy_generic`) over the
//! two match finders level 9 uses: rows of hashed positions with a tag
//! byte each (`ZSTD_RowFindBestMatch`, lazy2) and a binary tree sorted
//! lazily from hash chains (`ZSTD_DUBT_findBestMatch`, btlazy2).
//!
//! Positions are held as the C's indices — a byte's index is its offset
//! plus [`START`] — so that 0 stays "empty" in every table and each limit
//! compares as the C's does.

use std::ops::Range;

use super::Params;
use super::entropy::Store;
use crate::bits::highbit;

/// `ZSTD_WINDOW_START_INDEX`: the index of the input's first byte.
pub(super) const START: u32 = 2;
/// The offset a search answers when it finds nothing (`999999999`).
const NOT_FOUND: u32 = 999_999_999;
/// `ZSTD_DUBT_UNSORTED_MARK`.
const UNSORTED: u32 = 1;
/// `ZSTD_ROW_HASH_TAG_BITS`.
const TAG_BITS: u32 = 8;
/// `ZSTD_ROW_HASH_CACHE_SIZE`.
const CACHE: usize = 8;
/// `kSearchStrength`.
const SEARCH_STRENGTH: u32 = 8;
/// `kLazySkippingStep`.
const LAZY_SKIPPING_STEP: usize = 8;

fn index(position: usize) -> u32 {
    position as u32 + START
}

fn position(index: u32) -> usize {
    (index - START) as usize
}

fn read32(src: &[u8], at: usize) -> u32 {
    u32::from_le_bytes(src[at..at + 4].try_into().expect("4 bytes"))
}

fn read64(src: &[u8], at: usize) -> u64 {
    u64::from_le_bytes(src[at..at + 8].try_into().expect("8 bytes"))
}

/// `ZSTD_count`: how many bytes from `at` repeat those from `from`, up to
/// `end`.
fn count(src: &[u8], at: usize, from: usize, end: usize) -> usize {
    let mut length = 0;
    while at + length + 8 <= end {
        let differ = read64(src, at + length) ^ read64(src, from + length);
        if differ != 0 {
            return length + (differ.trailing_zeros() / 8) as usize;
        }
        length += 8;
    }
    while at + length < end && src[at + length] == src[from + length] {
        length += 1;
    }
    length
}

const PRIME_4: u32 = 2_654_435_761;
const PRIME_5: u64 = 889_523_592_379;

/// `ZSTD_hashPtrSalted` at a minimum match of 4 or 5 bytes, `bits` long.
fn hash(src: &[u8], at: usize, bits: u32, min_match: u32, salt: u64) -> u32 {
    if min_match == 5 {
        (((read64(src, at) << 24).wrapping_mul(PRIME_5) ^ salt) >> (64 - bits)) as u32
    } else {
        (read32(src, at).wrapping_mul(PRIME_4) ^ salt as u32) >> (32 - bits)
    }
}

/// What both finders share of `ZSTD_matchState_t`.
struct Shared {
    window_log: u32,
    search_log: u32,
    /// `mls`: the length hashed.
    min_match: u32,
    /// `window.lowLimit` and `window.dictLimit`, one index here: with no
    /// dictionary the window is one segment.
    low: u32,
    next_to_update: u32,
    /// `lazySkipping`.
    skipping: bool,
    hash: Vec<u32>,
}

impl Shared {
    /// `ZSTD_getLowestMatchIndex` (and `ZSTD_getLowestPrefixIndex`, the
    /// same here): the oldest index a match at `current` may reach.
    fn lowest(&self, current: u32) -> u32 {
        let max_distance = 1u32 << self.window_log;
        if current - self.low > max_distance { current - max_distance } else { self.low }
    }
}

/// The row match finder's own state.
struct Rows {
    /// `rowLog`: 2^log entries a row.
    log: u32,
    /// `rowHashLog`: the rows a table holds.
    hash_log: u32,
    /// `tagTable`: each row's tags, its first byte the row's head.
    tags: Vec<u8>,
    /// `hashCache`: the next positions' hashes, computed ahead.
    cache: [u32; CACHE],
    /// `hashSalt`.
    salt: u64,
}

/// `ZSTD_bitmix`, after XXH3's rrmxmx.
fn bitmix(mut value: u64, length: u64) -> u64 {
    const K: u64 = 0x9FB2_1C65_1E98_DF25;
    value ^= value.rotate_right(49) ^ value.rotate_right(24);
    value = value.wrapping_mul(K);
    value ^= (value >> 35).wrapping_add(length);
    value = value.wrapping_mul(K);
    value ^ (value >> 28)
}

impl Rows {
    fn mask(&self) -> u32 {
        (1 << self.log) - 1
    }

    fn hash(&self, shared: &Shared, src: &[u8], index: u32) -> u32 {
        hash(src, position(index), self.hash_log + TAG_BITS, shared.min_match, self.salt)
    }

    /// `ZSTD_row_nextIndex`: the slot a row's next entry takes — the head
    /// cycles back through 1..entries, slot 0 holding it.
    fn next_slot(&mut self, row: usize) -> usize {
        let mut next = u32::from(self.tags[row].wrapping_sub(1)) & self.mask();
        if next == 0 {
            next = self.mask();
        }
        self.tags[row] = next as u8;
        next as usize
    }

    /// `ZSTD_row_fillHashCache`: the hashes from `index` on, not past
    /// position `limit`.
    fn fill_cache(&mut self, shared: &Shared, src: &[u8], index: u32, limit: isize) {
        let first = position(index) as isize;
        let count = if first > limit { 0 } else { (limit - first + 1) as u32 };
        for at in index..index + count.min(CACHE as u32) {
            self.cache[at as usize & (CACHE - 1)] = self.hash(shared, src, at);
        }
    }

    /// `ZSTD_row_nextCachedHash`: `index`'s hash, the one `CACHE` on
    /// computed in its place.
    fn next_hash(&mut self, shared: &Shared, src: &[u8], index: u32) -> u32 {
        let ahead = self.hash(shared, src, index + CACHE as u32);
        std::mem::replace(&mut self.cache[index as usize & (CACHE - 1)], ahead)
    }

    /// `ZSTD_row_update_internalImpl`.
    fn insert(&mut self, shared: &mut Shared, src: &[u8], from: u32, to: u32) {
        for at in from..to {
            let hash = self.next_hash(shared, src, at);
            let row = ((hash >> TAG_BITS) << self.log) as usize;
            let slot = self.next_slot(row);
            self.tags[row + slot] = hash as u8;
            shared.hash[row + slot] = at;
        }
    }

    /// `ZSTD_row_update_internal`: every position up to `target` in — past
    /// a long match only its first 96 and last 32.
    fn update(&mut self, shared: &mut Shared, src: &[u8], target: u32) {
        let mut from = shared.next_to_update;
        if target.wrapping_sub(from) > 384 {
            self.insert(shared, src, from, from + 96);
            from = target - 32;
            self.fill_cache(shared, src, from, position(target) as isize + 1);
        }
        self.insert(shared, src, from, target);
        shared.next_to_update = target;
    }

    /// The slots of `row` whose tag is `tag`, as a mask rotated to start at
    /// the head — newest first (`ZSTD_row_getMatchMask`).
    fn matching(&self, row: usize, tag: u8, head: u32) -> u64 {
        let entries = 1u32 << self.log;
        let mut mask = 0u64;
        for (slot, &t) in self.tags[row..row + entries as usize].iter().enumerate() {
            mask |= u64::from(t == tag) << slot;
        }
        if head == 0 { mask } else { ((mask >> head) | (mask << (entries - head))) & (u64::MAX >> (64 - entries)) }
    }

    /// `ZSTD_RowFindBestMatch`: the longest match at `ip` among the
    /// entries of its row whose tag agrees; `ip` is entered behind them.
    fn search(&mut self, shared: &mut Shared, src: &[u8], ip: usize, end: usize) -> (usize, u32) {
        let current = index(ip);
        let low = shared.lowest(current);
        let mut attempts = 1u32 << shared.search_log.min(self.log);
        let hash = if !shared.skipping {
            self.update(shared, src, current);
            self.next_hash(shared, src, current)
        } else {
            // Skipping: only the searched positions go in, uncached.
            shared.next_to_update = current;
            self.hash(shared, src, current)
        };
        let row = ((hash >> TAG_BITS) << self.log) as usize;
        let tag = hash as u8;
        let head = u32::from(self.tags[row]) & self.mask();
        let mut matches = self.matching(row, tag, head);
        let mut candidates = [0u32; 64];
        let mut found = 0;
        while matches != 0 && attempts > 0 {
            let slot = (head + matches.trailing_zeros()) & self.mask();
            matches &= matches - 1;
            let candidate = shared.hash[row + slot as usize];
            if slot == 0 {
                continue;
            }
            if candidate < low {
                break;
            }
            candidates[found] = candidate;
            found += 1;
            attempts -= 1;
        }
        let slot = self.next_slot(row);
        self.tags[row + slot] = tag;
        shared.hash[row + slot] = shared.next_to_update;
        shared.next_to_update += 1;

        let (mut best, mut off_base) = (3, NOT_FOUND);
        for &candidate in &candidates[..found] {
            let from = position(candidate);
            // Only one that agrees on the bytes ending past the best yet.
            if read32(src, from + best - 3) == read32(src, ip + best - 3) {
                let length = count(src, ip, from, end);
                if length > best {
                    best = length;
                    off_base = current - candidate + 3;
                    if ip + length == end {
                        break;
                    }
                }
            }
        }
        (best, off_base)
    }
}

/// The tree's own state: `chainTable` as pairs — a node's smaller and
/// larger child once sorted; before, the next in its hash chain and the
/// unsorted mark.
struct Tree {
    hash_log: u32,
    /// `chainLog - 1`: the pairs the tree holds.
    log: u32,
    nodes: Vec<u32>,
}

/// Where a search writes the next child it finds: a slot of the tree, or
/// nowhere (the C's `dummy32`) once past the tree's reach.
const NOWHERE: usize = usize::MAX;

impl Tree {
    fn mask(&self) -> u32 {
        (1 << self.log) - 1
    }

    fn pair(&self, index: u32) -> usize {
        2 * (index & self.mask()) as usize
    }

    fn set(&mut self, slot: usize, value: u32) {
        if slot != NOWHERE {
            self.nodes[slot] = value;
        }
    }

    /// `ZSTD_updateDUBT`: every position up to `target` pushed on its hash
    /// chain, unsorted.
    fn update(&mut self, shared: &mut Shared, src: &[u8], target: u32) {
        for at in shared.next_to_update..target {
            let hash = hash(src, position(at), self.hash_log, shared.min_match, 0) as usize;
            let next = shared.hash[hash];
            shared.hash[hash] = at;
            let pair = self.pair(at);
            self.nodes[pair] = next;
            self.nodes[pair + 1] = UNSORTED;
        }
        shared.next_to_update = target;
    }

    /// `ZSTD_insertDUBT1`: sorts the unsorted `current` into the tree.
    fn insert(&mut self, shared: &Shared, src: &[u8], current: u32, end: usize, mut compares: u32, tree_low: u32) {
        let ip = position(current);
        let mut smaller = self.pair(current);
        let mut larger = smaller + 1;
        let mut candidate = self.nodes[smaller];
        let (mut common_smaller, mut common_larger) = (0, 0);
        let max_distance = 1u32 << shared.window_log;
        let window_low =
            if current - shared.low > max_distance { current - max_distance } else { shared.low };
        while compares > 0 && candidate > window_low {
            let next = self.pair(candidate);
            let from = position(candidate);
            let mut length = common_smaller.min(common_larger);
            length += count(src, ip + length, from + length, end);
            if ip + length == end {
                // Equal to the end: no way to know which side it is on.
                break;
            }
            if src[from + length] < src[ip + length] {
                self.set(smaller, candidate);
                common_smaller = length;
                if candidate <= tree_low {
                    smaller = NOWHERE;
                    break;
                }
                smaller = next + 1;
                candidate = self.nodes[next + 1];
            } else {
                self.set(larger, candidate);
                common_larger = length;
                if candidate <= tree_low {
                    larger = NOWHERE;
                    break;
                }
                larger = next;
                candidate = self.nodes[next];
            }
            compares -= 1;
        }
        self.set(smaller, 0);
        self.set(larger, 0);
    }

    /// `ZSTD_DUBT_findBestMatch`: sorts the chain's unsorted head into the
    /// tree, then walks the tree for `ip`, inserting it.
    fn find(&mut self, shared: &mut Shared, src: &[u8], ip: usize, end: usize) -> (usize, u32) {
        let hash = hash(src, ip, self.hash_log, shared.min_match, 0) as usize;
        let current = index(ip);
        let window_low = shared.lowest(current);
        let mask = self.mask();
        let tree_low = if mask >= current { 0 } else { current - mask };
        let unsort_limit = tree_low.max(window_low);
        let mut compares = 1u32 << shared.search_log;
        let mut candidates = compares;
        let mut previous = 0;

        // Down to the end of the unsorted run, reversing it.
        let mut candidate = shared.hash[hash];
        let mut pair = self.pair(candidate);
        while candidate > unsort_limit && self.nodes[pair + 1] == UNSORTED && candidates > 1 {
            self.nodes[pair + 1] = previous;
            previous = candidate;
            candidate = self.nodes[pair];
            pair = self.pair(candidate);
            candidates -= 1;
        }
        if candidate > unsort_limit && self.nodes[pair + 1] == UNSORTED {
            // Still unsorted: dropped, for speed.
            self.nodes[pair] = 0;
            self.nodes[pair + 1] = 0;
        }
        // Back up the run, sorting each in.
        candidate = previous;
        while candidate != 0 {
            let next = self.nodes[self.pair(candidate) + 1];
            self.insert(shared, src, candidate, end, candidates, unsort_limit);
            candidate = next;
            candidates += 1;
        }

        let (mut common_smaller, mut common_larger) = (0, 0);
        let mut smaller = self.pair(current);
        let mut larger = smaller + 1;
        let mut match_end = current + 8 + 1;
        let (mut best, mut off_base) = (0, NOT_FOUND);
        candidate = shared.hash[hash];
        shared.hash[hash] = current;
        while compares > 0 && candidate > window_low {
            let next = self.pair(candidate);
            let from = position(candidate);
            let mut length = common_smaller.min(common_larger);
            length += count(src, ip + length, from + length, end);
            if length > best {
                if length > (match_end - candidate) as usize {
                    match_end = candidate + length as u32;
                }
                let gain = highbit(current - candidate + 1).wrapping_sub(highbit(off_base)) as i32;
                if 4 * (length - best) as i32 > gain {
                    best = length;
                    off_base = current - candidate + 3;
                }
                if ip + length == end {
                    break;
                }
            }
            if src[from + length] < src[ip + length] {
                self.set(smaller, candidate);
                common_smaller = length;
                if candidate <= tree_low {
                    smaller = NOWHERE;
                    break;
                }
                smaller = next + 1;
                candidate = self.nodes[next + 1];
            } else {
                self.set(larger, candidate);
                common_larger = length;
                if candidate <= tree_low {
                    larger = NOWHERE;
                    break;
                }
                larger = next;
                candidate = self.nodes[next];
            }
            compares -= 1;
        }
        self.set(smaller, 0);
        self.set(larger, 0);
        // Past a long match, positions inside it are skipped.
        shared.next_to_update = match_end - 8;
        (best, off_base)
    }

    /// `ZSTD_BtFindBestMatch`.
    fn search(&mut self, shared: &mut Shared, src: &[u8], ip: usize, end: usize) -> (usize, u32) {
        let current = index(ip);
        if current < shared.next_to_update {
            return (0, NOT_FOUND);
        }
        self.update(shared, src, current);
        self.find(shared, src, ip, end)
    }
}

enum Search {
    Rows(Rows),
    Tree(Tree),
}

/// The match state of one compression: tables zeroed, salt fresh, as
/// `ZSTD_compress` makes them for each call.
pub(super) struct Finder {
    shared: Shared,
    search: Search,
}

impl Finder {
    /// `ZSTD_reset_matchState` for `params`: btlazy2's tree, or lazy2's
    /// rows.
    pub(super) fn new(params: &Params) -> Self {
        let Params { window_log, chain_log, hash_log, search_log, min_match, tree } = *params;
        let shared = Shared {
            window_log,
            search_log,
            min_match: min_match.clamp(4, 6),
            low: START,
            next_to_update: START,
            skipping: false,
            hash: vec![0; 1 << hash_log],
        };
        let search = if !tree {
            let log = search_log.clamp(4, 6);
            Search::Rows(Rows {
                log,
                hash_log: hash_log - log,
                tags: vec![0; 1 << hash_log],
                cache: [0; CACHE],
                // A fresh context's salt: its first advance, from no entropy.
                salt: bitmix(0, 8) ^ bitmix(0, 4),
            })
        } else {
            Search::Tree(Tree { hash_log, log: chain_log - 1, nodes: vec![0; 1 << chain_log] })
        };
        Finder { shared, search }
    }

    /// `ZSTD_window_enforceMaxDist` for the block starting at `start`, and
    /// insertion resumed no lower than the window.
    pub(super) fn enter_block(&mut self, start: usize) {
        let max_distance = 1u32 << self.shared.window_log;
        let start = index(start);
        if start > max_distance && self.shared.low < start - max_distance {
            self.shared.low = start - max_distance;
        }
        self.shared.next_to_update = self.shared.next_to_update.max(self.shared.low);
    }

    /// `ZSTD_buildSeqStore`'s "limited update": past a long match from the
    /// last block, only the last 192 positions before `start` go in.
    pub(super) fn skip_long_match(&mut self, start: usize) {
        let current = index(start);
        let next = self.shared.next_to_update;
        if current > next + 384 {
            self.shared.next_to_update = current - 192.min(current - next - 384);
        }
    }

    fn search(&mut self, src: &[u8], ip: usize, end: usize) -> (usize, u32) {
        match &mut self.search {
            Search::Rows(rows) => rows.search(&mut self.shared, src, ip, end),
            Search::Tree(tree) => tree.search(&mut self.shared, src, ip, end),
        }
    }

    fn fill_cache(&mut self, src: &[u8], limit: isize) {
        if let Search::Rows(rows) = &mut self.search {
            rows.fill_cache(&self.shared, src, self.shared.next_to_update, limit);
        }
    }

    /// `ZSTD_compressBlock_lazy_generic` at depth 2: the block's sequences
    /// into `store`, the repeat offsets carried in `reps`; the literals
    /// left after the last match.
    pub(super) fn parse(&mut self, src: &[u8], block: Range<usize>, reps: &mut [u32; 3], store: &mut Store) -> usize {
        let Range { start: istart, end: iend } = block;
        let rows = matches!(self.search, Search::Rows(_));
        let limit = iend as isize - 8 - if rows { CACHE as isize } else { 0 };
        let prefix = position(self.shared.low);
        let mut ip = istart + usize::from(istart == prefix);
        let mut anchor = istart;
        let (mut offset_1, mut offset_2) = (reps[0], reps[1]);
        let (mut saved_1, mut saved_2) = (0, 0);
        let max_rep = index(ip) - self.shared.lowest(index(ip));
        if offset_2 > max_rep {
            (saved_2, offset_2) = (offset_2, 0);
        }
        if offset_1 > max_rep {
            (saved_1, offset_1) = (offset_1, 0);
        }
        self.shared.skipping = false;
        self.fill_cache(src, limit);

        let repeats = |at: usize, offset: u32| offset > 0 && read32(src, at) == read32(src, at - offset as usize);
        while (ip as isize) < limit {
            let mut length = 0;
            let mut off_base = 1;
            let mut start = ip + 1;
            if repeats(ip + 1, offset_1) {
                length = count(src, ip + 1 + 4, ip + 1 + 4 - offset_1 as usize, iend) + 4;
            }
            let (found, found_off) = self.search(src, ip, iend);
            if found > length {
                (length, start, off_base) = (found, ip, found_off);
            }
            if length < 4 {
                // Faster over what does not compress.
                let step = ((ip - anchor) >> SEARCH_STRENGTH) + 1;
                ip += step;
                self.shared.skipping = step > LAZY_SKIPPING_STEP;
                continue;
            }

            // A better match one or two bytes on?
            while (ip as isize) < limit {
                ip += 1;
                if repeats(ip, offset_1) {
                    let repeat = count(src, ip + 4, ip + 4 - offset_1 as usize, iend) + 4;
                    let gain = (length * 3) as i32 - highbit(off_base) as i32 + 1;
                    if repeat >= 4 && (repeat * 3) as i32 > gain {
                        (length, off_base, start) = (repeat, 1, ip);
                    }
                }
                let (found, found_off) = self.search(src, ip, iend);
                let gain = (length * 4) as i32 - highbit(off_base) as i32 + 4;
                if found >= 4 && (found * 4) as i32 - highbit(found_off) as i32 > gain {
                    (length, off_base, start) = (found, found_off, ip);
                    continue;
                }
                if (ip as isize) < limit {
                    ip += 1;
                    if repeats(ip, offset_1) {
                        let repeat = count(src, ip + 4, ip + 4 - offset_1 as usize, iend) + 4;
                        let gain = (length * 4) as i32 - highbit(off_base) as i32 + 1;
                        if repeat >= 4 && (repeat * 4) as i32 > gain {
                            (length, off_base, start) = (repeat, 1, ip);
                        }
                    }
                    let (found, found_off) = self.search(src, ip, iend);
                    let gain = (length * 4) as i32 - highbit(off_base) as i32 + 7;
                    if found >= 4 && (found * 4) as i32 - highbit(found_off) as i32 > gain {
                        (length, off_base, start) = (found, found_off, ip);
                        continue;
                    }
                }
                break;
            }

            if off_base > 3 {
                // Catch up backwards over bytes the match also covers.
                let offset = (off_base - 3) as usize;
                while start > anchor && start - offset > prefix && src[start - 1] == src[start - offset - 1] {
                    start -= 1;
                    length += 1;
                }
                (offset_2, offset_1) = (offset_1, offset as u32);
            }
            store.push(&src[anchor..start], off_base, length);
            ip = start + length;
            anchor = ip;
            if self.shared.skipping {
                self.fill_cache(src, limit);
                self.shared.skipping = false;
            }

            // The second repeat offset straight after.
            while (ip as isize) <= limit && repeats(ip, offset_2) {
                let length = count(src, ip + 4, ip + 4 - offset_2 as usize, iend) + 4;
                (offset_1, offset_2) = (offset_2, offset_1);
                store.push(&[], 1, length);
                ip += length;
                anchor = ip;
            }
        }

        // An offset that started out of reach and is replaced moves down.
        if saved_1 != 0 && offset_1 != 0 {
            saved_2 = saved_1;
        }
        reps[0] = if offset_1 != 0 { offset_1 } else { saved_1 };
        reps[1] = if offset_2 != 0 { offset_2 } else { saved_2 };
        iend - anchor
    }
}
