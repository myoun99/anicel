// PINNING A CUT'S THUMBNAIL FRAME ROUND-TRIPS, AND A RESET IS THE SAME
// COMMAND WITH NO FRAME.
//
// No test named this command file (audit 2026-09-04); the storyboard's pin
// verb reached it through the session. These pins drive it directly.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/services/commands/update_cut_thumbnail_frame_command.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  late ProjectRepository repository;
  late CutId cutId;

  setUp(() {
    repository = ProjectRepository(initialProject: createDefaultProject());
    cutId = repository.requireProject().tracks.first.cuts.first.id;
  });

  int? pinned() =>
      requireCut(repository.requireProject(), cutId).metadata.thumbnailFrameIndex;

  test('a pin applies, undoes to the unpinned cut, and re-applies', () {
    expect(pinned(), isNull, reason: 'fixture: nothing pinned');
    final pin = UpdateCutThumbnailFrameCommand(
      repository: repository,
      cutId: cutId,
      frameIndex: 3,
    );
    pin.execute();
    expect(pinned(), 3);
    pin.undo();
    expect(pinned(), isNull);
    pin.execute();
    expect(pinned(), 3);
  });

  test('a reset after a pin clears it, and its undo brings the pin back', () {
    UpdateCutThumbnailFrameCommand(
      repository: repository,
      cutId: cutId,
      frameIndex: 5,
    ).execute();
    final reset = UpdateCutThumbnailFrameCommand(
      repository: repository,
      cutId: cutId,
      frameIndex: null,
    );
    reset.execute();
    expect(pinned(), isNull);
    reset.undo();
    expect(pinned(), 5);
  });

  test('the description names the frame as the user counts it', () {
    expect(
      UpdateCutThumbnailFrameCommand(
        repository: repository,
        cutId: cutId,
        frameIndex: 0,
      ).description,
      contains('frame 1'),
    );
    expect(
      UpdateCutThumbnailFrameCommand(
        repository: repository,
        cutId: cutId,
        frameIndex: null,
      ).description,
      contains('Reset'),
    );
  });

  test('undo before execute is refused', () {
    expect(
      UpdateCutThumbnailFrameCommand(
        repository: repository,
        cutId: cutId,
        frameIndex: 1,
      ).undo,
      throwsStateError,
    );
  });
}
