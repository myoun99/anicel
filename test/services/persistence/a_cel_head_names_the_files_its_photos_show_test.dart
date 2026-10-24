import 'dart:typed_data';

import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/persistence/anicel_payload_codec.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cel_photo_fixture.dart';
import '../../helpers/cel_text_fixture.dart';

/// I-97 E: a saved cel's HEAD names the pool files its photos show — what
/// a reader of heads alone (the open path) can answer without inflating a
/// cel, so the media pool can say where a file is used, take it away and
/// move it along without decoding every sheet.
///
/// The photos themselves stay in the stream. The index is what a head can
/// answer — never a second copy that a decode would read.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = celTextTestKey;
  final a = TileCoord(x: 0, y: 0);
  final ink = tileOf({
    (1, 1): [9, 9, 9, 255],
  });

  test('a cel indexes the pool files its photos name — each once, in the '
      'order they first stand', () {
    final picture = drawingOf({a: ink}).withPhotos([
      photoOf(1, path: 'C:/pool/a.png'),
      photoOf(2, path: 'C:/pool/b.png'),
      photoOf(3, path: 'C:/pool/a.png'),
    ]);

    final blob = AnicelCelBlob.ofSurface(key, picture);

    expect(blob.photoPaths, ['C:/pool/a.png', 'C:/pool/b.png']);
    expect(AnicelCelBlob(blob.bytes).photoPaths, blob.photoPaths);
  });

  test('a cel without photos names none, and its head ends where its '
      'stream begins', () {
    final blob = AnicelCelBlob.ofSurface(key, drawingOf({a: ink}));

    expect(blob.photoPaths, isEmpty);
    expect(
      AnicelCelBlob.headerLengthOf(blob.bytes),
      lessThan(blob.bytes.length),
    );
  });

  test('🚨the head says how long it is, index and all: one read short of it '
      'is read again, and then names every file', () {
    final paths = [
      for (var index = 0; index < 60; index += 1)
        'C:/pool/${'a folder deep down/' * 6}photo $index.png',
    ];
    final picture = drawingOf({a: ink}).withPhotos([
      for (final (index, path) in paths.indexed) photoOf(index + 1, path: path),
    ]);
    final blob = AnicelCelBlob.ofSurface(key, picture);
    final first = Uint8List.sublistView(blob.bytes, 0, 4096);

    final length = AnicelCelBlob.headerLengthOf(first);

    expect(
      length,
      greaterThan(first.length),
      reason: '⛔fixture: the head outgrows a first read',
    );
    expect(
      AnicelCelBlob(Uint8List.sublistView(blob.bytes, 0, length)).photoPaths,
      paths,
    );
  });

  test('a head\'s index never stands in for the photos — a decode reads '
      'them off the stream', () {
    final picture = drawingOf({
      a: ink,
    }).withPhotos([photoOf(1, path: 'C:/pool/a.png')]);
    final compressed = compressAnicelPayload(
      encodeCelEntryFromSurface(key, picture),
    );
    final blob = AnicelCelBlob.fromCompressedBody(
      key: key,
      canvasSize: picture.canvasSize,
      tileSize: picture.tileSize,
      photoPaths: const ['C:/pool/elsewhere.png'],
      showsSomething: true,
      codec: compressed.codec,
      body: compressed.bytes,
    );

    expect(
      blob.photoPaths,
      ['C:/pool/elsewhere.png'],
      reason: 'the CONTROL — the head says what it was handed',
    );
    expect(blob.decode().toSurface().photos, picture.photos);
  });

  test('🚨a re-keyed cel keeps its index: the stream it splices through '
      'still names those files', () {
    final picture = drawingOf({
      a: ink,
    }).withPhotos([photoOf(1, path: 'C:/pool/a.png')]);
    final blob = AnicelCelBlob.ofSurface(key, picture);
    final elsewhere = BrushFrameKey(
      projectId: key.projectId,
      trackId: key.trackId,
      cutId: const CutId('elsewhere'),
      layerId: key.layerId,
      frameId: key.frameId,
    );

    final moved = AnicelCelBlob.reKeyed(blob, elsewhere);

    expect(moved.key, elsewhere, reason: 'the CONTROL — it was re-keyed');
    expect(moved.photoPaths, ['C:/pool/a.png']);
    expect(AnicelCelBlob(moved.bytes).photoPaths, ['C:/pool/a.png']);
    expect(moved.decode().toSurface().photos, picture.photos);
  });
}
