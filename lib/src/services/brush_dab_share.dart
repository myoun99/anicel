import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/brush_dab.dart';

/// 🚨★★★A DAB LAYS ITS SHARE OF ONE STAMP PER TENTH OF ITS SIZE (유저
/// 2026-10-01, board `one-pixel-steps-change-a-brush-with-its-size`: Q1
/// 「엔진이 쌓임을 환산 — 크기와 무관하게(클튜처럼)」, Q2 「획을 정밀하게
/// 쌓고, 환산은 커널에서 — 모든 브러시」).
///
/// The interpolator lays dabs no closer than a pixel apart, so a big brush
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

/// [dab]'s share of one stamp per tenth of its size, in (0, 1].
double stampShareOf(BrushDab dab) {
  final step = dab.pathStep;
  if (step == null) {
    return 1.0;
  }
  final share = step / (dab.size * 0.1);
  if (share >= 1.0) {
    return 1.0;
  }
  return math.max(1, (share * shareSteps).round()) / shareSteps;
}

/// Entries past the first in an evening table: a laid alpha `a` in [0, 1]
/// reads entry `a * eveningTableSteps`, linearly between two.
const int eveningTableSteps = 1024;

/// The tables built so far, newest last — a stroke lays a few shares, and
/// a table is 8 KB.
final LinkedHashMap<double, Float64List> _tables =
    LinkedHashMap<double, Float64List>();
const int _tableCap = 64;

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
  final held = _tables.remove(share);
  if (held != null) {
    _tables[share] = held;
    return held;
  }
  final table = Float64List(eveningTableSteps + 1);
  for (var i = 0; i <= eveningTableSteps; i += 1) {
    table[i] = 1.0 - math.pow(1.0 - i / eveningTableSteps, share);
  }
  _tables[share] = table;
  if (_tables.length > _tableCap) {
    _tables.remove(_tables.keys.first);
  }
  return table;
}

/// What a dab laying [laid] whole lays at the share [table] was built for —
/// `qa_dab_even`'s arithmetic, operation by operation.
double evenedLaid(Float64List table, double laid) {
  final x = laid * eveningTableSteps;
  if (x >= eveningTableSteps) {
    return table[eveningTableSteps];
  }
  final i = x.toInt();
  final low = table[i];
  return low + (table[i + 1] - low) * (x - i);
}
