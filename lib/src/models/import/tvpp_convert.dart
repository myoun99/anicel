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
    position += 1;

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
          blendingMode: 'Color',
          groupColor: null,
          blocks: const [],
          isFolder: true,
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
          blendingMode: 'Color',
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
  final keyframes = [
    for (final p in clip.cameraPoints)
      TvpCameraPose(
        frame: p.instant + 1,
        x: p.x,
        y: p.y,
        angleDegrees: p.rotationDegrees,
        scale: p.zoomFactor,
        sizeX: p.sizeX,
        sizeY: p.sizeY,
      ),
  ];

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
        keyframes: poses.isEmpty ? const [] : keyframes,
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
        breakdownOffsets: List.unmodifiable(openMarks..sort()),
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
    blendingMode: 'Color',
    groupColor: null,
    blocks: blocks,
  );
}

/// TVPaint stores opacity as 0..255 but its UI deals in whole percent —
/// the artist typed 76, the file holds 195, and 195/255 would surface as
/// 76.47%. Round to the percent the artist chose.
double _opacityFrom(int raw) => (raw / 255 * 100).round() / 100;
