import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';

/// 🚨★★★**THE POOL IS KEYED BY PATH, AND A PATH HAS ONE SPELLING** — given
/// by the models themselves, whatever door the path came by (audit
/// 2026-09-24, card `carried-bytes-audit-0924` ②).
///
/// It used to be each door's job. The cut folder's door did not do it, so
/// its scans went into the pool as `C:\…\cut/A1.png`; the project's own
/// copy of one, asked for in the pool's spelling, was not found, and the
/// file on disk was read instead.
void main() {
  const os = r'C:\cuts\csm_13_069\A1.png';
  const pool = 'C:/cuts/csm_13_069/A1.png';

  test('a pool entry, a row\'s reference and a sound each spell the path the '
      'one way', () {
    expect(MediaAsset(path: os, name: 'A1').path, pool);
    expect(MediaReference(assetPath: os).assetPath, pool);
    expect(
      AudioClip(filePath: os, frameId: const FrameId('f')).filePath,
      pool,
    );
  });

  test('and keep spelling it through a copy and through a file', () {
    final asset = MediaAsset(path: pool, name: 'A1');
    expect(asset.copyWith(path: os).path, pool);
    expect(MediaAsset.fromJson({...asset.toJson(), 'path': os}).path, pool);
    expect(MediaReference.fromJson({'path': os}).assetPath, pool);
    final clip = AudioClip(filePath: pool, frameId: const FrameId('f'));
    expect(clip.copyWith(filePath: os).filePath, pool);
    expect(AudioClip.fromJson({...clip.toJson(), 'file': os}).filePath, pool);
  });

  test('a question asked by path, in either spelling, finds the entry', () {
    final project = createDefaultProject().copyWith(
      mediaAssets: [MediaAsset(path: pool, name: 'A1')],
    );
    expect(project.mediaAssetByPath(os)?.path, pool);
    expect(project.mediaAssetByPath(pool)?.path, pool);
  });

  test('a file that recorded another spelling names the same entries the '
      'pool now asks for', () {
    final project = createDefaultProject().copyWith(
      mediaAssets: [MediaAsset(path: pool, name: 'A1', carriedAs: 'c1')],
    );
    final json = project.toJson();
    final assets = json['mediaAssets'] as List;
    assets[0] = {...assets[0] as Map<String, dynamic>, 'path': os};

    final document = decodeAnicelProjectDocument(
      utf8.encode(
        jsonEncode({
          'formatVersion': anicelFormatVersion,
          'project': json,
          'mediaEntries': {os: 'media/0a1b2c3d-A1.png'},
          'mediaPaths': {os: 'A1.png'},
        }),
      ),
    );

    expect(document.project.mediaAssets.single.path, pool);
    expect(document.mediaEntryNames, {pool: 'media/0a1b2c3d-A1.png'});
    expect(document.mediaRelativePaths, {pool: 'A1.png'});
  });
}
