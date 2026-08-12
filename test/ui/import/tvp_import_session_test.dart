import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// An import through the SESSION, which is where the ids come from.
///
/// The planner takes its minting seam as an argument, so every planner
/// test supplies a counter of its own and gets unique ids for free. The
/// session's real mint was the thing that collided, and nothing exercised
/// it: a layer of ten drawings arrived as ten exposures of ONE drawing,
/// because the id formatter reads a sequence it does not advance and the
/// only other ingredient — the wall clock — does not tick fast enough to
/// separate a mint loop on Windows.
///
/// The image files are absent here (the fixture ships the JSON alone), so
/// the bakes are skipped and the cels come out empty. The cel IDENTITIES
/// are what this pins, and those are minted before any pixel is read.
void main() {
  test('every imported cel is its own drawing', () async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);

    final warnings = await session.importTvpJson(
      jsonPath: 'test/fixtures/tvpaint/production_clip.json',
    );
    expect(warnings, isNotNull, reason: 'the fixture parses');

    final cut = session.repository
        .requireProject()
        .tracks
        .expand((track) => track.cuts)
        .firstWhere((cut) => cut.name == '番号');

    final ids = <FrameId>[];
    for (final layer in cut.layers) {
      ids.addAll(layer.frames.map((frame) => frame.id));
    }

    expect(ids, isNotEmpty);
    expect(
      ids.toSet(),
      hasLength(ids.length),
      reason: 'two cels sharing an id are ONE drawing — the timeline shows '
          'the same picture in every block and the first cel\'s name in '
          'every cell',
    );
  });

  test('a layer keeps one cel per drawing, re-exposures included', () async {
    // The count is the other half: unique ids would also be satisfied by
    // minting one per BLOCK, which would break TVPaint's re-exposure (the
    // same drawing shown twice must stay one cel).
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);

    await session.importTvpJson(
      jsonPath: 'test/fixtures/tvpaint/edge_behaviors.json',
    );

    final cut = session.repository
        .requireProject()
        .tracks
        .expand((track) => track.cuts)
        .firstWhere((cut) => cut.name == 'クリップ_001');

    final d = cut.layers.firstWhere((layer) => layer.name == 'D');
    expect(d.frames, hasLength(3), reason: 'three instances, three cels');
    expect(d.frames.map((frame) => frame.id).toSet(), hasLength(3));

    final tap = cut.layers.firstWhere((layer) => layer.name == 'TAP');
    expect(
      tap.frames,
      hasLength(1),
      reason: 'one drawing held across the clip stays one cel',
    );
  });
}
