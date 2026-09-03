// A FRAME-RATE CHANGE ROUND-TRIPS, WITH OR WITHOUT THE AUDIO SPEED IT
// CARRIES.
//
// No test named this command file (audit 2026-09-04); the settings dialog
// reached it through the session. These pins drive it directly: execute
// applies the rate (and the audio speed when given), undo restores what
// the FIRST execute captured, and a rate-only command leaves the audio
// speed alone in both directions.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/commands/update_project_frame_rate_command.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  late ProjectRepository repository;
  late ProjectFrameRate before;
  late ProjectFrameRate other;

  setUp(() {
    repository = ProjectRepository(initialProject: createDefaultProject());
    before = repository.requireProject().frameRate;
    other = ProjectFrameRate.presets.firstWhere((rate) => rate != before);
  });

  test('execute applies the rate, undo restores it, execute re-applies', () {
    final command = UpdateProjectFrameRateCommand(
      repository: repository,
      frameRate: other,
    );
    command.execute();
    expect(repository.requireProject().frameRate, other);
    command.undo();
    expect(repository.requireProject().frameRate, before);
    command.execute();
    expect(repository.requireProject().frameRate, other);
  });

  test('with an audio speed the speed rides both ways; without one it is '
      'left alone', () {
    final speedBefore = (
      repository.requireProject().audioSpeedNumerator,
      repository.requireProject().audioSpeedDenominator,
    );
    final withSpeed = UpdateProjectFrameRateCommand(
      repository: repository,
      frameRate: other,
      audioSpeedNumerator: 5,
      audioSpeedDenominator: 4,
    );
    withSpeed.execute();
    expect(repository.requireProject().audioSpeedNumerator, 5);
    expect(repository.requireProject().audioSpeedDenominator, 4);
    withSpeed.undo();
    expect(repository.requireProject().audioSpeedNumerator, speedBefore.$1);
    expect(repository.requireProject().audioSpeedDenominator, speedBefore.$2);

    withSpeed.execute();
    final rateOnly = UpdateProjectFrameRateCommand(
      repository: repository,
      frameRate: before,
    );
    rateOnly.execute();
    expect(repository.requireProject().frameRate, before);
    expect(repository.requireProject().audioSpeedNumerator, 5);
    rateOnly.undo();
    expect(repository.requireProject().frameRate, other);
    expect(repository.requireProject().audioSpeedNumerator, 5);
  });

  test('undo before execute is refused', () {
    final command = UpdateProjectFrameRateCommand(
      repository: repository,
      frameRate: other,
    );
    expect(command.undo, throwsStateError);
  });
}
