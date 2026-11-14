import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';

import '../../native/qa_pen_points.dart';

/// 🚨★★★**EVERY POINT THE OS SAW GOES INTO THE LINE, EACH AT ITS OWN TIME**
/// (H56) — whatever the frames are doing.
///
/// 🗣️유저 2026-11-14: 「선 빠르게그으면 곡선이아니라 각져져서 포인트끼리
/// 이어지는거 살짝 남아있는데 … 점이 들어오는 길이 이상하지 않냐는거야」 →
/// 「플랫폼 구분없이 통합해결 … 그쪽을원하는데」. An embedder hands Flutter
/// one point a message — the newest — and the points the OS merged into it
/// while the thread that takes the messages was busy are gone by then
/// (none of the five embedders asks for them, Flutter 3.47.4). A line drawn
/// from the messages joined what was left with long straight steps
/// whenever the UI's thread was slow, and read its speed off the time the
/// message was HANDLED.
///
/// So the ONE way a line takes its points: [arrived] pairs each datum, as
/// it comes in, with the points the platform's reader wrote for its message
/// ([QaPenPoints] — every reader writes the same book), and [eventsOf]
/// hands a line those points as the datum's own event made over at each:
/// its place, its time, its pressure. Everything a line reads off an event
/// — the pressure's law, the lean's, the speed, the stabilizer's time —
/// reads each point as it read the event, because each point IS an event
/// now. Where no reader wrote a message's points the event is its own one
/// point, as it always was: there is no second way in.
///
/// ⛔What reads one point of a move — where a press is, where a handle is
/// dragged to — reads the event: the newest point is the datum's own, in
/// the shape the embedder hands it (관제 2026-11-14, H56: 「마지막 점보다
/// 많이 읽는 곳만 큐로」).
abstract final class PenPath {
  /// Each datum's points as they came in, by the event made of it.
  static final Expando<List<OsPoint>> _points = Expando<List<OsPoint>>(
    'the points the OS saw',
  );

  /// Pairs [event], made of [datum] at [ratio] physical pixels a logical
  /// one, with the points the platform's reader wrote for its message.
  /// Every datum a message makes, as it comes in — ahead of every gate,
  /// so a datum kept out still takes its message's points out of the book.
  static void arrived(PointerEvent event, ui.PointerData datum, double ratio) {
    if (!_pairs(datum.change)) {
      return;
    }
    QaPenPoints.start();
    final points = QaPenPoints.take(datum.physicalX, datum.physicalY);
    if (points == null || points.isEmpty) {
      return;
    }
    _points[event] = [
      for (final point in points)
        (
          x: point.x / ratio,
          y: point.y / ratio,
          at: point.at,
          pressure: point.pressure,
          tilt: point.tilt,
          orientation: point.orientation,
        ),
    ];
  }

  /// The changes a message of a contact makes: the ones its points are
  /// written for.
  static bool _pairs(ui.PointerChange change) => switch (change) {
    ui.PointerChange.hover ||
    ui.PointerChange.down ||
    ui.PointerChange.move ||
    ui.PointerChange.up => true,
    _ => false,
  };

  /// The points [event] stands for, the oldest first, each [event] made
  /// over at it — in [event]'s own frame — and [event] alone where no
  /// reader wrote its message's.
  static List<PointerEvent> eventsOf(PointerEvent event) {
    final original = event.original ?? event;
    final points = _points[original];
    if (points == null) {
      return [event];
    }
    final made = <PointerEvent>[];
    var before = original.position - original.delta;
    for (final point in points) {
      final at = _at(original, point, before, event.transform);
      made.add(at);
      before = at.position;
    }
    return made;
  }

  /// [original] made over at [point], moved from [before].
  static PointerEvent _at(
    PointerEvent original,
    OsPoint point,
    Offset before,
    Matrix4? transform,
  ) {
    final position = Offset(point.x, point.y);
    final pressure = point.pressure;
    return original
        .copyWith(
          position: position,
          delta: position - before,
          timeStamp: point.at,
          pressure: pressure == null
              ? null
              : original.pressureMin +
                    pressure * (original.pressureMax - original.pressureMin),
          tilt: point.tilt,
          orientation: point.orientation,
        )
        .transformed(transform);
  }
}
