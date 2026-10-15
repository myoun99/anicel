import 'dart:io';

import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cel_photo_fixture.dart';
import '../helpers/cel_text_fixture.dart';
import '../helpers/temp_dir.dart';

/// I-97 E: a sheet store says which pool files its cels' photos name, in
/// every tier a cel can be in — hot from its picture, cooled or in the
/// project's file from the ref its head was read into — without decoding a
/// cel to answer. It is what the media pool asks of a sheet (사용 중 · 제거
/// · 다시 연결 · 열 때 옮기기).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cel_photo_paths_');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  const key = celTextTestKey;
  final a = TileCoord(x: 0, y: 0);
  final ink = tileOf({
    (1, 1): [9, 9, 9, 255],
  });
  final picture = drawingOf({
    a: ink,
  }).withPhotos([photoOf(1, path: 'C:/pool/a.png')]);

  /// [picture] written into a file of its own, and the ref its head reads
  /// into — the open path's.
  AnicelCelFileRef inAFile() {
    final blob = AnicelCelBlob.encode(AnicelCelEntry.fromSurface(key, picture));
    final file = File('${tempDir.path}/cel.bin')..writeAsBytesSync(blob.bytes);
    return AnicelCelFileRef(
      filePath: file.path,
      dataOffset: 0,
      length: blob.bytes.length,
      canvasSize: blob.canvasSize,
      tileSize: blob.tileSize,
      photoPaths: blob.photoPaths,
    );
  }

  test('a hot cel names its photos\' files off its picture', () {
    final store = BrushFrameStore()..storeBakedSurface(key, picture);

    expect(store.celPhotoPathsByKey, {
      key: ['C:/pool/a.png'],
    });
  });

  test('🚨a cel whose bytes are in the file names them off its ref — '
      'nothing is decoded to ask', () {
    final store = BrushFrameStore()..restoreFromFile({key: inAFile()});

    expect(store.celPhotoPathsByKey, {
      key: ['C:/pool/a.png'],
    });
    expect(
      store.hotBakedSurfaceOrNull(key),
      isNull,
      reason: 'asked without a decode',
    );
  });

  test('a cooled cel names them off the ref its room keeps', () async {
    final store = BrushFrameStore()..hotCelByteBudget = 0;
    final other = BrushFrameKey(
      projectId: key.projectId,
      trackId: key.trackId,
      cutId: const CutId('other'),
      layerId: key.layerId,
      frameId: key.frameId,
    );
    store.storeBakedSurface(key, picture);
    store.storeBakedSurface(other, drawingOf({a: ink}));
    await store.drainCooling();

    expect(store.isCelCold(key), isTrue, reason: '⛔fixture: it cooled');
    expect(store.celPhotoPathsByKey, {
      key: ['C:/pool/a.png'],
    });
  });

  test('the hot picture answers for its key: an edit that took its photos '
      'off is not outvoted by the file it was read from', () {
    final store = BrushFrameStore()..restoreFromFile({key: inAFile()});
    final read = store.bakedSurfaceOrNull(key)!;

    store.storeBakedSurface(key, read.withPhotos(const []));

    expect(store.celPhotoPathsByKey, isEmpty);
  });

  test('a ref moved to another file, or within one, keeps its index', () {
    final store = BrushFrameStore()..restoreFromFile({key: inAFile()});
    final ref = inAFile();
    final rescued = File('${tempDir.path}/rescued.bin')
      ..writeAsBytesSync(File(ref.filePath).readAsBytesSync());

    store.repointFileRefs(ref.filePath, rescued.path);
    expect(store.celPhotoPathsByKey, {
      key: ['C:/pool/a.png'],
    });

    store.relocateFileRefs((_) => true, {
      0: (dataOffset: 0, length: ref.length),
    });
    expect(store.celPhotoPathsByKey, {
      key: ['C:/pool/a.png'],
    });
    expect(store.isCelFileBacked(key), isTrue, reason: 'the CONTROL');
  });
}
