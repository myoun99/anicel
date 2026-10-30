import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../../models/frame.dart' show InbetweenMark;
import '../persistence/sqlite_bytes.dart';
import 'clip_cmt.dart';
import 'clip_container.dart';
import 'clip_layer_effects.dart';
import 'clip_placement.dart';
import 'clip_track_clip.dart';

export 'clip_track_clip.dart'
    show
        ClipCelKey,
        ClipCurve,
        ClipMove,
        ClipPiece,
        ClipSoundCue,
        ClipSpan;

/// What a CLIP STUDIO PAINT layer is, as the import tells them apart.
enum ClipLayerKind {
  /// The canvas's root folder.
  root,
  folder,

  /// A raster layer — its picture is the layer's own render.
  raster,

  /// A picture dropped into the file (an image material): its picture is
  /// the ORIGINAL, placed by its transform. Its render is declared and
  /// never stored — all 22 of the samples' (10-09).
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

/// A layer's mask as CLIP STUDIO applies it ([ClipLayer.mask]): where its
/// picture is stored — null when the file does not hold it — and where its
/// top-left stands on the canvas.
typedef ClipLayerMask = ({ClipPictureSource? source, int left, int top});

/// One sound a sound layer holds — the file CLIP STUDIO took in, whole, in
/// the external chunk [binaryId] (an mp3 of the samples began 「ID3」 —
/// memory `csp-clip-format-notes` §3): what a sound track's clip names to
/// play it by ([objectUuid]), what it was called ([name]), and the
/// extension it was kept under.
typedef ClipSound = ({
  String objectUuid,
  String binaryId,
  String name,
  String extension,
});

/// One text of a text layer as the file keeps it: what it says and the
/// attribute parameters it is set by (`clip_lettering.dart` reads them —
/// memory `csp-clip-format-notes` 6-1 §13).
typedef ClipLettering = ({String text, Uint8List attributes});

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
    this.vectorData = const [],
    this.sounds = const [],
    this.texts = const [],
    this.textPictures = const [],
    this.camera,
    this.mainColour,
    this.effectsOn = false,
    this.clipped = false,
    this.mask,
    this.locked = false,
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

  /// `LayerUuid` as [clipUuidKey] spells it — what a track names its layer
  /// by.
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

  /// The external chunks a vector layer's strokes are in, in the file's
  /// order — its picture, drawn here: the render it keeps beside them has
  /// no blocks in the file (the one sample with vectors, all seven layers).
  final List<String> vectorData;

  /// A sound layer's sounds, in its objects' chain order — the ones whose
  /// bytes the file holds the address of.
  final List<ClipSound> sounds;

  /// A text layer's texts, in the file's order: `TextLayerString` with
  /// `TextLayerAttributes`, then each of their `…Array`s.
  final List<ClipLettering> texts;

  /// The pictures CLIP STUDIO drew of a text layer's texts — offscreens the
  /// layer names through `Offscreen.LayerId` alone, no mipmap level and no
  /// thumbnail (all 16 texts of the samples have one, 10-17), in `MainId`
  /// order. ⛔Not its [render]: a text layer's is declared and never stored,
  /// as an image material's is.
  final List<ClipPictureSource> textPictures;

  /// The 2D camera this folder is (`Camera2DResizableImageInfo` — memory
  /// `csp-clip-format-notes` §3), as it stands where no clip of its track
  /// moves it: its picture is the shooting frame, placed by this. Null on
  /// every other layer.
  final ClipPlacement? camera;

  /// `DrawColorMainRed` · `Green` · `Blue` as one opaque ARGB — a paper
  /// layer's colour; null where the file names none.
  ///
  /// ⚠️Each channel is 32 bits, read by its top byte: every sample's paper
  /// is white, every bit set (F-370, 10-17), so no sample tells a byte
  /// copied four times from a value scaled to 32 bits — and the top byte is
  /// the 8-bit value either way.
  final int? mainColour;

  /// Whether CLIP STUDIO draws an effect of the layer's properties over
  /// its own pixels: one its `LayerEffectInfo` turns on ([clipEffectsOn]),
  /// or its layer colour — `DrawColorEnable`, the main colour shown in
  /// place of black and the sub in place of white (the manual's 「Layer
  /// color」). Two samples' cels wear it on hundreds of layers, in red,
  /// blue and green (10-17).
  ///
  /// ⛔Never a paper's: a paper keeps its own colour in those columns
  /// ([mainColour]), its `DrawColorEnable` 1 on every sample's.
  final bool effectsOn;

  /// `LayerClip` — clipped to the layer under it.
  final bool clipped;

  /// The layer mask CLIP STUDIO applies: a `LayerLayerMaskMipmap` with
  /// [visibility]'s bit 2 on, standing at `LayerOffset + LayerMaskOffset +
  /// LayerMaskOffscrOffset` (MoArt's reading — memory `csp-clip-format-notes`
  /// §2; no sample holds a mask). Null for a layer with none, and for one
  /// whose mask is off: CLIP STUDIO does not apply that either.
  final ClipLayerMask? mask;

  /// `LayerLock` not 0 — some lock is on (the samples' are 1 and 16).
  final bool locked;

  /// Bottom to top, the way the sibling chain runs.
  final List<ClipLayer> children;

  bool get isShown => visibility & 1 != 0;
  bool get isFolder => folderFlags != 0 || kind == ClipLayerKind.root;
  bool get isCollapsed => folderFlags & 16 != 0;

  /// Whether it has a picture: a render, a dropped picture's original, a
  /// vector layer's strokes, or a text layer's texts.
  bool get hasPicture =>
      render != null ||
      original != null ||
      vectorData.isNotEmpty ||
      texts.isNotEmpty;

  /// This layer and every layer under it, this one first.
  Iterable<ClipLayer> get everyLayer sync* {
    yield this;
    for (final child in children) {
      yield* child.everyLayer;
    }
  }
}

/// One layer's track on one timeline.
final class ClipTrack {
  const ClipTrack({
    required this.kind,
    required this.pieces,
    this.breakdownMarks = const {},
    this.sounds = const [],
    this.moves = const [],
  });

  /// `TrackKind`: 2000 animation folder · 2001 layer · 1000 folder ·
  /// 2003 paper · 2005 2D camera folder · 4001 sound.
  final int kind;

  /// Its clips, in order of frame; outside them the layer is not shown.
  final List<ClipPiece> pieces;

  /// Its in-between labels, by the frame each stands on, as the mark each
  /// puts there ([_markOfLabel]) — in order of frame.
  final Map<int, InbetweenMark> breakdownMarks;

  /// A sound track's clips, as what each plays — in order of frame.
  final List<ClipSoundCue> sounds;

  /// Its clips that key its layer's placement, as how each moves it — a 2D
  /// camera folder's its camera, any other layer itself — in order of
  /// frame.
  final List<ClipMove> moves;
}

/// The mark a timeline label of [labelType] puts on its frame, or null for
/// a label that is no in-between.
///
/// 🗣️I-130-csp-import-Q1 (유저 2026-10-27, a sample made for it): its
/// 「中割りトラックラベル○」 on frame 3 and its 「中割りトラックラベル●」 on
/// frame 5, as asked, were the first two labels it made — 1 and 2. ↩️Only
/// 1 was read until then, as mark 2, the one mark there was before I-130;
/// the work samples s1–s5 hold 1 alone.
InbetweenMark? _markOfLabel(int labelType) => switch (labelType) {
  1 => InbetweenMark.one,
  2 => InbetweenMark.two,
  _ => null,
};

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
    this.resolution = 72,
  });

  final int width;
  final int height;
  final ClipLayer root;

  /// `CanvasResolution`, dots per inch — what a text's point size is on
  /// this canvas (`clip_lettering.dart`). 72 — a point a pixel — where the
  /// file names none.
  final double resolution;

  /// The shooting frame — null when the file has none (the whole canvas).
  final ClipFrame? frame;

  /// In the file's order.
  final List<ClipTimeline> timelines;

  /// `AnimationCutBank.CurrentIndex`.
  final int currentTimeline;

  /// What the read found and could not follow — said, not hidden.
  final List<String> warnings;
}

/// [path]'s structure: its embedded database, read as every SQLite file
/// the app reads from bytes is ([readSqliteBytes]) — its copy made in
/// [scratch].
ClipDocument readClipDocument(String path, {required Directory scratch}) {
  final file = File(path).openSync();
  try {
    final container = ClipContainer.indexOf(file);
    return readSqliteBytes(
      readClipPlace(file, container.database),
      (database) => _DocumentReader(database, file, container).read(),
      within: scratch,
    );
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

  /// The rows of [table] a chain walks: from [first] along each row's
  /// [next] to 0 — every list the file keeps is one (the timelines, a
  /// timeline's tracks, a track's labels, a layer's children and objects, a
  /// mipmap's scales). It stops where the chain comes back on itself, and
  /// where it names a row that is not there — said as [missing] when the
  /// chain is one a reader must not lose quietly.
  Iterable<Map<String, Object?>> _chain(
    Map<int, Map<String, Object?>> table,
    int first,
    String next, {
    String? missing,
  }) sync* {
    final seen = <int>{};
    var id = first;
    while (id != 0 && seen.add(id)) {
      final row = table[id];
      if (row == null) {
        if (missing != null) {
          warnings.add('$missing $id, which is not there');
        }
        return;
      }
      yield row;
      id = _int(row[next]);
    }
  }

  ClipDocument read() {
    final canvas = _rows('Canvas', [
      'CanvasWidth',
      'CanvasHeight',
      'CanvasResolution',
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
    final resolution = _num(canvas['CanvasResolution']);
    return ClipDocument(
      width: width.round(),
      height: height.round(),
      root: root,
      timelines: bank == null ? const [] : _timelines(bank),
      currentTimeline: bank == null ? 0 : _int(bank['CurrentIndex']),
      warnings: warnings,
      frame: _frameOf(canvas, width, height),
      resolution: resolution > 0 ? resolution : 72,
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
    'TextLayerType',
    'TextLayerString',
    'TextLayerAttributes',
    'TextLayerStringArray',
    'TextLayerAttributesArray',
    'FirstLayerObject',
    'Camera2DResizableImageInfo',
    'LayerEffectInfo',
    'DrawColorEnable',
    'LayerClip',
    'LayerLayerMaskMipmap',
    'LayerMaskOffsetX',
    'LayerMaskOffsetY',
    'LayerMaskOffscrOffsetX',
    'LayerMaskOffscrOffsetY',
    'LayerLock',
    ..._mainColourColumns,
  ];

  static const _mainColourColumns = [
    'DrawColorMainRed',
    'DrawColorMainGreen',
    'DrawColorMainBlue',
  ];

  /// A mipmap's 100% picture, by the mipmap's id.
  Map<int, ClipPictureSource> _picturesById() {
    final mipmaps = _rows('Mipmap', ['BaseMipmapInfo']);
    final infos = _rows('MipmapInfo', ['ThisScale', 'Offscreen', 'NextIndex']);
    final offscreens = _rows('Offscreen', ['Attribute', 'BlockData']);
    final out = <int, ClipPictureSource>{};
    mipmaps.forEach((id, mipmap) {
      final full = _chain(
        infos,
        _int(mipmap['BaseMipmapInfo']),
        'NextIndex',
      ).where((info) => _num(info['ThisScale']) == 100).firstOrNull;
      if (full == null) {
        return;
      }
      final offscreen = offscreens[_int(full['Offscreen'])];
      final attribute = offscreen?['Attribute'];
      final blocks = _text(offscreen?['BlockData']);
      if (attribute is Uint8List && blocks.isNotEmpty) {
        out[id] = ClipPictureSource(attribute: attribute, blocksId: blocks);
      }
    });
    return out;
  }

  /// Each layer's vector data (`VectorObjectList.VectorData` — the external
  /// chunk its strokes are in), in the file's order.
  Map<int, List<String>> _vectorDataByLayer() {
    final columns = _columnsOf('VectorObjectList');
    if (!columns.contains('LayerId') || !columns.contains('VectorData')) {
      return const {};
    }
    final out = <int, List<String>>{};
    for (final row in database.select(
      'SELECT LayerId, VectorData FROM VectorObjectList ORDER BY rowid',
    )) {
      (out[_int(row['LayerId'])] ??= []).add(_text(row['VectorData']));
    }
    return out;
  }

  /// Each sound layer's sounds (memory `csp-clip-format-notes` §3): the
  /// layer's objects (`FirstLayerObject` → `LayerObject.ObjectNext`), each
  /// through its bank item (`CanvasItem`, by `BankItemUuid`) to the
  /// external chunk the sound file is in (`CanvasItemBinary.ItemBinaryData`).
  /// An object whose chunk is named nowhere is left out.
  List<ClipSound> _soundsOf(Map<String, Object?> layer) {
    final out = <ClipSound>[];
    for (final object in _chain(
      _soundObjects,
      _int(layer['FirstLayerObject']),
      'ObjectNext',
    )) {
      final item = _soundItems[clipUuidKey(object['BankItemUuid'])];
      final binaryId = _text(
        _soundBinaries[_int(item?['ItemBinaryMainIndex'])]?['ItemBinaryData'],
      );
      if (item != null && binaryId.isNotEmpty) {
        out.add((
          objectUuid: clipUuidKey(object['ObjectUuid']),
          binaryId: binaryId,
          name: _text(object['ObjectName']),
          extension: _text(item['ItemFileExtension']),
        ));
      }
    }
    return out;
  }

  late final _soundObjects = _rows('LayerObject', [
    'ObjectUuid',
    'BankItemUuid',
    'ObjectName',
    'ObjectNext',
  ]);
  late final _soundItems = {
    for (final row in _rows('CanvasItem', [
      'ItemUuid',
      'ItemFileExtension',
      'ItemBinaryMainIndex',
    ]).values)
      clipUuidKey(row['ItemUuid']): row,
  };
  late final _soundBinaries = _rows('CanvasItemBinary', ['ItemBinaryData']);

  /// [layer]'s texts ([ClipLayer.texts]): the one its own columns hold, then
  /// each of the `…Array` columns' — `u32 LE length + bytes`, again and
  /// again (one sample layer holds two). A text with no setting to go with
  /// it is said.
  List<ClipLettering> _textsOf(Map<String, Object?> layer) {
    final texts = [
      if (layer['TextLayerString'] case final Object one) _utf8(one),
      for (final part in _parts(layer['TextLayerStringArray'])) _utf8(part),
    ];
    final settings = [
      if (layer['TextLayerAttributes'] case final Uint8List one) one,
      ..._parts(layer['TextLayerAttributesArray']),
    ];
    if (texts.length != settings.length) {
      warnings.add(
        'text layer ${layer['MainId']} holds ${texts.length} texts and '
        '${settings.length} settings for them',
      );
    }
    return [
      for (var i = 0; i < texts.length && i < settings.length; i += 1)
        (text: texts[i], attributes: settings[i]),
    ];
  }

  /// [layer]'s pictures of its texts ([ClipLayer.textPictures]).
  List<ClipPictureSource> _textPicturesOf(int layer) {
    const wanted = ['LayerId', 'Attribute', 'BlockData'];
    if (!_columnsOf('Offscreen').containsAll(wanted)) {
      return const [];
    }
    return [
      for (final row in database.select(
        'SELECT MainId, Attribute, BlockData FROM Offscreen '
        'WHERE LayerId = ? ORDER BY MainId',
        [layer],
      ))
        if (row['Attribute'] case final Uint8List attribute
            when !_offscreensNamed.contains(row['MainId']))
          ClipPictureSource(
            attribute: attribute,
            blocksId: _text(row['BlockData']),
          ),
    ];
  }

  /// The offscreens a mipmap level or a thumbnail names — any other
  /// offscreen of a layer is a picture of one of its objects (wamsoft
  /// `clipparse` · `docs/CLIP_FORMAT.md`, measured on the samples 10-17).
  late final _offscreensNamed = {
    for (final info in _rows('MipmapInfo', ['Offscreen']).values)
      _int(info['Offscreen']),
    for (final thumbnail in _rows('LayerThumbnail', [
      'ThumbnailOffscreen',
    ]).values)
      _int(thumbnail['ThumbnailOffscreen']),
  };

  /// What every step of the tree walk asks: the layer table, the 100%
  /// pictures, and the layers' vector data.
  late final _layerRows = _rows('Layer', _layerColumns);
  late final _pictures = _picturesById();
  late final _vectorData = _vectorDataByLayer();

  /// The layers the walk has reached — one a chain names again, as its own
  /// folder's child or another's, is not walked twice.
  final _walked = <int>{};

  ClipLayer? _layer(int id) {
    final row = _layerRows[id];
    if (row == null || !_walked.add(id)) {
      return null;
    }
    final children = <ClipLayer>[];
    for (final childRow in _chain(
      _layerRows,
      _int(row['LayerFirstChildIndex']),
      'LayerNextIndex',
      missing: 'a layer chain names layer',
    )) {
      final childId = _int(childRow['MainId']);
      final child = _layer(childId);
      if (child == null) {
        warnings.add('a layer chain names layer $childId a second time');
        continue;
      }
      children.add(child);
    }
    final pictures = _pictures;
    final transform = row['ResizableImageInfo'];
    final camera = row['Camera2DResizableImageInfo'];
    final kind = _kindOf(row, _vectorData.containsKey(id));
    final lettering = kind == ClipLayerKind.lettering;
    return ClipLayer(
      id: id,
      name: _text(row['LayerName']),
      kind: kind,
      visibility: _int(row['LayerVisibility']),
      opacity: _int(row['LayerOpacity']),
      composite: _int(row['LayerComposite']),
      folderFlags: _int(row['LayerFolder']),
      isAnimationFolder: _int(row['AnimationFolder']) == 1,
      uuid: clipUuidKey(row['LayerUuid']),
      left: _int(row['LayerOffsetX']) + _int(row['LayerRenderOffscrOffsetX']),
      top: _int(row['LayerOffsetY']) + _int(row['LayerRenderOffscrOffsetY']),
      offsetX: _int(row['LayerOffsetX']),
      offsetY: _int(row['LayerOffsetY']),
      render: pictures[_int(row['LayerRenderMipmap'])],
      original: pictures[_int(row['ResizableOriginalMipmap'])],
      originalTransform: transform is Uint8List ? transform : null,
      vectorData: _vectorData[id] ?? const [],
      sounds: kind == ClipLayerKind.sound ? _soundsOf(row) : const [],
      texts: lettering ? _textsOf(row) : const [],
      textPictures: lettering ? _textPicturesOf(id) : const [],
      camera: camera is Uint8List ? clipPlacementOf(camera) : null,
      mainColour: _mainColourOf(row),
      effectsOn: _effectsOn(row, kind),
      clipped: _int(row['LayerClip']) != 0,
      mask: _maskOf(row, pictures),
      locked: _int(row['LayerLock']) != 0,
      children: children,
    );
  }

  /// [row]'s [ClipLayer.mask].
  static ClipLayerMask? _maskOf(
    Map<String, Object?> row,
    Map<int, ClipPictureSource> pictures,
  ) {
    final mipmap = _int(row['LayerLayerMaskMipmap']);
    if (mipmap == 0 || _int(row['LayerVisibility']) & 2 == 0) {
      return null;
    }
    int at(String axis) =>
        _int(row['LayerOffset$axis']) +
        _int(row['LayerMaskOffset$axis']) +
        _int(row['LayerMaskOffscrOffset$axis']);
    return (source: pictures[mipmap], left: at('X'), top: at('Y'));
  }

  /// [row]'s [ClipLayer.effectsOn].
  static bool _effectsOn(Map<String, Object?> row, ClipLayerKind kind) {
    final info = row['LayerEffectInfo'];
    return (info is Uint8List && clipEffectsOn(info)) ||
        (kind != ClipLayerKind.paper && _int(row['DrawColorEnable']) != 0);
  }

  /// [row]'s [ClipLayer.mainColour].
  static int? _mainColourOf(Map<String, Object?> row) {
    final [red, green, blue] = [
      for (final column in _mainColourColumns) row[column],
    ];
    if (red is! int || green is! int || blue is! int) {
      return null;
    }
    int top(int channel) => (channel >> 24) & 0xFF;
    return 0xFF000000 | (top(red) << 16) | (top(green) << 8) | top(blue);
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
    // A text layer is 800 — or 0 with its text's columns filled (four in
    // two samples, 10-09).
    if (type == 800 || row['TextLayerType'] != null) {
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
    for (final row in _chain(
      timelines,
      _int(bank['FirstTimeLine']),
      'NextTimeLine',
      missing: 'the timeline chain names timeline',
    )) {
      final fps = _num(row['FrameRate']);
      out.add(
        ClipTimeline(
          name: _text(row['TimeLineName']),
          fps: fps,
          start: _int(row['StartFrame']),
          end: _int(row['EndFrame']),
          tracks: {
            for (final track in _chain(
              tracks,
              _int(row['FirstTrack']),
              'TrackNextIndex',
              missing: 'a track chain names track',
            ))
              if (clipUuidKey(track['LayerUuidWithTrack']) case final uuid
                  when uuid.isNotEmpty)
                uuid: _track(track, fps, labels),
          },
        ),
      );
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
    final clips = [
      if (mixer != null)
        for (final node in cmtDocumentOfTrackData(
          readClipPlace(file, mixer),
        ).everyNode)
          if (node.name == 'ActionNodeClip')
            ?readTrackClip(node, fps, kind: kind, warnings: warnings),
    ];
    int byStart(ClipSpan a, ClipSpan b) => a.start.compareTo(b.start);
    final marks = <int, InbetweenMark>{};
    final unread = <int, int>{};
    for (final label in _chain(
      labels,
      _int(track['TrackLabelFirstIndex']),
      'LabelNextIndex',
    )) {
      final type = _int(label['LabelType']);
      switch (_markOfLabel(type)) {
        case final mark?:
          marks[_int(label['LabelFrame'])] = mark;
        case null:
          unread[type] = (unread[type] ?? 0) + 1;
      }
    }
    for (final MapEntry(key: type, value: count) in unread.entries) {
      warnings.add(
        '$count timeline label(s) of LabelType $type, which no in-between '
        'mark is, left out',
      );
    }
    return ClipTrack(
      kind: kind,
      pieces: [
        for (final clip in clips) clip.piece,
      ]..sort((a, b) => byStart(a.span, b.span)),
      breakdownMarks: {
        for (final frame in marks.keys.toList()..sort()) frame: marks[frame]!,
      },
      sounds: [
        for (final clip in clips) ?clip.sound,
      ]..sort((a, b) => a.frame.compareTo(b.frame)),
      moves: [
        for (final clip in clips) ?clip.move,
      ]..sort((a, b) => byStart(a.span, b.span)),
    );
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

  /// A text column the program writes as UTF-8 bytes (`TextLayerString`).
  static String _utf8(Object value) => switch (value) {
    final Uint8List v => utf8.decode(v, allowMalformed: true),
    _ => '$value',
  };

  /// An `…Array` column's parts: `u32 LE length + bytes`, again and again —
  /// up to a length that runs past the end.
  static List<Uint8List> _parts(Object? value) {
    if (value is! Uint8List) {
      return const [];
    }
    final data = ByteData.sublistView(value);
    final parts = <Uint8List>[];
    var at = 0;
    while (at + 4 <= value.length) {
      final length = data.getUint32(at, Endian.little);
      at += 4;
      if (at + length > value.length) {
        break;
      }
      parts.add(Uint8List.sublistView(value, at, at + length));
      at += length;
    }
    return parts;
  }
}
