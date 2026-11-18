import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cel_text_fixture.dart';
import '../../helpers/project_scratch_folder.dart';

/// F-608-Q2 (유저 2026-11-17: 「내려받는중에 퍼센테이지가 조금이라도
/// 안느는게 문제」): an open reads the project's entry and each cel's head
/// — and a drive that says nothing of a file the cloud still holds brings
/// it down inside that read — so the window's bar is told as it goes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String path;

  setUp(() async {
    final directory = await Directory.systemTemp.createTemp('qa-open-read');
    deleteAfterSessionEnds(directory);
    path = '${directory.path}/read.anicel';
    final store = BrushFrameStore();
    for (final name in ['a', 'b', 'c']) {
      store.storeBakedSurface(
        BrushFrameKey(
          projectId: celTextTestKey.projectId,
          trackId: celTextTestKey.trackId,
          cutId: celTextTestKey.cutId,
          layerId: celTextTestKey.layerId,
          frameId: FrameId(name),
        ),
        drawingOf({
          TileCoord(x: 0, y: 0): tileFilledWith([9, 9, 9, 255]),
        }),
      );
    }
    await const AnicelFileService().save(
      project: createDefaultProject(),
      brushFrameStore: store,
      filePath: path,
    );
  });

  test('🎯an open tells how much of what it reads is in — none, the '
      'project, then each cel\'s head, to all of it', () async {
    final told = <double>[];

    final opened = await const AnicelFileService().open(
      filePath: path,
      onRead: told.add,
    );

    expect(opened.cels, hasLength(3), reason: '⛔premise: three cels kept');
    expect(told, hasLength(5), reason: 'none, the project, and three heads');
    expect(told.first, 0);
    expect(told.last, 1);
    for (var i = 1; i < told.length; i += 1) {
      expect(told[i], greaterThan(told[i - 1]));
    }
  });

  test('on the road production takes — a worker of its own — the read '
      'crosses and its bar is heard', () async {
    debugWorkersRunHere = false;
    addTearDown(() => debugWorkersRunHere = true);
    final told = <double>[];

    final opened = await const AnicelFileService().open(
      filePath: path,
      onRead: told.add,
    );

    expect(opened.cels, hasLength(3));
    expect(told, isNotEmpty);
    expect(told.first, 0);
    for (var i = 1; i < told.length; i += 1) {
      expect(told[i], greaterThan(told[i - 1]));
    }
  });
}
