import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../models/import/tvpp_test_builder.dart';

/// An import through the SESSION, which is where the ids come from.
///
/// The planner takes its minting seam as an argument, so every planner
/// test supplies a counter of its own and gets unique ids for free. The
/// session's real mint was the thing that collided, and nothing exercised
/// it: a layer of ten drawings arrived as ten exposures of ONE drawing,
/// because the id formatter reads a sequence it does not advance and the
/// only other ingredient — the wall clock — does not tick fast enough to
/// separate a mint loop on Windows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('tvpp-session'));
  tearDown(() => temp.deleteSync(recursive: true));

  String writeTvpp() {
    final b = TvppBuilder();
    b.clipProperties('番号');
    b.clipHeader(width: 64, height: 48);
    b.layerHead('카메라레이어', headerChunk: 'LRCA');
    b.layerExt(const {});
    // TEN drawings back to back — the mint loop the wall clock could
    // not separate.
    b.layerHead('A', end: 9, count: 10, layerId: 901);
    b.layerExt(const {});
    for (var i = 0; i < 10; i++) {
      b.zchkSlot(srawRecord(List.filled(64 * 48, 0), 64, 48));
    }
    // One drawing held across the same span.
    b.layerHead('TAP', end: 9, count: 10, layerId: 902);
    b.layerExt(const {});
    b.zchkSlot(srawRecord(List.filled(64 * 48, 0), 64, 48));
    for (var i = 0; i < 9; i++) {
      b.zchkHold();
    }
    final path = '${temp.path}${Platform.pathSeparator}番号.tvpp';
    File(path).writeAsBytesSync(b.bytes);
    return path;
  }

  test('a .tvpp opens AS the project and every cel is its own drawing',
      () async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);

    final warnings = await session.openTvppAsProject(tvppPath: writeTvpp());
    expect(warnings, isNotNull, reason: 'the file parses');

    // The open REPLACES the project — the default cut is gone and the
    // file's name is the project's.
    final project = session.repository.requireProject();
    expect(project.name, '番号');
    final cuts = project.tracks.expand((track) => track.cuts).toList();
    expect(cuts, hasLength(1));
    expect(cuts.single.name, '番号');

    final ids = <FrameId>[];
    for (final layer in cuts.single.layers) {
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

    // The count is the other half: unique ids would also be satisfied by
    // minting one per BLOCK, which would break exposure runs (one drawing
    // held ten frames must stay one cel).
    final a = cuts.single.layers.firstWhere((layer) => layer.name == 'A');
    expect(a.frames, hasLength(10), reason: 'ten drawings, ten cels');
    final tap =
        cuts.single.layers.firstWhere((layer) => layer.name == 'TAP');
    expect(
      tap.frames,
      hasLength(1),
      reason: 'one drawing held across the clip stays one cel',
    );
    expect(tap.timeline[0]!.length, 10);
  });
}
