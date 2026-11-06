//! Huffman, the encoding half (`huf_compress.c`): a literal section's code
//! lengths from its histogram, capped at a depth; their description; and
//! the bytes coded with them in one stream or four.

use super::Repeat;
use super::fse;
use super::stream::Stream;
use crate::bits::highbit;
use crate::huffman::{SYMBOLS, TABLE_LOG_MAX};

/// `LitHufLog`: the deepest code a literal section uses.
const LITERALS_LOG: u32 = 11;
/// `MAX_FSE_TABLELOG_FOR_HUFF_HEADER`.
const WEIGHTS_LOG: u32 = 6;

#[derive(Clone, Copy, Default)]
struct Code {
    bits: u8,
    value: u16,
}

/// `HUF_CElt[]` with its header.
#[derive(Clone)]
pub(super) struct Table {
    log: u32,
    max_symbol: u32,
    codes: [Code; SYMBOLS],
}

impl Table {
    pub(super) fn new() -> Self {
        Table { log: 0, max_symbol: 0, codes: [Code::default(); SYMBOLS] }
    }
}

/// `nodeElt`.
#[derive(Clone, Copy, Default)]
struct Node {
    count: u32,
    parent: u16,
    symbol: u8,
    bits: u8,
}

/// `huffNodeTable` and the barrier before it: node `i` sits at `i + 1`, so
/// that the barrier is node -1.
const NODES: usize = 2 * SYMBOLS + 1;
/// `STARTNODE`: the first parent.
const FIRST_PARENT: i32 = SYMBOLS as i32;

fn at(node: i32) -> usize {
    (node + 1) as usize
}

/// `RANK_POSITION_TABLE_SIZE`: the buckets `HUF_sort` counts into.
const BUCKETS: usize = 192;
/// `RANK_POSITION_LOG_BUCKETS_BEGIN`: past the distinct counts, a bucket
/// per power of two.
const LOG_BUCKETS_BEGIN: u32 = (BUCKETS as u32 - 1) - 32 - 1;
/// `RANK_POSITION_DISTINCT_COUNT_CUTOFF`.
const DISTINCT_CUTOFF: u32 = LOG_BUCKETS_BEGIN + (31 - LOG_BUCKETS_BEGIN.leading_zeros());

/// `HUF_getIndex`.
fn bucket(count: u32) -> usize {
    (if count < DISTINCT_CUTOFF { count } else { highbit(count) + LOG_BUCKETS_BEGIN }) as usize
}

/// `HUF_insertionSort`: by count, descending, ties in place.
fn insertion_sort(nodes: &mut [Node], low: i32, high: i32) {
    let nodes = &mut nodes[low as usize..];
    for i in 1..(high - low + 1).max(0) as usize {
        let key = nodes[i];
        let mut j = i as i32 - 1;
        while j >= 0 && nodes[j as usize].count < key.count {
            nodes[j as usize + 1] = nodes[j as usize];
            j -= 1;
        }
        nodes[(j + 1) as usize] = key;
    }
}

/// `HUF_quickSortPartition`: the last node is the pivot.
fn partition(nodes: &mut [Node], low: i32, high: i32) -> i32 {
    let pivot = nodes[high as usize].count;
    let mut i = low - 1;
    for j in low..high {
        if nodes[j as usize].count > pivot {
            i += 1;
            nodes.swap(i as usize, j as usize);
        }
    }
    nodes.swap((i + 1) as usize, high as usize);
    i + 1
}

/// `HUF_simpleQuickSort`: not stable — equal counts in a large bucket move,
/// and the C's order is the one the tree is built in.
fn quick_sort(nodes: &mut [Node], mut low: i32, mut high: i32) {
    if high - low < 8 {
        insertion_sort(nodes, low, high);
        return;
    }
    while low < high {
        let pivot = partition(nodes, low, high);
        if pivot - low < high - pivot {
            quick_sort(nodes, low, pivot - 1);
            low = pivot + 1;
        } else {
            quick_sort(nodes, pivot + 1, high);
            high = pivot - 1;
        }
    }
}

/// `HUF_sort`: symbols 0..=`max_symbol` by count, descending — bucketed,
/// then the buckets that hold more than one count sorted.
fn sort(nodes: &mut [Node], count: &[u32; SYMBOLS], max_symbol: u32) {
    let symbols = max_symbol as usize + 1;
    let mut base = [0u16; BUCKETS];
    let mut next = [0u16; BUCKETS];
    for &c in &count[..symbols] {
        base[bucket(c)] += 1;
    }
    for n in (1..BUCKETS).rev() {
        base[n - 1] += base[n];
        next[n - 1] = base[n - 1];
    }
    for (symbol, &c) in count[..symbols].iter().enumerate() {
        let rank = bucket(c) + 1;
        let position = next[rank] as usize;
        next[rank] += 1;
        nodes[position].count = c;
        nodes[position].symbol = symbol as u8;
    }
    for n in DISTINCT_CUTOFF as usize..BUCKETS - 1 {
        let size = i32::from(next[n] - base[n]);
        if size > 1 {
            quick_sort(&mut nodes[base[n] as usize..], 0, size - 1);
        }
    }
}

/// `HUF_buildTree`: the unlimited tree over the sorted symbols; the last
/// symbol counted.
fn build_tree(nodes: &mut [Node; NODES], max_symbol: u32) -> i32 {
    let mut last = max_symbol as i32;
    while nodes[at(last)].count == 0 {
        last -= 1;
    }
    let mut low_symbol = last;
    let root = FIRST_PARENT + low_symbol - 1;
    let mut low_parent = FIRST_PARENT;
    let mut parent = FIRST_PARENT;
    nodes[at(parent)].count = nodes[at(low_symbol)].count + nodes[at(low_symbol - 1)].count;
    nodes[at(low_symbol)].parent = parent as u16;
    nodes[at(low_symbol - 1)].parent = parent as u16;
    parent += 1;
    low_symbol -= 2;
    for n in parent..=root {
        nodes[at(n)].count = 1 << 30;
    }
    nodes[at(-1)].count = 1 << 31;
    while parent <= root {
        let mut lightest = || {
            if nodes[at(low_symbol)].count < nodes[at(low_parent)].count {
                low_symbol -= 1;
                low_symbol + 1
            } else {
                low_parent += 1;
                low_parent - 1
            }
        };
        let (one, two) = (lightest(), lightest());
        nodes[at(parent)].count = nodes[at(one)].count + nodes[at(two)].count;
        nodes[at(one)].parent = parent as u16;
        nodes[at(two)].parent = parent as u16;
        parent += 1;
    }
    nodes[at(root)].bits = 0;
    for n in (FIRST_PARENT..root).rev() {
        nodes[at(n)].bits = nodes[at(i32::from(nodes[at(n)].parent))].bits + 1;
    }
    for n in 0..=last {
        nodes[at(n)].bits = nodes[at(i32::from(nodes[at(n)].parent))].bits + 1;
    }
    last
}

/// `HUF_setMaxHeight`: no code deeper than `target`, the tree kept whole
/// by deepening the cheapest shallow codes; the depth it comes to.
fn set_max_height(nodes: &mut [Node; NODES], last: i32, target: u32) -> u32 {
    let largest_bits = u32::from(nodes[at(last)].bits);
    if largest_bits <= target {
        return largest_bits;
    }
    let mut total_cost = 0i32;
    let base_cost = 1u32 << (largest_bits - target);
    let mut n = last;
    while u32::from(nodes[at(n)].bits) > target {
        total_cost += (base_cost - (1 << (largest_bits - u32::from(nodes[at(n)].bits)))) as i32;
        nodes[at(n)].bits = target as u8;
        n -= 1;
    }
    while u32::from(nodes[at(n)].bits) == target {
        n -= 1;
    }
    total_cost >>= largest_bits - target;

    const NO_SYMBOL: u32 = 0xF0F0_F0F0;
    // The last (rarest) symbol of each depth above the target.
    let mut rank_last = [NO_SYMBOL; TABLE_LOG_MAX as usize + 2];
    let mut current = target;
    for position in (0..=n).rev() {
        let bits = u32::from(nodes[at(position)].bits);
        if bits < current {
            current = bits;
            rank_last[(target - current) as usize] = position as u32;
        }
    }
    while total_cost > 0 {
        let mut decrease = highbit(total_cost as u32) + 1;
        while decrease > 1 {
            let high = rank_last[decrease as usize];
            let low = rank_last[decrease as usize - 1];
            if high == NO_SYMBOL {
                decrease -= 1;
                continue;
            }
            if low == NO_SYMBOL || nodes[at(high as i32)].count <= 2 * nodes[at(low as i32)].count {
                break;
            }
            decrease -= 1;
        }
        while decrease <= TABLE_LOG_MAX && rank_last[decrease as usize] == NO_SYMBOL {
            decrease += 1;
        }
        total_cost -= 1 << (decrease - 1);
        let moved = rank_last[decrease as usize];
        nodes[at(moved as i32)].bits += 1;
        if rank_last[decrease as usize - 1] == NO_SYMBOL {
            rank_last[decrease as usize - 1] = moved;
        }
        if moved == 0 {
            rank_last[decrease as usize] = NO_SYMBOL;
        } else {
            rank_last[decrease as usize] -= 1;
            let previous = rank_last[decrease as usize];
            if u32::from(nodes[at(previous as i32)].bits) != target.wrapping_sub(decrease) {
                rank_last[decrease as usize] = NO_SYMBOL;
            }
        }
    }
    // Overshot: give back from the shallowest depth below the target.
    while total_cost < 0 {
        if rank_last[1] == NO_SYMBOL {
            while u32::from(nodes[at(n)].bits) == target {
                n -= 1;
            }
            nodes[at(n + 1)].bits -= 1;
            rank_last[1] = (n + 1) as u32;
        } else {
            nodes[at(rank_last[1] as i32 + 1)].bits -= 1;
            rank_last[1] += 1;
        }
        total_cost += 1;
    }
    target
}

/// `HUF_buildCTable_wksp`: `count`'s code lengths, the deepest capped at
/// `max_bits`, and their canonical codes; the depth it came to.
fn build(table: &mut Table, count: &[u32; SYMBOLS], max_symbol: u32, max_bits: u32) -> u32 {
    let mut nodes = [Node::default(); NODES];
    sort(&mut nodes[1..], count, max_symbol);
    let last = build_tree(&mut nodes, max_symbol);
    let max_bits = set_max_height(&mut nodes, last, max_bits);
    // `HUF_buildCTableFromTree`.
    let mut per_rank = [0u16; TABLE_LOG_MAX as usize + 1];
    let mut first_value = [0u16; TABLE_LOG_MAX as usize + 1];
    for n in 0..=last {
        per_rank[nodes[at(n)].bits as usize] += 1;
    }
    let mut min = 0u16;
    for bits in (1..=max_bits as usize).rev() {
        first_value[bits] = min;
        min += per_rank[bits];
        min >>= 1;
    }
    for n in 0..=max_symbol as i32 {
        let node = nodes[at(n)];
        table.codes[node.symbol as usize] = Code { bits: node.bits, value: 0 };
    }
    for code in &mut table.codes[..=max_symbol as usize] {
        if code.bits > 0 {
            code.value = first_value[code.bits as usize];
        }
        first_value[code.bits as usize] += 1;
    }
    table.log = max_bits;
    table.max_symbol = max_symbol;
    max_bits
}

/// `HUF_compressWeights`: the weights FSE-coded — the size, 1 when they
/// are all one weight, 0 when coding them does not pay.
fn code_weights(out: &mut [u8], weights: &[u8]) -> Option<usize> {
    if weights.len() <= 1 {
        return Some(0);
    }
    let mut count = [0u32; TABLE_LOG_MAX as usize + 1];
    for &w in weights {
        count[w as usize] += 1;
    }
    let mut max_symbol = TABLE_LOG_MAX;
    while count[max_symbol as usize] == 0 {
        max_symbol -= 1;
    }
    let largest = count.iter().copied().max().unwrap_or(0) as usize;
    if largest == weights.len() {
        return Some(1);
    }
    if largest == 1 {
        return Some(0);
    }
    let log = fse::optimal_table_log(WEIGHTS_LOG, weights.len(), max_symbol, 2);
    let mut norm = [0i16; fse::SYMBOLS];
    fse::normalize(&mut norm, log, &count, weights.len(), max_symbol, false)?;
    let header = fse::describe(out, &norm, max_symbol, log)?;
    let mut table = fse::Table::new();
    table.build(&norm, max_symbol, log);
    match fse::code(&mut out[header..], weights, &table) {
        0 => Some(0),
        size => Some(header + size),
    }
}

/// `HUF_writeCTable_wksp`: the tree's description — every symbol's
/// weight but the last's, FSE-coded when that is shorter, else four bits
/// each. None on the C's errors.
fn describe(out: &mut [u8], table: &Table) -> Option<usize> {
    let (max_symbol, log) = (table.max_symbol as usize, table.log);
    let mut to_weight = [0u8; TABLE_LOG_MAX as usize + 1];
    for bits in 1..=log {
        to_weight[bits as usize] = (log + 1 - bits) as u8;
    }
    let mut weights = [0u8; SYMBOLS];
    for (weight, code) in weights.iter_mut().zip(&table.codes[..max_symbol]) {
        *weight = to_weight[code.bits as usize];
    }
    let (first, rest) = out.split_first_mut()?;
    let coded = code_weights(rest, &weights[..max_symbol])?;
    if coded > 1 && coded < max_symbol / 2 {
        *first = coded as u8;
        return Some(coded + 1);
    }
    let size = max_symbol.div_ceil(2) + 1;
    if max_symbol > 128 || size > out.len() {
        return None;
    }
    out[0] = (128 + (max_symbol - 1)) as u8;
    for n in (0..max_symbol).step_by(2) {
        out[n / 2 + 1] = (weights[n] << 4) + weights[n + 1];
    }
    Some(size)
}

/// `HUF_estimateCompressedSize`.
fn estimate(table: &Table, count: &[u32; SYMBOLS], max_symbol: u32) -> usize {
    let symbols = max_symbol as usize + 1;
    let codes = table.codes[..symbols].iter().zip(&count[..symbols]);
    codes.map(|(code, &c)| usize::from(code.bits) * c as usize).sum::<usize>() >> 3
}

/// `HUF_validateCTable`: whether `table` codes every symbol counted.
fn codes_all(table: &Table, count: &[u32; SYMBOLS], max_symbol: u32) -> bool {
    let symbols = max_symbol as usize + 1;
    table.max_symbol >= max_symbol
        && table.codes[..symbols].iter().zip(&count[..symbols]).all(|(code, &c)| c == 0 || code.bits > 0)
}

/// `HUF_compress1X_usingCTable_internal`: `src` in one stream, from its
/// last byte back — the size, or 0 when it does not fit.
fn one_stream(out: &mut [u8], src: &[u8], table: &Table) -> usize {
    if out.len() < 8 {
        return 0;
    }
    let Some(mut stream) = Stream::new(out) else {
        return 0;
    };
    // Five codes of at most 11 bits, and 7 bits not yet flushed, fit the
    // register.
    debug_assert!(table.log <= LITERALS_LOG);
    for chunk in src.rchunks(5) {
        for &byte in chunk.iter().rev() {
            let code = table.codes[byte as usize];
            stream.add(u64::from(code.value), u32::from(code.bits));
        }
        stream.flush();
    }
    stream.close()
}

/// `HUF_compress4X_usingCTable_internal`: `src` in four streams behind a
/// table of their sizes — the size, or 0 when it does not fit.
fn four_streams(out: &mut [u8], src: &[u8], table: &Table) -> usize {
    if out.len() < 6 + 1 + 1 + 1 + 8 || src.len() < 12 {
        return 0;
    }
    let segment = src.len().div_ceil(4);
    let mut op = 6;
    for k in 0..4 {
        let part = if k < 3 { &src[k * segment..(k + 1) * segment] } else { &src[3 * segment..] };
        let size = one_stream(&mut out[op..], part, table);
        if size == 0 || size > 65535 {
            return 0;
        }
        if k < 3 {
            out[2 * k..2 * k + 2].copy_from_slice(&(size as u16).to_le_bytes());
        }
        op += size;
    }
    op
}

/// `HUF_compressCTable_internal`: `src` coded with `table` behind the
/// `header` bytes already in `out` — the whole size, or 0 when it saves
/// less than two bytes.
fn code(out: &mut [u8], header: usize, src: &[u8], four: bool, table: &Table) -> usize {
    let streams = if four { four_streams } else { one_stream };
    let size = streams(&mut out[header..], src, table);
    if size == 0 || header + size >= src.len() - 1 {
        return 0;
    }
    header + size
}

/// `HUF_compress_internal` at the literal section's bounds (symbols to
/// 255, depth 11): the section coded — description and streams — with a
/// new tree, or with `previous` when that is no longer. Its size, 1 when
/// `src` is one byte repeated (written), 0 when coding does not pay, None
/// on the C's errors. A new tree replaces `previous` and clears `repeat`.
pub(super) fn compress(
    out: &mut [u8],
    src: &[u8],
    four: bool,
    repeat: &mut Repeat,
    previous: &mut Table,
    suspect_incompressible: bool,
) -> Option<usize> {
    if src.is_empty() || out.is_empty() {
        return Some(0);
    }
    const SAMPLE: usize = 4096;
    let largest_count = |bytes: &[u8]| {
        let mut count = [0u32; SYMBOLS];
        for &b in bytes {
            count[b as usize] += 1;
        }
        count.iter().copied().max().unwrap_or(0) as usize
    };
    if suspect_incompressible
        && src.len() >= SAMPLE * 10
        && largest_count(&src[..SAMPLE]) + largest_count(&src[src.len() - SAMPLE..]) <= ((2 * SAMPLE) >> 7) + 4
    {
        return Some(0);
    }
    let mut count = [0u32; SYMBOLS];
    for &b in src {
        count[b as usize] += 1;
    }
    let mut max_symbol = SYMBOLS as u32 - 1;
    while count[max_symbol as usize] == 0 {
        max_symbol -= 1;
    }
    let largest = count.iter().copied().max().unwrap_or(0) as usize;
    if largest == src.len() {
        out[0] = src[0];
        return Some(1);
    }
    if largest <= (src.len() >> 7) + 4 {
        return Some(0);
    }
    if *repeat == Repeat::Check && !codes_all(previous, &count, max_symbol) {
        *repeat = Repeat::None;
    }
    let mut table = Table::new();
    let log = fse::optimal_table_log(LITERALS_LOG, src.len(), max_symbol, 1);
    build(&mut table, &count, max_symbol, log);
    let header = describe(out, &table)?;
    if *repeat != Repeat::None {
        let old = estimate(previous, &count, max_symbol);
        if old <= header + estimate(&table, &count, max_symbol) || header + 12 >= src.len() {
            return Some(code(out, 0, src, four, previous));
        }
    }
    if header + 12 >= src.len() {
        return Some(0);
    }
    *repeat = Repeat::None;
    *previous = table;
    Some(code(out, header, src, four, previous))
}
