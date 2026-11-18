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
/// null where the reader gives none, and the message's own datum says it —
/// and the tablet driver's pressure at its moment, 0..1, where the reader
/// paired a pen's or a mouse's point with the driver's packet (points.rs
/// `Point::driven`).
typedef OsPoint = ({
  double x,
  double y,
  Duration at,
  double? pressure,
  double? tilt,
  double? orientation,
  double? driven,
});

@Native<Int32 Function()>(symbol: 'qa_pen_points_start')
external int _start();

@Native<Int32 Function(Double, Double)>(symbol: 'qa_pen_points_take')
external int _take(double x, double y);

@Native<Size Function(Pointer<Double>, Size)>(symbol: 'qa_pen_points_taken')
external int _taken(Pointer<Double> out, int room);

@Native<Uint64 Function()>(symbol: 'qa_pen_points_passed')
external int _passed();

@Native<Size Function(Pointer<Uint64>, Size)>(symbol: 'qa_pen_points_lost')
external int _lost(Pointer<Uint64> out, int room);

/// THE POINTS THE OS SAW (H56) — the book a platform's reader writes each
/// message's points into before Flutter hears of the message, read here by
/// the point the message's datum is handed at.
///
/// ⚠️A channel could not carry this, for the pen ledger's reason
/// ([QaPenLedger]): a channel message and a pointer event travel two queues
/// with no order between them.
abstract final class QaPenPoints {
  /// The numbers a point is handed as (points.rs `POINT_WORDS`).
  static const int _words = 7;

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
    final count = _take(x, y);
    if (count < 0) {
      return null;
    }
    if (count == 0) {
      return const [];
    }
    // As many as the batch has, however many: the book keeps every point.
    final out = malloc<Double>(count * _words);
    try {
      final read = _taken(out, count);
      return pointsOf(out.asTypedList(read * _words));
    } finally {
      malloc.free(out);
    }
  }

  /// The points [words] hand, [_words] numbers each as the book writes them
  /// (points.rs `Point::words`): x, y, the time in microseconds, the
  /// pressure, the tilt, the orientation and the driver's pressure — NaN
  /// read as none.
  @visibleForTesting
  static List<OsPoint> pointsOf(List<double> words) {
    double? given(double word) => word.isNaN ? null : word;
    return [
      for (var at = 0; at + _words <= words.length; at += _words)
        (
          x: words[at],
          y: words[at + 1],
          at: Duration(microseconds: words[at + 2].toInt()),
          pressure: given(words[at + 3]),
          tilt: given(words[at + 4]),
          orientation: given(words[at + 5]),
          driven: given(words[at + 6]),
        ),
    ];
  }

  /// How many messages' points no datum was paired with — each a message
  /// whose points no stroke got.
  static int get passed => debugTake != null ? 0 : _passed();

  /// How many messages' points did not all reach the book, by why
  /// (points.rs `Lost`): the mouse's history [full], a history [unread]
  /// — each a stretch of a line the OS saw and no stroke got (H59 법 A:
  /// counted first). The book itself keeps every point a reader writes.
  static ({int full, int unread}) get lost {
    if (debugTake != null) {
      return (full: 0, unread: 0);
    }
    final out = malloc<Uint64>(_losses);
    try {
      final count = _lost(out, _losses);
      int at(int why) => why < count ? out[why] : 0;
      return (full: at(0), unread: at(1));
    } finally {
      malloc.free(out);
    }
  }

  /// The ways a message's points are lost (points.rs `LOSSES`).
  static const int _losses = 2;
}
