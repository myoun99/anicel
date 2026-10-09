import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/property_track.dart';
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
/// point, scale, turn and pivot — as keys on the timeline's frames, the way
/// the app's own keys go ([PropertyTrack]): straight to the next, or held
/// where the file says `Constant`. A value the clip keys no curve for holds the
/// clip's `Param`; one with neither is empty, and the camera keeps its rest
/// there. [scale] is 1 at the camera's own size, as a placement's is (the
/// file keys percent). [unread] when a key names another curve — one this
/// reader does not know, moved straight.
typedef ClipCameraMove = ({
  ClipSpan span,
  PropertyTrack<double> x,
  PropertyTrack<double> y,
  PropertyTrack<double> scale,
  PropertyTrack<double> degrees,
  PropertyTrack<double> pivotX,
  PropertyTrack<double> pivotY,
  bool unread,
});

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
/// `csp-clip-format-notes` §3, measured on s6): an `FCurve` per value —
/// `ImagePosition` and `ImageCenter` by `Axis` X · Y, `ImageScale` and
/// `ImageRotation` alone — its `Frame` ticks and `Value`s; a `Param` of the
/// same name holds a value no curve keys (a pair for the two by axis). Its
/// keys stand on the frames the clip's ticks land on, rounded as a cel
/// key's are.
ClipCameraMove _cameraMoveOf(
  CmtNode clip,
  ClipSpan span,
  double Function(double tick) frameAt,
) {
  final anim = clip.child('AnimInfo');
  var unread = false;
  PropertyTrack<double> keysOf(
    String type, {
    String? axis,
    int index = 0,
    double unit = 1,
  }) {
    if (anim == null) {
      return PropertyTrack.empty();
    }
    final curve = _childOf(anim, 'FCurve', {'Type': type, 'Axis': ?axis});
    final ticks = _numbers(curve, 'Frame');
    final values = _numbers(curve, 'Value');
    if (ticks.isNotEmpty && values.isNotEmpty) {
      final curves = switch (curve?.child('Interp')?.value) {
        final List<Object?> named => named,
        _ => const <Object?>[],
      };
      unread = unread || curves.any((named) => named != 'Constant');
      return PropertyTrack(
        keys: {
          for (var i = 0; i < ticks.length && i < values.length; i += 1)
            frameAt(ticks[i]).round(): PropertyKey(
              values[i] / unit,
              interpolation: i < curves.length && curves[i] == 'Constant'
                  ? PropertyKeyInterpolation.hold
                  : PropertyKeyInterpolation.linear,
            ),
        },
      );
    }
    final held = switch (_childOf(anim, 'Param', {'Name': type})?.value) {
      final num value => value,
      final List<Object?> pair when index < pair.length => pair[index],
      _ => null,
    };
    return held is num
        ? PropertyTrack(keys: {span.start: PropertyKey(held / unit)})
        : PropertyTrack.empty();
  }

  final x = keysOf('ImagePosition', axis: 'X');
  final y = keysOf('ImagePosition', axis: 'Y', index: 1);
  final scale = keysOf('ImageScale', unit: 100);
  final degrees = keysOf('ImageRotation');
  final pivotX = keysOf('ImageCenter', axis: 'X');
  final pivotY = keysOf('ImageCenter', axis: 'Y', index: 1);
  return (
    span: span,
    x: x,
    y: y,
    scale: scale,
    degrees: degrees,
    pivotX: pivotX,
    pivotY: pivotY,
    unread: unread,
  );
}
