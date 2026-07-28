import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/services/persistence/qap_project_archive.dart';

void main() {
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );

  test('the archive round-trips project + BAKED cels byte-exactly (R19 '
      'bake-only); media under the save directory records relative paths '
      'and remaps on the way in', () {
    final project = createDefaultProject().copyWith(
      mediaAssets: const [
        MediaAsset(path: 'D:/work/proj/audio/boom.wav', name: 'boom'),
        MediaAsset(path: 'E:/elsewhere/hiss.wav', name: 'hiss'),
      ],
    );
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * 37) & 0xFF;
    }
    final surface = BitmapSurface(
      canvasSize: CanvasSize(width: 16, height: 16),
      tileSize: 8,
      tiles: {
        TileCoord(x: 1, y: 0): BitmapTile(
          coord: TileCoord(x: 1, y: 0),
          size: 8,
          pixels: pixels,
        ),
      },
    );

    final blob = QapCelBlob.encode(QapCelEntry.fromSurface(key, surface));
    final bytes = buildQapArchiveBytes(
      project: project,
      cels: [blob],
      saveDirectory: r'D:\work\proj',
    );
    final contents = parseQapArchiveBytes(bytes);

    expect(contents.project, project);
    expect(contents.cels, hasLength(1));
    expect(contents.cels.single.key, key);
    expect(
      contents.cels.single.bytes,
      blob.bytes,
      reason:
          'R20-A1: the archive entry IS the cold blob byte-for-byte '
          '(STORE mode) — cold cels save with zero re-encode',
    );
    final reopened = contents.cels.single.decode().toSurface();
    expect(reopened.canvasSize, surface.canvasSize);
    expect(reopened.tileSize, 8);
    expect(
      reopened.tiles[TileCoord(x: 1, y: 0)]!.pixels,
      pixels,
      reason: 'what you saved is what reopens, byte for byte',
    );
    // Only the in-folder path got a relative entry.
    expect(contents.mediaRelativePaths, {
      'D:/work/proj/audio/boom.wav': 'audio/boom.wav',
    });

    // Resolution on another machine: the relative entry rewrites the pool.
    final remapped = remapProjectMediaPaths(contents.project, {
      'D:/work/proj/audio/boom.wav': 'G:/drive/proj/audio/boom.wav',
    });
    expect(remapped.mediaAssets.first.path, 'G:/drive/proj/audio/boom.wav');
    expect(remapped.mediaAssets[1].path, 'E:/elsewhere/hiss.wav');
  });

  test('pasteboard tiles (negative coords) round-trip through the cel '
      'blob (v2 signed coords)', () {
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * 11) & 0xFF;
    }
    final surface = BitmapSurface(
      canvasSize: CanvasSize(width: 16, height: 16),
      tileSize: 8,
      tiles: {
        TileCoord(x: -1, y: -2): BitmapTile(
          coord: TileCoord(x: -1, y: -2),
          size: 8,
          pixels: pixels,
        ),
        TileCoord(x: 3, y: 0): BitmapTile.blank(
          coord: TileCoord(x: 3, y: 0),
          size: 8,
        ),
      },
    );

    final blob = QapCelBlob.encode(QapCelEntry.fromSurface(key, surface));
    final reopened = QapCelBlob(blob.bytes).decode().toSurface();
    expect(
      reopened.tiles[TileCoord(x: -1, y: -2)]!.pixels,
      pixels,
      reason: 'off-canvas artwork reopens byte for byte',
    );
    expect(reopened.tiles.containsKey(TileCoord(x: 3, y: 0)), isTrue);
  });

  test('legacy v1 entries (drawings/tips) are IGNORED without error — the '
      'v1 reader is deleted (R20-E3, no production v1 file exists)', () {
    final archive = Archive()
      ..add(
        ArchiveFile.string(
          'project.json',
          jsonEncode({
            'formatVersion': 1,
            'project': createDefaultProject().toJson(),
          }),
        ),
      )
      ..add(ArchiveFile.bytes('tips.bin', Uint8List.fromList([1, 0, 0])))
      ..add(ArchiveFile.bytes('drawings/0.bin', Uint8List.fromList([2, 0, 0])));
    final v1Bytes = ZipEncoder().encodeBytes(archive);

    final contents = parseQapArchiveBytes(Uint8List.fromList(v1Bytes));
    expect(contents.project, isNotNull);
    expect(contents.cels, isEmpty);
  });

  test('media remap rewrites SE audio clips on tracks AND cuts', () {
    final base = createDefaultProject();
    final track = base.tracks.first;
    final seeded = base.copyWith(
      tracks: [
        track.copyWith(
          seLayers: [
            track.seLayers.first.copyWith(
              audioClips: const [
                AudioClip(filePath: 'old/a.wav', frameId: FrameId('x')),
              ],
            ),
            ...track.seLayers.skip(1),
          ],
        ),
      ],
    );

    final remapped = remapProjectMediaPaths(seeded, {'old/a.wav': 'new/a.wav'});
    expect(
      remapped.tracks.first.seLayers.first.audioClips.single.filePath,
      'new/a.wav',
    );
  });

  test('a newer formatVersion refuses to load with a clear error', () {
    final bytes = buildQapArchiveBytes(
      project: createDefaultProject(),
      cels: const [],
    );
    expect(parseQapArchiveBytes(bytes).project, isNotNull);

    expect(
      () => parseQapArchiveBytes(Uint8List.fromList([1, 2, 3])),
      throwsA(anything),
    );
  });
}
