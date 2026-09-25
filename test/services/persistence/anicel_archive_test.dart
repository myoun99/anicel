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
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';

void main() {
  _manifestCompression();
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
      mediaAssets: [
        MediaAsset(path: 'D:/work/proj/audio/boom.wav', name: 'boom'),
        MediaAsset(path: 'E:/elsewhere/hiss.wav', name: 'hiss'),
      ],
    );
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * 37) & 0xFF;
    }
    final surface = BitmapSurface(
      canvasSize: const CanvasSize(width: 16, height: 16),
      tileSize: 8,
      tiles: {
        TileCoord(x: 1, y: 0): BitmapTile(
          size: 8,
          pixels: pixels,
        ),
      },
    );

    final blob = AnicelCelBlob.encode(AnicelCelEntry.fromSurface(key, surface));
    final bytes = buildAnicelArchiveBytes(
      project: project,
      cels: [blob],
      saveDirectory: r'D:\work\proj',
    );
    final contents = parseAnicelArchiveBytes(bytes);

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
      canvasSize: const CanvasSize(width: 16, height: 16),
      tileSize: 8,
      tiles: {
        TileCoord(x: -1, y: -2): BitmapTile(
          size: 8,
          pixels: pixels,
        ),
        TileCoord(x: 3, y: 0): BitmapTile.blank(
          size: 8,
        ),
      },
    );

    final blob = AnicelCelBlob.encode(AnicelCelEntry.fromSurface(key, surface));
    final reopened = AnicelCelBlob(blob.bytes).decode().toSurface();
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

    final contents = parseAnicelArchiveBytes(Uint8List.fromList(v1Bytes));
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
              audioClips: [
                AudioClip(filePath: 'old/a.wav', frameId: const FrameId('x')),
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
    final bytes = buildAnicelArchiveBytes(
      project: createDefaultProject(),
      cels: const [],
    );
    expect(parseAnicelArchiveBytes(bytes).project, isNotNull);

    expect(
      () => decodeAnicelProjectDocument(
        utf8.encode(
          jsonEncode({
            'formatVersion': anicelFormatVersion + 1,
            'project': createDefaultProject().toJson(),
          }),
        ),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('newer Anicel'),
        ),
      ),
      reason:
          'what a build does not understand it must not open and save '
          'back shortened',
    );
    expect(
      () => parseAnicelArchiveBytes(Uint8List.fromList([1, 2, 3])),
      throwsA(anything),
    );
  });

  test('🚨a build that reads version 3 refuses what this one writes — a '
      'carry\'s name is the whole name now', () {
    final archive = ZipDecoder().decodeBytes(
      buildAnicelArchiveBytes(project: createDefaultProject(), cels: const []),
    );
    final entry = archive.find(anicelProjectEntryNameCompressed)!;
    final written =
        jsonDecode(
              utf8.decode(
                decodeAnicelProjectEntryBytes(entry.name, entry.readBytes()!),
              ),
            )
            as Map<String, dynamic>;

    expect(
      written['formatVersion'],
      greaterThan(3),
      reason:
          'a v3 build reads `carriedAs` as a bare token and finds none of '
          'the carried bytes — it must refuse the file, not open it without '
          'them and save it back that way (audit 09-25)',
    );
  });
}

/// The project manifest is compressed, and an old uncompressed one still
/// opens — 유저 2026-08-29 asked for「압축한게 좋은것들」 compressed even
/// where the number is small, and this is the one that grows with the film
/// (`anicel_file_service` notes it「can be megabytes」).
void _manifestCompression() {
  test('🚨the manifest entry is COMPRESSED, and it is much smaller', () {
    final project = createDefaultProject();
    final bytes = buildAnicelArchiveBytes(project: project, cels: const []);
    final archive = ZipDecoder().decodeBytes(bytes);

    final entry = archive.find(anicelProjectEntryNameCompressed);
    expect(entry, isNotNull, reason: 'the save writes the compressed name');
    expect(
      archive.find(anicelProjectEntryName),
      isNull,
      reason: 'and not both — one manifest, or a reader has to pick',
    );

    final raw = buildAnicelProjectJsonBytes(project: project);
    expect(
      entry!.readBytes()!.length,
      lessThan(raw.length),
      reason: 'JSON deflates; measured ~14× on a real project',
    );
  });

  test('🚨an OLD archive — uncompressed manifest — still parses', () {
    final project = createDefaultProject();
    final legacy = Archive()
      ..add(
        ArchiveFile.bytes(
          anicelProjectEntryName,
          buildAnicelProjectJsonBytes(project: project),
        )..compression = CompressionType.none,
      );
    final contents = parseAnicelArchiveBytes(
      Uint8List.fromList(ZipEncoder().encodeBytes(legacy)),
    );
    expect(contents.project.name, project.name);
  });
}
