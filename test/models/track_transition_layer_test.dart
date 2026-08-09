import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';

/// The TRANSITION row: one per track, on the track's global frame axis, made
/// of the same instruction events the cut's direction row carries.
void main() {
  final trackId = TrackId('t1');

  Cut cut(String id, int duration) => Cut(
    id: CutId(id),
    name: id,
    layers: const [],
    duration: duration,
    canvasSize: const CanvasSize(width: 100, height: 100),
  );

  Track track() =>
      Track(id: trackId, name: 'V1', cuts: [cut('c1', 24), cut('c2', 24)]);

  test('a new track already has its transition row', () {
    final t = track();

    expect(t.transitionLayer.kind, LayerKind.transition);
    expect(t.transitionLayer.id, transitionLayerIdForTrack(trackId));
    expect(t.transitionLayer.instructions, isEmpty);
  });

  test('an untouched transition row writes nothing', () {
    // R8's rule: a default is silence, so a project that never used a
    // transition keeps exactly the file shape it had before the row existed.
    expect(track().toJson().containsKey('transition'), isFalse);
  });

  test('a file written before the row existed backfills one', () {
    final json = track().toJson();
    expect(json.containsKey('transition'), isFalse);

    final reloaded = Track.fromJson(json);

    expect(reloaded.transitionLayer.kind, LayerKind.transition);
    expect(reloaded.transitionLayer.id, transitionLayerIdForTrack(trackId));
  });

  test('a transition span survives the JSON round trip', () {
    final withSpan = track().copyWith(
      transitionLayer: createTrackTransitionLayer(trackId).copyWith(
        instructions: SplayTreeMap<int, InstructionEvent>.from({
          // Straddles the c1|c2 boundary at global frame 24: an O.L is the
          // outgoing cut's F.O and the incoming cut's F.I over one span.
          12: const InstructionEvent(instructionId: 'ol', length: 24),
        }),
      ),
    );

    final json = withSpan.toJson();
    expect(json.containsKey('transition'), isTrue);

    final reloaded = Track.fromJson(json);
    final event = reloaded.transitionLayer.instructions[12];

    expect(event, isNotNull);
    expect(event!.instructionId, 'ol');
    expect(event.length, 24);
    // Not a whole-object comparison: fromJson also backfills the SE floor
    // and each cut's CAM row, so the reload is deliberately richer than the
    // literal we built.
    expect(reloaded.transitionLayer, withSpan.transitionLayer);
  });

  test('the transition row keys on the GLOBAL axis, not a cut', () {
    // The span above starts at 12 and runs 24 frames, so it reaches into
    // the second cut — which no cut-scoped row could express.
    final t = track().copyWith(
      transitionLayer: createTrackTransitionLayer(trackId).copyWith(
        instructions: SplayTreeMap<int, InstructionEvent>.from({
          12: const InstructionEvent(instructionId: 'ol', length: 24),
        }),
      ),
    );

    final firstCutLength = t.cuts.first.duration;
    final span = t.transitionLayer.instructions.entries.single;

    expect(span.key, lessThan(firstCutLength));
    expect(span.key + span.value.length, greaterThan(firstCutLength));
  });

  group('the transition vocabulary', () {
    final standard = CameraInstructionSet.standard;

    test('is exactly the five 場面転換 terms', () {
      final transitionIds = [
        for (final def in standard.defs)
          if (cameraInstructionIsTransition(def)) def.id,
      ];

      expect(transitionIds, ['fi', 'fo', 'wi', 'wo', 'ol']);
    });

    test('leaves the camera-work terms on the direction row', () {
      for (final id in ['fix', 'pan', 'tu', 'tb', 'sl', 'wipe']) {
        final def = standard.defById(id);
        if (def == null) {
          continue;
        }
        expect(
          cameraInstructionIsTransition(def),
          isFalse,
          reason: '$id is camera work, not a scene change',
        );
      }
    });
  });
}
