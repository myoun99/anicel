import 'dart:collection';

import '../../models/audio_clip.dart';
import '../../models/camera_instruction.dart';
import '../../models/frame.dart';
import '../../models/layer.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../../models/media_reference.dart';
import '../../models/timeline_exposure.dart';
import '../../models/timeline_repeat.dart';
import '../../models/transform_track.dart';

/// What "copy layer" carries: EVERYTHING about the row that a standalone
/// copy can mean (user, 2026-07-30 — "합성포함해서 싹다").
///
/// That includes the composite-time state the payload used to drop — the
/// blend mode, the transform track and the R6 effect chain — so a pasted
/// layer looks like the one you copied instead of an un-styled version of
/// it.
///
/// What it deliberately cannot carry is STRUCTURAL POINTERS, because they
/// name rows that the paste target may not have:
/// - [Layer.folderId]: the target cut has no such folder row;
/// - the attach linkage ([Layer.attachedToLayerId] and its cell links): a
///   copy has no base, so it pastes as a row of its own;
/// - SE-only state (mute/gain/pan, the on-canvas name tag): SE rows are
///   track-owned and refuse the clipboard outright
///   ([layerKindIsClipboardCopyable]).
class LayerCopyPayload {
  LayerCopyPayload({
    required this.name,
    required this.kind,
    required this.isVisible,
    required this.opacity,
    required List<Frame> frames,
    required Map<int, TimelineExposure> timeline,
    Map<int, InstructionEvent> instructions = const {},
    List<AudioClip> audioClips = const [],
    this.mediaReference,
    this.blendMode = LayerBlendMode.normal,
    TransformTrack? transformTrack,
    List<LayerEffect> effects = const [],
    List<TimelineRunBehavior> runBehaviors = const [],
    this.mark = LayerMark.none,
    this.onTimesheet = true,
    this.isFillReference = false,
  }) : frames = List.unmodifiable(frames),
       timeline = UnmodifiableMapView(
         SplayTreeMap<int, TimelineExposure>.of(timeline),
       ),
       instructions = UnmodifiableMapView(
         SplayTreeMap<int, InstructionEvent>.of(instructions),
       ),
       audioClips = List.unmodifiable(audioClips),
       transformTrack = transformTrack ?? TransformTrack.empty(),
       effects = List.unmodifiable(effects),
       runBehaviors = List.unmodifiable(runBehaviors);

  final String name;
  final LayerKind kind;
  final bool isVisible;
  final double opacity;
  final List<Frame> frames;
  final Map<int, TimelineExposure> timeline;

  /// Instruction spans ride copies so duplicating a CAM row keeps its data.
  final Map<int, InstructionEvent> instructions;

  /// Audio clips ride copies so duplicating an SE row keeps its sound.
  final List<AudioClip> audioClips;

  /// The media reference rides copies so duplicating a referenced layer
  /// keeps its picture (the copy shows the same library asset).
  final MediaReference? mediaReference;

  /// The row's composite blend (R26 #30).
  final LayerBlendMode blendMode;

  /// The row's keyframed transform — the AE Transform lanes.
  final TransformTrack transformTrack;

  /// The row's effect chain (R6).
  final List<LayerEffect> effects;

  /// Run-edge properties. These are addressed by FRAME ID, so the paste
  /// planner must REMAP their anchors onto the copied frames — carrying
  /// them verbatim would name blocks the copy does not have.
  final List<TimelineRunBehavior> runBehaviors;

  final LayerMark mark;
  final bool onTimesheet;

  /// The FILL tool's reference flag (R20-C2).
  final bool isFillReference;
}

LayerCopyPayload copyLayerToPayload(Layer source) {
  return LayerCopyPayload(
    name: source.name,
    kind: source.kind,
    isVisible: source.isVisible,
    opacity: source.opacity,
    frames: source.frames,
    timeline: source.timeline,
    instructions: source.instructions,
    audioClips: source.audioClips,
    mediaReference: source.mediaReference,
    blendMode: source.blendMode,
    transformTrack: source.transformTrack,
    effects: source.effects,
    runBehaviors: source.runBehaviors,
    mark: source.mark,
    onTimesheet: source.onTimesheet,
    isFillReference: source.isFillReference,
  );
}
