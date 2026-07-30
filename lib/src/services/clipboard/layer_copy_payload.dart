import 'dart:collection';

import '../../models/audio_clip.dart';
import '../../models/camera_instruction.dart';
import '../../models/frame.dart';
import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../../models/media_reference.dart';
import '../../models/timeline_exposure.dart';

/// What "copy layer" carries. A POSITIVE list, so anything not named here
/// is deliberately left behind — and today that is every piece of
/// COMPOSITE-TIME state: the blend mode, the transform track and (R6) the
/// effect chain. A pasted layer arrives as the artwork and its timing, with
/// its FX un-set. That has been the behaviour since the transform lanes
/// landed; effects follow the same rule rather than inventing a second one.
/// Changing it is one decision about all three, not three decisions.
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
  }) : frames = List.unmodifiable(frames),
       timeline = UnmodifiableMapView(
         SplayTreeMap<int, TimelineExposure>.of(timeline),
       ),
       instructions = UnmodifiableMapView(
         SplayTreeMap<int, InstructionEvent>.of(instructions),
       ),
       audioClips = List.unmodifiable(audioClips);

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
  );
}
