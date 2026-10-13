import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/cubic_curve.dart';
import 'clip_cmt.dart';

/// Where a track shows its layer, in the timeline's frames: from [start]
/// up to (not including) [end].
typedef ClipSpan = ({int start, int end});

/// A cel shown from [frame] on — until the next key, or its clip's end.
typedef ClipCelKey = ({int frame, String cel});

/// One clip of a track: where it shows its layer, and the cels it keys
/// (in order of frame). A key holds until the next one or the clip's end,
/// never into the next clip — the gap between two clips shows nothing.
typedef ClipPiece = ({ClipSpan span, List<ClipCelKey> cels});

/// What one clip of a sound track plays: the sound [player] names (a
/// sound's `objectUuid`), from [startSeconds] into it on [frame] — the
/// timeline frame it starts on — at [speed] (1 = as it was recorded) and
/// [volume] (1 = its own level), until the clip ends at [span]'s end.
/// [volumeVaries] when the clip's volume moves within it.
typedef ClipSoundCue = ({
  ClipSpan span,
  String player,
  int frame,
  double startSeconds,
  double speed,
  double volume,
  bool volumeVaries,
});

/// How a 2D camera track's clip moves its camera (memory
/// `csp-clip-format-notes` §3): each value of the camera's placement — its
/// point, scale, turn and pivot — as CLIP STUDIO keys it over the clip
/// ([ClipCurve]). A value the clip keys no curve for holds the clip's
/// `Param`; one with neither is empty, and the camera keeps its rest there.
/// [scale] is 1 at the camera's own size, as a placement's is (the file
/// keys percent).
typedef ClipCameraMove = ({
  ClipSpan span,
  ClipCurve x,
  ClipCurve y,
  ClipCurve scale,
  ClipCurve degrees,
  ClipCurve pivotX,
  ClipCurve pivotY,
});

/// One key of a [ClipCurve]: its [value] on the timeline's [frame] —
/// unrounded, where the clip's tick lands.
typedef ClipCurveKey = ({double frame, double value});

/// How a CLIP STUDIO value goes from one key to the next, as CLIP STUDIO
/// draws it (memory `csp-clip-format-notes` §3 — the user's camera sample
/// against the frames CLIP STUDIO wrote of it, 2026-10-13).
sealed class ClipWay {
  const ClipWay();

  /// `Constant`: the key's value until the next.
  static const ClipWay held = ClipHold._();

  /// `Linear`: straight on to the next key — and how a way this reader does
  /// not know is run, which its curve says ([ClipCurve.unread]).
  static const ClipWay straight = ClipStraight._();
}

/// [ClipWay.held]'s type.
final class ClipHold extends ClipWay {
  const ClipHold._();
}

/// [ClipWay.straight]'s type.
final class ClipStraight extends ClipWay {
  const ClipStraight._();
}

/// A cubic from one key to the next, moving at [leaving] as it leaves the
/// one and at [arriving] as it reaches the other — value per frame.
/// `Hermite` is this with the slopes the keys keep; CLIP STUDIO's own way
/// (no `Interp` at all) is this with the slopes its keys' values give
/// (`_ownSlope`) — slow out and slow in, between two keys alone.
final class ClipCubic extends ClipWay {
  const ClipCubic({required this.leaving, required this.arriving});

  final double leaving;
  final double arriving;
}

/// One of a 2D camera's values over its clip, as CLIP STUDIO plays it: its
/// [keys] in order of frame, and the way from each to the next — one fewer
/// [ways] than keys. A curve of the point keeps each axis apart, so a way
/// whose two axes' slopes differ walks a bent path (유저 10-13: 「그래프를
/// 만지면 시간+공간을 같이움직임」).
final class ClipCurve {
  ClipCurve(this.keys, this.ways, {this.unread = false})
    : assert(ways.length == math.max(0, keys.length - 1));

  /// A value the clip holds throughout — its `Param`, which no curve keys —
  /// keyed on the clip's first [frame].
  ClipCurve.held(double frame, double value)
    : this([(frame: frame, value: value)], const []);

  /// A value the clip says nothing of.
  static final ClipCurve none = ClipCurve(const [], const []);

  final List<ClipCurveKey> keys;
  final List<ClipWay> ways;

  /// Whether a way of it is one this reader does not know — run straight
  /// ([ClipWay.straight]). ↩️It was whether a way of it is straight, while
  /// no way the reader knew was (until the user's zoom-and-turn sample,
  /// 10-13: `Linear`).
  final bool unread;

  bool get isEmpty => keys.isEmpty;

  /// The frames its keys stand on, rounded as a cel key's are.
  Iterable<int> get keyedFrames => [for (final key in keys) key.frame.round()];

  /// The value on the timeline's [frame] — the first key's before it, the
  /// last key's after it; null for a curve with no key.
  double? at(double frame) {
    if (keys.isEmpty) {
      return null;
    }
    for (var i = 0; i < ways.length; i += 1) {
      final (frame: start, value: from) = keys[i];
      final (frame: end, value: to) = keys[i + 1];
      if (frame >= end) {
        continue;
      }
      if (frame <= start) {
        return from;
      }
      final span = end - start;
      final u = (frame - start) / span;
      return switch (ways[i]) {
        ClipHold() => from,
        ClipStraight() => from + (to - from) * u,
        ClipCubic(:final leaving, :final arriving) => cubicAt(
          u,
          from,
          from + leaving * span / 3,
          to - arriving * span / 3,
          to,
        ),
      };
    }
    return keys.last.value;
  }
}

/// What one clip of a track says: [piece] — where it shows and the cels it
/// keys — and, on a sound track, the [sound] it plays; on a 2D camera's,
/// the [camera] move.
typedef ClipTrackClip = ({
  ClipPiece piece,
  ClipSoundCue? sound,
  ClipCameraMove? camera,
});

/// `TrackKind` of a sound track.
const int _soundTrackKind = 4001;

/// `TrackKind` of a 2D camera folder's track.
const int _cameraTrackKind = 2005;

/// One clip of a [kind] track's action mixer — an `ActionNodeClip` of the
/// track's CMT document — read on a timeline of [fps]. A key holds until
/// the next one; the last one holds to the clip's end. Null for a clip
/// with no time; what cannot be followed is said in [warnings].
ClipTrackClip? readTrackClip(
  CmtNode clip,
  double fps, {
  required int kind,
  required List<String> warnings,
}) {
  final timing = _timingOf(clip, fps, warnings);
  if (timing == null) {
    return null;
  }
  final (:span, :frameAt) = timing;
  int frameOf(double tick) => frameAt(tick).round();
  final cels = <ClipCelKey>[];
  for (final curve in clip.everyNode) {
    if (curve.name != 'FCurve' || curve.attributes['Type'] != 'ImageCelName') {
      continue;
    }
    final frames = curve.child('Frame')?.value;
    final tags = curve.child('Tag')?.value;
    if (frames is! List || tags is! List) {
      continue;
    }
    for (var i = 0; i < frames.length && i < tags.length; i += 1) {
      final tick = frames[i];
      final tag = tags[i];
      if (tick is num && tag is String) {
        cels.add((frame: frameOf(tick.toDouble()), cel: tag));
      }
    }
  }
  cels.sort((a, b) => a.frame.compareTo(b.frame));
  return (
    piece: (span: span, cels: cels),
    sound: kind == _soundTrackKind
        ? _soundCueOf(clip, span, frameAt, fps)
        : null,
    camera: kind == _cameraTrackKind
        ? _cameraMoveOf(clip, span, frameAt)
        : null,
  );
}

/// A CLIP STUDIO uuid in one spelling, so the file's two ways of writing
/// one meet: a blob's bytes in hex, or a text without its hyphens, lower
/// case.
String clipUuidKey(Object? value) => switch (value) {
  final Uint8List bytes => [
    for (final b in bytes) b.toRadixString(16).padLeft(2, '0'),
  ].join(),
  final String text => text.replaceAll('-', '').toLowerCase(),
  _ => '',
};

/// Where one clip stands: its span in the timeline's frames, and the
/// frame — unrounded — a tick of its motion lands on.
///
/// `frame = (TimeClip.Start + (tick − MotionClip.Start) × stretch) × fps
/// ÷ Rate`, with `stretch = (TimeClip.End − TimeClip.Start) ÷
/// (MotionClip.End − MotionClip.Start)` (1 when the motion has no
/// length) — memory `csp-clip-format-notes` §3.
({ClipSpan span, double Function(double tick) frameAt})? _timingOf(
  CmtNode clip,
  double fps,
  List<String> warnings,
) {
  final time = clip.child('TimeClip');
  final motion = clip.child('MotionClip');
  if (time == null) {
    return null;
  }
  final rate = _number(time, 'Rate') != 0
      ? _number(time, 'Rate')
      : _number(clip.child('TimeInfo'), 'Rate');
  if (rate == 0) {
    warnings.add('a clip says no tick rate');
    return null;
  }
  final timeStart = _number(time, 'Start');
  final timeEnd = _number(time, 'End');
  final motionStart = _number(motion, 'Start');
  final motionLength = _number(motion, 'End') - motionStart;
  final stretch = motionLength == 0
      ? 1.0
      : (timeEnd - timeStart) / motionLength;
  return (
    span: (
      start: (timeStart * fps / rate).round(),
      end: (timeEnd * fps / rate).round(),
    ),
    frameAt: (tick) =>
        (timeStart + (tick - motionStart) * stretch) * fps / rate,
  );
}

/// [name]'s number under [node] — 0 when there is none.
double _number(CmtNode? node, String name) =>
    _numberOf(node?.child(name)) ?? 0;

/// The number [node] holds — null when it holds none.
double? _numberOf(CmtNode? node) => switch (node?.value) {
  final num value => value.toDouble(),
  _ => null,
};

/// The numbers of [node]'s [name] list — a curve's `Frame` or `Value`.
List<double> _numbers(CmtNode? node, String name) =>
    switch (node?.child(name)?.value) {
      final List<Object?> values => [
        for (final value in values)
          if (value is num) value.toDouble(),
      ],
      _ => const [],
    };

/// [anim]'s first [node] whose attributes hold every one of [attributes]
/// — a `Param` by its `Name`, an `FCurve` by its `Type`.
CmtNode? _childOf(
  CmtNode anim,
  String node,
  Map<String, String> attributes,
) {
  for (final child in anim.children) {
    if (child.name == node &&
        attributes.entries.every(
          (attribute) => child.attributes[attribute.key] == attribute.value,
        )) {
      return child;
    }
  }
  return null;
}

/// What a sound track's clip plays (memory `csp-clip-format-notes` §3):
/// the sound its `AudioPlayer` names, at the level its `AudioVolume` gives
/// (100 = the sound's own), placed so its `PlayTime` curve holds — the
/// first key says which second of the sound plays on its frame, the
/// second how fast; with no curve, the clip plays its `PlayTime` second
/// on from its start. The sound starts where its second 0 lands, but
/// never before its clip — then from the second the clip's start meets.
ClipSoundCue? _soundCueOf(
  CmtNode clip,
  ClipSpan span,
  double Function(double tick) frameAt,
  double fps,
) {
  final anim = clip.child('AnimInfo');
  if (anim == null) {
    return null;
  }
  CmtNode? curve(String type) => _childOf(anim, 'FCurve', {'Type': type});
  CmtNode? param(String name) => _childOf(anim, 'Param', {'Name': name});
  final player =
      param('AudioPlayer')?.attributes['Tag'] ??
      switch (curve('AudioPlayer')?.child('Tag')?.value) {
        [final String first, ...] => first,
        _ => null,
      };
  if (player == null) {
    return null;
  }
  final ticks = _numbers(curve('PlayTime'), 'Frame');
  final seconds = _numbers(curve('PlayTime'), 'Value');
  final keyed = ticks.isNotEmpty && seconds.isNotEmpty;
  final f0 = keyed ? frameAt(ticks[0]) : span.start.toDouble();
  final v0 = keyed ? seconds[0] : _numberOf(param('PlayTime')) ?? 0.0;
  final speed =
      keyed &&
          ticks.length >= 2 &&
          seconds.length >= 2 &&
          frameAt(ticks[1]) != f0
      ? (seconds[1] - v0) * fps / (frameAt(ticks[1]) - f0)
      : 1.0;
  // A sound cannot run backwards or stand still: placed as if at its own
  // speed, which the planner says it is not.
  final pace = speed > 0 ? speed : 1.0;
  final frame = math.max(span.start.toDouble(), f0 - v0 * fps / pace);
  final volumes = _numbers(curve('AudioVolume'), 'Value');
  final level = volumes.isNotEmpty
      ? volumes.first
      : _numberOf(param('AudioVolume')) ?? 100.0;
  return (
    span: span,
    player: clipUuidKey(player),
    frame: frame.round(),
    startSeconds: v0 + (frame - f0) * pace / fps,
    speed: speed,
    volume: level / 100,
    volumeVaries: volumes.any((volume) => volume != volumes.first),
  );
}

/// How a 2D camera track's [clip] moves the camera (memory
/// `csp-clip-format-notes` §3, measured on s6 and the user's camera
/// samples): an `FCurve` per value — `ImagePosition` and `ImageCenter` by
/// `Axis` X · Y, `ImageScale` and `ImageRotation` alone — its `Frame` ticks
/// and `Value`s, each key's way to the next ([_curveOf]); a `Param` of the
/// same name holds a value no curve keys (a pair for the two by axis).
ClipCameraMove _cameraMoveOf(
  CmtNode clip,
  ClipSpan span,
  double Function(double tick) frameAt,
) {
  final anim = clip.child('AnimInfo');
  final framesPerTick = frameAt(1) - frameAt(0);
  ClipCurve curveOf(
    String type, {
    String? axis,
    int index = 0,
    double unit = 1,
  }) {
    if (anim == null) {
      return ClipCurve.none;
    }
    final curve = _childOf(anim, 'FCurve', {'Type': type, 'Axis': ?axis});
    final ticks = _numbers(curve, 'Frame');
    final values = _numbers(curve, 'Value');
    final count = math.min(ticks.length, values.length);
    if (curve != null && count > 0) {
      return _curveOf(
        curve,
        [
          for (var i = 0; i < count; i += 1)
            (frame: frameAt(ticks[i]), value: values[i] / unit),
        ],
        slopeDivisor: framesPerTick * unit,
      );
    }
    final held = switch (_childOf(anim, 'Param', {'Name': type})?.value) {
      final num value => value,
      final List<Object?> pair when index < pair.length => pair[index],
      _ => null,
    };
    return held is num
        ? ClipCurve.held(span.start.toDouble(), held / unit)
        : ClipCurve.none;
  }

  return (
    span: span,
    x: curveOf('ImagePosition', axis: 'X'),
    y: curveOf('ImagePosition', axis: 'Y', index: 1),
    scale: curveOf('ImageScale', unit: 100),
    degrees: curveOf('ImageRotation'),
    pivotX: curveOf('ImageCenter', axis: 'X'),
    pivotY: curveOf('ImageCenter', axis: 'Y', index: 1),
  );
}

/// [keys] — [curve]'s, on the timeline's frames — with the way from each to
/// the next as CLIP STUDIO draws it (memory `csp-clip-format-notes` §3,
/// measured 2026-10-13 against the frames CLIP STUDIO wrote of the user's
/// three camera samples, 0.06px): each axis apart, the cubic two keys'
/// slopes make — or, from a `Constant` key, its value held to the next;
/// from a `Linear` one, straight on to it (the zoom-and-turn sample's
/// 「등속」, both keys `Linear`: the zoom and the turn on a straight ramp).
///
/// A key's slopes — value per frame, as the way before it arrives and the
/// way after it leaves — are its own kind's. `Hermite`, a graph pulled,
/// keeps them in the file in value per TICK (a slope per frame overshot
/// nothing where CLIP STUDIO's output overshot by a tenth), divided by
/// [slopeDivisor] — the timeline's frames a tick times the value's unit —
/// to move it per frame: its `LeftSlope` arriving, its `RightSlope`
/// leaving. A key of CLIP STUDIO's own — no `Interp` at all, `Default`,
/// `Constant` or `Linear` — moves at the slope [_ownSlope] gives. ⚠️The
/// slopes a file keeps beside such a key are not read: the ones the
/// samples keep, a `Default` last key's and every `Constant` and `Linear`
/// key's, are 0 — which a `Default` end's own slope is too. A way from or
/// to a key of a kind this reader does not know runs straight, and is
/// said. ↩️Every way that was not `Constant` ran straight (s6, 10-09: a
/// guess, never held to an output).
ClipCurve _curveOf(
  CmtNode curve,
  List<ClipCurveKey> keys, {
  required double slopeDivisor,
}) {
  final kinds = switch (curve.child('Interp')?.value) {
    final List<Object?> named => named,
    _ => const <Object?>[],
  };
  Object? kindOf(int i) => i < kinds.length ? kinds[i] : null;
  final arriving = _numbers(curve, 'LeftSlope');
  final leaving = _numbers(curve, 'RightSlope');
  ({double arriving, double leaving}) through(double slope) =>
      (arriving: slope, leaving: slope);
  final slopes = <({double arriving, double leaving})?>[
    for (var i = 0; i < keys.length; i += 1)
      switch (kindOf(i)) {
        'Hermite' when i < arriving.length && i < leaving.length => (
          arriving: arriving[i] / slopeDivisor,
          leaving: leaving[i] / slopeDivisor,
        ),
        null || 'Default' || 'Constant' || 'Linear' => through(
          _ownSlope(keys, i),
        ),
        _ => null,
      },
  ];
  final ways = <ClipWay?>[
    for (var i = 0; i + 1 < keys.length; i += 1)
      switch ((kindOf(i), slopes[i], slopes[i + 1])) {
        ('Constant', _, _) => ClipWay.held,
        ('Linear', _, _) => ClipWay.straight,
        (_, (leaving: final leaving, arriving: _), (
          leaving: _,
          arriving: final arriving,
        )) =>
          ClipCubic(leaving: leaving, arriving: arriving),
        _ => null,
      },
  ];
  return ClipCurve(
    keys,
    [for (final way in ways) way ?? ClipWay.straight],
    unread: ways.contains(null),
  );
}

/// The slope CLIP STUDIO's own way moves at through key [i] of [keys]: none
/// at the curve's two ends and where the value turns back, and between, the
/// gentler of the two ways' own average slopes — so the curve never
/// overshoots a key (the user's 4-key sample, 2026-10-13: a slope fitted
/// freely to its output came out at exactly the gentler one, 2.00 and 2.00,
/// and no other rule tried came within 1px). A key of two keys' curve is
/// an end, so that way is slow out and slow in — After Effects' Easy Ease
/// (the first sample). ⚠️A `Constant` or `Linear` key is read the same —
/// what CLIP STUDIO moves at into one, or beside a held or a straight way,
/// no sample shows: theirs are two keys of the one kind.
double _ownSlope(List<ClipCurveKey> keys, int i) {
  if (i == 0 || i == keys.length - 1) {
    return 0;
  }
  double average(ClipCurveKey from, ClipCurveKey to) => to.frame == from.frame
      ? 0
      : (to.value - from.value) / (to.frame - from.frame);
  final before = average(keys[i - 1], keys[i]);
  final after = average(keys[i], keys[i + 1]);
  if (before * after <= 0) {
    return 0;
  }
  return before.abs() < after.abs() ? before : after;
}
