// The engine's Rust library carries the book of the points the OS saw
// (rust/native/pen/src/points.rs), and its names are found in that code
// asset — no library opened, no path named.
@DefaultAsset(gpuEngineAsset)
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart' show malloc;
import 'package:flutter/foundation.dart';

import 'gpu_engine_asset.dart';

/// One point the OS saw of a contact (H56): where in the view's physical
/// pixels, when on the clock Flutter stamps that platform's pointer data
/// by, and what a pointer datum carries of the pen in a datum's own units —
/// null where the reader gives none, and the message's own datum says it.
typedef OsPoint = ({
  double x,
  double y,
  Duration at,
  double? pressure,
  double? tilt,
  double? orientation,
});

@Native<Int32 Function()>(symbol: 'qa_pen_points_start')
external int _start();

@Native<Int32 Function(Double, Double, Pointer<Double>, Int32)>(
  symbol: 'qa_pen_points_take',
)
external int _take(double x, double y, Pointer<Double> out, int cap);

@Native<Uint64 Function()>(symbol: 'qa_pen_points_passed')
external int _passed();

/// THE POINTS THE OS SAW (H56) — the book a platform's reader writes each
/// message's points into before Flutter hears of the message, read here by
/// the point the message's datum is handed at.
///
/// ⚠️A channel could not carry this, for the pen ledger's reason
/// ([QaPenLedger]): a channel message and a pointer event travel two queues
/// with no order between them.
abstract final class QaPenPoints {
  /// The most points a batch keeps (points.rs `MOST_POINTS`).
  static const int _mostPoints = 512;

  /// The numbers a point is handed as (points.rs `POINT_WORDS`).
  static const int _words = 6;

  /// Where the native side writes a batch — one, for the life of the
  /// process: the door reads one datum's at a time, on the UI isolate.
  static final Pointer<Double> _out = malloc<Double>(_mostPoints * _words);

  static bool _started = false;

  /// Replaces the native book in tests — the test binding runs on no
  /// platform that writes one.
  @visibleForTesting
  static List<OsPoint>? Function(double x, double y)? debugTake;

  /// Starts the platform's reader once there is a window to read
  /// (Windows: the Flutter view's subclass): asked at each datum till it
  /// answers.
  static void start() {
    if (_started || debugTake != null) {
      return;
    }
    _started = _start() != 0;
  }

  /// The points of the datum Flutter was handed at ([x], [y]) — in the
  /// shape the embedder hands it — the oldest first; null where no reader
  /// wrote its message's, and the datum's own point is all there is.
  static List<OsPoint>? take(double x, double y) {
    final override = debugTake;
    if (override != null) {
      return override(x, y);
    }
    final count = _take(x, y, _out, _mostPoints);
    if (count < 0) {
      return null;
    }
    double? given(double word) => word.isNaN ? null : word;
    return [
      for (var at = 0; at < count * _words; at += _words)
        (
          x: _out[at],
          y: _out[at + 1],
          at: Duration(microseconds: _out[at + 2].toInt()),
          pressure: given(_out[at + 3]),
          tilt: given(_out[at + 4]),
          orientation: given(_out[at + 5]),
        ),
    ];
  }

  /// How many messages' points no datum was paired with — each a message
  /// whose points no stroke got.
  static int get passed => debugTake != null ? 0 : _passed();
}
