import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🔑 THE LAW: **a recovery overlay's `project.json` must carry everything
/// a save's would.**
///
/// The overlay replaces the base file's `project.json` OUTRIGHT when a
/// project is recovered, so anything the snapshot leaves out is a thing
/// the recovered session believes does not exist. And a recovered session
/// is dirty by construction — it saves almost immediately — so whatever it
/// believes gets written back over the real file.
///
/// That has now cost two separate data-loss bugs, both the same shape and
/// both a parameter quietly taking its default:
///
/// - the overlay was written without `grants`, so recovering stripped the
///   security-scoped bookmarks and every referenced movie was refused at
///   the next launch;
/// - then without `mediaEntries`, so a recovered session did not know its
///   own audio was inside the archive, fell back to an import path that
///   the user had deleted (which is what carrying it in permits), and
///   saved an archive that no longer held it.
///
/// Fixing each one in turn does not stop the third. This file states the
/// property instead: whatever keys a SAVE writes, an overlay writes too.
/// A new field added to `buildAnicelProjectJsonBytes` fails here until
/// somebody decides what it means for a snapshot.
void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('qa-overlay-parity-');
  });

  tearDown(() {
    try {
      directory.deleteSync(recursive: true);
    } on Object {
      // Windows handles.
    }
  });

  EditorSessionManager session() => EditorSessionManager(
    initialProject: createDefaultProject(),
    audioConformStore: AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async => const ConformResult(
        outcome: ConformOutcome.undecodable,
        error: 'test stub',
      ),
      log: (_) {},
    ),
  );

  Map<String, dynamic> projectJsonOf(String archivePath) {
    final archive = ZipDecoder().decodeBytes(
      File(archivePath).readAsBytesSync(),
    );
    final entry = archive.findFile(anicelProjectEntryNameCompressed);
    expect(entry, isNotNull, reason: '$archivePath has a project manifest');
    return jsonDecode(
          utf8.decode(
            decodeAnicelProjectEntryBytes(entry!.name, entry.readBytes()!),
          ),
        )
        as Map<String, dynamic>;
  }

  /// A project that exercises every sidecar fact at once: audio carried
  /// INSIDE the archive, a movie left outside as a reference, and a grant
  /// for that reference.
  Future<(String project, String overlay)> loadedProject() async {
    final s = session();
    File('${directory.path}/대사.wav')
      ..createSync()
      ..writeAsBytesSync(List<int>.filled(256, 3));
    File('${directory.path}/참고영상.mp4')
      ..createSync()
      ..writeAsBytesSync([0, 0, 0, 24]);
    s.importMediaFiles([
      '${directory.path}/대사.wav',
    ], copyIntoProject: true);
    s.importMediaFiles([
      '${directory.path}/참고영상.mp4',
    ], copyIntoProject: false);
    s.rememberMediaGrants([
      FolderGrant.granted(
        path: '${directory.path}/참고영상.mp4'.replaceAll('\\', '/'),
        bookmark: 'Ym9va21hcms=',
        kind: GrantKind.file,
      ),
    ]);
    // ⚠️ Every sidecar fact has to be PRESENT in the fixture or this file
    // guards nothing. `mediaCrcs` was added to the writer and these tests
    // stayed green, because a project with no fingerprints writes no
    // fingerprint key and the pinned set still matched. The law can only
    // catch an omission it can see, so each new fact earns a line here.
    s.rememberMediaFingerprint(
      '${directory.path}/참고영상.mp4'.replaceAll('\\', '/'),
      File('${directory.path}/참고영상.mp4').readAsBytesSync(),
    );
    final projectPath = '${directory.path}/scene.anicel';
    await s.saveProjectToFile(projectPath);
    final overlayPath = '${directory.path}/scene.overlay';
    await s.writeAutosaveSnapshot(overlayPath);
    s.dispose();
    return (projectPath, overlayPath);
  }

  test('🚨 every key a SAVE writes, an OVERLAY writes too', () async {
    final (projectPath, overlayPath) = await loadedProject();
    final saved = projectJsonOf(projectPath);
    final overlay = projectJsonOf(overlayPath);

    // `mediaPaths` is the one exception, and it is not an omission: it
    // records where media sits RELATIVE to the file, and the overlay sits
    // somewhere else entirely. Everything else describes the project and
    // must survive the swap.
    final expected = saved.keys.where((key) => key != 'mediaPaths').toSet();
    expect(
      overlay.keys.toSet(),
      containsAll(expected),
      reason: 'the overlay replaces this file\'s project.json outright, so '
          'a key it omits is a fact the recovered session loses — and it '
          'saves that belief back over the real file',
    );
  });

  test('🚨 and the VALUES match, not just the key names', () async {
    // Key parity alone would pass on an empty list. Both bugs this file
    // exists for wrote the key and left it empty, or wrote nothing at all.
    final (projectPath, overlayPath) = await loadedProject();
    final saved = projectJsonOf(projectPath);
    final overlay = projectJsonOf(overlayPath);

    expect(overlay['mediaEntries'], saved['mediaEntries']);
    expect(overlay['mediaEntries'], isNotEmpty, reason: 'the fixture carries');
    expect(overlay['grants'], saved['grants']);
    expect(overlay['grants'], isNotEmpty, reason: 'the fixture has one');
    expect(overlay['mediaCrcs'], saved['mediaCrcs']);
    expect(
      overlay['mediaCrcs'],
      isNotEmpty,
      reason: 'the fixture recorded one — without that this asserts nothing',
    );
  });

  test('⛔ the writer has not grown a key nobody has thought about', () async {
    // The generalizing half. When someone adds a field to
    // `buildAnicelProjectJsonBytes`, this fails and they have to decide
    // whether a snapshot needs it — instead of it defaulting quietly at
    // the overlay call site, which is how both previous bugs happened.
    final (projectPath, _) = await loadedProject();
    expect(
      projectJsonOf(projectPath).keys.toSet(),
      {
        'formatVersion',
        'project',
        'mediaPaths',
        'mediaEntries',
        'grants',
        'mediaCrcs',
      },
      reason: 'a new top-level key is a decision for the overlay too — add '
          'it here once the snapshot handles it',
    );
  });

  test('🚨 the aux ink namespaces (conte row, conte page, envelope) ride '
      'the overlay', () async {
    // The same law one namespace over. Cels are not project.json keys, so
    // the parity tests above cannot see them — and before this test,
    // deleting the `auxCelStores` argument at the snapshot call site kept
    // every suite green while crash recovery silently lost all timesheet
    // and envelope handwriting drawn since the last save.
    BitmapSurface inkSurface({int seed = 1}) {
      final pixels = Uint8List(8 * 8 * 4);
      for (var i = 0; i < pixels.length; i += 1) {
        pixels[i] = (i * seed * 13 + seed) & 0xFF;
      }
      return BitmapSurface(
        canvasSize: const CanvasSize(width: 16, height: 16),
        tileSize: 8,
        tiles: {
          TileCoord(x: 0, y: 0): BitmapTile(
            coord: TileCoord(x: 0, y: 0),
            size: 8,
            pixels: pixels,
          ),
        },
      );
    }

    // Graft a real storyboard block so the row-plane key survives the
    // open's "ink dies with the drawing" prune.
    Project project = createDefaultProject();
    final track = project.tracks.first;
    final baseCut = track.cuts.first;
    project = project.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            baseCut.copyWith(
              layers: [
                baseCut.layers.first.copyWith(
                  frames: [
                    Frame(
                      id: const FrameId('sb-f1'),
                      duration: 8,
                      strokes: const [],
                    ),
                  ],
                  timeline: {
                    0: const TimelineExposure.drawing(
                      FrameId('sb-f1'),
                      length: 8,
                    ),
                  },
                ),
                ...baseCut.layers.skip(1),
              ],
            ),
          ],
        ),
      ],
    );
    final s = EditorSessionManager(initialProject: project);
    final projectPath = '${directory.path.replaceAll('\\', '/')}/ink.anicel';
    await s.saveProjectToFile(projectPath);

    // Drawn AFTER the save, so only the overlay can be holding it.
    final cutId = s.requireActiveCut.id;
    final rowKey = conteInkRowKey(cutId, const FrameId('sb-f1'));
    final pageKey = conteInkPageKey(0);
    final envelopeKey = envelopeInkBoxKey(cutId, 'cel-row-3');
    s.conteInkRowStore.storeBakedSurface(rowKey, inkSurface(seed: 3));
    s.conteInkPageStore.storeBakedSurface(pageKey, inkSurface(seed: 4));
    s.envelopeInkStore.storeBakedSurface(envelopeKey, inkSurface(seed: 5));
    final overlayPath = '${directory.path.replaceAll('\\', '/')}/ink.overlay';
    await s.writeAutosaveSnapshot(overlayPath);
    s.dispose();

    final restored = session();
    addTearDown(restored.dispose);
    await restored.openProjectFromFile(projectPath, overlayPath: overlayPath);
    expect(
      restored.conteInkRowStore.celHasRenderableContent(rowKey),
      isTrue,
      reason: 'the conte row plane rides the overlay',
    );
    expect(
      restored.conteInkPageStore.celHasRenderableContent(pageKey),
      isTrue,
      reason: 'the conte page plane rides the overlay',
    );
    expect(
      restored.envelopeInkStore.celHasRenderableContent(envelopeKey),
      isTrue,
      reason: 'the envelope sheet rides the overlay',
    );
  });
}
