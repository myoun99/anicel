/// TVPaint's JSON export (File ▸ Export ▸ JSON), read as a pure model —
/// no dart:io, no pixels, so the whole interpretation is testable against
/// the real exports checked in under `test/fixtures/tvpaint/`.
///
/// The export is TWO things: a folder of PNGs, one per INSTANCE, and this
/// JSON describing where each instance sits. The JSON is the only thing
/// that knows exposure, hold/repeat edges, cel names and camera work, so
/// it — not the PNG folder, and not the CSV export — is what the import
/// reads.
///
/// ## What the format does and does not say (measured, 2026-08-12)
///
/// `link[]` is an IMAGE MANIFEST, not a timeline dump: one entry per
/// instance that got a file. Its `instance-index` is the frame the
/// instance STARTS on; nothing in the entry says how long it runs. The
/// length comes from the next boundary — the next instance, the next
/// `repeat` span, or the layer's own `end`. Six layers of the `test4`
/// export and seventeen of `test_ge2` confirm this reading against the
/// CSV export of the same clips.
///
/// **The export must be taken with 「빈 사진 포함」 (include empty images)
/// ON.** With it off, instances whose image is blank are omitted from
/// `link[]` entirely — eleven of `test_ge2`'s seventeen layers came
/// through as `link: []` and their whole timeline was invisible, taking
/// the meaning of `repeat[]` with it. A blank instance is not nothing: SE
/// rows carry their dialogue in the instance NAME with no pixels at all
/// (`"arisu,おはよ"`), and camera rows carry `"PAN"`/`"FI"` the same way.
///
/// 「화상の重複」 (duplicate images) may be either way. With it off TVPaint
/// can point several instances at one file and list every position in
/// `images[]`; [parseTvpJson] treats each element of `images` as its own
/// block start, so both settings read identically.
library;

import 'dart:collection';
import 'dart:convert';

/// A JSON that is not a TVPaint export, or is one this build cannot read.
class TvpJsonParseException implements Exception {
  const TvpJsonParseException(this.message);

  final String message;

  @override
  String toString() => 'TvpJsonParseException: $message';
}

/// What a layer does with the frames OUTSIDE its own `[start, end]` —
/// TVPaint's pre/post behaviour, and the same four choices Anicel's run
/// edges speak (`TimelineRunEdgeMode`, minus ping-pong).
enum TvpEdgeBehavior {
  none,
  repeat,
  pingPong,
  hold;

  /// The wire values, confirmed against the timeline UI: `Ø` = 0,
  /// `↻` = 1, `II▸` = 3. 2 is ping-pong by elimination (TVPaint's own
  /// menu order), and no export has produced one yet.
  static TvpEdgeBehavior fromJson(Object? value) => switch (value) {
    0 => TvpEdgeBehavior.none,
    1 => TvpEdgeBehavior.repeat,
    2 => TvpEdgeBehavior.pingPong,
    3 => TvpEdgeBehavior.hold,
    _ => TvpEdgeBehavior.none,
  };
}

/// One `link[]` entry: an image and the instance(s) it belongs to.
class TvpInstance {
  const TvpInstance({
    required this.index,
    required this.name,
    required this.file,
    required this.images,
  });

  /// 0-based frame the instance starts on.
  final int index;

  /// `instance-name`. TVPaint reports an ORDINAL here when the animator
  /// left the instance unnamed — the fifth unnamed instance of a layer
  /// comes through as `"5"` — and nothing in the JSON distinguishes that
  /// from a cel genuinely named `5`. (The CSV export does, by falling
  /// back to the layer name in the file name; reading it just for that is
  /// not worth a second export, so the ordinal is kept as the cel name.)
  final String name;

  /// Path relative to the JSON's own directory, e.g.
  /// `[003] D/[0004] D.png`.
  final String file;

  /// Every frame index this image occupies a block start at. Normally
  /// `[index]`; a linked image exported with 「화상の重複」 off lists all
  /// of its positions here.
  final List<int> images;
}

/// A `repeat[]` entry: from [index], replay the [value] frames that
/// precede it, until the next boundary or the layer's `end`.
class TvpRepeatSpan {
  const TvpRepeatSpan({
    required this.index,
    required this.value,
    required this.mode,
  });

  final int index;

  /// Pattern length in frames. The pattern itself is
  /// `[index - value, index - 1]`.
  final int value;

  final int mode;
}

/// One resolved run of frames showing one image — the layer's timeline
/// after instances, `images[]` positions and `repeat[]` spans are all
/// folded together and run-length encoded.
class TvpExposureBlock {
  const TvpExposureBlock({
    required this.start,
    required this.length,
    required this.name,
    required this.file,
    required this.sourceIndex,
    required this.isReexposure,
  });

  /// 0-based frame this block starts on.
  final int start;

  /// Frames covered. Always at least 1.
  final int length;

  /// The instance name to show as the cel name.
  final String name;

  /// The instance's image file, relative to the JSON's directory.
  final String file;

  /// The `instance-index` of the instance whose pixels this block shows —
  /// the DRAWING's identity, not this block's position. Two blocks with
  /// the same [sourceIndex] are the same drawing exposed twice, and the
  /// import gives them one cel between them. Both a `repeat` span and a
  /// linked image listing several `images[]` positions produce that.
  final int sourceIndex;

  /// Whether an earlier block already showed this drawing.
  final bool isReexposure;

  int get endExclusive => start + length;
}

/// A camera pose at one frame. TVPaint gives both the authored keyframes
/// (`points`, carrying the CLIP size) and the per-frame baked curve
/// (`positions`, carrying the CAMERA size); [x] and [y] are the camera's
/// centre in clip coordinates.
class TvpCameraPose {
  const TvpCameraPose({
    required this.frame,
    required this.x,
    required this.y,
    required this.angleDegrees,
    required this.scale,
    required this.sizeX,
    required this.sizeY,
  });

  /// 1-based, as the export writes it.
  final int frame;

  final double x;
  final double y;
  final double angleDegrees;
  final double scale;
  final double sizeX;
  final double sizeY;
}

/// The clip's camera: the shooting frame ([width] × [height], which can
/// be smaller than the clip) and its motion.
class TvpCamera {
  const TvpCamera({
    required this.width,
    required this.height,
    required this.keyframes,
    required this.positions,
  });

  final int width;
  final int height;

  /// Authored keys. Empty when the camera never moves.
  final List<TvpCameraPose> keyframes;

  /// One entry per frame, baked by TVPaint.
  final List<TvpCameraPose> positions;

  /// Whether the camera actually goes anywhere — a still camera exports a
  /// full `positions` list of identical poses, which is not camera work.
  bool get isAnimated {
    if (positions.length < 2) {
      return false;
    }
    final first = positions.first;
    for (final pose in positions.skip(1)) {
      if (pose.x != first.x ||
          pose.y != first.y ||
          pose.angleDegrees != first.angleDegrees ||
          pose.scale != first.scale) {
        return true;
      }
    }
    return false;
  }
}

/// One layer of the clip, with its timeline already resolved.
class TvpLayer {
  const TvpLayer({
    required this.name,
    required this.position,
    required this.visible,
    required this.opacity,
    required this.start,
    required this.end,
    required this.preBehavior,
    required this.postBehavior,
    required this.blendingMode,
    required this.groupColor,
    required this.instances,
    required this.repeats,
    required this.blocks,
  });

  final String name;

  /// TVPaint's stacking number: **1 is the TOP layer**. Anicel stacks the
  /// other way (`Cut.layers.first` is the bottom), so the import reverses
  /// on this field rather than on array order.
  final int position;

  final bool visible;

  /// 0..1. The wire value is 0..255.
  final double opacity;

  /// The layer's own span, 0-based and INCLUSIVE. Frames outside it are
  /// the behaviour edges' business, not the timeline's.
  final int start;
  final int end;

  final TvpEdgeBehavior preBehavior;
  final TvpEdgeBehavior postBehavior;

  /// TVPaint's blending mode name. `"Color"` is its NORMAL — the default
  /// every layer of every measured export carries.
  final String blendingMode;

  /// The colour group swatch, or null when the layer has none.
  final TvpColor? groupColor;

  final List<TvpInstance> instances;
  final List<TvpRepeatSpan> repeats;

  /// The resolved timeline, in frame order and gapless within the frames
  /// it covers.
  final List<TvpExposureBlock> blocks;

  /// Whether the layer has anything to show at all.
  bool get isEmpty => blocks.isEmpty;
}

class TvpColor {
  const TvpColor(this.red, this.green, this.blue);

  final int red;
  final int green;
  final int blue;
}

/// The whole export, interpreted.
class TvpJsonParseResult {
  const TvpJsonParseResult({
    required this.versionMajor,
    required this.versionMinor,
    required this.clipName,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.pixelAspectRatio,
    required this.frameCount,
    required this.background,
    required this.markIn,
    required this.markOut,
    required this.camera,
    required this.layers,
    required this.warnings,
  });

  final int versionMajor;
  final int versionMinor;

  final String clipName;
  final int width;
  final int height;
  final double frameRate;
  final double pixelAspectRatio;

  /// `image-count`: the clip's length in frames.
  final int frameCount;

  final TvpColor background;

  /// 0-based mark in/out, or null when the export says they are off.
  final int? markIn;
  final int? markOut;

  final TvpCamera camera;

  /// Bottom-first — already reversed out of TVPaint's top-first
  /// `position` order, so this list drops straight into `Cut.layers`.
  final List<TvpLayer> layers;

  final List<String> warnings;
}

/// Reads [jsonText] as a TVPaint JSON export.
///
/// Throws [TvpJsonParseException] when the document is not one. Anything
/// that is merely ODD — a layer whose instance sits outside its own span,
/// a repeat whose pattern reaches before the layer starts, a ping-pong
/// edge Anicel has no mode for — lands in
/// [TvpJsonParseResult.warnings] and the rest still imports. Nothing
/// exits silently (§6-z21).
TvpJsonParseResult parseTvpJson(String jsonText) {
  final Object? decoded;
  try {
    decoded = jsonDecode(jsonText);
  } on FormatException catch (error) {
    throw TvpJsonParseException('Not valid JSON: ${error.message}');
  }
  if (decoded is! Map<String, dynamic>) {
    throw TvpJsonParseException('The document is not a JSON object.');
  }
  final project = decoded['project'];
  final clip = project is Map<String, dynamic> ? project['clip'] : null;
  if (clip is! Map<String, dynamic>) {
    throw TvpJsonParseException(
      'No project.clip — this is not a TVPaint JSON export.',
    );
  }

  final warnings = <String>[];
  final version = decoded['version'];
  final versionMajor = _int(
    version is Map<String, dynamic> ? version['major'] : null,
    0,
  );
  final versionMinor = _int(
    version is Map<String, dynamic> ? version['minor'] : null,
    0,
  );
  // Read forward: a newer writer is a warning, not a refusal — every
  // field this import needs has been stable across 5.x.
  if (versionMajor != 5) {
    warnings.add(
      'Export version $versionMajor.$versionMinor is newer than the 5.x '
      'this build was measured against — reading it anyway.',
    );
  }

  final width = _int(clip['width'], 0);
  final height = _int(clip['height'], 0);
  if (width <= 0 || height <= 0) {
    throw TvpJsonParseException('The clip has no size ($width×$height).');
  }
  final frameCount = _int(clip['image-count'], 0);
  if (frameCount <= 0) {
    throw TvpJsonParseException('The clip has no frames.');
  }

  final rawLayers = clip['layers'];
  final layers = <TvpLayer>[];
  if (rawLayers is List) {
    for (final raw in rawLayers) {
      if (raw is! Map<String, dynamic>) {
        continue;
      }
      layers.add(_parseLayer(raw, frameCount, warnings));
    }
  }
  if (layers.isEmpty) {
    warnings.add('The clip has no layers.');
  }
  // TVPaint numbers 1 = top; Anicel's stack is bottom-first. Sort on the
  // FIELD, not on array order — the array has always agreed so far, and
  // one day it will not.
  layers.sort((a, b) => b.position.compareTo(a.position));

  final markIn = _mark(clip['markin']);
  final markOut = _mark(clip['markout']);

  return TvpJsonParseResult(
    versionMajor: versionMajor,
    versionMinor: versionMinor,
    clipName: _string(clip['name'], 'clip'),
    width: width,
    height: height,
    frameRate: _double(clip['framerate'], 24),
    pixelAspectRatio: _double(clip['pixelaspectratio'], 1),
    frameCount: frameCount,
    background: _color(clip['bg']) ?? const TvpColor(255, 255, 255),
    markIn: markIn,
    markOut: markOut,
    camera: _parseCamera(project, clip),
    layers: layers,
    warnings: warnings,
  );
}

TvpLayer _parseLayer(
  Map<String, dynamic> raw,
  int frameCount,
  List<String> warnings,
) {
  final name = _string(raw['name'], 'layer');
  final start = _int(raw['start'], 0);
  final end = _int(raw['end'], -1);

  final instances = <TvpInstance>[];
  final rawLink = raw['link'];
  if (rawLink is List) {
    for (final entry in rawLink) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      final index = _int(entry['instance-index'], -1);
      if (index < 0) {
        continue;
      }
      final rawImages = entry['images'];
      final images = <int>[];
      if (rawImages is List) {
        for (final image in rawImages) {
          final value = _int(image, -1);
          if (value >= 0 && !images.contains(value)) {
            images.add(value);
          }
        }
      }
      if (images.isEmpty) {
        images.add(index);
      }
      instances.add(
        TvpInstance(
          index: index,
          name: _string(entry['instance-name'], ''),
          file: _string(entry['file'], ''),
          images: List.unmodifiable(images..sort()),
        ),
      );
    }
  }
  instances.sort((a, b) => a.index.compareTo(b.index));

  final repeats = <TvpRepeatSpan>[];
  final rawRepeat = raw['repeat'];
  if (rawRepeat is List) {
    for (final entry in rawRepeat) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      repeats.add(
        TvpRepeatSpan(
          index: _int(entry['index'], -1),
          value: _int(entry['value'], 0),
          mode: _int(entry['mode'], 1),
        ),
      );
    }
  }
  repeats.sort((a, b) => a.index.compareTo(b.index));

  final opacity = _int(raw['opacity'], 255).clamp(0, 255) / 255;
  final preBehavior = TvpEdgeBehavior.fromJson(raw['pre-behavior']);
  final postBehavior = TvpEdgeBehavior.fromJson(raw['post-behavior']);
  if (preBehavior == TvpEdgeBehavior.pingPong ||
      postBehavior == TvpEdgeBehavior.pingPong) {
    warnings.add(
      '$name: ping-pong edges have no Anicel equivalent — imported as '
      'repeat.',
    );
  }

  return TvpLayer(
    name: name,
    position: _int(raw['position'], 0),
    visible: raw['visible'] != false,
    opacity: opacity,
    start: start,
    end: end,
    preBehavior: preBehavior,
    postBehavior: postBehavior,
    blendingMode: _string(raw['blending-mode'], 'Color'),
    groupColor: _color(raw['group']),
    instances: List.unmodifiable(instances),
    repeats: List.unmodifiable(repeats),
    blocks: List.unmodifiable(
      resolveExposureBlocks(
        layerName: name,
        start: start,
        end: end,
        frameCount: frameCount,
        instances: instances,
        repeats: repeats,
        warnings: warnings,
      ),
    ),
  );
}

/// Folds instances, their `images[]` positions and `repeat[]` spans into
/// the layer's timeline.
///
/// Exposed for tests: this is the one piece of interpretation the format
/// does not hand over, and every claim about it was measured rather than
/// assumed.
///
/// The walk fills a per-frame array of "which instance shows here", then
/// run-length encodes it. Doing it per-frame is what makes `repeat`
/// tractable: a repeat span replays the [TvpRepeatSpan.value] frames
/// before it, and those frames may hold several instances — `test_ge2`'s
/// BG repeats a 9-frame block of three 3-frame drawings, and the CSV
/// export of the same clip shows exactly that cycle.
List<TvpExposureBlock> resolveExposureBlocks({
  required String layerName,
  required int start,
  required int end,
  required int frameCount,
  required List<TvpInstance> instances,
  required List<TvpRepeatSpan> repeats,
  required List<String> warnings,
}) {
  if (end < start || start < 0) {
    return const [];
  }
  // A span past the clip end would write cels nothing can ever show.
  var last = end;
  if (last >= frameCount) {
    warnings.add(
      '$layerName: span ends at frame ${end + 1} but the clip is '
      '$frameCount frames — clipped.',
    );
    last = frameCount - 1;
  }
  if (last < start) {
    return const [];
  }

  // Block starts, instance boundaries winning over repeat ones (authored
  // content beats a synthesized replay when both land on a frame).
  final boundaries = SplayTreeMap<int, TvpInstance?>();
  for (final instance in instances) {
    for (final at in instance.images) {
      if (at < start || at > last) {
        warnings.add(
          '$layerName: instance "${instance.name}" sits at frame ${at + 1}, '
          'outside the layer span — skipped.',
        );
        continue;
      }
      boundaries[at] = instance;
    }
  }
  for (final repeat in repeats) {
    if (repeat.index < start || repeat.index > last) {
      continue;
    }
    boundaries.putIfAbsent(repeat.index, () => null);
  }
  if (boundaries.isEmpty) {
    return const [];
  }

  final span = last - start + 1;
  // Which DRAWING shows at each frame, by its owning instance's index;
  // -1 = nothing. Keying on the instance rather than on the boundary is
  // what makes a linked image (one file, several `images[]` positions)
  // stay one drawing instead of splitting into one cel per position.
  final source = List<int>.filled(span, -1);
  final byInstanceIndex = <int, TvpInstance>{};

  final keys = boundaries.keys.toList();
  for (var i = 0; i < keys.length; i += 1) {
    final from = keys[i];
    final to = i + 1 < keys.length ? keys[i + 1] - 1 : last;
    final instance = boundaries[from];
    if (instance != null) {
      byInstanceIndex[instance.index] = instance;
      for (var frame = from; frame <= to; frame += 1) {
        source[frame - start] = instance.index;
      }
      continue;
    }
    // A repeat span. Its pattern is the `value` frames before it, which
    // the walk has already filled.
    final repeat = repeats.firstWhere((entry) => entry.index == from);
    if (repeat.value < 1 || from - repeat.value < start) {
      warnings.add(
        '$layerName: a repeat at frame ${from + 1} asks for '
        '${repeat.value} frame(s) of pattern that start before the layer '
        '— ignored.',
      );
      continue;
    }
    for (var frame = from; frame <= to; frame += 1) {
      final offset = (frame - from) % repeat.value;
      source[frame - start] = source[from - repeat.value + offset - start];
    }
  }

  // Run-length encode. Consecutive frames showing the same instance are
  // one exposure — which is the whole point: a 3-comma drawing becomes
  // ONE cel held 3 frames, not three cels.
  final blocks = <TvpExposureBlock>[];
  final shown = <int>{};
  var runStart = 0;
  for (var i = 1; i <= span; i += 1) {
    if (i < span && source[i] == source[runStart]) {
      continue;
    }
    final instanceIndex = source[runStart];
    final instance = instanceIndex < 0 ? null : byInstanceIndex[instanceIndex];
    if (instance != null) {
      blocks.add(
        TvpExposureBlock(
          start: start + runStart,
          length: i - runStart,
          name: instance.name,
          file: instance.file,
          sourceIndex: instanceIndex,
          isReexposure: !shown.add(instanceIndex),
        ),
      );
    }
    runStart = i;
  }
  return blocks;
}

TvpCamera _parseCamera(Object? project, Map<String, dynamic> clip) {
  final projectCamera = project is Map<String, dynamic>
      ? project['camera']
      : null;
  final clipCamera = clip['camera'];
  return TvpCamera(
    width: _int(
      projectCamera is Map<String, dynamic> ? projectCamera['width'] : null,
      _int(clip['width'], 0),
    ),
    height: _int(
      projectCamera is Map<String, dynamic> ? projectCamera['height'] : null,
      _int(clip['height'], 0),
    ),
    keyframes: _poses(
      clipCamera is Map<String, dynamic> ? clipCamera['points'] : null,
    ),
    positions: _poses(
      clipCamera is Map<String, dynamic> ? clipCamera['positions'] : null,
    ),
  );
}

List<TvpCameraPose> _poses(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  final poses = <TvpCameraPose>[];
  for (final entry in raw) {
    if (entry is! Map<String, dynamic>) {
      continue;
    }
    poses.add(
      TvpCameraPose(
        frame: _int(entry['frame'], 0),
        x: _double(entry['x'], 0),
        y: _double(entry['y'], 0),
        angleDegrees: _double(entry['angle'], 0),
        scale: _double(entry['scale'], 1),
        sizeX: _double(entry['sizeX'], 0),
        sizeY: _double(entry['sizeY'], 0),
      ),
    );
  }
  return List.unmodifiable(poses);
}

/// `{"status": bool, "value": int}` — the value only counts when the
/// status says the mark is on.
int? _mark(Object? raw) {
  if (raw is! Map<String, dynamic> || raw['status'] != true) {
    return null;
  }
  final value = _int(raw['value'], -1);
  return value < 0 ? null : value;
}

TvpColor? _color(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    return null;
  }
  return TvpColor(
    _int(raw['red'], 0).clamp(0, 255),
    _int(raw['green'], 0).clamp(0, 255),
    _int(raw['blue'], 0).clamp(0, 255),
  );
}

int _int(Object? value, int fallback) => switch (value) {
  final int number => number,
  final double number => number.round(),
  final String text => int.tryParse(text) ?? fallback,
  _ => fallback,
};

double _double(Object? value, double fallback) => switch (value) {
  final double number => number,
  final int number => number.toDouble(),
  final String text => double.tryParse(text) ?? fallback,
  _ => fallback,
};

String _string(Object? value, String fallback) =>
    value is String && value.isNotEmpty ? value : fallback;
