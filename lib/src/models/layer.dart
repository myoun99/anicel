import 'dart:collection';
import 'dart:math' as math;

import '../core/collection_equality.dart';
import '../core/copy_with_sentinel.dart';
import 'attached_mode.dart';
import 'attached_placement.dart';
import 'audio_clip.dart';
import 'camera_instruction.dart';
import 'conte_key.dart';
import 'exposure_instruction.dart';
import 'exposure_memo.dart';
import 'frame.dart';
import 'frame_id.dart';
import 'layer_blend_mode.dart';
import 'layer_effect.dart';
import 'layer_id.dart';
import 'layer_kind.dart';
import 'layer_mark.dart';
import 'layer_process.dart';
import 'media_reference.dart';
import 'non_negative_index_map.dart';
import 'se_name_tag.dart';
import 'se_sound.dart';
import 'storyboard_coverage.dart' show storyboardConteStart;
import 'timeline_coverage.dart';
import 'timeline_exposure.dart';
import 'timeline_run_behavior.dart';
import 'transform_track.dart';

/// A cel layer. Its single [timeline] map records everything authored on
/// the frame axis: drawing block starts (frame + explicit hold length),
/// each carrying its own inbetween dots
/// ([TimelineExposure.breakdownMarks]). Emptiness has no entry —
/// uncovered cells are the timesheet "X" cells. There is no separate marks
/// map, no blank entry type, and no standalone mark entry.
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
    this.lanesExpanded = false,
    Set<String> expandedLaneGroups = const {},
    this.muted = false,
    this.seSound = const SeSound(),
    this.opacity = 1.0,
    this.blendMode = LayerBlendMode.normal,
    this.kind = LayerKind.animation,
    this.onTimesheet = true,
    this.mark = LayerMark.none,
    this.clipsToBelow = false,
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
    this.conteKey,
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
       expandedLaneGroups = Set.unmodifiable(expandedLaneGroups),
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

  /// The row's GROUP fold: a collapsed FOLDER swallows its member rows, a
  /// collapsed BASE its attach group. One control — a row that holds other
  /// rows, folding them (유저 2026-08-29: 「접기도 마찬가지야. 폴더든
  /// 어태치든」) — and a row is a folder or a base, never both
  /// (`canCarryAttachedLayers`). Persisted, like CSP.
  ///
  /// ↩️The attach-group fold was session view state (`RailView`, UI-R20 #9,
  /// 07-18) and every reload opened it back up, until F-360 (유저
  /// 2026-10-14: 「어태치레이어 분명 접은채로 저장했는데 다시열면
  /// 펼쳐져있음 … 제대로 기록되도록」).
  final bool collapsed;

  /// Whether the row's AE-style property-lane twirl-down is open — its
  /// Transform and fx lanes live under it. The row's own, as its fold is
  /// (F-360): one command writes it on every row of its head, it undoes,
  /// and the file keeps it. ↩️It was `RailView.expandedLaneLayerIds`,
  /// session-only.
  final bool lanesExpanded;

  /// The LANE GROUPS twirled open inside the row's twirl-down, by lane id —
  /// Transform, plus one header per effect (AE group collapse, default
  /// shut). The row's own, as [lanesExpanded] is (F-360). ↩️It was
  /// `RailView.expandedLaneGroupKeys`, session-only and outside history.
  final Set<String> expandedLaneGroups;

  /// Whether this layer's sounds are silenced (SE rows' speaker button —
  /// the audio counterpart of [isVisible]): playback and export skip the
  /// clips of muted layers, the waveforms keep displaying.
  final bool muted;

  /// The SE row's sound — its volume over time and its pan, the 「오디오」
  /// group of its twirl-down (I-140). Multiplies every clip on the row,
  /// applied exactly by the mixer (headroom, no platform clamp); the pan
  /// reaches the device mixer path alone — the platform-player fallback
  /// cannot pan.
  final SeSound seSound;

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

  /// Which row of its TRACK'S CONTE this is (F-343, `TrackConte`) — set on
  /// a row or 공정 folder riding a cut's conte, null on every other row and
  /// on the conte itself. The structure is the track's and this row is one
  /// cut's copy of one row of it: what it wears and where it sits are laid
  /// from the track on every write, and only what it holds is its own.
  ///
  /// ⛔Not an id: each cut's copy of the row has a layer id of its own, and
  /// they all carry this one.
  final ConteKey? conteKey;

  /// CLIP TO LAYER BELOW (I-92, Photoshop's clipping mask): shown only where
  /// its base has pixels, at the base's strength and blend — the law is
  /// `clipTargetOf`'s. ↩️It was the FILL's reference flag (R20-C2; I-36)
  /// until I-92: 「그런버튼 삭제하고 … 포토샵이나 클튜에서 사용하는
  /// 마스크기능이 되면 됨」.
  final bool clipsToBelow;

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
    bool? lanesExpanded,
    Set<String>? expandedLaneGroups,
    bool? muted,
    SeSound? seSound,
    double? opacity,
    LayerBlendMode? blendMode,
    LayerKind? kind,
    bool? onTimesheet,
    LayerMark? mark,
    bool? clipsToBelow,
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
    Object? conteKey = copyWithSentinel,
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
      lanesExpanded: lanesExpanded ?? this.lanesExpanded,
      expandedLaneGroups: expandedLaneGroups ?? this.expandedLaneGroups,
      muted: muted ?? this.muted,
      seSound: seSound ?? this.seSound,
      opacity: opacity ?? this.opacity,
      blendMode: blendMode ?? this.blendMode,
      kind: kind ?? this.kind,
      onTimesheet: onTimesheet ?? this.onTimesheet,
      mark: mark ?? this.mark,
      clipsToBelow: clipsToBelow ?? this.clipsToBelow,
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
      // Sentinel: a row the track's conte lets go of says so with null.
      conteKey: identical(conteKey, copyWithSentinel)
          ? this.conteKey
          : conteKey as ConteKey?,
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
    if (lanesExpanded) 'lanesExpanded': true,
    if (expandedLaneGroups.isNotEmpty)
      'expandedLaneGroups': [...expandedLaneGroups]..sort(),
    if (muted) 'muted': true,
    if (seSound != const SeSound()) 'seSound': seSound.toJson(),
    'opacity': opacity,
    // Default normal omitted — pre-blend files read back unchanged.
    if (blendMode != LayerBlendMode.normal) 'blendMode': blendMode.toJson(),
    'kind': kind.toJson(),
    'onTimesheet': onTimesheet,
    'mark': mark.toJson(),
    if (clipsToBelow) 'clipToBelow': true,
    if (mediaReference != null) 'mediaReference': mediaReference!.toJson(),
    if (seNameTag != null) 'seNameTag': seNameTag!.toJson(),
    if (folderId != null) 'folderId': folderId!.toJson(),
    if (conteKey case final key?) 'conteKey': key.value,
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

  factory Layer.fromJson(Map<String, dynamic> json) {
    return Layer(
      id: LayerId.fromJson(json['id'] as Map<String, dynamic>),
      name: json['name'] as String,
      frames: [
        for (final frame in json['frames'] as List<dynamic>)
          Frame.fromJson(frame as Map<String, dynamic>),
      ],
      timeline: _timelineFromJson(json['timeline']),
      instructions: instructionMapFromJson(json['instructions']),
      audioClips: json['audioClips'] == null
          ? const []
          : [
              for (final clip in json['audioClips'] as List<dynamic>)
                AudioClip.fromJson(clip as Map<String, dynamic>),
            ],
      isVisible: json['isVisible'] as bool,
      collapsed: json['collapsed'] as bool? ?? false,
      lanesExpanded: json['lanesExpanded'] as bool? ?? false,
      expandedLaneGroups: {
        for (final laneId
            in json['expandedLaneGroups'] as List<dynamic>? ?? const [])
          laneId as String,
      },
      muted: json['muted'] as bool? ?? false,
      seSound: json['seSound'] is Map<String, dynamic>
          ? SeSound.fromJson(json['seSound'] as Map<String, dynamic>)
          : const SeSound(),
      opacity: (json['opacity'] as num).toDouble(),
      blendMode: LayerBlendMode.fromJson(json['blendMode']),
      kind: json.containsKey('kind')
          ? LayerKind.fromJson(json['kind'])
          : LayerKind.animation,
      onTimesheet: !json.containsKey('onTimesheet') || json['onTimesheet'] as bool,
      mark: json.containsKey('mark')
          ? LayerMark.fromJson(json['mark'])
          : LayerMark.none,
      clipsToBelow: json['clipToBelow'] as bool? ?? false,
      mediaReference: json['mediaReference'] == null
          ? null
          : MediaReference.fromJson(
              json['mediaReference'] as Map<String, dynamic>,
            ),
      seNameTag: json['seNameTag'] == null
          ? null
          : SeNameTag.fromJson(json['seNameTag'] as Map<String, dynamic>),
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
      conteKey: json['conteKey'] == null
          ? null
          : ConteKey(json['conteKey'] as String),
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
          sameBesideTimeline(other) &&
          mapEquals(other.timeline, timeline) &&
          foldsLike(other);

  /// Whether [other] is this layer in every field but its [timeline] and
  /// its folds ([foldsLike]) — the ONE list of those fields, and [==]'s
  /// own.
  ///
  /// 🚨F-244: the timeline's tiles keep what an edit left alone across the
  /// new instance the edit made (`firstCellThatMayDiffer`), and this is
  /// where they learn that nothing but the timeline moved. A field missing
  /// here would keep a tile across a change of it — which is why [==] reads
  /// this list rather than a copy of it.
  bool sameBesideTimeline(Layer other) =>
      identical(this, other) ||
      other.id == id &&
          other.name == name &&
          listEquals(other.frames, frames) &&
          // A direction row's spans are READ OFF its blocks ([instructions]),
          // so what stands beside its timeline is the stored map.
          mapEquals(other._storedInstructions, _storedInstructions) &&
          listEquals(other.audioClips, audioClips) &&
          other.isVisible == isVisible &&
          other.muted == muted &&
          other.seSound == seSound &&
          other.opacity == opacity &&
          other.blendMode == blendMode &&
          other.kind == kind &&
          other.onTimesheet == onTimesheet &&
          other.mark == mark &&
          other.clipsToBelow == clipsToBelow &&
          other.mediaReference == mediaReference &&
          other.seNameTag == seNameTag &&
          other.transformTrack == transformTrack &&
          other.transformEnabled == transformEnabled &&
          listEquals(other.effects, effects) &&
          other.attachedToLayerId == attachedToLayerId &&
          other.attachedPlacement == attachedPlacement &&
          other.attachedMode == attachedMode &&
          mapEquals(other.baseFrameLinks, baseFrameLinks) &&
          other.folderId == folderId &&
          other.conteKey == conteKey;

  /// Whether [other] folds and twirls as this layer does — [collapsed],
  /// [lanesExpanded] and [expandedLaneGroups]: how the rail is laid out
  /// around the row (F-360).
  ///
  /// ⚠️Not in [sameBesideTimeline]: none of the row's cells reads them —
  /// the rows they show or hide are rows of their own — and in that list a
  /// twirl would bake every tile of the row again (F-244 measured 25–57ms
  /// for a step that did that on a heavy cut).
  bool foldsLike(Layer other) =>
      other.collapsed == collapsed &&
      other.lanesExpanded == lanesExpanded &&
      setEquals(other.expandedLaneGroups, expandedLaneGroups);

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
    Object.hash(
      isVisible,
      collapsed,
      lanesExpanded,
      Object.hashAllUnordered(expandedLaneGroups),
    ),
    muted,
    seSound,
    // Folded with opacity: Object.hash caps at 20 positional args.
    Object.hash(opacity, blendMode),
    kind,
    onTimesheet,
    mark,
    // Folded with clipsToBelow: Object.hash caps at 20 positional args.
    Object.hash(clipsToBelow, mediaReference, seNameTag),
    // Folded with transformTrack: Object.hash caps at 20 positional args.
    Object.hash(transformTrack, transformEnabled, Object.hashAll(effects)),
    attachedToLayerId,
    Object.hash(attachedPlacement, attachedMode),
    Object.hashAllUnordered(
      baseFrameLinks.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
    // Folded with folderId: Object.hash caps at 20 positional args.
    Object.hash(folderId, conteKey),
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

/// Whether [layer] is a COVERING row: one that tiles its cut edge to edge,
/// with no empty cell in its world ([LayerKind.coversWithoutGaps] — a cut's
/// conte, an image row).
///
/// 🚨A LAYER's question, not its kind's — for the kind a cut holds ONE of
/// ([LayerKind.isSingletonPerCut], the conte). An attach row takes its
/// BASE's kind (`FoldersAndAttachments.addAttachedLayer`), and a row riding
/// the cut's conte is not that conte ([holdsSingletonOfKind]): a synced one
/// mirrors its base and stores no lane, a free one is timed like any
/// drawing row (UI-R21 #3). 🧪Asked of the kind, a free attach row riding a
/// conte was tiled to the cut by the write, refused the frame added at a
/// block's head — and a comma set on one of its blocks resized the CUT to
/// the row's end (12 frames to 10, measured 2026-10-08 beside the same row
/// riding a cel layer, which did neither).
///
/// An image row's kind still answers for every row of it, an attach row
/// among them: a cut holds as many as it likes, and each is its one
/// picture held over the cut (`covering_image_normalize.dart`).
bool layerCoversWithoutGaps(Layer layer) =>
    layer.kind.coversWithoutGaps &&
    !(layer.kind.isSingletonPerCut && isAttachedLayer(layer));

/// The first frame a block of [layer] may stand on — what a block moved,
/// a cel made and a cel pasted all ask.
///
/// 0 on every row but one that TILES its cut ([layerCoversWithoutGaps]),
/// whose blocks start where its conte does: a cut an O.L arrives into keeps
/// its panels after the のりしろ it owes ([storyboardConteStart], F-227) —
/// the frames in front are its first panel held back, not room for a panel.
///
/// 🗣️F-339 (유저 2026-10-11): 「OL있어서 콘티레이어의 앞부분에 서있을때
/// 프레임 추가버튼 활성화되고 눌러도 아무반응없는데 추가나 붙여넣기나
/// 관련로직 해당부분에서 못하게 하는게 맞는거같은데」. ↩️Only the move asked
/// it: the ＋ and the paste took the held-back frames for room, and the
/// conte's write folded what they made back onto its first panel.
int layerBlockFloor(Layer layer) =>
    layerCoversWithoutGaps(layer) ? storyboardConteStart(layer.timeline) : 0;

/// Whether [layers] already hold the ONE row a singleton kind allows a cut
/// ([LayerKind.isSingletonPerCut]).
///
/// 🚨A row riding another is NOT that row. An attach row takes its base's
/// kind, so the conte row's attach rows are storyboard rows — and asked of
/// the kind alone, each of them answered for the cut's one conte. The one
/// row is the one that stands by itself (I-73, 2026-10-08).
bool holdsSingletonOfKind(Iterable<Layer> layers, LayerKind kind) =>
    layers.any((layer) => layer.kind == kind && !isAttachedLayer(layer));

/// Whether a clipboard can hold [layer] as a row of its own — what a copy
/// and a duplicate both ask first.
///
/// A track-owned SE row has no cut-layer shape to copy
/// ([LayerKind.isClipboardCopyable]), and an attach row's cel links point
/// into its base's cels, so a copy of it would double-link them.
///
/// ★Named when the THIRD speller arrived (I-77's pill copy): the layer
/// board's copy, the duplicate and the linked duplicate each wrote it out.
bool layerTakesACopy(Layer layer) =>
    layer.kind.isClipboardCopyable && !isAttachedLayer(layer);

/// Whether a copy of [layer] may land in the cut [layer] stands in — a
/// duplicate, a linked copy. R9 #7: a per-cut singleton cannot have a
/// second.
bool layerTakesACopyBesideIt(Layer layer) =>
    layerTakesACopy(layer) && !layer.kind.isSingletonPerCut;

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

/// D24: whether this layer prints a cel column — the ONE gate the
/// printed timesheet, the cut envelope's cel counts and the XDTS export
/// all read (three inline copies of `animation && onTimesheet` used to
/// drift apart). The real sheets keep BG/BOOK picture rows out of the
/// cel columns, so the image kind never qualifies regardless of its
/// sheet flag — the flag itself STAYS meaningful on image rows: D24
/// 후반's 끼움 표시 reads it ([layerMarksSheetBook]).
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

/// F-406: whether this layer's cel column is the timesheet's CELL block's
/// rather than its ACTION block's — a row whose colour label is 動画 or
/// 仕上げ, whatever its revise (유저 2026-10-19: 「색라벨 공정이 동화면
/// 타임시트용지패널의 CELL란에 표시하도록. 액션란에는 표시안함. 동화의 어떤
/// 수정공정이던 CELL란표시」 · 10-21, F-431: 「시아게 공정쪽 레이어도
/// 동일하게 CELL란에 등록」).
bool layerTakesTheCelBlock(Layer layer) =>
    celStageOf(layer) != LayerProcess.key;

/// The stage a cel row's drawings are counted under on paper, by its
/// colour label whatever its revise: 動画 ([LayerProcess.inbetween]) and
/// 仕上げ ([LayerProcess.finish]) — the CELL block's rows — and 原画
/// ([LayerProcess.key]) for every other: the ACTION block's.
///
/// 🗣️F-498 (유저 2026-10-29): 「원화 세는건 타임시트용지패널이랑 맞추고
/// (액션란이 원화), 동화도 그거 맞추고(셀란. 이 경우는 색라벨이 동화쪽일때만.
/// 어떤 수정이던.). 시아게도 색라벨 맞춰서. 이런 법 하나로 통일. 뭐가 원화,
/// 뭐가 동화로 인식되는지 라는 법」 — the sheet's two blocks
/// ([layerTakesTheCelBlock]) and the cut envelope's counts
/// (`cutEnvelopeCelCounts`) read this one answer. ↩️The envelope counted
/// every cel row's drawings as 原画 and estimated its 動画 off them.
LayerProcess celStageOf(Layer layer) => switch (layer.mark.process) {
  LayerProcess.inbetween => LayerProcess.inbetween,
  LayerProcess.finish => LayerProcess.finish,
  _ => LayerProcess.key,
};

/// D24 후반: whether this layer marks a BOOK on the sheet — an image row
/// whose colour label is 美術, whatever its revise and whatever its name
/// (유저 2026-09-26: 「이름 bg든 북이든 구별없이 이미지레이어면서 미술이면
/// 수정공정뭐던간에 북표시하는거 잊지말고」 — ⛔never by the name BG/BOOK).
///
/// The cel column's law with the image row's words: the row's sheet
/// switch is the flag the note above kept for this.
bool layerMarksSheetBook(Layer layer) =>
    layerCarriesTimesheetToggle(layer) &&
    layer.kind == LayerKind.image &&
    layer.onTimesheet &&
    layer.mark.process == LayerProcess.art;

/// Whether this layer's lines print on paper — an SE row with its sheet
/// switch on: the timesheet's SE column, the XDTS export and the conte
/// sheet's dialogue all read it.
///
/// 🗣️F-345 (유저 2026-10-12): 「se트랙 타임시트off시, 콘티용지패널에도 대사
/// 안적도록」. ↩️The conte sheet read every SE row, switch or not.
bool layerPrintsSheetLines(Layer layer) =>
    layerCarriesTimesheetToggle(layer) &&
    layer.kind == LayerKind.se &&
    layer.onTimesheet;

/// The block [layer]'s lane holds that somebody AUTHORED — its first drawing
/// that is not a ghost — or null when the row stands empty.
///
/// An IMAGE row holds at most one ([LayerKind.holdsSingleCel]), so this is
/// 「the picture this row shows」. ⛔Not the first cel of its BANK: the bank
/// is its link group's, and holds another cut's picture while this row
/// shows a different one or none (F-98 — an image row has an empty state,
/// and links by name alone).
TimelineExposure? authoredBlockOf(Layer layer) {
  for (final exposure in layer.timeline.values) {
    if (exposure.isDrawing && !exposure.ghost) {
      return exposure;
    }
  }
  return null;
}

/// Whether [layer]'s lane holds an authored block ([authoredBlockOf]).
bool rowHoldsABlock(Layer layer) => authoredBlockOf(layer) != null;

/// Whether [layer] is a PICTURE row with no picture — an image row whose
/// lane holds no block (F-98, 유저 2026-09-12: 「이미지 레이어도 프레임이
/// 없는 상태는 존재함. 생성하면 기본적으로 프레임 생성되는건 그대로지만
/// 삭제가능하도록」). The one state in which a row that holds a single cel
/// has a cel to make: every door that makes one asks this.
bool pictureRowStandsEmpty(Layer layer) =>
    layer.kind.holdsSingleCel && !rowHoldsABlock(layer);

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

  /// Whether the cut's camera work is bypassed — the camera row's own
  /// transform switch (R8: persisted like every other row's). A bypassed
  /// camera shows the canvas centred, whatever its keys say.
  bool get cameraWorkBypassed => cameraLayer?.transformEnabled == false;

  /// Whether the cut's camera work prints on paper — the camera row's sheet
  /// switch: the timesheet's CAM column and the conte's ACTION lines read
  /// this one answer.
  ///
  /// 🗣️I-93 (유저 2026-10-30): 「se가 해당 행 시트off하면 콘티용지나 타임시트등
  /// 기록되는곳에서 사라지듯이 액션쪽도 카메라레이어 움직임인거니까 그거
  /// 시트off되면 사라지게」 — the SE row's law ([layerPrintsSheetLines]) for
  /// the camera's. ↩️The conte read every camera, switch or not.
  bool get cameraOnSheet => cameraLayer?.onTimesheet ?? true;

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

/// The spans a direction row's blocks carry — see [Layer.instructions]. Every
/// authored block is one: a block that says nothing is a span of nothing
/// (I-72-block-without-instruction — the block is the span, R27), as an SE
/// entry with nothing written is still an entry. ↩️Only a block carrying
/// writing was a span; a bare one was filled with the vocabulary's first
/// entry on every write.
SplayTreeMap<int, InstructionEvent> _spansOnBlocks(
  SplayTreeMap<int, TimelineExposure> timeline,
) => SplayTreeMap.of({
  for (final MapEntry(key: start, value: entry) in timeline.entries)
    if (!entry.ghost)
      start: InstructionEvent.of(entry.instruction, length: entry.length!),
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

/// Raw parse of one timeline item.
class _RawTimelineItem {
  const _RawTimelineItem({
    required this.index,
    required this.frameId,
    required this.length,
    this.ghostOf,
    this.startEdge = TimelineRunEdgeMark.none,
    this.endEdge = TimelineRunEdgeMark.none,
    this.breakdownMarks = const {},
    this.memo,
    this.instruction,
  });

  final int index;
  final FrameId frameId;
  final int length;
  final TimelineRunEdgeGhost? ghostOf;
  final TimelineRunEdgeMark startEdge;
  final TimelineRunEdgeMark endEdge;
  final Map<int, InbetweenMark> breakdownMarks;

  /// The block's memo. [TimelineExposure.toJson] writes it, so a decoder
  /// that skipped the key silently threw away every memo the user typed
  /// the moment the project was reopened.
  final ExposureMemo? memo;

  /// The block's instruction — a direction row's span (R27). Carried here
  /// for [memo]'s reason: a decoder that skipped it would drop every span
  /// on reopening.
  final ExposureInstruction? instruction;
}

/// The timeline entries as the FILE spells them, validated and keyed by
/// index — both spellings (a list of `{index, exposure}` pairs, and an
/// object keyed by index) read into one map here so the walk below sees
/// one shape.
///
/// 🗣️유저 2026-10-06 (the save law): 「옛파일 읽는코드는 필요없다고
/// 확신했어」. ↩️This read four older shapes too — `blank` entries that cut
/// a hold, drawings with no length, standalone `mark` entries with the
/// separate `marks` map, and ghosts written before F-134 — none of which a
/// file of a format this build opens holds (`anicelOldestReadFormatVersion`).
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
    if (type != 'drawing') {
      throw FormatException('Unknown timeline exposure type: $type');
    }
    final frameIdJson = exposureJson['frameId'];
    if (frameIdJson == null) {
      throw const FormatException(
        'Drawing timeline exposure requires frameId.',
      );
    }
    final length = exposureJson['length'];
    if (length is! int || length < 1) {
      throw const FormatException(
        'Drawing timeline exposure requires a positive length.',
      );
    }
    items[index] = _RawTimelineItem(
      index: index,
      frameId: FrameId.fromJson(frameIdJson as Map<String, dynamic>),
      length: length,
      ghostOf: TimelineRunEdgeGhost.fromJsonOrNull(exposureJson['ghostOf']),
      startEdge: TimelineRunEdgeMark.fromJsonOrNone(exposureJson['startEdge']),
      endEdge: TimelineRunEdgeMark.fromJsonOrNone(exposureJson['endEdge']),
      breakdownMarks: TimelineExposure.breakdownMarksFromJson(exposureJson),
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

/// The frames a drawing entry covers: its length, never past the start of
/// the next one — the invariant that outranks the file, because a file
/// that says otherwise draws two cels on one frame.
int _drawingLength(List<_RawTimelineItem> rawItems, int at) {
  final item = rawItems[at];
  return at + 1 < rawItems.length
      ? math.min(item.length, rawItems[at + 1].index - item.index)
      : item.length;
}

/// The entry one raw item decodes to, [length] already resolved.
TimelineExposure _exposureFromRawItem(
  _RawTimelineItem item, {
  required int length,
}) {
  final authored = item.ghostOf == null;
  var exposure = TimelineExposure.drawing(
    item.frameId,
    length: length,
    ghostOf: item.ghostOf,
    // A ghost never carries marks: it is a property's output.
    startEdge: authored ? item.startEdge : TimelineRunEdgeMark.none,
    endEdge: authored ? item.endEdge : TimelineRunEdgeMark.none,
  );
  if (item.breakdownMarks.isNotEmpty) {
    // copyWith normalizes (sorts, clamps to the length).
    exposure = exposure.copyWith(breakdownMarks: item.breakdownMarks);
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

/// The frames of [layer] that [ids] name, in their order — null where one
/// is not [layer]'s.
List<Frame>? framesNamed(Layer layer, Iterable<FrameId> ids) {
  final found = <Frame>[];
  for (final id in ids) {
    final frame = layer.frameById(id);
    if (frame == null) {
      return null;
    }
    found.add(frame);
  }
  return found;
}

SplayTreeMap<int, TimelineExposure> _timelineFromJson(Object? json) {
  final rawItems = _rawTimelineItems(json).values.toList(growable: false);
  return SplayTreeMap.of({
    for (final (at, item) in rawItems.indexed)
      item.index: _exposureFromRawItem(
        item,
        length: _drawingLength(rawItems, at),
      ),
  });
}
