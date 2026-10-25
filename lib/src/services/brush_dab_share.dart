import 'dart:math' as math;
import 'dart:typed_data';

import '../core/bounded_memo.dart';
import '../models/brush_dab.dart';

/// 🚨★★★A DAB LAYS ITS SHARE OF ONE STAMP PER TENTH OF ITS SIZE (유저
/// 2026-10-01, board `one-pixel-steps-change-a-brush-with-its-size`: Q1
/// 「엔진이 쌓임을 환산 — 크기와 무관하게(클튜처럼)」, Q2 「획을 정밀하게
/// 쌓고, 환산은 커널에서 — 모든 브러시」).
///
/// The interpolator lays dabs no closer than a pixel apart (a brush under
/// ten pixels, a tenth of its size — [finestDabStep]), so a big brush
/// laid far more of them across its width than a small one and piled up
/// darker and harder-edged for it — one flow at size 10 and at size 160
/// drew two different brushes. Clip Studio lays about one stamp per tenth of
/// the size at every size. A dab standing for [BrushDab.pathStep] of the
/// stroke is `pathStep / (size / 10)` of such a stamp, capped at one, and
/// lays what that share of a stamp lays: `1 − (1 − a)^share` where it would
/// lay `a` whole — ten dabs of share 0.1 pile up exactly as one stamp.
///
/// ⚠️IN THE KERNEL, on the laid alpha, after the whole coverage cascade
/// (edge, dual, texture): one law for every tip, round or raster, textured,
/// AA none. ↩️The first try baked the share into the stamp's table, and that
/// could be exact only for a round tip without texture or dual and with an
/// edge (board Q2).
///
/// A dab with no path step — a tap, the stamp that opens a stroke — lays
/// whole, and so does one laid a tenth of its size apart or more. The share
/// is quantized to 1/[shareSteps] so the tables repeat
/// ([eveningTableOf]).
const int shareSteps = 1024;

/// The stretch of a stroke one whole stamp of a brush [size] across stands
/// for: a tenth of the size.
double stampStepFor(double size) => size * 0.1;

/// The finest step between two dabs of a brush [size] across: one stamp's
/// ([stampStepFor]), not under a quarter of a pixel nor over one.
///
/// 🚨★★★(board a-one-pixel-dab-drops-out-by-where-it-lies Q4, 2026-10-25)
/// A round tip's edge does not pile (`edgeCeiling`), so a thin line is as
/// high at a pixel as the highest dab there lays it — and a 1px brush laid
/// a pixel apart drew about half the ink of Clip Studio's (0.25–0.33 a
/// column against 0.48–0.52, measured through the stroke path). Under ten
/// pixels a whole-pixel step also laid fewer stamps than one a tenth of the
/// size, each capped at one, so a small brush piled lighter than a large
/// one — what Q1 above rules out.
/// ⚠️A quarter of a pixel bounds the finest brushes to four dabs a pixel:
/// finer drew no more ink (the 1px line 0.37 a column at half a pixel,
/// 0.38 at a quarter).
/// ↩️One pixel at every size from the T2 foundation (2026-07-02) on, 「to
/// prevent excessive dab counts」.
double finestDabStep(double size) =>
    stampStepFor(size).clamp(0.25, 1.0).toDouble();

/// [dab]'s share of one stamp per tenth of its size, in (0, 1].
double stampShareOf(BrushDab dab) {
  final step = dab.pathStep;
  if (step == null) {
    return 1.0;
  }
  final share = step / stampStepFor(dab.size);
  if (share >= 1.0) {
    return 1.0;
  }
  return math.max(1, (share * shareSteps).round()) / shareSteps;
}

/// Entries past the first in an evening table: a laid alpha `a` in [0, 1]
/// reads entry `a * eveningTableSteps`, linearly between two. One more
/// entry repeats `a = 1`, so a laid alpha of 1 reads its pair like any
/// other — the C kernel's pair path reads both lanes' pairs without a
/// branch (`qa_d2_even`).
const int eveningTableSteps = 1024;

/// The tables built so far — a stroke lays a few shares, and a table is
/// 8 KB. ⚠️Not an LRU: this is asked once per dab, and a recency shuffle a
/// dab (remove, re-insert) was most of what the share cost a stroke of small
/// dabs in a debug build (2026-10-01: a 301-dab size-30 commit, 2.0 ms →
/// 2.8 ms). A full cache starts over instead; [_lastShare] answers the run
/// of dabs one move lays, which share one step.
final BoundedMemo<double, Float64List> _tables = BoundedMemo(_tableCap);
const int _tableCap = 64;
double _lastShare = -1;
Float64List? _lastTable;

/// The table [dab] lays through, or null where it lays whole
/// ([stampShareOf] is one).
Float64List? eveningTableOf(BrushDab dab) {
  final share = stampShareOf(dab);
  return share >= 1.0 ? null : eveningTableFor(share);
}

/// `1 − (1 − a)^share` at `a = i / eveningTableSteps` — built once per
/// share, and the ONE place `pow` is called: the Dart and C kernels, the
/// reference and the swatch all read these numbers through [evenedLaid], so
/// they agree to the byte, and no pixel pays a power.
Float64List eveningTableFor(double share) {
  final last = _lastTable;
  if (last != null && share == _lastShare) {
    return last;
  }
  final table = _tables.resolve(share, () {
    final built = Float64List(eveningTableSteps + 2);
    for (var i = 0; i <= eveningTableSteps; i += 1) {
      built[i] = 1.0 - math.pow(1.0 - i / eveningTableSteps, share);
    }
    built[eveningTableSteps + 1] = built[eveningTableSteps];
    return built;
  });
  _lastShare = share;
  _lastTable = table;
  return table;
}

/// What a dab laying [laid] whole lays at the share [table] was built for —
/// `qa_dab_even`'s arithmetic, operation by operation.
double evenedLaid(Float64List table, double laid) {
  final scaled = laid * eveningTableSteps;
  final x = scaled < eveningTableSteps ? scaled : eveningTableSteps.toDouble();
  final i = x.toInt();
  final low = table[i];
  return low + (table[i + 1] - low) * (x - i);
}
