// A TRACK'S EFFECT CHAIN ROUND-TRIPS THROUGH ITS COMMAND.
//
// No test named this command file (audit 2026-09-04); the effects panel
// reached it through the session. These pins drive it directly: execute
// replaces the chain, undo restores the chain captured at the FIRST
// execute (a redo in between changes nothing about that), and a track
// that is not there is refused before anything is written.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/update_track_effects_command.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  late ProjectRepository repository;
  late TrackId trackId;

  setUp(() {
    repository = ProjectRepository(initialProject: createDefaultProject());
    trackId = repository.requireProject().tracks.first.id;
  });

  List<LayerEffect> effectsOf() => repository
      .requireProject()
      .tracks
      .firstWhere((track) => track.id == trackId)
      .effects;

  test('execute replaces the chain, undo restores it, execute re-applies', () {
    final before = effectsOf();
    final blur = LayerEffect.defaults(id: const EffectId('e1'), kind: EffectKind.blur);
    final command = UpdateTrackEffectsCommand(
      repository: repository,
      trackId: trackId,
      effects: [blur],
    );
    command.execute();
    expect(effectsOf().map((e) => e.id), [const EffectId('e1')]);
    command.undo();
    expect(effectsOf().map((e) => e.id), before.map((e) => e.id));
    command.execute();
    expect(effectsOf().map((e) => e.id), [const EffectId('e1')]);
  });

  test('undo restores what the first execute saw, not what a later edit '
      'left', () {
    final before = effectsOf();
    final command = UpdateTrackEffectsCommand(
      repository: repository,
      trackId: trackId,
      effects: [
        LayerEffect.defaults(id: const EffectId('e1'), kind: EffectKind.blur),
      ],
    );
    command.execute();
    UpdateTrackEffectsCommand(
      repository: repository,
      trackId: trackId,
      effects: [
        LayerEffect.defaults(
          id: const EffectId('e2'),
          kind: EffectKind.brightnessContrast,
        ),
      ],
    ).execute();
    command.undo();
    expect(effectsOf().map((e) => e.id), before.map((e) => e.id));
  });

  test('a track that is not there is refused, and undo stays refused', () {
    final command = UpdateTrackEffectsCommand(
      repository: repository,
      trackId: const TrackId('no-such-track'),
      effects: const [],
    );
    expect(command.execute, throwsStateError);
    expect(command.undo, throwsStateError);
  });
}
