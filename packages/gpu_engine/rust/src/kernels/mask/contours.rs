//! The closed contours of the pixels a box's runs hold, on the pixel grid
//! ([`walked`]): one walk for every outline drawn round pixels — a
//! selection's ants (`CanvasSelectionRegion.pixelOutlineIn`) and the range a
//! held fill will cover (I-160), each from its own runs
//! ([`super::runs::SelectionRuns`] · the fill's).
//!
//! 🔬WHY HERE (card pixel-ants-cost-a-frame-while-moving, 2026-11-16): the
//! app walked them in Dart (`pixel_run_contours.dart`), and a transform's
//! drag walks a new region every frame — a 4K lasso's 15,644 points were
//! 2.4 ms of the UI's frame, 5.2 at p90 (the Surface, profile), beside the
//! runs' 1.3. ⛔Not moved off the frame: an outline that came a frame later
//! would stand where the box no longer is (관제 11-16 ⓐ — 「늦게 선 윤곽이
//! 상자와 어긋나 보이면 그것도 사고」). The same frame asks it, cheaper.
//!
//! 🚨THE ORDER IS THE LAW, as it was in Dart: a contour starts where the
//! scan first met it and walks one way round, so the dashes the app cuts
//! along it stay put. Every rule below is the Dart walk's, step for step.

#[cfg(test)]
#[path = "contours_tests.rs"]
mod tests;

/// The contours [`walked`] gives: contour `c`'s points are `points[2 *
/// starts[c] .. 2 * starts[c + 1]]`, a column and a line in turn, counted
/// from the box's top-left corner.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct RunContours {
    pub(crate) starts: Vec<u32>,
    pub(crate) points: Vec<i32>,
}

/// The ways a boundary edge goes from the vertex it starts at.
const RIGHT: u32 = 0;
const DOWN: u32 = 1;
const LEFT: u32 = 2;
const UP: u32 = 3;

/// How far an edge's every step moves its vertex, across and down, each
/// way ([`RIGHT`], [`DOWN`], [`LEFT`], [`UP`]).
const ACROSS_BY: [i64; 4] = [1, 0, -1, 0];
const DOWN_BY: [i64; 4] = [0, 1, 0, -1];

/// An edge's way and span once it is walked.
const TAKEN: u32 = u32::MAX;

/// Whether the runs row by row — row `r`'s `ends[offsets[r] .. offsets[r +
/// 1]]`, a start and an end in turn — are runs of a box `width` wide: each
/// row's in order, none empty, none past the box.
pub(crate) fn runs_hold(offsets: &[u32], ends: &[u32], width: u32) -> bool {
    let rows_in_order = offsets.windows(2).all(|row| row[0] <= row[1]);
    let within = offsets.last().is_none_or(|&last| last as usize <= ends.len());
    rows_in_order
        && within
        && offsets.windows(2).all(|row| {
            let runs = &ends[row[0] as usize..row[1] as usize];
            let in_order = runs.windows(2).enumerate().all(|(at, pair)| match at % 2 {
                0 => pair[0] < pair[1],
                _ => pair[0] <= pair[1],
            });
            in_order && runs.iter().all(|&end| end <= width)
        })
}

/// The closed contours of the pixels the runs hold ([`runs_hold`]) in a box
/// `width` wide, in the order the scan meets them: each from its first
/// vertex, a component one way round and a hole the other, a straight run
/// a point at each end.
pub(crate) fn walked(offsets: &[u32], ends: &[u32], width: u32) -> RunContours {
    let mut contours = RunContours { starts: vec![0], points: Vec::new() };
    let rows: Vec<&[u32]> = offsets.windows(2).map(|row| &ends[row[0] as usize..row[1] as usize]).collect();
    if width == 0 || rows.is_empty() {
        return contours;
    }
    let laid = boundary_edges(&rows);
    let mut edges = EdgeTable::of(&laid, width, rows.len() + 1);
    // Every vertex in the order its first edge was laid, walked from for as
    // long as it still has an edge — the very starts the scan took, in the
    // same order.
    for edge in 0..laid.xs.len() {
        let line = laid.ys[edge];
        let Some(start) = edges.place_first_laid_by(edge, line) else {
            continue;
        };
        while edges.has_at(start, line) {
            for (x, y) in closed_contour(&mut edges, start, line) {
                contours.points.extend([x as i32, y as i32]);
            }
            contours.starts.push((contours.points.len() / 2) as u32);
        }
    }
    contours
}

/// The contour walked from the vertex whose first place is `start`, on
/// `line` ([`walk_contour`]), its join merged.
fn closed_contour(edges: &mut EdgeTable, start: usize, line: u32) -> Vec<(i64, i64)> {
    let mut contour = walk_contour(edges, start, line);
    // ⚠️And once more AROUND the join: the walk starts wherever the table
    // handed it a vertex, usually the middle of a straight run, and the
    // segment that closes the contour is implied rather than stepped.
    while contour.len() > 3 && straight(contour[contour.len() - 2], contour[contour.len() - 1], contour[0]) {
        contour.pop();
    }
    while contour.len() > 3 && straight(contour[contour.len() - 1], contour[0], contour[1]) {
        contour.remove(0);
    }
    contour
}

/// Whether `b` sits on the straight line from `a` to `c` — axis-aligned
/// steps only, which is all a pixel boundary has.
fn straight(a: (i64, i64), b: (i64, i64), c: (i64, i64)) -> bool {
    (b.0 - a.0) * (c.1 - b.1) == (b.1 - a.1) * (c.0 - b.0)
}

/// One closed contour of `edges`, walked from the vertex whose first place
/// is `start`, on `line`, and taken as it goes. ⚠️Its first edge is taken at
/// `start`, the very place the caller asked [`EdgeTable::has_at`] of: every
/// walk asked for takes an edge, and the asking ends.
fn walk_contour(edges: &mut EdgeTable, start: usize, line: u32) -> Vec<(i64, i64)> {
    let (start_x, start_y) = (i64::from(edges.xs[start]), i64::from(line));
    let (mut x, mut y) = (start_x, start_y);
    let mut contour = vec![(x, y)];
    // ⚠️STRAIGHT RUNS COLLAPSE: a run's end is made a point once, where the
    // walk turns off it; a true staircase keeps its steps.
    let mut last_way = None;
    // Whether the contour's last point is behind (x, y) on a straight run.
    let mut behind = false;
    // ⚠️Bounded by the edge count rather than trusted to close: a malformed
    // walk must end, not hang the paint thread.
    let mut guard = edges.xs.len() + 8;
    let mut taken = edges.take_at(start, line);
    while let Some(edge) = taken {
        if guard == 0 {
            break;
        }
        guard -= 1;
        let (way, span) = ((edge & 3) as usize, i64::from(edge >> 2));
        let (next_x, next_y) = (x + ACROSS_BY[way] * span, y + DOWN_BY[way] * span);
        if (next_x, next_y) == (start_x, start_y) {
            break;
        }
        if last_way == Some(way) {
            behind = true;
        } else {
            if behind {
                *contour.last_mut().expect("a contour holds its start") = (x, y);
                behind = false;
            }
            contour.push((next_x, next_y));
        }
        last_way = Some(way);
        (x, y) = (next_x, next_y);
        taken = edges.take(x as u32, y as u32);
    }
    if behind {
        *contour.last_mut().expect("a contour holds its start") = (x, y);
    }
    contour
}

/// The boundary's edges in the order they were laid: the vertex each
/// starts from — its column and line — and its way and span, the way in
/// bits 0–1 and the span, in vertices, above them.
#[derive(Default)]
struct Laid {
    xs: Vec<u32>,
    ys: Vec<u32>,
    ways: Vec<u32>,
}

impl Laid {
    fn add(&mut self, x: u32, y: u32, way: u32, span: u32) {
        self.xs.push(x);
        self.ys.push(y);
        self.ways.push(span << 2 | way);
    }
}

/// Every boundary edge of the pixels `rows` hold, wound so the covered side
/// is on the same hand throughout. 🚨ROW BY ROW, NEVER A MASK (I-23): an
/// inverse's box is the whole pasteboard wall, ~35 MB at a byte a pixel; only a
/// pixel with an edge is visited. ⛔In exactly the order the pixel-by-pixel
/// scan emitted them — row-major, then top, right, bottom, left within a
/// pixel — so every contour starts where it always did. A row's run is
/// taken a STRETCH at a time — pixels the rows above and below cover alike
/// — its top and bottom an edge each.
fn boundary_edges(rows: &[&[u32]]) -> Laid {
    let mut edges = Laid::default();
    for (y, runs) in rows.iter().enumerate() {
        let mut above = RunCursor { runs: if y > 0 { rows[y - 1] } else { &[] }, at: 0 };
        let mut below = RunCursor { runs: rows.get(y + 1).copied().unwrap_or(&[]), at: 0 };
        let y = y as u32;
        for run in runs.chunks_exact(2) {
            let (start, end) = (run[0], run[1]);
            let mut x = start;
            while x < end {
                let up = above.covers(x);
                let down = below.covers(x);
                let to = end.min(above.changes_after(x).min(below.changes_after(x)));
                if !up {
                    edges.add(x, y, RIGHT, to - x);
                }
                if x == end - 1 {
                    edges.add(x + 1, y, DOWN, 1);
                }
                if !down {
                    edges.add(x + 1, y + 1, LEFT, 1);
                }
                if x == start {
                    edges.add(x, y + 1, UP, 1);
                }
                if to - 1 > x {
                    if to == end {
                        edges.add(to, y, DOWN, 1);
                    }
                    if !down {
                        edges.add(to, y + 1, LEFT, to - 1 - x);
                    }
                }
                x = to;
            }
        }
    }
    edges
}

/// One row's runs, read left to right: asked about columns that never go
/// back, it answers in a single pass over the row.
struct RunCursor<'a> {
    runs: &'a [u32],
    at: usize,
}

impl RunCursor<'_> {
    /// Whether a run covers column `x`.
    fn covers(&mut self, x: u32) -> bool {
        while self.at + 1 < self.runs.len() && self.runs[self.at + 1] <= x {
            self.at += 2;
        }
        self.at + 1 < self.runs.len() && self.runs[self.at] <= x
    }

    /// The first column past `x` that [`RunCursor::covers`] answers
    /// otherwise for than it just did for `x` — asked only right after it.
    fn changes_after(&self, x: u32) -> u32 {
        match self.runs.get(self.at..self.at + 2) {
            Some(&[start, end]) if start <= x => end,
            Some(&[start, _]) => start,
            _ => u32::MAX,
        }
    }
}

/// The laid edges found by the vertex they start from: sorted by line, then
/// column, then the order they were laid — a counting sort each, so a
/// vertex's edges sit side by side, the first taken as the scan took them —
/// and a vertex found in its line by halving. A vertex of a pixel boundary
/// has at most two edges out (two pixels touching only at a corner).
struct EdgeTable {
    /// Where each line's places begin, and a line past the last ends them.
    line_starts: Vec<u32>,
    /// Per place: the column its edge starts at, and its way and span —
    /// [`TAKEN`] once walked.
    xs: Vec<u32>,
    ways: Vec<u32>,
    /// Per laid edge, its place.
    at: Vec<u32>,
}

impl EdgeTable {
    fn of(laid: &Laid, width: u32, lines: usize) -> Self {
        let (by_column, _) = sorted_by(&laid.xs, width as usize + 1, None);
        let (sorted, line_starts) = sorted_by(&laid.ys, lines, Some(&by_column));
        let mut at = vec![0; sorted.len()];
        for (place, &edge) in sorted.iter().enumerate() {
            at[edge as usize] = place as u32;
        }
        Self {
            line_starts,
            xs: sorted.iter().map(|&edge| laid.xs[edge as usize]).collect(),
            ways: sorted.iter().map(|&edge| laid.ways[edge as usize]).collect(),
            at,
        }
    }

    /// `edge`'s place, when it is the first laid from its vertex on `line`.
    fn place_first_laid_by(&self, edge: usize, line: u32) -> Option<usize> {
        let place = self.at[edge] as usize;
        let first = place == self.line_starts[line as usize] as usize || self.xs[place - 1] != self.xs[place];
        first.then_some(place)
    }

    /// Whether an edge from the vertex whose first place is `place`, on
    /// `line`, is still untaken.
    fn has_at(&self, place: usize, line: u32) -> bool {
        self.ways[place] != TAKEN || self.paired(place, line) && self.ways[place + 1] != TAKEN
    }

    /// Takes the last untaken edge laid from vertex (`x`, `line`) — its way
    /// and span — none where none is left.
    fn take(&mut self, x: u32, line: u32) -> Option<u32> {
        let place = self.place_of(x, line)?;
        self.take_at(place, line)
    }

    /// [`EdgeTable::take`] from the vertex whose first place is `place`.
    fn take_at(&mut self, place: usize, line: u32) -> Option<u32> {
        let place = match self.paired(place, line) && self.ways[place + 1] != TAKEN {
            true => place + 1,
            false => place,
        };
        let way = std::mem::replace(&mut self.ways[place], TAKEN);
        (way != TAKEN).then_some(way)
    }

    /// Whether the vertex whose first place is `place` has a second edge.
    fn paired(&self, place: usize, line: u32) -> bool {
        place + 1 < self.line_starts[line as usize + 1] as usize && self.xs[place + 1] == self.xs[place]
    }

    /// The first place of vertex (`x`, `line`), none where no edge starts
    /// there.
    fn place_of(&self, x: u32, line: u32) -> Option<usize> {
        let line = line as usize;
        let (begin, end) = (*self.line_starts.get(line)? as usize, *self.line_starts.get(line + 1)? as usize);
        let place = begin + self.xs[begin..end].partition_point(|&column| column < x);
        (place < end && self.xs[place] == x).then_some(place)
    }
}

/// `order` — laid edges, or every one in the order laid where none —
/// sorted stably by their `keys`, each below `range`: the edges sorted, and
/// where each key's begin, a key past the last ending them.
fn sorted_by(keys: &[u32], range: usize, order: Option<&[u32]>) -> (Vec<u32>, Vec<u32>) {
    let mut starts = vec![0u32; range + 1];
    for &key in keys {
        starts[key as usize + 1] += 1;
    }
    for key in 0..range {
        starts[key + 1] += starts[key];
    }
    let mut next = starts.clone();
    let mut sorted = vec![0; keys.len()];
    for place in 0..keys.len() {
        let edge = order.map_or(place, |order| order[place] as usize);
        let key = keys[edge] as usize;
        sorted[next[key] as usize] = edge as u32;
        next[key] += 1;
    }
    (sorted, starts)
}

/// How many edges [`boundary_edges`] lays for the runs: what pins that a
/// straight side is an edge or two, not a pixel's each.
#[cfg(test)]
pub(crate) fn laid_count(offsets: &[u32], ends: &[u32]) -> usize {
    let rows: Vec<&[u32]> = offsets.windows(2).map(|row| &ends[row[0] as usize..row[1] as usize]).collect();
    boundary_edges(&rows).xs.len()
}
