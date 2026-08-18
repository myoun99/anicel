import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_section_defaults.dart'
    show transitionLayerIdForTrack;
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

/// C④ (#1116's open cell ④) — a MIXED multi-row rigid range move (SE rows
/// + the transition row) carries the transition spans as frame-axis
/// riders, exactly as the plain slide already does (C1): they shift with
/// the frame delta on their OWN row, preview live on the transition's own
/// channel, and land in the SAME single undo.
const _trackId = TrackId('mixed-track');
const _seLayerId = LayerId('mixed-se-1');
const _seLayer2Id = LayerId('mixed-se-2');

Cut _cut(String id, int duration) => Cut(
  id: CutId(id),
  name: id,
  duration: duration,
  canvasSize: const CanvasSize(width: 640, height: 360),
  layers: [
    Layer(
      id: LayerId('$id-cel'),
      name: 'A',
      frames: const [],
      timeline: const {},
    ),
  ],
);

/// Cut 1 covers [0,8), cut 2 covers [8,14). S1 carries a sound at [2,5);
/// S2 is empty (the hop's landing row). The transition row carries a span
/// at [2,5).
Project _project() => Project(
  id: const ProjectId('mixed-project'),
  name: 'Mixed',
  createdAt: DateTime.utc(2026, 8, 18),
  tracks: [
    Track(
      id: _trackId,
      name: 'Video',
      cuts: [_cut('cut-1', 8), _cut('cut-2', 6)],
      seLayers: [
        Layer(
          id: _seLayerId,
          name: 'S1',
          kind: LayerKind.se,
          frames: [
            Frame(
              id: const FrameId('se-one'),
              duration: 3,
              name: 'One!',
              strokes: const [],
            ),
          ],
          timeline: const {
            2: TimelineExposure.drawing(FrameId('se-one'), length: 3),
          },
        ),
        Layer(
          id: _seLayer2Id,
          name: 'S2',
          kind: LayerKind.se,
          frames: const [],
          timeline: const {},
        ),
      ],
      transitionLayer: Layer(
        id: transitionLayerIdForTrack(_trackId),
        name: 'Transition',
        frames: const [],
        timeline: const {},
        kind: LayerKind.transition,
        instructions: const {
          2: InstructionEvent(instructionId: 'ol', length: 3),
        },
      ),
    ),
  ],
);

void main() {
  EditorSessionManager sessionFor() {
    final session = EditorSessionManager(initialProject: _project());
    addTearDown(session.dispose);
    return session;
  }

  LayerId transitionId() => transitionLayerIdForTrack(_trackId);

  /// Selects the span [2,5) across the transition row AND S1 (the rail
  /// order runs transition → SE rows → track row, so anchoring on S1 with
  /// the transition as head covers both).
  void selectMixedSpan(EditorSessionManager session) {
    session.updateTrackRowRangeSelectionByFrame(
      layerId: _seLayerId,
      anchorGlobalFrame: 2,
      headGlobalFrame: 4,
      headRow: LayerRowAddress(transitionId()),
    );
    expect(
      session.trackFrameRangeSelection.value!.spanRows,
      containsAll([
        const LayerRowAddress(_seLayerId),
        LayerRowAddress(transitionId()),
      ]),
    );
  }

  Map<int, InstructionEvent> transitionSpansOf(EditorSessionManager session) =>
      session.repository
          .requireProject()
          .tracks
          .single
          .transitionLayer
          .instructions;

  test('a rigid row-hop step carries the transition spans: live preview '
      'on the transition\'s own channel, never the layers map, and ONE '
      'undo lands both', () {
    final session = sessionFor();
    selectMixedSpan(session);

    expect(session.beginTrackRangeMoveDrag(_seLayerId), isTrue);
    // A step with BOTH a frame delta and a row hop (S1 → S2): the rigid
    // machine owns it.
    session.updateFrameRangeMoveDrag(frameDelta: 1, targetLayerId: _seLayer2Id);

    // Mid-step: the transition previews its shifted span on its own
    // channel (C④: it used to be CLEARED here — the spans snapped home
    // the moment the pointer crossed a row)…
    final transitionPreview = session.transitionEdgeDragPreview.value;
    expect(transitionPreview, isNotNull);
    expect(transitionPreview!.instructions.keys.toList(), [3]);
    // …and never leaks into the layers map, where the cut timeline's
    // read-only clone would pick up its GLOBAL keys.
    final preview = session.dragPreview.value;
    if (preview is BlockMoveDragPreview) {
      expect(preview.previewLayers.containsKey(transitionId()), isFalse);
    }

    session.endFrameRangeMoveDrag();

    // The sound hopped S1 → S2 and slid +1; the transition span slid +1
    // on its OWN row.
    expect(
      session.repository
          .requireProject()
          .tracks
          .single
          .seLayers
          .first
          .timeline,
      isEmpty,
    );
    expect(
      session.repository
          .requireProject()
          .tracks
          .single
          .seLayers
          .last
          .timeline
          .keys
          .toList(),
      [3],
    );
    expect(transitionSpansOf(session).keys.toList(), [3]);

    // ONE undo restores the whole mixed move.
    session.undo();
    expect(
      session.repository
          .requireProject()
          .tracks
          .single
          .seLayers
          .first
          .timeline
          .keys
          .toList(),
      [2],
    );
    expect(transitionSpansOf(session).keys.toList(), [2]);
  });

  test('a rider that cannot land VOIDS the step — the last valid preview '
      'holds and nothing commits', () {
    final session = sessionFor();
    selectMixedSpan(session);

    expect(session.beginTrackRangeMoveDrag(_seLayerId), isTrue);
    // Landing at -1: the transition span cannot shift, so the whole rigid
    // step holds (the rider contract).
    session.updateFrameRangeMoveDrag(
      frameDelta: -3,
      targetLayerId: _seLayer2Id,
    );
    session.endFrameRangeMoveDrag();

    expect(transitionSpansOf(session).keys.toList(), [2]);
    expect(
      session.repository
          .requireProject()
          .tracks
          .single
          .seLayers
          .first
          .timeline
          .keys
          .toList(),
      [2],
    );
  });

  test('a PURE row hop (frameDelta 0) carries the blocks and HOLDS the '
      'riders in place — "nothing to shift" is not "blocked"', () {
    final session = sessionFor();
    selectMixedSpan(session);

    expect(session.beginTrackRangeMoveDrag(_seLayerId), isTrue);
    // Straight down onto S2: no frame delta at all.
    session.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: _seLayer2Id);
    session.endFrameRangeMoveDrag();

    expect(
      session.repository
          .requireProject()
          .tracks
          .single
          .seLayers
          .last
          .timeline
          .keys
          .toList(),
      [2],
      reason: 'the sound hopped rows at its own frames',
    );
    expect(
      transitionSpansOf(session).keys.toList(),
      [2],
      reason: 'the transition moved no frames — it simply holds',
    );

    session.undo();
    expect(
      session.repository
          .requireProject()
          .tracks
          .single
          .seLayers
          .first
          .timeline
          .keys
          .toList(),
      [2],
    );
  });

  test('an ILLEGAL slide step after a valid rigid step kills the rigid '
      'riders with the rigid plans — release commits NOTHING, never the '
      'riders alone', () {
    final session = sessionFor();
    selectMixedSpan(session);

    expect(session.beginTrackRangeMoveDrag(_seLayerId), isTrue);
    // Step A: a valid rigid diagonal (+1, S1 → S2) captures rider shifts.
    session.updateFrameRangeMoveDrag(frameDelta: 1, targetLayerId: _seLayer2Id);
    // Step B: back over the grab row, far left — the slide owns the step
    // and the transition's landing (-7) is illegal, so it HOLDS.
    session.updateFrameRangeMoveDrag(frameDelta: -9);
    session.endFrameRangeMoveDrag();

    // The rigid group is all-or-nothing THROUGH the release: nothing
    // landed — most of all not the transition alone.
    expect(transitionSpansOf(session).keys.toList(), [2]);
    expect(
      session.repository
          .requireProject()
          .tracks
          .single
          .seLayers
          .first
          .timeline
          .keys
          .toList(),
      [2],
    );
    expect(
      session.repository
          .requireProject()
          .tracks
          .single
          .seLayers
          .last
          .timeline,
      isEmpty,
    );
  });

  test('the plain slide keeps the transition OFF the layers map too — the '
      'active track\'s display clone shares its id', () {
    final session = sessionFor();
    selectMixedSpan(session);

    expect(session.beginTrackRangeMoveDrag(_seLayerId), isTrue);
    // No row hop: the plain slide owns the step.
    session.updateFrameRangeMoveDrag(frameDelta: 1);

    final preview = session.dragPreview.value;
    expect(preview, isA<BlockMoveDragPreview>());
    expect(
      (preview as BlockMoveDragPreview).previewLayers.containsKey(
        transitionId(),
      ),
      isFalse,
      reason: 'a global-keyed transition entry would leak into the cut '
          'timeline\'s read-only projection',
    );
    expect(session.transitionEdgeDragPreview.value, isNotNull);

    session.cancelFrameRangeMoveDrag();
  });
}
