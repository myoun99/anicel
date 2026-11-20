import '../../core/frozen_collections.dart';
import 'tvp_import_model.dart';
import 'tvpp_camera_bake.dart';
import 'tvpp_parse.dart';
import 'import_warning.dart';

/// One clip of a .tvpp, translated into the SAME parse-result model the
/// JSON export produces — so `planTvpImport` builds the cut for both
/// paths with one set of rules (one cel per drawing, run behaviours,
/// camera fitting). What only the project file knows arrives as the
/// model's optional edges: folders, inbetween marks, blank instances.
class TvppClipConversion {
  const TvppClipConversion({
    required this.result,
    required this.slotsByFile,
  });

  final TvpImportClip result;

  /// [TvpExposureBlock.file] keys → the slot to decode. The keys are
  /// synthetic (`tvpp:layer:stream:slot`) and only meaningful together
  /// with the file bytes this clip was parsed from.
  final Map<String, TvppSlot> slotsByFile;
}

/// Converts [clip] (clip [clipIndex] of the file) for the planner.
///
/// Slot semantics, all verified against TVPaint's own JSON export of the
/// same clip:
///  * an image slot starts an instance on its frame;
///  * a hold slot extends the instance before it (NOT a blank cel);
///  * a blank instance is an image slot whose raster decodes to nothing —
///    it still starts a block, whose cel simply stays empty.
///
/// Re-exposed drawings are stored as separate, pixel-identical images in
/// the file, and import as separate cels: in TVPaint they ARE separate
/// images (editing one never edits the other), so collapsing them the
/// way the export's `images[]` manifest suggests would invent a link.
TvppClipConversion convertTvppClip(
  TvppClip clip, {
  required int clipIndex,
}) {
  final warnings = <ImportWarning>[];
  final slotsByFile = <String, TvppSlot>{};

  // The stream is TOP-first (like the JSON's array); the parse-result
  // list is bottom-first, so build top-first and reverse at the end —
  // which also lands every folder AFTER its members, the shape
  // `Layer.folderId` construction wants.
  final topFirst = <TvpLayer>[];
  final topFirstParentLayerId = <int>[];
  final idToTopIndex = <int, int>{};
  var position = 0;

  for (var li = 0; li < clip.layers.length; li++) {
    final layer = clip.layers[li];
    if (layer.kind == TvppLayerKind.camera) {
      continue; // the camera layer is the clip's camera, not a row.
    }
    if (layer.kind == TvppLayerKind.unknown) {
      warnings.add(unsupportedLayerKind(layer.name));
      continue;
    }
    position += 1;
    if (layer.locked) {
      warnings.add(lockNotImported(layer.name));
    }

    if (layer.kind == TvppLayerKind.folder) {
      topFirst.add(
        TvpLayer(
          name: layer.name,
          position: position,
          visible: layer.visible,
          opacity: _opacityFrom(layer.opacity),
          start: layer.start,
          end: layer.end,
          preBehavior: layer.preBehavior,
          postBehavior: layer.postBehavior,
          // ⚠️No folder of a file measured here carries a mode word —
          // LRFH[15] stays unread until one does (card F-621 ③).
          blendingMode: 'Color',
          groupColor: null,
          blocks: const [],
          isFolder: true,
          collapsed: layer.collapsed,
        ),
      );
      topFirstParentLayerId.add(layer.parentId);
      if (layer.layerId != 0) {
        idToTopIndex[layer.layerId] = topFirst.length - 1;
      }
      continue;
    }

    // A CTG layer's two source streams arrive as two raster rows inside
    // a folder named after it — the sources survive verbatim; nothing
    // pretends to know TVPaint's compositing of them.
    if (layer.kind == TvppLayerKind.ctg) {
      topFirst.add(
        TvpLayer(
          name: layer.name,
          position: position,
          visible: layer.visible,
          opacity: 1,
          start: layer.start,
          end: layer.end,
          preBehavior: layer.preBehavior,
          postBehavior: layer.postBehavior,
          // The layer's blend goes where its two streams meet: the folder
          // blends them as one picture onto what is below, as TVPaint
          // blends the one layer. On each stream it would blend that
          // stream onto the other inside the folder and never reach the
          // picture below. ⚠️No CTG of a measured file carries a mode —
          // LRSH[15] is read as LRHD[15] is, as its other words are.
          blendingMode: _blendingModeName(layer.blendingModeId),
          groupColor: null,
          blocks: const [],
          isFolder: true,
        ),
      );
      topFirstParentLayerId.add(layer.parentId);
      final ctgFolderTopIndex = topFirst.length - 1;
      if (layer.layerId != 0) {
        idToTopIndex[layer.layerId] = ctgFolderTopIndex;
      }
      for (final (stream, slots) in [(0, layer.slots), (1, layer.ctgSecondStream)]) {
        position += 1;
        topFirst.add(
          _rasterLayer(
            clip,
            li,
            layer,
            slots,
            stream: stream,
            name: stream == 0 ? layer.name : '${layer.name} (2)',
            blendingMode: 'Color',
            position: position,
            slotsByFile: slotsByFile,
            warnings: warnings,
          ),
        );
        // Members of the CTG folder — resolved via the folder's own
        // top-first index when its id is 0 (never seen, but cheap).
        topFirstParentLayerId.add(
          layer.layerId != 0 ? layer.layerId : -2 - ctgFolderTopIndex,
        );
      }
      continue;
    }

    topFirst.add(
      _rasterLayer(
        clip,
        li,
        layer,
        layer.slots,
        stream: 0,
        name: layer.name,
        blendingMode: _blendingModeName(layer.blendingModeId),
        position: position,
        slotsByFile: slotsByFile,
        warnings: warnings,
      ),
    );
    topFirstParentLayerId.add(layer.parentId);
  }

  // Resolve parent links to bottom-first indexes.
  final count = topFirst.length;
  int bottomIndexOf(int topIndex) => count - 1 - topIndex;

  final layers = <TvpLayer>[];
  for (var i = count - 1; i >= 0; i--) {
    final marker = topFirstParentLayerId[i];
    var parentBottom = -1;
    if (marker <= -2) {
      parentBottom = bottomIndexOf(-2 - marker);
    } else if (marker != 0) {
      final topIndex = idToTopIndex[marker];
      if (topIndex != null) {
        parentBottom = bottomIndexOf(topIndex);
      }
    }
    final layer = topFirst[i];
    layers.add(
      parentBottom < 0
          ? layer
          : TvpLayer(
              name: layer.name,
              position: layer.position,
              visible: layer.visible,
              opacity: layer.opacity,
              start: layer.start,
              end: layer.end,
              preBehavior: layer.preBehavior,
              postBehavior: layer.postBehavior,
              blendingMode: layer.blendingMode,
              groupColor: layer.groupColor,
              blocks: layer.blocks,
              isFolder: layer.isFolder,
              parentIndex: parentBottom,
              collapsed: layer.collapsed,
            ),
    );
  }

  // Camera: the project file carries only the authored keys — the
  // per-frame bake the JSON export ships is computed here (spatial
  // bezier between keys, each segment eased by its position profile).
  final poses = bakeTvppCamera(
    clip.cameraPoints,
    parseTvppCameraProfiles(clip.cameraDataText),
    frameCount: clip.frameCount,
  );

  return TvppClipConversion(
    result: TvpImportClip(
      versionMajor: 0,
      versionMinor: 0,
      clipName: clip.name,
      width: clip.width,
      height: clip.height,
      frameRate: clip.frameRate,
      pixelAspectRatio: clip.pixelAspectRatio,
      frameCount: clip.frameCount,
      background: const TvpColor(255, 255, 255),
      markIn: null,
      markOut: null,
      camera: TvpCamera(
        width: clip.width,
        height: clip.height,
        keyedOn: tvppCameraKeyFrames(clip.cameraPoints),
        positions: poses,
      ),
      layers: layers,
      warnings: warnings,
      audioTracks: [
        for (final track in clip.audioTracks)
          TvpAudioTrack(
            filePath: track.filePath,
            offsetSeconds: track.offsetSeconds,
            volume: track.volume,
            muted: track.muted,
            locked: track.locked,
          ),
      ],
    ),
    slotsByFile: slotsByFile,
  );
}

TvpLayer _rasterLayer(
  TvppClip clip,
  int layerIndex,
  TvppLayer layer,
  List<TvppSlot> slots, {
  required int stream,
  required String name,
  required String blendingMode,
  required int position,
  required Map<String, TvppSlot> slotsByFile,
  required List<ImportWarning> warnings,
}) {
  final blocks = <TvpExposureBlock>[];
  final marksByFrame = <int, List<int>>{};
  for (final mark in clip.imageMarks) {
    if (mark.layerIndex == layerIndex) {
      marksByFrame.putIfAbsent(mark.frame, () => []).add(mark.colorIndex);
    }
  }

  TvpExposureBlock? open;
  var openMarks = <int>[];
  void closeOpen() {
    final b = open;
    if (b == null) {
      return;
    }
    blocks.add(
      TvpExposureBlock(
        start: b.start,
        length: b.length,
        name: b.name,
        file: b.file,
        sourceIndex: b.sourceIndex,
        isReexposure: false,
        breakdownOffsets: frozenList(openMarks..sort()),
      ),
    );
    open = null;
    openMarks = <int>[];
  }

  for (var k = 0; k < slots.length; k++) {
    final slot = slots[k];
    final frame = layer.start + k;
    if (slot.kind == TvppSlotKind.image) {
      closeOpen();
      final key = 'tvpp:$layerIndex:$stream:$k';
      slotsByFile[key] = slot;
      open = TvpExposureBlock(
        start: frame,
        length: 1,
        name: layer.instanceNames[k] ?? '',
        file: key,
        sourceIndex: stream * 100000 + k,
        isReexposure: false,
      );
    } else {
      final b = open;
      if (b == null) {
        warnings.add(
          ImportWarning(
            'tvppHoldNoDrawing',
            '{name}: the hold at frame {frame} has no drawing to carry.',
            {'name': name, 'frame': '${frame + 1}'},
          ),
        );
        continue;
      }
      open = TvpExposureBlock(
        start: b.start,
        length: b.length + 1,
        name: b.name,
        file: b.file,
        sourceIndex: b.sourceIndex,
        isReexposure: false,
      );
    }
    // A mark on the block head marks nothing (the workflow rule: heads
    // are the drawing itself); inside the exposure it is an inbetween.
    if (marksByFrame.containsKey(frame) && open != null && frame != open!.start) {
      openMarks.add(frame - open!.start);
    }
  }
  closeOpen();

  return TvpLayer(
    name: name,
    position: position,
    visible: layer.visible,
    opacity: _opacityFrom(layer.opacity),
    start: layer.start,
    end: layer.end,
    preBehavior: layer.preBehavior,
    postBehavior: layer.postBehavior,
    blendingMode: blendingMode,
    groupColor: null,
    blocks: blocks,
  );
}

/// TVPaint stores opacity as 0..255 but its UI deals in whole percent —
/// the artist typed 76, the file holds 195, and 195/255 would surface as
/// 76.47%. Round to the percent the artist chose.
double _opacityFrom(int raw) => (raw / 255 * 100).round() / 100;

/// TVPaint's name for blending mode [id] ([TvppLayer.blendingModeId]),
/// in TVPaint's own English — the name the import's notice shows when
/// Anicel has no such mode.
///
/// 🔬The numbers are read off the user's calibration file (card F-621 ③,
/// 11-19): a layer per mode of TVPaint 12's picker, each named with the
/// picker's label. The English is TVPaint's blending-mode list
/// (doc.tvpaint.com); where the file's label carries it in brackets
/// (Divide, Grain Extract, Subtract, Alpha Diff) the two agree. 13 and 14
/// were in no layer — they come in by number, as any number TVPaint adds.
String _blendingModeName(int id) => switch (id) {
      0 => 'Color',
      1 => 'Behind',
      2 => 'Erase',
      3 => 'Shade',
      4 => 'Light',
      5 => 'Colorize',
      6 => 'Tint',
      7 => 'Add',
      8 => 'Sub',
      9 => 'Multiply',
      10 => 'Screen',
      11 => 'Replace',
      12 => 'Substitute',
      15 => 'Difference',
      16 => 'Divide',
      17 => 'Overlay',
      18 => 'Dodge',
      19 => 'Burn',
      20 => 'Hard Light',
      21 => 'Soft Light',
      22 => 'Grain Extract',
      23 => 'Grain Merge',
      24 => 'Subtract',
      25 => 'Darken Only',
      26 => 'Lighten Only',
      27 => 'Value',
      28 => 'Saturate',
      29 => 'Overlay 2',
      30 => 'Alpha Diff',
      _ => '$id',
    };
