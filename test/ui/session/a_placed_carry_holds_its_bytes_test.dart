import 'dart:io';
import 'dart:ui' as ui show Size;

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_pdf_document.dart';
import '../../helpers/fake_video_backend.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/psd_fixture.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★**A FILE PLACED WITH KEEP IS HELD FROM THAT MOMENT — BY EVERY DOOR.**
///
/// 유저 2026-08-30: 「품은 순간 데이터를 가지고있고 불변이었으면좋겠어서」.
/// The pool's own registration kept that promise
/// (`carried_media_survives_the_original_test`); the five doors a
/// PLACEMENT goes through did not, from the day staging landed until
/// 2026-09-23 — they recorded the asset carried and left its bytes where
/// they lay, so a placed file edited or deleted before the first save was
/// saved as it was THEN. Every door, both answers: Keep holds the bytes
/// the moment the placement lands, and the original can go; Link holds
/// nothing, because a second copy nobody asked for is the other failure.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-placed-carry');
  });

  tearDown(() {
    PdfRenderService.debugResetForTests();
    debugVideoDecodeBackend = null;
    deleteTempQuietly(tempDir);
  });

  String inTemp(String name) => '${tempDir.path}${Platform.pathSeparator}$name';

  /// A file of [name] holding [bytes] — what a door with a stand-in reader
  /// is handed, and what its staged copy has to equal.
  String writeBytes(String name, List<int> bytes) {
    final path = inTemp(name);
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  /// Three frames, one pixel each: black · white · black.
  List<int> gifBytes() {
    List<int> frame(int lzw) => [
      0x21, 0xF9, 0x04, 0x00, 0x0A, 0x00, 0x00, 0x00,
      0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
      0x02, 0x02, lzw, 0x01, 0x00,
    ];
    return [
      ...'GIF89a'.codeUnits,
      0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00,
      0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF,
      ...frame(0x44), ...frame(0x4C), ...frame(0x44),
      0x3B,
    ];
  }

  /// Every door a placement goes through: how its file is written, and how
  /// it is placed, kept inside or linked.
  final doors = <({
    String name,
    Future<String> Function() write,
    Future<bool> Function(EditorSessionManager s, String path, bool keep)
    place,
  })>[
    (
      name: 'a still',
      write: () => writeSolidPng(tempDir, 'bg.png', rgba: 0x336699FF),
      place: (s, path, keep) => s.importDoors.importImageFile(
        path: path,
        destination: ImportDestination.activeCutLayer,
        copyIntoProject: keep,
      ),
    ),
    (
      name: 'an animation',
      write: () async => writeBytes('walk.gif', gifBytes()),
      place: (s, path, keep) => s.importDoors.importImageFile(
        path: path,
        destination: ImportDestination.activeCutLayer,
        copyIntoProject: keep,
      ),
    ),
    (
      name: 'a PDF',
      write: () async {
        PdfRenderService.debugOpenerOverride = (_) async =>
            FakePdfDocument(pageSizes: const [ui.Size(8, 8), ui.Size(8, 8)]);
        return writeBytes('conte.pdf', '%PDF-1.4 two pages'.codeUnits);
      },
      place: (s, path, keep) => s.importDoors.importPdfFile(
        path: path,
        destination: ImportDestination.activeCutLayer,
        copyIntoProject: keep,
      ),
    ),
    (
      name: 'an expanded PSD',
      write: () async => writeBytes(
        'bg.psd',
        buildPsd(
          width: 8,
          height: 8,
          layers: [
            PsdTestLayer(
              name: 'bg',
              left: 0,
              top: 0,
              right: 8,
              bottom: 8,
              planes: psdSolidPlanes(8, 8, [10, 20, 30]),
            ),
          ],
        ),
      ),
      place: (s, path, keep) async =>
          await s.importDoors.importPsdExpanded(
            path: path,
            destination: ImportDestination.activeCutLayer,
            copyIntoProject: keep,
          ) !=
          null,
    ),
    (
      name: 'a movie',
      write: () async {
        debugVideoDecodeBackend = FakeVideoBackend(frameCount: 4);
        return writeBytes('take.mp4', List<int>.generate(4096, (i) => i));
      },
      place: (s, path, keep) => s.importDoors.importVideoFile(
        path: path,
        settings: ImportFileSettings(
          mode: keep ? ImportFileMode.keepInside : ImportFileMode.reference,
          sound: false,
        ),
      ),
    ),
    (
      name: 'a sound',
      write: () async =>
          writeBytes('line.wav', List<int>.generate(4096, (i) => i * 7)),
      place: (s, path, keep) =>
          s.importDoors.importSoundFile(path: path, copyIntoProject: keep),
    ),
  ];

  EditorSessionManager session() {
    final s = EditorSessionManager(
      initialProject: createDefaultProject(),
      mediaStagingStore: MediaStagingStore(
        directoryPath: '${tempDir.path}/Staged',
      ),
      // A sound's length, answered without the isolate a widget test
      // cannot run.
      audioConformStore: soundConformStore(),
    );
    addTearDown(s.dispose);
    return s;
  }

  for (final door in doors) {
    testWidgets('🚨${door.name} placed with Keep is held the moment it lands '
        '— the original can go and the bytes stay', (tester) async {
      final s = session();
      final path = normalizedMediaPath((await tester.runAsync(door.write))!);
      final original = File(path).readAsBytesSync();

      final landed = await tester.runAsync(() => door.place(s, path, true));

      expect(landed, isTrue);
      expect(
        s.repository.requireProject().mediaAssetByPath(path)?.carried,
        isTrue,
        reason: 'the premise: the pool records it carried',
      );
      final staged = s.mediaStagingStore.find(path);
      expect(staged, isNotNull, reason: '「품은 순간」 — not at the save');
      File(path).deleteSync();
      final held = MediaAppFileBytes(path: staged!.path, framed: staged.framed);
      final bytes = await tester.runAsync(
        () async => staged.framed
            ? MediaFramedBytes(held).readSync()
            : held.readSync(),
      );
      expect(bytes, original, reason: 'what was placed, byte for byte');
      await tester.pumpAndSettle();
    });

    testWidgets('⛔${door.name} placed as a Link holds nothing', (
      tester,
    ) async {
      final s = session();
      final path = normalizedMediaPath((await tester.runAsync(door.write))!);

      final landed = await tester.runAsync(() => door.place(s, path, false));

      expect(landed, isTrue);
      expect(
        s.mediaStagingStore.find(path),
        isNull,
        reason: 'the user said keep the link — a copy anyway is a second '
            'copy nobody asked for',
      );
      await tester.pumpAndSettle();
    });
  }
}
