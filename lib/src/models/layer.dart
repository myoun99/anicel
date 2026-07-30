import 'dart:collection';

import '../core/collection_equality.dart';
import '../core/copy_with_sentinel.dart';
import 'attached_mode.dart';
import 'attached_placement.dart';
import 'audio_clip.dart';
import 'camera_instruction.dart';
import 'frame.dart';
import 'frame_id.dart';
import 'layer_blend_mode.dart';
import 'layer_effect.dart';
import 'layer_id.dart';
import 'layer_kind.dart';
import 'layer_mark.dart';
import 'media_reference.dart';
import 'se_name_tag.dart';
import 'timeline_coverage.dart';
import 'timeline_exposure.dart';
import 'timeline_repeat.dart';
import 'transform_track.dart';

/// A cel layer. Its single [timeline] map records everything authored on
/// the frame axis: drawing block starts (frame + explicit hold length),
/// each carrying its own inbetween-dot offsets
/// ([TimelineExposure.breakdownOffsets]). Emptiness has no entry —
/// uncovered cells are the timesheet "X" cells. There is no separate marks
/// map, no blank entry type, and no standalone mark entry (legacy files
/// carrying any of those are migrated in [Layer.fromJson]).
class Layer {
  Layer({
    required this.id,
    required this.name,
    required List<Frame> frames,
    Map<int, TimelineExposure>? timeline,
    Map<int, InstructionEvent>? instructions,
    List<AudioClip> audioClips = const [],
    this.isVisible = true,
    this.collapsed = false,
    this.muted = false,
    this.audioGain = 1.0,
    this.audioPan = 0.0,
    this.opacity = 1.0,
    this.blendMode = LayerBlendMode.normal,
    this.kind = LayerKind.animation,
    this.onTimesheet = true,
    this.mark = LayerMark.none,
    this.isFillReference = false,
    this.mediaReference,
    this.seNameTag,
    TransformTrack? transformTrack,
    this.transformEnabled = true,
    List<LayerEffect> effects = const [],
    this.attachedToLayerId,
    this.attachedPlacement = AttachedPlacement.above,
    this.attachedMode = AttachedMode.synced,
    Map<FrameId, FrameId> baseFrameLinks = const {},
    List<TimelineRunBehavior> runBehaviors = const [],
    this.folderId,
  }) : frames = List.unmodifiable(frames),
       timeline = _immutableTimeline(timeline ?? _deriveTimeline(frames)),
       instructions = immutableInstructionMap(instructions ?? const {}),
       audioClips = List.unmodifiable(audioClips),
       transformTrack = transformTrack ?? TransformTrack.empty(),
       effects = List.unmodifiable(effects),
       baseFrameLinks = Map.unmodifiable(baseFrameLinks),
       runBehaviors = List.unmodifiable(runBehaviors);

  final LayerId id;
  final String name;
  final List<Frame> frames;
  final SplayTreeMap<int, TimelineExposure> timeline;

  /// Camera-work instruction spans (instruction rows only; empty elsewhere).
  /// Keyed by start frame; see [InstructionEvent].
  final SplayTreeMap<int, InstructionEvent> instructions;

  /// Sound files placed on this SE layer (empty on other kinds).
  final List<AudioClip> audioClips;
  final bool isVisible;

  /// The row's twirl: a collapsed FOLDER swallows its member rows in the
  /// layer list (persisted, like CSP). Meaningless on other kinds today —
  /// the attach-group fold is still session view state.
  final bool collapsed;

  /// Whether this layer's sounds are silenced (SE rows' speaker button —
  /// the audio counterpart of [isVisible]): playback and export skip the
  /// clips of muted layers, the waveforms keep displaying.
  final bool muted;

  /// The SE row's track fader (AUDIO-PRO R1): multiplies every clip on
  /// this layer. 1.0 = unity; applied exactly by the mixer (headroom, no
  /// platform clamp), like clip gain.
  final double audioGain;

  /// The SE row's pan, -1 (left) .. +1 (right), equal-power law. 0 =
  /// center. Applied on the device mixer path; the platform-player
  /// fallback cannot pan (honest limitation, like exact gain before it).
  final double audioPan;

  final double opacity;

  /// The composite blend against everything below (R26 #30); [normal]
  /// keeps plain srcOver. Applied at composite time, never baked.
  final LayerBlendMode blendMode;
  final LayerKind kind;

  /// Whether this layer's exposures are recorded on the timesheet output
  /// (preview/export). Only meaningful for cel layers — the camera track has
  /// its own sheet column regardless.
  final bool onTimesheet;

  /// Organizational color label; see [LayerMark].
  final LayerMark mark;

  /// The enclosing FOLDER LAYER ([LayerKind.folder]); null = top level.
  /// Render/timeline order stays the cut's flat layer list: a folder's
  /// members occupy a contiguous run with the folder row directly above
  /// it, and the members composite into the folder's buffer. Attach groups
  /// share one folder (never split across a folder boundary; the commands
  /// keep the invariant).
  final LayerId? folderId;

  /// Reference layer for the FILL tool (R20-C2, the CSP lighthouse):
  /// when any visible layer of the cut carries this flag, fills read
  /// ONLY the flagged layers as their source picture — paint on a color
  /// layer never blocks or leaks a fill traced against the line art.
  /// Display/export composite untouched.
  final bool isFillReference;

  /// Non-null makes this a REFERENCE layer showing an external media
  /// asset (§6-z23's second axis): the brush refuses
  /// ([layerAcceptsBrushInput]), the pixels come from the library, and
  /// RASTERIZING bakes them into cels and nulls only this field — the
  /// kind never changes.
  final MediaReference? mediaReference;

  /// SE rows only (R5b, §6-z15): where this speaker's ON-CANVAS name tag
  /// sits and how it looks. Null keeps the row on the stacked default
  /// ([defaultSeNameTagPosition]) — the tag still SHOWS, because the row's
  /// eye is the display switch; this field only overrides its placement.
  final SeNameTag? seNameTag;

  /// The layer's keyframed transform (the AE Transform group), applied at
  /// COMPOSITE time — playback, export, thumbnails and the editing canvas's
  /// layer stack — never baked into the artwork. Empty = identity (the
  /// untouched default for every layer).
  final TransformTrack transformTrack;

  /// The TRANSFORM group's own switch (R8) — AE's per-group bypass, and the
  /// twin of [LayerEffect.enabled] one level up. False bypasses this row's
  /// transform FX (the pose and the animated Opacity sample) on every
  /// composite route; its STATIC opacity and blend are display properties
  /// and stay.
  ///
  /// PERSISTED, deliberately: it used to be session-only view state, which
  /// meant a bypass vanished on reload while a per-effect bypass survived —
  /// one row of switches behaving two different ways. The layer-label fx
  /// button is a MASTER over this field and the effect chain's switches
  /// (user, 2026-07-30: "통합토글버튼").
  ///
  /// On the CAMERA row this is the camera-work bypass: the render routes
  /// (playback/export/thumbnails) ignore the cut's camera track while it is
  /// false, and the authoring overlays keep showing the real pose.
  final bool transformEnabled;

  /// The layer's EFFECT CHAIN (R6), applied at COMPOSITE time like the
  /// transform — never baked into the artwork. Applied in list order over
  /// the row's own picture, after its transform and before its
  /// opacity/blend meet the stack.
  ///
  /// A FOLDER row's effects land on its group buffer instead (so an effect
  /// on a folder is one filter over the composed members, not one filter
  /// each). Empty = no effect work at all, which is every layer until
  /// somebody adds one.
  final List<LayerEffect> effects;

  /// Non-null makes this an ATTACH LAYER riding the named base layer (W5):
  /// it shares the base's exposure timing and FX (transform + opacity
  /// lanes) while keeping its own cels, eye, static opacity and mark. Its
  /// own [timeline] stays empty — cels resolve through [baseFrameLinks].
  /// v1: bases are drawing-kind layers only, no nesting.
  final LayerId? attachedToLayerId;

  /// Whether this attach layer draws above or below its base (meaningful
  /// only while [attachedToLayerId] is set; the layer list keeps attach
  /// layers adjacent to their base in [below…, base, above…] order).
  final AttachedPlacement attachedPlacement;

  /// The attach TIMING mode (UI-R21 #3): [AttachedMode.synced] mirrors
  /// the base through [baseFrameLinks] (own [timeline] stays empty);
  /// [AttachedMode.free] authors its own timeline like a normal drawing
  /// layer. Meaningful only while [attachedToLayerId] is set.
  final AttachedMode attachedMode;

  /// CELL-level links: base frame id → this layer's frame id. Linking per
  /// cel (not per block start) keeps attach cels riding linked-cel reuse
  /// and comma drags automatically. A base cel without a link simply shows
  /// nothing on this layer; links to deleted base cels are orphans that
  /// come back with the cel (audio-clip semantics).
  final Map<FrameId, FrameId> baseFrameLinks;

  /// TVP-style run-edge properties (UI-R9 #10 N/H/R): live specs whose
  /// GHOST exposures are derived from the current timeline by
  /// [rederiveRunBehaviors] on every edit and cut-duration change — see
  /// [TimelineRunBehavior].
  final List<TimelineRunBehavior> runBehaviors;

  Layer copyWith({
    LayerId? id,
    String? name,
    List<Frame>? frames,
    Map<int, TimelineExposure>? timeline,
    Map<int, InstructionEvent>? instructions,
    List<AudioClip>? audioClips,
    bool? isVisible,
    bool? collapsed,
    bool? muted,
    double? audioGain,
    double? audioPan,
    double? opacity,
    LayerBlendMode? blendMode,
    LayerKind? kind,
    bool? onTimesheet,
    LayerMark? mark,
    bool? isFillReference,
    TransformTrack? transformTrack,
    bool? transformEnabled,
    List<LayerEffect>? effects,
    LayerId? attachedToLayerId,
    AttachedPlacement? attachedPlacement,
    AttachedMode? attachedMode,
    Map<FrameId, FrameId>? baseFrameLinks,
    List<TimelineRunBehavior>? runBehaviors,
    Object? folderId = copyWithSentinel,
    Object? mediaReference = copyWithSentinel,
    Object? seNameTag = copyWithSentinel,
  }) {
    final nextFrames = frames ?? this.frames;
    return Layer(
      id: id ?? this.id,
      name: name ?? this.name,
      frames: nextFrames,
      timeline: timeline ?? this.timeline,
      instructions: instructions ?? this.instructions,
      audioClips: audioClips ?? this.audioClips,
      isVisible: isVisible ?? this.isVisible,
      collapsed: collapsed ?? this.collapsed,
      muted: muted ?? this.muted,
      audioGain: audioGain ?? this.audioGain,
      audioPan: audioPan ?? this.audioPan,
      opacity: opacity ?? this.opacity,
      blendMode: blendMode ?? this.blendMode,
      kind: kind ?? this.kind,
      onTimesheet: onTimesheet ?? this.onTimesheet,
      mark: mark ?? this.mark,
      isFillReference: isFillReference ?? this.isFillReference,
      transformTrack: transformTrack ?? this.transformTrack,
      transformEnabled: transformEnabled ?? this.transformEnabled,
      effects: effects ?? this.effects,
      // Detaching is not expressible here (attach rows are created and
      // deleted whole); copyWith only carries the linkage along.
      attachedToLayerId: attachedToLayerId ?? this.attachedToLayerId,
      attachedPlacement: attachedPlacement ?? this.attachedPlacement,
      attachedMode: attachedMode ?? this.attachedMode,
      baseFrameLinks: baseFrameLinks ?? this.baseFrameLinks,
      runBehaviors: runBehaviors ?? this.runBehaviors,
      // Sentinel: moving a layer OUT of its folder (null) must be
      // expressible.
      folderId: identical(folderId, copyWithSentinel)
          ? this.folderId
          : folderId as LayerId?,
      // Sentinel: RASTERIZING clears the reference to null — that edit
      // must be expressible.
      mediaReference: identical(mediaReference, copyWithSentinel)
          ? this.mediaReference
          : mediaReference as MediaReference?,
      // Sentinel: clearing the tag back to the stacked default must be
      // expressible.
      seNameTag: identical(seNameTag, copyWithSentinel)
          ? this.seNameTag
          : seNameTag as SeNameTag?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'name': name,
    'frames': frames.map((frame) => frame.toJson()).toList(),
    'timeline': timeline.entries
        .map((entry) => {'index': entry.key, 'exposure': entry.value.toJson()})
        .toList(),
    if (instructions.isNotEmpty)
      'instructions': instructionMapToJson(instructions),
    if (audioClips.isNotEmpty)
      'audioClips': audioClips.map((clip) => clip.toJson()).toList(),
    'isVisible': isVisible,
    if (collapsed) 'collapsed': true,
    if (muted) 'muted': true,
    if (audioGain != 1.0) 'audioGain': audioGain,
    if (audioPan != 0.0) 'audioPan': audioPan,
    'opacity': opacity,
    // Default normal omitted — pre-blend files read back unchanged.
    if (blendMode != LayerBlendMode.normal) 'blendMode': blendMode.toJson(),
    'kind': kind.toJson(),
    'onTimesheet': onTimesheet,
    'mark': mark.toJson(),
    if (isFillReference) 'fillReference': true,
    if (mediaReference != null) 'mediaReference': mediaReference!.toJson(),
    if (seNameTag != null) 'seNameTag': seNameTag!.toJson(),
    if (folderId != null) 'folderId': folderId!.toJson(),
    if (runBehaviors.isNotEmpty)
      'runBehaviors': [for (final behavior in runBehaviors) behavior.toJson()],
    if (transformTrack.isNotEmpty) 'transform': transformTrack.toJson(),
    // Default true omitted — pre-R8 files read back with their FX applied.
    if (!transformEnabled) 'transformEnabled': false,
    if (effects.isNotEmpty)
      'effects': [for (final effect in effects) effect.toJson()],
    if (attachedToLayerId != null) ...{
      'attachedTo': attachedToLayerId!.toJson(),
      'attachedPlacement': attachedPlacement.toJson(),
      // Default synced omitted — pre-mode files read back unchanged.
      if (attachedMode != AttachedMode.synced)
        'attachedMode': attachedMode.toJson(),
      if (baseFrameLinks.isNotEmpty)
        'baseFrameLinks': [
          for (final entry in baseFrameLinks.entries)
            {'base': entry.key.toJson(), 'frame': entry.value.toJson()},
        ],
    },
  };

  /// Migrates a legacy free-floating clip ({'file', 'start'}) onto the SE
  /// frame whose block covered its start frame; clips landing on empty
  /// cells have nothing to link to and drop.
  static AudioClip? _audioClipFromJson(
    Map<String, dynamic> json,
    Map<int, TimelineExposure> timeline,
  ) {
    if (json.containsKey('frame')) {
      return AudioClip.fromJson(json);
    }
    final startFrame = json['start'] as int? ?? 0;
    for (final block in drawingBlocks(SplayTreeMap.of(timeline))) {
      if (block.startIndex <= startFrame &&
          startFrame < block.endIndexExclusive) {
        return AudioClip(
          filePath: json['file'] as String,
          frameId: block.frameId,
        );
      }
    }
    return null;
  }

  factory Layer.fromJson(Map<String, dynamic> json) {
    final frames = (json['frames'] as List<dynamic>)
        .map((frame) => Frame.fromJson(frame as Map<String, dynamic>))
        .toList();
    final timeline = json.containsKey('timeline')
        ? _timelineFromJson(
            json['timeline'],
            legacyMarksJson: json['marks'],
            frames: frames,
          )
        : _deriveTimeline(frames);
    return Layer(
      id: LayerId.fromJson(json['id'] as Map<String, dynamic>),
      name: json['name'] as String,
      frames: frames,
      timeline: timeline,
      instructions: instructionMapFromJson(json['instructions']),
      audioClips: json['audioClips'] == null
          ? const []
          : [
              for (final clip in json['audioClips'] as List<dynamic>)
                ?_audioClipFromJson(clip as Map<String, dynamic>, timeline),
            ],
      isVisible: json['isVisible'] as bool,
      collapsed: json['collapsed'] as bool? ?? false,
      muted: json['muted'] as bool? ?? false,
      audioGain: (json['audioGain'] as num?)?.toDouble() ?? 1.0,
      audioPan: (json['audioPan'] as num?)?.toDouble() ?? 0.0,
      opacity: (json['opacity'] as num).toDouble(),
      blendMode: LayerBlendMode.fromJson(json['blendMode']),
      kind: json.containsKey('kind')
          ? LayerKind.fromJson(json['kind'])
          : LayerKind.animation,
      onTimesheet: json.containsKey('onTimesheet')
          ? json['onTimesheet'] as bool
          : true,
      mark: json.containsKey('mark')
          ? LayerMark.fromJson(json['mark'])
          : LayerMark.none,
      isFillReference: json['fillReference'] as bool? ?? false,
      mediaReference: json['mediaReference'] == null
          ? null
          : MediaReference.fromJson(
              json['mediaReference'] as Map<String, dynamic>,
            ),
      seNameTag: json['seNameTag'] == null
          ? null
          : SeNameTag.fromJson(json['seNameTag'] as Map<String, dynamic>),
      // Legacy 'repeatRegions' JSON is ignored (no production data): its
      // stale ghost entries strip on the first rederive.
      runBehaviors: json['runBehaviors'] == null
          ? const []
          : [
              for (final behavior in json['runBehaviors'] as List<dynamic>)
                TimelineRunBehavior.fromJson(behavior as Map<String, dynamic>),
            ],
      transformTrack: json['transform'] == null
          ? null
          : TransformTrack.fromJson(json['transform'] as Map<String, dynamic>),
      transformEnabled: json['transformEnabled'] as bool? ?? true,
      effects: json['effects'] == null
          ? const []
          : [
              for (final effect in json['effects'] as List<dynamic>)
                LayerEffect.fromJson(effect as Map<String, dynamic>),
            ],
      attachedToLayerId: json['attachedTo'] == null
          ? null
          : LayerId.fromJson(json['attachedTo'] as Map<String, dynamic>),
      attachedPlacement: AttachedPlacement.fromJson(json['attachedPlacement']),
      attachedMode: AttachedMode.fromJson(json['attachedMode']),
      folderId: json['folderId'] == null
          ? null
          : LayerId.fromJson(json['folderId'] as Map<String, dynamic>),
      baseFrameLinks: json['baseFrameLinks'] == null
          ? const {}
          : {
              for (final link in json['baseFrameLinks'] as List<dynamic>)
                FrameId.fromJson(
                  (link as Map<String, dynamic>)['base']
                      as Map<String, dynamic>,
                ): FrameId.fromJson(
                  link['frame'] as Map<String, dynamic>,
                ),
            },
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Layer &&
          other.id == id &&
          other.name == name &&
          listEquals(other.frames, frames) &&
          mapEquals(other.timeline, timeline) &&
          mapEquals(other.instructions, instructions) &&
          listEquals(other.audioClips, audioClips) &&
          other.isVisible == isVisible &&
          other.collapsed == collapsed &&
          other.muted == muted &&
          other.audioGain == audioGain &&
          other.audioPan == audioPan &&
          other.opacity == opacity &&
          other.blendMode == blendMode &&
          other.kind == kind &&
          other.onTimesheet == onTimesheet &&
          other.mark == mark &&
          other.isFillReference == isFillReference &&
          other.mediaReference == mediaReference &&
          other.seNameTag == seNameTag &&
          other.transformTrack == transformTrack &&
          other.transformEnabled == transformEnabled &&
          listEquals(other.effects, effects) &&
          other.attachedToLayerId == attachedToLayerId &&
          other.attachedPlacement == attachedPlacement &&
          other.attachedMode == attachedMode &&
          mapEquals(other.baseFrameLinks, baseFrameLinks) &&
          listEquals(other.runBehaviors, runBehaviors) &&
          other.folderId == folderId;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    Object.hashAll(frames),
    Object.hashAll(
      timeline.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    Object.hashAll(
      instructions.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    Object.hashAll(audioClips),
    // Folded with isVisible: Object.hash caps at 20 positional args.
    Object.hash(isVisible, collapsed),
    muted,
    Object.hash(audioGain, audioPan),
    // Folded with opacity: Object.hash caps at 20 positional args.
    Object.hash(opacity, blendMode),
    kind,
    onTimesheet,
    mark,
    // Folded with isFillReference: Object.hash caps at 20 positional args.
    Object.hash(isFillReference, mediaReference, seNameTag),
    // Folded with transformTrack: Object.hash caps at 20 positional args.
    Object.hash(transformTrack, transformEnabled, Object.hashAll(effects)),
    attachedToLayerId,
    Object.hash(attachedPlacement, attachedMode),
    Object.hashAllUnordered(
      baseFrameLinks.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
    Object.hashAll(runBehaviors),
    folderId,
  );

  @override
  String toString() =>
      'Layer(id: $id, name: $name, frames: $frames, timeline: $timeline, '
      'instructions: $instructions, '
      'isVisible: $isVisible, opacity: $opacity, kind: $kind, '
      'onTimesheet: $onTimesheet, mark: $mark)';
}

/// Whether the brush may land on THIS layer's cels: the KIND must accept
/// it AND the pixels must be the layer's own — a media-REFERENCE layer
/// (§6-z23's second axis) shows a library asset, so strokes have nowhere
/// to live until it is rasterized (which nulls [Layer.mediaReference] and
/// changes nothing else). The layer-level question; kind-only callers
/// keep [layerKindAcceptsBrushInput].
bool layerAcceptsBrushInput(Layer layer) =>
    layerKindAcceptsBrushInput(layer.kind) && layer.mediaReference == null;

/// Stack-shaped queries over a cut's flat layer list. The list is the
/// single truth of render/timeline order, so everything that needs to find
/// a row BY WHAT IT IS asks here instead of open-coding a kind comparison.
extension LayerStackQueries on List<Layer> {
  Layer? byId(LayerId id) {
    for (final layer in this) {
      if (layer.id == id) {
        return layer;
      }
    }
    return null;
  }

  /// The cut's camera row (exactly one per cut; null only mid-migration).
  Layer? get cameraLayer {
    for (final layer in this) {
      if (layer.kind == LayerKind.camera) {
        return layer;
      }
    }
    return null;
  }

  /// The camera row's stack index, or -1.
  int get cameraIndex {
    for (var index = 0; index < length; index += 1) {
      if (this[index].kind == LayerKind.camera) {
        return index;
      }
    }
    return -1;
  }

  /// The rows that take part in the composited picture, bottom → top.
  Iterable<Layer> get compositingLayers =>
      where((layer) => layerKindComposites(layer.kind));
}

SplayTreeMap<int, TimelineExposure> _immutableTimeline(
  Map<int, TimelineExposure> timeline,
) {
  final result = SplayTreeMap<int, TimelineExposure>();
  for (final entry in timeline.entries) {
    if (entry.key < 0) {
      throw ArgumentError.value(
        entry.key,
        'timeline',
        'Timeline indexes must be non-negative.',
      );
    }
    result[entry.key] = entry.value;
  }
  validateTimelineCoverage(result);
  return result;
}

SplayTreeMap<int, TimelineExposure> _deriveTimeline(List<Frame> frames) {
  final timeline = SplayTreeMap<int, TimelineExposure>();
  var index = 0;
  for (final frame in frames) {
    final length = frame.duration <= 0 ? 1 : frame.duration;
    timeline[index] = TimelineExposure.drawing(frame.id, length: length);
    index += length;
  }
  return timeline;
}

/// Raw parse of one legacy or current timeline item.
class _RawTimelineItem {
  const _RawTimelineItem({
    required this.index,
    required this.type,
    this.frameId,
    this.length,
    this.ghost = false,
    this.ghostOwnerId,
    this.breakdownOffsets = const [],
  });

  final int index;

  /// 'drawing' | 'blank' | 'mark'
  final String type;
  final FrameId? frameId;
  final int? length;
  final bool ghost;
  final String? ghostOwnerId;
  final List<int> breakdownOffsets;
}

/// Decodes a timeline from JSON, migrating legacy formats in one pass:
///
/// - legacy `blank` entries become nothing — each one cuts the preceding
///   drawing's hold at its index;
/// - legacy drawing entries without `length` get their old visual length:
///   up to the next entry (drawing or blank), or `Frame.duration` for the
///   last block (the old trailing infinite hold becomes finite);
/// - legacy standalone `mark` entries and the legacy separate `marks` map
///   fold into the covering drawing's [TimelineExposure.breakdownOffsets];
///   marks on a drawing start (offset 0) or on uncovered cells drop
///   (block-owned dots can't live off a block, and no production data
///   exists to preserve).
SplayTreeMap<int, TimelineExposure> _timelineFromJson(
  Object? json, {
  Object? legacyMarksJson,
  required List<Frame> frames,
}) {
  final items = SplayTreeMap<int, _RawTimelineItem>();

  void addItem(int index, Map<String, dynamic> exposureJson) {
    if (index < 0) {
      throw const FormatException('Timeline indexes must be non-negative.');
    }
    if (items.containsKey(index)) {
      throw FormatException('Duplicate timeline index: $index');
    }
    final type = exposureJson['type'];
    if (type != 'drawing' && type != 'blank' && type != 'mark') {
      throw FormatException('Unknown timeline exposure type: $type');
    }
    final frameIdJson = exposureJson['frameId'];
    final lengthJson = exposureJson['length'];
    if (type == 'drawing' && frameIdJson == null) {
      throw const FormatException(
        'Drawing timeline exposure requires frameId.',
      );
    }
    if (type != 'drawing' && frameIdJson != null) {
      throw FormatException('$type timeline exposure cannot have frameId.');
    }
    items[index] = _RawTimelineItem(
      index: index,
      type: type as String,
      frameId: frameIdJson == null
          ? null
          : FrameId.fromJson(frameIdJson as Map<String, dynamic>),
      length: lengthJson is int && lengthJson >= 1 ? lengthJson : null,
      ghost: exposureJson['ghost'] == true,
      ghostOwnerId:
          (exposureJson['ghostOwner'] ?? exposureJson['repeatRegionId'])
              as String?,
      breakdownOffsets: [
        for (final offset
            in exposureJson['breakdown'] as List<dynamic>? ?? const [])
          offset as int,
      ],
    );
  }

  if (json is List<dynamic>) {
    for (final item in json) {
      final entry = item as Map<String, dynamic>;
      addItem(entry['index'] as int, entry['exposure'] as Map<String, dynamic>);
    }
  } else if (json is Map<String, dynamic>) {
    for (final entry in json.entries) {
      final index = int.tryParse(entry.key);
      if (index == null) {
        throw FormatException('Invalid timeline index: ${entry.key}');
      }
      addItem(index, entry.value as Map<String, dynamic>);
    }
  } else {
    throw const FormatException('Layer timeline must be a list or object.');
  }

  final frameDurations = <FrameId, int>{
    for (final frame in frames)
      frame.id: frame.duration <= 0 ? 1 : frame.duration,
  };

  final timeline = SplayTreeMap<int, TimelineExposure>();
  final legacyMarkIndexes = <int>[];
  final rawItems = items.values.toList(growable: false);
  for (var i = 0; i < rawItems.length; i += 1) {
    final item = rawItems[i];
    switch (item.type) {
      case 'mark':
        // Legacy standalone dot: folded into its covering block below.
        legacyMarkIndexes.add(item.index);
      case 'blank':
        // Legacy hold terminator: consumed as the previous block's boundary.
        break;
      case 'drawing':
        var length = item.length;
        if (length == null) {
          // Legacy entry: old visuals held until the next drawing/blank
          // entry; the last block held its Frame.duration.
          int? boundary;
          for (var j = i + 1; j < rawItems.length; j += 1) {
            if (rawItems[j].type != 'mark') {
              boundary = rawItems[j].index;
              break;
            }
          }
          length = boundary != null
              ? boundary - item.index
              : (frameDurations[item.frameId] ?? 1);
        }
        // Never overlap the next drawing regardless of what the file says.
        for (var j = i + 1; j < rawItems.length; j += 1) {
          if (rawItems[j].type == 'drawing') {
            final maxLength = rawItems[j].index - item.index;
            if (length! > maxLength) {
              length = maxLength;
            }
            break;
          }
        }
        if (length! < 1) {
          length = 1;
        }
        var exposure = TimelineExposure.drawing(
          item.frameId!,
          length: length,
          ghost: item.ghost,
          ghostOwnerId: item.ghostOwnerId,
        );
        if (item.breakdownOffsets.isNotEmpty) {
          // copyWith normalizes (sorts, dedupes, clamps to the length).
          exposure = exposure.copyWith(breakdownOffsets: item.breakdownOffsets);
        }
        timeline[item.index] = exposure;
    }
  }

  _foldLegacyMarks(timeline, [
    ...legacyMarkIndexes,
    ..._legacyMarkIndexes(legacyMarksJson),
  ]);
  return timeline;
}

List<int> _legacyMarkIndexes(Object? legacyMarksJson) {
  if (legacyMarksJson == null) {
    return const [];
  }

  final indexes = <int>[];
  if (legacyMarksJson is List<dynamic>) {
    for (final item in legacyMarksJson) {
      indexes.add((item as Map<String, dynamic>)['index'] as int);
    }
  } else if (legacyMarksJson is Map<String, dynamic>) {
    for (final key in legacyMarksJson.keys) {
      final index = int.tryParse(key);
      if (index == null) {
        throw FormatException('Invalid timeline mark index: $key');
      }
      indexes.add(index);
    }
  } else {
    throw const FormatException('Layer marks must be a list or object.');
  }
  for (final index in indexes) {
    if (index < 0) {
      throw const FormatException(
        'Timeline mark indexes must be non-negative.',
      );
    }
  }
  return indexes;
}

/// Folds legacy standalone marks into the covering drawing block's
/// [TimelineExposure.breakdownOffsets]. Marks on a block start (the dot
/// would sit on the drawing itself) or on uncovered cells drop.
void _foldLegacyMarks(
  SplayTreeMap<int, TimelineExposure> timeline,
  Iterable<int> markIndexes,
) {
  for (final index in markIndexes) {
    final start = timeline.lastKeyBefore(index + 1);
    if (start == null) {
      continue;
    }
    final exposure = timeline[start]!;
    final offset = index - start;
    if (offset < 1 || offset >= exposure.length!) {
      continue;
    }
    timeline[start] = exposure.copyWith(
      breakdownOffsets: [...exposure.breakdownOffsets, offset],
    );
  }
}
