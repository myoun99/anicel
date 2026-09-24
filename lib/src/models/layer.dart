import 'dart:collection';
import 'dart:math' as math;

import '../core/collection_equality.dart';
import '../core/copy_with_sentinel.dart';
import 'attached_mode.dart';
import 'attached_placement.dart';
import 'audio_clip.dart';
import 'camera_instruction.dart';
import 'exposure_instruction.dart';
import 'exposure_memo.dart';
import 'frame.dart';
import 'frame_id.dart';
import 'layer_blend_mode.dart';
import 'layer_effect.dart';
import 'layer_id.dart';
import 'layer_kind.dart';
import 'layer_mark.dart';
import 'media_reference.dart';
import 'non_negative_index_map.dart';
import 'se_name_tag.dart';
import 'timeline_coverage.dart';
import 'timeline_exposure.dart';
import 'timeline_run_behavior.dart';
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
    this.folderId,
  }) : frames = List.unmodifiable(
         _spansLaidAsBlocks(kind, id, frames, timeline, instructions).frames,
       ),
       timeline = _immutableTimeline(
         _spansLaidAsBlocks(kind, id, frames, timeline, instructions).timeline,
       ),
       _storedInstructions = immutableInstructionMap(
         kind.spansRideBlocks ? const {} : instructions ?? const {},
       ),
       audioClips = List.unmodifiable(audioClips),
       transformTrack = transformTrack ?? TransformTrack.empty(),
       // ⛔NOT NORMALIZED. 유저 2026-08-27: 「ae는 순서 자유잖아. 자유롭게
       // 해야지. 순서가 결과에 영향주는거고」 — a chain means what it says,
       // top to bottom, and a colour key UNDER a blur keys the blurred
       // result. The composite honours that by taking a raster per key
       // (`resolveCompositeEffectPlan`) instead of reordering the list.
       effects = List.unmodifiable(effects),
       baseFrameLinks = Map.unmodifiable(baseFrameLinks);

  final LayerId id;
  final String name;
  final List<Frame> frames;
  final SplayTreeMap<int, TimelineExposure> timeline;

  /// Camera-work instruction spans (instruction rows only; empty elsewhere).
  /// Keyed by start frame; see [InstructionEvent].
  ///
  /// 🚨On a DIRECTION row this is READ OFF THE BLOCKS
  /// ([LayerKind.spansRideBlocks], R27): every authored block carrying an
  /// instruction is a span of the block's start and length. Nothing stores
  /// it there, so nothing can write it there — the block verbs move, copy,
  /// link and delete spans by moving, copying, linking and deleting blocks.
  late final SplayTreeMap<int, InstructionEvent> instructions =
      kind.spansRideBlocks ? _spansOnBlocks(timeline) : _storedInstructions;

  /// The spans a row WITHOUT a timeline of its own stores (the transition,
  /// and every row that carries none, as an empty map).
  final SplayTreeMap<int, InstructionEvent> _storedInstructions;

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

  /// Reference layer for the FILL tool (R20-C2, the CSP lighthouse): a
  /// fill set to read its references reads ONLY the flagged layers — paint
  /// on a color layer never blocks or leaks a fill traced against the line
  /// art — and the current layer when no layer is flagged (I-36).
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

  /// The cel with [id], or null.
  ///
  /// 🚨ONE lookup. Twelve call sites used to spell this loop themselves
  /// (the audit's clone scan, 2026-09-03).
  /// The spans a copy hands its constructor: [spans] when a caller wrote
  /// some, else what this row stores.
  ///
  /// ⛔A DIRECTION row's spans cannot be written through a map
  /// ([instructions] is read off its blocks), and a write that tried would
  /// have to guess from positions alone which block a span meant — so a
  /// span that moved would read as one deleted and one created, and the
  /// drawing under it would stay behind. Loud instead: write the blocks.
  Map<int, InstructionEvent> _instructionsForCopy(
    Map<int, InstructionEvent>? spans,
  ) {
    if (spans != null &&
        kind.spansRideBlocks &&
        !mapEquals(spans, instructions)) {
      throw StateError(
        "A direction row's spans are its blocks — edit the timeline, "
        'not the span map.',
      );
    }
    return spans ?? _storedInstructions;
  }

  Frame? frameById(FrameId id) {
    for (final frame in frames) {
      if (frame.id == id) {
        return frame;
      }
    }
    return null;
  }

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
    Object? attachedToLayerId = copyWithSentinel,
    AttachedPlacement? attachedPlacement,
    AttachedMode? attachedMode,
    Map<FrameId, FrameId>? baseFrameLinks,
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
      instructions: _instructionsForCopy(instructions),
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
      // Sentinel: DETACHING (P3) clears the linkage — an attach row can
      // become an ordinary drawing row again, so null must be expressible.
      // It used to be a plain `??`, which silently meant "keep".
      attachedToLayerId: identical(attachedToLayerId, copyWithSentinel)
          ? this.attachedToLayerId
          : attachedToLayerId as LayerId?,
      attachedPlacement: attachedPlacement ?? this.attachedPlacement,
      attachedMode: attachedMode ?? this.attachedMode,
      baseFrameLinks: baseFrameLinks ?? this.baseFrameLinks,
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
    // A direction row's spans are written with its blocks.
    if (_storedInstructions.isNotEmpty)
      'instructions': instructionMapToJson(_storedInstructions),
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
      onTimesheet: !json.containsKey('onTimesheet') || json['onTimesheet'] as bool,
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
      // Legacy 'repeatRegions' JSON is ignored (no production data), and so
      // is the 'runBehaviors' spec list F-134 moved into the blocks' own
      // marks: the stale ghost entries of either drop as the timeline
      // decodes.
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
/// keep [LayerKind.acceptsBrushInput].
bool layerAcceptsBrushInput(Layer layer) =>
    layer.kind.acceptsBrushInput && layer.mediaReference == null;

/// Whether [layer] is an attach layer of EITHER mode (rides a base
/// layer's transform/FX and group structure).
///
/// ⚠️It lives HERE, next to the field, rather than with the attach
/// resolvers: it is a fact about one Layer, and the sheet gate below —
/// which `models` cannot reach the resolvers from — has to ask it.
/// `attached_layer_resolve.dart` re-exports it, so its callers are
/// unchanged.
bool isAttachedLayer(Layer layer) => layer.attachedToLayerId != null;

/// Every layer kind that PRINTS carries the timesheet-output toggle — one
/// entrance for every row (unified layer controls, user rule): cel/image/SE
/// gate their sheet columns and the CAMERA layer gates the printed CAM
/// column. A folder prints nothing of its own, so its slot stays reserved
/// but empty.
bool layerKindEligibleForTimesheetToggle(LayerKind kind) => !kind.groupsLayers;

/// 🚨THE ONE LAW OF THE SHEET SWITCH: whether [layer]'s row carries a live
/// sheet toggle — its kind prints AND it is not an attach row (W5), which
/// is a display accessory of its base, never a sheet column of its own.
/// 유저 2026-09-09: 「부속 레이어엔 타임시트 on/off 버튼이 없도록 만들었어.
/// 자기 열 안 가지도록 해왔을텐데」.
///
/// ⚠️It lives in `models`, not with the rail's widgets, because the SHEET
/// reads it too ([layerTakesSheetCelColumn] below) and `models` cannot
/// import `ui`. Round 8 (2026-09-06) unified the rail's own surfaces here
/// and its note claimed the storyboard was among them; the storyboard rail
/// and the legend's bulk verb were still spelling the pair themselves when
/// the sheet round found them (2026-09-10).
bool layerCarriesTimesheetToggle(Layer layer) =>
    layerKindEligibleForTimesheetToggle(layer.kind) && !isAttachedLayer(layer);

/// D24: whether this layer prints an ACTION cel column — the ONE gate the
/// printed timesheet, the cut envelope's cel counts and the XDTS export
/// all read (three inline copies of `animation && onTimesheet` used to
/// drift apart). The real sheets keep BG/BOOK picture rows out of the
/// cel columns, so the image kind never qualifies regardless of its
/// sheet flag — the flag itself STAYS meaningful on image rows (D24
/// 후반's 끼움 표시 will consume it).
///
/// 🚨IT IS THE SWITCH'S LAW PLUS TWO WORDS: a row can only print what it
/// can switch, so this asks [layerCarriesTimesheetToggle] FIRST rather
/// than re-deciding who is eligible. That is what an attach row's column
/// was: nothing clears `onTimesheet` when a row is attached, so a gate
/// that never asked gave every attach row a column — a synced one printed
/// an EMPTY column (its timing lives on its base), a free one printed its
/// own cel numbers, and the envelope counted both, while the rail showed
/// no switch to turn any of it off.
bool layerTakesSheetCelColumn(Layer layer) =>
    layerCarriesTimesheetToggle(layer) &&
    layer.kind == LayerKind.animation &&
    layer.onTimesheet;

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
      where((layer) => layer.kind.composites);
}

SplayTreeMap<int, TimelineExposure> _immutableTimeline(
  Map<int, TimelineExposure> timeline,
) {
  final result = nonNegativeIndexedCopy(
    timeline,
    argumentName: 'timeline',
    indexNoun: 'Timeline',
  );
  validateTimelineCoverage(result);
  return result;
}

/// A DIRECTION row's [spans] laid down as the blocks they are (R27,
/// [LayerKind.spansRideBlocks]) — how a span handed to the constructor (a
/// file from before R27, a fixture) becomes one. Every other row, and a
/// direction row handed none, comes back as given.
///
/// Each span lands the gentlest way that loses nothing:
///  · on an entry that STARTS where it does → that block carries it (a copy
///    of the row hands its own spans back, and they land where they were);
///  · on free cells → a blank cel of its own ([_spanCelId]) exposed for the
///    span's length, clamped at the next entry;
///  · inside an entry that starts earlier → nowhere. ⛔Not a divide: a
///    constructor that cut a drawing in two would be the one thing here
///    that changed a picture.
({List<Frame> frames, SplayTreeMap<int, TimelineExposure> timeline})
_spansLaidAsBlocks(
  LayerKind kind,
  LayerId id,
  List<Frame> frames,
  Map<int, TimelineExposure>? timeline,
  Map<int, InstructionEvent>? spans,
) {
  final laid = SplayTreeMap<int, TimelineExposure>.of(
    timeline ?? _deriveTimeline(frames),
  );
  if (!kind.spansRideBlocks || spans == null || spans.isEmpty) {
    return (frames: frames, timeline: laid);
  }
  final cels = [...frames];
  final taken = {for (final frame in frames) frame.id};
  for (final MapEntry(key: start, value: span) in spans.entries) {
    final head = laid[start];
    if (head != null) {
      if (!head.ghost) {
        laid[start] = head.copyWith(instruction: () => span.writing);
      }
      continue;
    }
    if (coveringDrawingBlockAt(laid, start) != null) {
      continue;
    }
    final next = nextDrawingBlockAfter(laid, start)?.startIndex;
    final cel = _spanCelId(id, start, taken);
    taken.add(cel);
    cels.add(Frame(id: cel, duration: 1, strokes: const []));
    laid[start] = TimelineExposure.drawing(
      cel,
      length: next == null ? span.length : math.min(span.length, next - start),
      instruction: span.writing,
    );
  }
  return (frames: cels, timeline: laid);
}

/// The cel a span laid down by [_spansLaidAsBlocks] exposes: named for its
/// row and its start, so the same input lays down the same row every time,
/// and stepped past any id the row already uses.
FrameId _spanCelId(LayerId layer, int start, Set<FrameId> taken) {
  final base = '${layer.value}-span-$start';
  var id = FrameId(base);
  for (var n = 2; taken.contains(id); n += 1) {
    id = FrameId('$base-$n');
  }
  return id;
}

/// The spans a direction row's blocks carry — see [Layer.instructions].
SplayTreeMap<int, InstructionEvent> _spansOnBlocks(
  SplayTreeMap<int, TimelineExposure> timeline,
) => SplayTreeMap.of({
  for (final MapEntry(key: start, value: entry) in timeline.entries)
    if (entry.instruction case final writing? when !entry.ghost)
      start: InstructionEvent.of(writing, length: entry.length!),
});

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
    this.ghostOf,
    this.legacyGhost = false,
    this.startEdge = TimelineRunEdgeMark.none,
    this.endEdge = TimelineRunEdgeMark.none,
    this.breakdownOffsets = const [],
    this.memo,
    this.instruction,
  });

  final int index;

  /// 'drawing' | 'blank' | 'mark'
  final String type;
  final FrameId? frameId;
  final int? length;
  final TimelineRunEdgeGhost? ghostOf;

  /// A ghost written before F-134, whose owner was a frame id.
  final bool legacyGhost;
  final TimelineRunEdgeMark startEdge;
  final TimelineRunEdgeMark endEdge;
  final List<int> breakdownOffsets;

  /// The block's memo. [TimelineExposure.toJson] writes it, so a decoder
  /// that skipped the key silently threw away every memo the user typed
  /// the moment the project was reopened.
  final ExposureMemo? memo;

  /// The block's instruction — a direction row's span (R27). Carried here
  /// for [memo]'s reason: a decoder that skipped it would drop every span
  /// on reopening.
  final ExposureInstruction? instruction;
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
/// The timeline entries as the FILE spells them, validated and keyed by
/// index — both spellings (a list of `{index, exposure}` pairs, and an
/// object keyed by index) read into one map here so the walk below sees
/// one shape.
SplayTreeMap<int, _RawTimelineItem> _rawTimelineItems(Object? json) {
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
      ghostOf: TimelineRunEdgeGhost.fromJsonOrNull(exposureJson['ghostOf']),
      legacyGhost:
          exposureJson['ghost'] == true && exposureJson['ghostOf'] == null,
      startEdge: TimelineRunEdgeMark.fromJsonOrNone(exposureJson['startEdge']),
      endEdge: TimelineRunEdgeMark.fromJsonOrNone(exposureJson['endEdge']),
      breakdownOffsets: [
        for (final offset
            in exposureJson['breakdown'] as List<dynamic>? ?? const [])
          offset as int,
      ],
      memo: exposureJson['memo'] == null
          ? null
          : ExposureMemo.fromJson(
              exposureJson['memo'] as Map<String, dynamic>,
            ),
      instruction: exposureJson['instruction'] == null
          ? null
          : ExposureInstruction.fromJson(
              exposureJson['instruction'] as Map<String, dynamic>,
            ),
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
  return items;
}

/// The frames a drawing entry covers, resolved against what follows it.
///
/// Two legacy shapes and one invariant. A file written before lengths
/// existed held each visual until the next drawing or blank entry, and
/// the LAST block held its Frame.duration — that is the first branch.
/// The second is the invariant that outranks the file: a block never
/// overlaps the next drawing, whatever the length says, because a file
/// that says otherwise draws two cels on one frame.
int _drawingLength(
  List<_RawTimelineItem> rawItems,
  int at,
  Map<FrameId, int> frameDurations,
) {
  final item = rawItems[at];
  final i = at;
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
  return length;
}

/// The entry one raw DRAWING item decodes to, [length] already resolved —
/// or null for a ghost saved before F-134.
TimelineExposure? _exposureFromRawItem(
  _RawTimelineItem item, {
  required int length,
}) {
  if (item.legacyGhost) {
    // F-134: a ghost from before the edge properties moved into the
    // blocks names an owner that no longer exists, and nothing is left
    // to say what it was — kept, it would read back as an AUTHORED
    // block. Derived state drops; the next rederive rebuilds whatever
    // the blocks' own marks still say.
    return null;
  }
  final authored = item.ghostOf == null;
  var exposure = TimelineExposure.drawing(
    item.frameId!,
    length: length,
    ghostOf: item.ghostOf,
    // A ghost never carries marks: it is a property's output.
    startEdge: authored ? item.startEdge : TimelineRunEdgeMark.none,
    endEdge: authored ? item.endEdge : TimelineRunEdgeMark.none,
  );
  if (item.breakdownOffsets.isNotEmpty) {
    // copyWith normalizes (sorts, dedupes, clamps to the length).
    exposure = exposure.copyWith(breakdownOffsets: item.breakdownOffsets);
  }
  // Ghosts never carry a memo ([TimelineExposure]'s contract): they
  // are rederived on every edit, so a memo there would not survive
  // the next write anyway.
  if (item.memo != null && authored) {
    exposure = exposure.copyWith(memo: () => item.memo);
  }
  // Nor an instruction, for the same reason.
  if (item.instruction != null && authored) {
    exposure = exposure.copyWith(instruction: () => item.instruction);
  }
  return exposure;
}

SplayTreeMap<int, TimelineExposure> _timelineFromJson(
  Object? json, {
  Object? legacyMarksJson,
  required List<Frame> frames,
}) {
  final items = _rawTimelineItems(json);

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
        final exposure = _exposureFromRawItem(
          item,
          length: _drawingLength(rawItems, i, frameDurations),
        );
        if (exposure != null) {
          timeline[item.index] = exposure;
        }
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
