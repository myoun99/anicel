/// The clip model a TVPaint import hands the planner — one clip, layers
/// with their timelines already resolved to exposure blocks, the camera
/// baked to per-frame poses, sound tracks as references.
///
/// This began life as the JSON export's parse result; the .tvpp reader
/// (`tvpp_parse.dart` + `tvpp_convert.dart`) now produces it directly
/// and the JSON path is gone — the model stayed because the PLANNER's
/// rules (one cel per drawing, live run edges, camera fitting) are about
/// this shape, not about where the bytes came from. Everything here was
/// verified against TVPaint's own exports during the format work
/// (376/376 images pixel-perfect, 30/30 layer behaviours; spec in
/// project memory `tvpp-format-notes`).
library;

import 'import_warning.dart';

enum TvpEdgeBehavior {
  none,
  repeat,
  pingPong,
  hold;

  /// The wire values, confirmed against the timeline UI and the project
  /// file's layer header: `Ø` = 0, `↻` = 1, `II▸` = 3 — and 2 IS
  /// ping-pong, pinned live by SKK's B layer.
  static TvpEdgeBehavior fromJson(Object? value) => switch (value) {
    0 => TvpEdgeBehavior.none,
    1 => TvpEdgeBehavior.repeat,
    2 => TvpEdgeBehavior.pingPong,
    3 => TvpEdgeBehavior.hold,
    _ => TvpEdgeBehavior.none,
  };
}

/// One block of a layer's timeline: a drawing (or blank instance)
/// exposed for [length] frames from [start].
class TvpExposureBlock {
  const TvpExposureBlock({
    required this.start,
    required this.length,
    required this.name,
    required this.file,
    required this.sourceIndex,
    required this.isReexposure,
    this.breakdownOffsets = const [],
  });

  /// 0-based frame this block starts on.
  final int start;

  /// Frames covered. Always at least 1.
  final int length;

  /// The instance name to show as the cel name.
  final String name;

  /// Where the drawing's pixels live — for the .tvpp reader a synthetic
  /// slot key resolved against the file bytes at bake time.
  final String file;

  /// The DRAWING's identity: two blocks with the same [sourceIndex] show
  /// one cel between them.
  final int sourceIndex;

  /// Whether an earlier block already showed this drawing.
  final bool isReexposure;

  /// Inbetween dots (중간나누기 ●) inside this block, as offsets from
  /// [start] in `1..length-1` — from `IMRK` marks; a mark ON the block
  /// head is dropped there, per the workflow rule, so offset 0 never
  /// appears.
  final List<int> breakdownOffsets;

  int get endExclusive => start + length;
}

/// A camera pose at one frame; [x] and [y] are the camera's centre in
/// clip coordinates.
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

  /// 1-based, as TVPaint counts frames.
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

  /// Authored keys. Empty when the clip has no camera work.
  final List<TvpCameraPose> keyframes;

  /// One entry per frame — baked by `tvpp_camera_bake.dart` from the
  /// authored keys and their easing profiles.
  final List<TvpCameraPose> positions;

  /// Whether the camera actually goes anywhere — a still camera bakes a
  /// full [positions] list of identical poses, which is not camera work.
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
    required this.blocks,
    this.isFolder = false,
    this.parentIndex = -1,
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

  /// The resolved timeline, in frame order and gapless within the frames
  /// it covers.
  final List<TvpExposureBlock> blocks;

  /// TVPaint folders: a folder row carries no blocks, and its members
  /// point back at it through [parentIndex] — the index of the folder
  /// INSIDE the same bottom-first layer list, -1 for root. A folder
  /// always sits AFTER its members in that list (= directly above them
  /// in the stack), which is the shape [Layer.folderId] wants.
  final bool isFolder;
  final int parentIndex;

  /// Whether the layer has anything to show at all.
  bool get isEmpty => blocks.isEmpty;
}

class TvpColor {
  const TvpColor(this.red, this.green, this.blue);

  final int red;
  final int green;
  final int blue;
}

/// One sound track of the clip. A REFERENCE, never embedded.
class TvpAudioTrack {
  const TvpAudioTrack({
    required this.filePath,
    required this.offsetSeconds,
    required this.volume,
    required this.muted,
  });

  final String filePath;
  final double offsetSeconds;
  final double volume;
  final bool muted;
}

/// One clip, ready for the planner.
class TvpImportClip {
  const TvpImportClip({
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
    this.audioTracks = const [],
  });

  final int versionMajor;
  final int versionMinor;

  final String clipName;
  final int width;
  final int height;
  final double frameRate;
  final double pixelAspectRatio;

  /// Frames in the clip.
  final int frameCount;

  final TvpColor background;

  /// Mark in/out, 0-based inclusive, when set.
  final int? markIn;
  final int? markOut;

  final TvpCamera camera;

  /// Bottom-first — `Cut.layers` order.
  final List<TvpLayer> layers;

  final List<ImportWarning> warnings;

  /// Sound tracks, as references.
  final List<TvpAudioTrack> audioTracks;
}
