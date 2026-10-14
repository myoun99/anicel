import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
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
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🚨ONE ANSWER PER STATE (I-57, 10-14). The rows the session hands every
/// reader — the open cut's own, the track's S rows as the cut shows them
/// and its transition row projected onto the cut — are made once for the
/// project, the cut stood in, the track stood on, the take in flight and
/// the program's language, and handed back until one of them is another.
/// Made per ask, one cut crossing on the AMMI OP made them 1,231 times.
///
/// Cuts a [0, 24) and b [24, 48), an O.L over [18, 30) — six frames of it
/// b's のりしろ, so b's own frame 0 is the track's 18 — and an S row with
/// a sound at the track's 30, b's own 12.
void main() {
  const a = CutId('a');
  const b = CutId('b');
  const sound = LayerId('s1');

  Cut cut(String id) => Cut(
    id: CutId(id),
    name: id,
    duration: 24,
    canvasSize: const CanvasSize(width: 64, height: 36),
    layers: [Layer(id: LayerId('cel-$id'), name: 'A', frames: const [])],
  );

  EditorSessionManager session() {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('once'),
        name: 'Once',
        createdAt: DateTime.utc(2026, 10, 14),
        tracks: [
          Track(
            id: const TrackId('v1'),
            name: 'V1',
            seLayers: [
              Layer(
                id: sound,
                name: 'S1',
                kind: LayerKind.se,
                frames: [
                  Frame(
                    id: const FrameId('rain'),
                    duration: 1,
                    strokes: const [],
                  ),
                ],
                timeline: const {
                  30: TimelineExposure.drawing(FrameId('rain'), length: 4),
                },
              ),
            ],
            cuts: [cut('a'), cut('b')],
          ),
        ],
      ),
    );
    addTearDown(s.dispose);
    s.transitions.updateTransitionInstructions({
      18: const InstructionEvent(instructionId: 'ol', length: 12),
    });
    s.selectCut(a);
    return s;
  }

  Layer soundRow(EditorSessionManager s) =>
      s.layers.singleWhere((layer) => layer.id == sound);

  Layer transitionRow(EditorSessionManager s) =>
      s.layers.singleWhere((layer) => layer.kind == LayerKind.transition);

  test('with nothing changed, every reader is handed the same rows', () {
    final s = session();
    final rows = s.layers;
    final se = s.trackSe.trackSeDisplayLayers;
    final transition = s.transitions.trackTransitionDisplayLayer;

    s.notifyChanged();

    expect(identical(s.layers, rows), isTrue);
    expect(identical(s.trackSe.trackSeDisplayLayers, se), isTrue);
    expect(
      identical(s.transitions.trackTransitionDisplayLayer, transition),
      isTrue,
    );
  });

  test('no reader can change the rows the others are handed', () {
    final s = session();
    expect(() => s.layers.removeLast(), throwsUnsupportedError);
    expect(
      () => s.trackSe.trackSeDisplayLayers.removeLast(),
      throwsUnsupportedError,
    );
  });

  test('crossing into the next cut hands over that cut\'s rows, and '
      'crossing back the first cut\'s', () {
    final s = session();
    final soundInA = soundRow(s).timeline.keys.toList();
    expect(transitionRow(s).instructions.keys, [18]);

    s.selectCut(b);
    expect(
      s.layers.map((layer) => layer.id),
      containsAll(const [LayerId('cel-b'), sound]),
    );
    expect(soundRow(s).timeline.keys, [12]);
    expect(s.trackSe.trackSeDisplayLayers.single.timeline.keys, [12]);
    expect(transitionRow(s).instructions.keys, [0]);
    expect(s.transitions.trackTransitionDisplayLayer.instructions.keys, [0]);

    s.selectCut(a);
    expect(soundRow(s).timeline.keys, soundInA);
    expect(transitionRow(s).instructions.keys, [18]);
  });

  test('the program\'s language names the transition row\'s spans again, '
      'in the rows every reader is handed', () {
    final s = session();
    final before = AppText.settings.value;
    addTearDown(() => AppText.settings.value = before);
    final word = AppStrings.of(AppLanguage.ko).tlTransitionCutOl;
    expect(
      transitionRow(s).instructions.values.single.text,
      isNot(word),
      reason: 'the premise: the row was named in another language',
    );

    s.setLanguageSettings(before.copyWith(programLanguage: AppLanguage.ko));

    expect(
      s.transitions.trackTransitionDisplayLayer.instructions.values.single
          .text,
      word,
    );
    expect(transitionRow(s).instructions.values.single.text, word);
  });

  test('standing in a gap, the S rows and the transition row are the '
      'track stood on', () {
    const other = TrackId('track-b');
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('two'),
        name: 'Two',
        createdAt: DateTime.utc(2026, 10, 14),
        tracks: [
          createDefaultTrack(),
          Track(
            id: other,
            name: 'Track 2',
            cuts: [
              createDefaultCut(
                cutId: const CutId('cut-b1'),
                name: '1',
                layerId: const LayerId('layer-b1'),
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(s.dispose);
    // Track B's only cut slid right by 4: its global 0..3 are a gap.
    expect(s.cutMove.beginCutMoveDrag(const CutId('cut-b1')), isTrue);
    s.cutMove.updateCutMoveDrag(4);
    s.cutMove.endCutMoveDrag();
    s.selectFrameIndex(0);
    s.selectTrackCutAtPlayhead(other);
    expect(s.activeCutId, isNull, reason: 'the premise: parked in the gap');
    List<LayerId> seShown() => [
      for (final layer in s.trackSe.trackSeDisplayLayers) layer.id,
    ];
    final seOnB = seShown();
    final transitionOnB = s.transitions.trackTransitionDisplayLayer.id;

    s.selectTrackRow(const TrackId('default-track'));

    expect(s.activeCutId, isNull, reason: 'still parked in the gap');
    expect(s.selectedTrackId, const TrackId('default-track'));
    final track = s.activeTrack;
    final seOfTrack = [for (final layer in track.seLayers) layer.id];
    expect(seOnB, isNot(seOfTrack), reason: 'the premise: B has its own');
    expect(transitionOnB, isNot(track.transitionLayer.id));
    expect(seShown(), seOfTrack);
    expect(
      s.transitions.trackTransitionDisplayLayer.id,
      track.transitionLayer.id,
    );
  });
}
