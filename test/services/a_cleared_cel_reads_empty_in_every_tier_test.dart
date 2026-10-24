import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cel_text_fixture.dart';
import '../helpers/project_scratch_folder.dart';

/// 🗣️유저 2026-08-27: 「삭제눌렀으면 그림이 사라진거니 블록이 회색되고
/// 버튼도 비활성화되야하는데 둘다 아님」 — a cel cleared to nothing reads
/// empty. Card `a-cooled-empty-cel-reads-drawn` (2026-10-24): it did while
/// hot, and read 「그려짐」 again once its bytes were kept anywhere else —
/// cooled, or saved and opened again — because a kept cel answered by being
/// kept at all. It answers by its head now, as its picture does
/// ([AnicelCelBlob.showsSomething]), and without being decoded.
///
/// The wall's road (a cel cut to nothing by a shrinking pasteboard) is asked
/// beside the rest of the wall's
/// (`a_pasteboard_that_moves_takes_every_picture_with_it_test.dart`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BrushFrameKey cel(String frame) => BrushFrameKey(
    projectId: celTextTestKey.projectId,
    trackId: celTextTestKey.trackId,
    cutId: celTextTestKey.cutId,
    layerId: celTextTestKey.layerId,
    frameId: FrameId(frame),
  );
  final cleared = cel('cleared');
  final drawn = cel('drawn');
  final last = cel('last');
  final a = TileCoord(x: 0, y: 0);
  // What a clear of every pixel leaves: the tile, with nothing in it — the
  // undo counts on the tiles there were.
  final clear = tileFilledWith([0, 0, 0, 0]);
  final ink = tileOf({
    (1, 1): [9, 9, 9, 255],
  });

  /// [store] lets go of every hot picture it may let go of — cooled into
  /// the room, or dropped for free where a saved file holds it — but the
  /// one drawn [last]: the last hot cel never cools.
  Future<void> cool(BrushFrameStore store) async {
    store.storeBakedSurface(last, drawingOf({a: ink}));
    final budget = store.hotCelByteBudget;
    store
      ..hotCelByteBudget = 0
      ..coolToBudget();
    await store.drainCooling();
    store.hotCelByteBudget = budget;
  }

  void expectAskedOfItsHead(BrushFrameStore store) {
    expect(store.celHasRenderableContent(cleared), isFalse);
    expect(
      store.celHasRenderableContent(drawn),
      isTrue,
      reason: 'the CONTROL — a kept cel with ink in it reads drawn',
    );
    expect(
      store.hotBakedSurfaceOrNull(cleared),
      isNull,
      reason: 'asked of its head: nothing was thawed to answer',
    );
  }

  test('🚨① a cleared cel that cools reads empty', () async {
    final store = BrushFrameStore()
      ..storeBakedSurface(cleared, drawingOf({a: clear}))
      ..storeBakedSurface(drawn, drawingOf({a: ink}));
    expect(
      store.celHasRenderableContent(cleared),
      isFalse,
      reason: '⛔premise: hot, it reads its ink',
    );

    await cool(store);

    expect(store.isCelCold(cleared), isTrue, reason: '⛔premise: it cooled');
    expect(store.isCelCold(drawn), isTrue, reason: '⛔premise: it cooled');
    expectAskedOfItsHead(store);
  });

  group('③ saved', () {
    late String path;

    setUp(() async {
      final directory = await Directory.systemTemp.createTemp('qa-cleared');
      deleteAfterSessionEnds(directory);
      path = '${directory.path}/cleared.anicel';
    });

    Future<void> save(BrushFrameStore store) => const AnicelFileService().save(
      project: createDefaultProject(),
      brushFrameStore: store,
      filePath: path,
    );

    test('🚨and opened again, a cleared cel reads empty', () async {
      final store = BrushFrameStore()
        ..storeBakedSurface(cleared, drawingOf({a: clear}))
        ..storeBakedSurface(drawn, drawingOf({a: ink}));
      await save(store);

      final opened = await const AnicelFileService().open(filePath: path);
      final reopened = BrushFrameStore()..restoreFromFile(opened.cels);

      expect(
        reopened.isCelFileBacked(cleared),
        isTrue,
        reason: '⛔premise: the save kept it',
      );
      expectAskedOfItsHead(reopened);
    });

    test('🚨written whole, the ref the save hands back says so too', () async {
      final store = BrushFrameStore()
        ..storeBakedSurface(cleared, drawingOf({a: clear}))
        ..storeBakedSurface(drawn, drawingOf({a: ink}));
      await save(store);

      await cool(store);

      expect(
        store.isCelFileBacked(cleared),
        isTrue,
        reason: '⛔premise: kept in the file it was saved to',
      );
      expectAskedOfItsHead(store);
    });

    test('🚨appended, the ref the save hands back says so too', () async {
      final store = BrushFrameStore()
        ..storeBakedSurface(cleared, drawingOf({a: ink}))
        ..storeBakedSurface(drawn, drawingOf({a: ink}));
      await save(store);
      int drawnAt() => store.bakedSnapshotForSave().fileRefs[drawn]!.dataOffset;
      final before = drawnAt();
      store.storeBakedSurface(cleared, drawingOf({a: clear}));
      await save(store);
      expect(
        drawnAt(),
        before,
        reason: '⛔premise: an append — the clean cel never moved',
      );

      await cool(store);

      expect(
        store.isCelFileBacked(cleared),
        isTrue,
        reason: '⛔premise: kept in the file it was saved to',
      );
      expectAskedOfItsHead(store);
    });
  });

  // The format before any cel: a cel's head is read as THIS build writes
  // it, so the open has to refuse an older file by its number before it
  // reads one.
  test('🚨a file older than the floor is refused by its number, cels and '
      'all — not at its first cel\'s head', () async {
    final directory = await Directory.systemTemp.createTemp('qa-older');
    deleteAfterSessionEnds(directory);
    final path = '${directory.path}/older.anicel';
    const older = anicelOldestReadFormatVersion - 1;
    final head = AnicelCelBlob.ofSurface(cleared, drawingOf({a: ink}));
    writeAnicelArchiveFile(
      path: path,
      entries: [
        (
          name: anicelProjectEntryName,
          bytes: utf8.encode(
            jsonEncode({
              'formatVersion': older,
              'project': createDefaultProject().toJson(),
            }),
          ),
        ),
        (
          name: anicelCelEntryName(cleared),
          // A head this build does not read.
          bytes: Uint8List.fromList(head.bytes)..[0] = head.bytes.first - 1,
        ),
      ],
    );

    expect(
      () => const AnicelFileService().open(filePath: path),
      throwsA(
        isA<AnicelFormatRefused>().having(
          (error) => error.saved,
          'saved',
          older,
        ),
      ),
    );
  });
}
