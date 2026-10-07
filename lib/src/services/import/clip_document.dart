import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'clip_cmt.dart';
import 'clip_container.dart';

/// What a CLIP STUDIO PAINT layer is, as the import tells them apart.
enum ClipLayerKind {
  /// The canvas's root folder.
  root,
  folder,

  /// A raster layer — its picture is the layer's own render.
  raster,

  /// A picture dropped into the file (an image material): its picture is
  /// the ORIGINAL, placed by its transform; the render side stays empty.
  picture,
  vector,
  paper,

  /// A text layer (CLIP STUDIO's 「テキスト」). Named lettering, not text:
  /// the app's own text LAYER KIND was removed (F-154), and the scan that
  /// keeps it gone reads any name ending in its spelling as a remnant.
  lettering,
  sound,

  /// A fill layer (`GradationFillInfo`).
  fill,

  /// Anything else — read for its place in the tree only.
  other,
}

/// Where a layer's picture is stored: its offscreen's attribute and the
/// external chunk its blocks are in.
final class ClipPictureSource {
  const ClipPictureSource({required this.attribute, required this.blocksId});

  final Uint8List attribute;
  final String blocksId;
}

/// One layer of a CLIP STUDIO PAINT document's tree.
final class ClipLayer {
  ClipLayer({
    required this.id,
    required this.name,
    required this.kind,
    required this.visibility,
    required this.opacity,
    required this.composite,
    required this.folderFlags,
    required this.isAnimationFolder,
    required this.uuid,
    required this.left,
    required this.top,
    required this.offsetX,
    required this.offsetY,
    required this.render,
    required this.original,
    required this.originalTransform,
    required this.children,
  });

  /// `MainId`.
  final int id;
  final String name;
  final ClipLayerKind kind;

  /// `LayerVisibility`: bit 1 = shown, bit 2 = its mask is on.
  final int visibility;

  /// `LayerOpacity`, 0 … 256.
  final int opacity;

  /// `LayerComposite` — 0 normal, 2 multiply, 30 pass-through … (memory
  /// `csp-clip-format-notes` §4 has the table).
  final int composite;

  /// `LayerFolder`: not 0 = a folder; bit 16 = shown closed.
  final int folderFlags;

  /// `AnimationFolder` = 1 — its children are cels.
  final bool isAnimationFolder;

  /// `LayerUuid` without its hyphens, lower case — what a track names its
  /// layer by.
  final String uuid;

  /// Where the picture's top-left stands on the canvas:
  /// `LayerOffset + LayerRenderOffscrOffset` (a layer that was moved keeps
  /// the two moving in opposite directions, and only their sum is where it
  /// is).
  final int left;
  final int top;

  /// `LayerOffset` alone — what a dropped picture's [originalTransform]
  /// places its original from.
  final int offsetX;
  final int offsetY;

  /// The layer's own render at 100% — null when it has none.
  final ClipPictureSource? render;

  /// A dropped picture's original at 100% ([ClipLayerKind.picture]).
  final ClipPictureSource? original;

  /// `ResizableImageInfo` — how [original] is placed.
  final Uint8List? originalTransform;

  /// Bottom to top, the way the sibling chain runs.
  final List<ClipLayer> children;

  bool get isShown => visibility & 1 != 0;
  bool get isFolder => folderFlags != 0 || kind == ClipLayerKind.root;
  bool get isCollapsed => folderFlags & 16 != 0;

  /// Whether a picture of it is stored: a render, or a dropped picture's
  /// original. A vector, a text or a paper layer stores none.
  bool get hasPicture => render != null || original != null;

  /// This layer and every layer under it, this one first.
  Iterable<ClipLayer> get everyLayer sync* {
    yield this;
    for (final child in children) {
      yield* child.everyLayer;
    }
  }
}

/// Where a track shows its layer, in the timeline's frames: from [start]
/// up to (not including) [end].
typedef ClipSpan = ({int start, int end});

/// A cel shown from [frame] on — until the next key, or its clip's end.
typedef ClipCelKey = ({int frame, String cel});

/// One clip of a track: where it shows its layer, and the cels it keys
/// (in order of frame). A key holds until the next one or the clip's end,
/// never into the next clip — the gap between two clips shows nothing.
typedef ClipPiece = ({ClipSpan span, List<ClipCelKey> cels});

/// One layer's track on one timeline.
final class ClipTrack {
  const ClipTrack({
    required this.kind,
    required this.pieces,
    required this.labels,
  });

  /// `TrackKind`: 2000 animation folder · 2001 layer · 1000 folder ·
  /// 2003 paper · 4001 sound.
  final int kind;

  /// Its clips, in order of frame; outside them the layer is not shown.
  final List<ClipPiece> pieces;

  /// The frames a label (`LabelType` 1 — a breakdown) stands on.
  final List<int> labels;
}

/// One timeline — a cut.
final class ClipTimeline {
  const ClipTimeline({
    required this.name,
    required this.fps,
    required this.start,
    required this.end,
    required this.tracks,
  });

  final String name;
  final double fps;

  /// `StartFrame` · `EndFrame`.
  final int start;
  final int end;

  /// By the layer each names ([ClipLayer.uuid]).
  final Map<String, ClipTrack> tracks;
}

/// The shooting frame (撮影フレーム): its size, and where its centre stands
/// on the canvas.
typedef ClipFrame = ({int width, int height, double centerX, double centerY});

/// A CLIP STUDIO PAINT document's structure — what the import reads before
/// any pixel.
final class ClipDocument {
  const ClipDocument({
    required this.width,
    required this.height,
    required this.root,
    required this.timelines,
    required this.currentTimeline,
    required this.warnings,
    this.frame,
  });

  final int width;
  final int height;
  final ClipLayer root;

  /// The shooting frame — null when the file has none (the whole canvas).
  final ClipFrame? frame;

  /// In the file's order.
  final List<ClipTimeline> timelines;

  /// `AnimationCutBank.CurrentIndex`.
  final int currentTimeline;

  /// What the read found and could not follow — said, not hidden.
  final List<String> warnings;
}

/// [path]'s structure: its embedded database is copied into [scratch],
/// read, and deleted again.
ClipDocument readClipDocument(String path, {required Directory scratch}) {
  final file = File(path).openSync();
  try {
    final container = ClipContainer.indexOf(file);
    final copy = File(
      '${scratch.path}/clip-${DateTime.now().microsecondsSinceEpoch}.db',
    )..writeAsBytesSync(readClipPlace(file, container.database), flush: true);
    try {
      final database = sqlite3.open(copy.path, mode: OpenMode.readOnly);
      try {
        return _DocumentReader(database, file, container).read();
      } finally {
        database.close();
      }
    } finally {
      copy.deleteSync();
    }
  } finally {
    file.closeSync();
  }
}

final class _DocumentReader {
  _DocumentReader(this.database, this.file, this.container);

  final Database database;
  final RandomAccessFile file;
  final ClipContainer container;
  final warnings = <String>[];

  late final _tables = {
    for (final row in database.select(
      "SELECT name FROM sqlite_master WHERE type='table'",
    ))
      row['name'] as String,
  };

  final _columns = <String, Set<String>>{};

  /// The columns [table] has — the program writes only the ones in use, so
  /// a reader asks before it reads.
  Set<String> _columnsOf(String table) => _columns.putIfAbsent(
    table,
    () => _tables.contains(table)
        ? {
            for (final row in database.select('PRAGMA table_info("$table")'))
              row['name'] as String,
          }
        : const {},
  );

  /// Every row of [table] by `MainId`, with only [wanted] columns that
  /// exist read.
  Map<int, Map<String, Object?>> _rows(String table, List<String> wanted) {
    final have = _columnsOf(table);
    if (!have.contains('MainId')) {
      return const {};
    }
    final columns = ['MainId', ...wanted.where(have.contains)];
    return {
      for (final row in database.select(
        'SELECT ${[for (final c in columns) '"$c"'].join(', ')} '
        'FROM "$table"',
      ))
        row['MainId'] as int: {for (final c in columns) c: row[c]},
    };
  }

  ClipDocument read() {
    final canvas = _rows('Canvas', [
      'CanvasWidth',
      'CanvasHeight',
      'CanvasRootFolder',
      ..._frameColumns,
    ]).values.firstOrNull;
    if (canvas == null) {
      throw const ClipFormatException('the file holds no canvas');
    }
    final root = _layer(_int(canvas['CanvasRootFolder']));
    if (root == null) {
      throw const ClipFormatException('the canvas names no root folder');
    }
    final bank = _rows('AnimationCutBank', [
      'FirstTimeLine',
      'CurrentIndex',
    ]).values.firstOrNull;
    final width = _num(canvas['CanvasWidth']);
    final height = _num(canvas['CanvasHeight']);
    return ClipDocument(
      width: width.round(),
      height: height.round(),
      root: root,
      timelines: bank == null ? const [] : _timelines(bank),
      currentTimeline: bank == null ? 0 : _int(bank['CurrentIndex']),
      warnings: warnings,
      frame: _frameOf(canvas, width, height),
    );
  }

  static const _frameColumns = [
    'CropFrameInnerWidth',
    'CropFrameInnerHeight',
    'CropFrameCropOffsetX',
    'CropFrameCropOffsetY',
    'CropFrameInnerOffsetX',
    'CropFrameInnerOffsetY',
  ];

  /// The shooting frame: `CropFrameInner` is its size, and its centre
  /// stands at the canvas's centre moved by the crop's offset and the
  /// inner frame's (memory `csp-clip-format-notes` §3 — measured on a
  /// sample, a 1500×846 frame on 1754×2236 paper). None without a width.
  static ClipFrame? _frameOf(
    Map<String, Object?> canvas,
    double width,
    double height,
  ) {
    final frameWidth = _int(canvas['CropFrameInnerWidth']);
    final frameHeight = _int(canvas['CropFrameInnerHeight']);
    if (frameWidth <= 0 || frameHeight <= 0) {
      return null;
    }
    return (
      width: frameWidth,
      height: frameHeight,
      centerX:
          width / 2 +
          _num(canvas['CropFrameCropOffsetX']) +
          _num(canvas['CropFrameInnerOffsetX']),
      centerY:
          height / 2 +
          _num(canvas['CropFrameCropOffsetY']) +
          _num(canvas['CropFrameInnerOffsetY']),
    );
  }

  static const _layerColumns = [
    'LayerName',
    'LayerType',
    'LayerFolder',
    'LayerVisibility',
    'LayerOpacity',
    'LayerComposite',
    'LayerUuid',
    'LayerOffsetX',
    'LayerOffsetY',
    'LayerRenderOffscrOffsetX',
    'LayerRenderOffscrOffsetY',
    'LayerFirstChildIndex',
    'LayerNextIndex',
    'LayerRenderMipmap',
    'ResizableOriginalMipmap',
    'ResizableImageInfo',
    'DrawToRenderOffscreenType',
    'AnimationFolder',
    'AudioLayer',
    'GradationFillInfo',
  ];

  /// A mipmap's 100% picture, by the mipmap's id.
  Map<int, ClipPictureSource> _picturesById() {
    final mipmaps = _rows('Mipmap', ['BaseMipmapInfo']);
    final infos = _rows('MipmapInfo', ['ThisScale', 'Offscreen', 'NextIndex']);
    final offscreens = _rows('Offscreen', ['Attribute', 'BlockData']);
    final out = <int, ClipPictureSource>{};
    mipmaps.forEach((id, mipmap) {
      var infoId = _int(mipmap['BaseMipmapInfo']);
      final seen = <int>{};
      while (infoId != 0 && seen.add(infoId)) {
        final info = infos[infoId];
        if (info == null) {
          break;
        }
        if (_num(info['ThisScale']) == 100) {
          final offscreen = offscreens[_int(info['Offscreen'])];
          final attribute = offscreen?['Attribute'];
          final blocks = _text(offscreen?['BlockData']);
          if (attribute is Uint8List && blocks.isNotEmpty) {
            out[id] = ClipPictureSource(attribute: attribute, blocksId: blocks);
          }
          break;
        }
        infoId = _int(info['NextIndex']);
      }
    });
    return out;
  }

  Set<int> _vectorLayerIds() {
    if (!_columnsOf('VectorObjectList').contains('LayerId')) {
      return const {};
    }
    return {
      for (final row in database.select(
        'SELECT DISTINCT LayerId FROM VectorObjectList',
      ))
        _int(row['LayerId']),
    };
  }

  /// What every step of the tree walk asks: the layer table, the 100%
  /// pictures, and the layers that hold vectors.
  late final _layerRows = _rows('Layer', _layerColumns);
  late final _pictures = _picturesById();
  late final _vectorLayers = _vectorLayerIds();

  /// The layers the walk has reached — a chain that loops stops there.
  final _walked = <int>{};

  ClipLayer? _layer(int id) {
    final row = _layerRows[id];
    if (row == null || !_walked.add(id)) {
      return null;
    }
    final children = <ClipLayer>[];
    var childId = _int(row['LayerFirstChildIndex']);
    while (childId != 0) {
      final child = _layer(childId);
      if (child == null) {
        warnings.add('a layer chain names layer $childId, which is not there');
        break;
      }
      children.add(child);
      childId = _int(_layerRows[childId]!['LayerNextIndex']);
    }
    final pictures = _pictures;
    final transform = row['ResizableImageInfo'];
    return ClipLayer(
      id: id,
      name: _text(row['LayerName']),
      kind: _kindOf(row, _vectorLayers.contains(id)),
      visibility: _int(row['LayerVisibility']),
      opacity: _int(row['LayerOpacity']),
      composite: _int(row['LayerComposite']),
      folderFlags: _int(row['LayerFolder']),
      isAnimationFolder: _int(row['AnimationFolder']) == 1,
      uuid: _text(row['LayerUuid']).replaceAll('-', '').toLowerCase(),
      left: _int(row['LayerOffsetX']) + _int(row['LayerRenderOffscrOffsetX']),
      top: _int(row['LayerOffsetY']) + _int(row['LayerRenderOffscrOffsetY']),
      offsetX: _int(row['LayerOffsetX']),
      offsetY: _int(row['LayerOffsetY']),
      render: pictures[_int(row['LayerRenderMipmap'])],
      original: pictures[_int(row['ResizableOriginalMipmap'])],
      originalTransform: transform is Uint8List ? transform : null,
      children: children,
    );
  }

  static ClipLayerKind _kindOf(Map<String, Object?> row, bool hasVectors) {
    final type = _int(row['LayerType']);
    if (type == 256) {
      return ClipLayerKind.root;
    }
    if (_int(row['LayerFolder']) != 0) {
      return ClipLayerKind.folder;
    }
    if (type == 8720 || _int(row['AudioLayer']) == 1) {
      return ClipLayerKind.sound;
    }
    if (type == 800) {
      return ClipLayerKind.lettering;
    }
    if (type == 1584) {
      return ClipLayerKind.paper;
    }
    if (hasVectors || _int(row['DrawToRenderOffscreenType']) == 10) {
      return ClipLayerKind.vector;
    }
    if (_int(row['ResizableOriginalMipmap']) != 0) {
      return ClipLayerKind.picture;
    }
    if (row['GradationFillInfo'] is Uint8List) {
      return ClipLayerKind.fill;
    }
    if (type == 1) {
      return ClipLayerKind.raster;
    }
    return ClipLayerKind.other;
  }

  List<ClipTimeline> _timelines(Map<String, Object?> bank) {
    final timelines = _rows('TimeLine', [
      'NextTimeLine',
      'TimeLineName',
      'FrameRate',
      'StartFrame',
      'EndFrame',
      'FirstTrack',
    ]);
    final tracks = _rows('Track', [
      'TrackNextIndex',
      'TrackKind',
      'LayerUuidWithTrack',
      'TrackActionMixer',
      'TrackActionMixer2',
      'TrackLabelFirstIndex',
    ]);
    final labels = _rows('TimeLineLabel', [
      'LabelFrame',
      'LabelType',
      'LabelNextIndex',
    ]);
    final out = <ClipTimeline>[];
    final seen = <int>{};
    var id = _int(bank['FirstTimeLine']);
    while (id != 0 && seen.add(id)) {
      final row = timelines[id];
      if (row == null) {
        warnings.add('the timeline chain names timeline $id, not there');
        break;
      }
      final fps = _num(row['FrameRate']);
      final byLayer = <String, ClipTrack>{};
      final seenTracks = <int>{};
      var trackId = _int(row['FirstTrack']);
      while (trackId != 0 && seenTracks.add(trackId)) {
        final track = tracks[trackId];
        if (track == null) {
          warnings.add('a track chain names track $trackId, not there');
          break;
        }
        final uuid = _hex(track['LayerUuidWithTrack']);
        if (uuid.isNotEmpty) {
          byLayer[uuid] = _track(track, fps, labels);
        }
        trackId = _int(track['TrackNextIndex']);
      }
      out.add(
        ClipTimeline(
          name: _text(row['TimeLineName']),
          fps: fps,
          start: _int(row['StartFrame']),
          end: _int(row['EndFrame']),
          tracks: byLayer,
        ),
      );
      id = _int(row['NextTimeLine']);
    }
    return out;
  }

  ClipTrack _track(
    Map<String, Object?> track,
    double fps,
    Map<int, Map<String, Object?>> labels,
  ) {
    final kind = _int(track['TrackKind']);
    // The double document first: the single one rounds the ticks
    // (398.88 against 398.8800048828125).
    final mixerId = _text(track['TrackActionMixer2']).isNotEmpty
        ? _text(track['TrackActionMixer2'])
        : _text(track['TrackActionMixer']);
    final mixer = container.externals[mixerId];
    final pieces = <ClipPiece>[];
    if (mixer != null) {
      final document = cmtDocumentOfTrackData(readClipPlace(file, mixer));
      for (final clip in document.everyNode) {
        if (clip.name == 'ActionNodeClip') {
          if (_clip(clip, fps) case final piece?) {
            pieces.add(piece);
          }
        }
      }
    }
    final labelFrames = <int>[];
    final seen = <int>{};
    var labelId = _int(track['TrackLabelFirstIndex']);
    while (labelId != 0 && seen.add(labelId)) {
      final label = labels[labelId];
      if (label == null) {
        break;
      }
      if (_int(label['LabelType']) == 1) {
        labelFrames.add(_int(label['LabelFrame']));
      }
      labelId = _int(label['LabelNextIndex']);
    }
    return ClipTrack(
      kind: kind,
      pieces: pieces..sort((a, b) => a.span.start.compareTo(b.span.start)),
      labels: labelFrames..sort(),
    );
  }

  /// One clip of a track: where it shows, and the cels it keys.
  ///
  /// `frame = (TimeClip.Start + (tick − MotionClip.Start) × stretch) × fps
  /// ÷ Rate`, with `stretch = (TimeClip.End − TimeClip.Start) ÷
  /// (MotionClip.End − MotionClip.Start)` (1 when the motion has no
  /// length) — memory `csp-clip-format-notes` §3. A key holds until the
  /// next one; the last one holds to the clip's end.
  ClipPiece? _clip(CmtNode clip, double fps) {
    final time = clip.child('TimeClip');
    final motion = clip.child('MotionClip');
    if (time == null) {
      return null;
    }
    double field(CmtNode? node, String name) {
      final value = node?.child(name)?.value;
      return value is num ? value.toDouble() : 0;
    }

    final rate = field(time, 'Rate') != 0
        ? field(time, 'Rate')
        : field(clip.child('TimeInfo'), 'Rate');
    if (rate == 0) {
      warnings.add('a clip says no tick rate');
      return null;
    }
    final timeStart = field(time, 'Start');
    final timeEnd = field(time, 'End');
    final motionStart = field(motion, 'Start');
    final motionLength = field(motion, 'End') - motionStart;
    final stretch = motionLength == 0
        ? 1.0
        : (timeEnd - timeStart) / motionLength;
    int frameOf(double tick) =>
        ((timeStart + (tick - motionStart) * stretch) * fps / rate).round();
    final span = (
      start: (timeStart * fps / rate).round(),
      end: (timeEnd * fps / rate).round(),
    );
    final cels = <ClipCelKey>[];
    for (final curve in clip.everyNode) {
      if (curve.name != 'FCurve' ||
          curve.attributes['Type'] != 'ImageCelName') {
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
    return (span: span, cels: cels);
  }

  static int _int(Object? value) => switch (value) {
    final int v => v,
    final double v => v.round(),
    _ => 0,
  };

  static double _num(Object? value) => switch (value) {
    final num v => v.toDouble(),
    _ => 0,
  };

  static String _text(Object? value) => switch (value) {
    final String v => v,
    final Uint8List v => String.fromCharCodes(v),
    _ => '',
  };

  static String _hex(Object? value) => value is Uint8List
      ? [for (final b in value) b.toRadixString(16).padLeft(2, '0')].join()
      : _text(value).replaceAll('-', '').toLowerCase();
}
