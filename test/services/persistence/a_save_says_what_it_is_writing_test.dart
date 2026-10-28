import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_asset.dart' show MediaCarry;
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/media/project_font_sources.dart';
import 'package:anicel/src/services/media/project_media_sources.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/services/persistence/save_stretch.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/carried_media_fixture.dart' show noise;
import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/wait_window.dart' show expectOneBar;
import '../../helpers/whole_carry.dart';

/// Everything a save told, in order: a [SaveStretch] as it moved on, a
/// `double` for each fraction.
typedef Told = List<Object>;

/// 🗣️F-494 (유저 2026-10-28): 「저장같은것도 저장중 말고 어차피 창의 제목에
/// 저장이라고 있으니까 셀을 저장? … 하고있는 과정을 보여주는식으로」.
///
/// A save says WHAT it is writing as it moves on — a [SaveStretch], told
/// across the writing isolate's port beside the fraction — and each one is
/// told before the reports of its own work, so the window's line is never
/// a stretch behind the bar.
void main() {
  // A session warms playback's rows in the quiet a test leaves it, and a
  // row asks the binding for the quiet it takes its turn in.
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-save-stretch');
  });

  tearDown(() => deleteTempQuietly(directory));

  String inTemp(String name) =>
      '${directory.path.replaceAll('\\', '/')}/$name';

  /// Bytes that do not compress, so a carried file streams as itself.
  String writeIncompressible(String name, int length) {
    File(inTemp(name)).writeAsBytesSync(noise(length), flush: true);
    return inTemp(name);
  }

  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  BitmapSurface inked(int seed) => BitmapSurface(
    canvasSize: const CanvasSize(width: 16, height: 16),
    tileSize: 8,
    tiles: {
      TileCoord(x: 0, y: 0): BitmapTile(
        size: 8,
        pixels: Uint8List.fromList([
          for (var i = 0; i < 8 * 8 * 4; i += 1) (i * seed * 31 + seed) & 0xFF,
        ]),
      ),
    },
  );

  /// What a save hands over beside its cels: one of each kind it carries —
  /// a medium, a sound converted for playback and a font — each big enough
  /// to be read in several chunks.
  ({
    Map<MediaCarry, MediaByteSource> media,
    ProjectConforms conforms,
    ProjectFontsToStore fonts,
  })
  oneOfEachKind(String tag) {
    final sound = writeIncompressible('$tag.wav', 600 * 1024);
    final conform = writeIncompressible('$tag.conform', 600 * 1024);
    final font = writeIncompressible('$tag.ttf', 600 * 1024);
    final fontEntry = anicelFontEntryName('$tag-font.ttf');
    return (
      media: {wholeCarry(sound, tag): MediaFileBytes(sound)},
      conforms: ProjectConforms({
        anicelConformEntryName(
          sound,
          sampleRate: 48000,
          speedNumerator: 1,
          speedDenominator: 1,
        ): MediaFileBytes(
          conform,
        ),
      }),
      fonts: ProjectFontsToStore(
        held: {fontEntry},
        entries: {fontEntry: MediaFileBytes(font)},
      ),
    );
  }

  List<SaveStretch> stretchesIn(Told told) => [
    for (final said in told)
      if (said is SaveStretch) said,
  ];

  /// Whether every stretch in [told] was followed by a report of its own
  /// before the next one — it named the work it then counted.
  void expectEachStretchCounted(Told told) {
    for (var i = 0; i < told.length; i += 1) {
      if (told[i] is! SaveStretch) {
        continue;
      }
      final next = told.indexWhere((said) => said is SaveStretch, i + 1);
      final own = told.sublist(i + 1, next < 0 ? told.length : next);
      expect(
        own.whereType<double>(),
        isNotEmpty,
        reason: '${told[i]} was named and then counted nothing: $told',
      );
    }
  }

  group('the writer names each stretch as it moves on', () {
    test('🎯a whole write: the cels, then the media, the sounds converted '
        'for playback and the fonts, in the order they are written', () async {
      final carried = oneOfEachKind('whole');
      final told = <Object>[];
      await const AnicelFileService().save(
        project: createDefaultProject(),
        brushFrameStore: BrushFrameStore()
          ..storeBakedSurface(key('f1'), inked(3)),
        filePath: inTemp('whole.anicel'),
        mediaToStore: carried.media,
        conforms: carried.conforms,
        fonts: carried.fonts,
        onProgress: told.add,
        onStretch: told.add,
      );

      expect(stretchesIn(told), [
        SaveStretch.cels,
        SaveStretch.media,
        SaveStretch.conforms,
        SaveStretch.fonts,
      ]);
      expectEachStretchCounted(told);
    });

    test('🎯an append checks everything it carries before writing any of '
        'it, and then writes each kind in its own stretch', () async {
      final store = BrushFrameStore()..storeBakedSurface(key('f1'), inked(3));
      final path = inTemp('append.anicel');
      const service = AnicelFileService();
      await service.save(
        project: createDefaultProject(),
        brushFrameStore: store,
        filePath: path,
      );
      store.storeBakedSurface(key('f2'), inked(5));
      final carried = oneOfEachKind('append');
      final told = <Object>[];
      await service.save(
        project: createDefaultProject(),
        brushFrameStore: store,
        filePath: path,
        mediaToStore: carried.media,
        conforms: carried.conforms,
        fonts: carried.fonts,
        onProgress: told.add,
        onStretch: told.add,
      );

      expect(stretchesIn(told), [
        SaveStretch.cels,
        SaveStretch.checking,
        SaveStretch.media,
        SaveStretch.conforms,
        SaveStretch.fonts,
      ]);
      expectEachStretchCounted(told);
    });

    test('a save with no cel to write never says it writes cels', () async {
      final store = BrushFrameStore()..storeBakedSurface(key('f1'), inked(3));
      final path = inTemp('clean.anicel');
      const service = AnicelFileService();
      await service.save(
        project: createDefaultProject(),
        brushFrameStore: store,
        filePath: path,
      );
      final carried = oneOfEachKind('clean');
      final told = <Object>[];
      await service.save(
        project: createDefaultProject(),
        brushFrameStore: store,
        filePath: path,
        mediaToStore: carried.media,
        onStretch: told.add,
      );

      expect(stretchesIn(told), [SaveStretch.checking, SaveStretch.media]);
    });

    test('🎯the save that drops what it carried packs the file, and says '
        'so', () async {
      final store = BrushFrameStore()..storeBakedSurface(key('f1'), inked(3));
      final path = inTemp('drop.anicel');
      const service = AnicelFileService();
      final carried = oneOfEachKind('drop');
      await service.save(
        project: createDefaultProject(),
        brushFrameStore: store,
        filePath: path,
        mediaToStore: carried.media,
      );
      final told = <Object>[];
      await service.save(
        project: createDefaultProject(),
        brushFrameStore: store,
        filePath: path,
        onProgress: told.add,
        onStretch: told.add,
      );

      expect(stretchesIn(told), [SaveStretch.compacting]);
      expectEachStretchCounted(told);
    });

    test('🚨a save watched for its stretches alone still hears them — the '
        'port opens for them as it does for the bar', () async {
      final store = BrushFrameStore()..storeBakedSurface(key('f1'), inked(3));
      final path = inTemp('alone.anicel');
      const service = AnicelFileService();
      final whole = <SaveStretch>[];
      await service.save(
        project: createDefaultProject(),
        brushFrameStore: store,
        filePath: path,
        onStretch: whole.add,
      );
      store.storeBakedSurface(key('f2'), inked(5));
      final appended = <SaveStretch>[];
      await service.save(
        project: createDefaultProject(),
        brushFrameStore: store,
        filePath: path,
        onStretch: appended.add,
      );

      expect(whole, [SaveStretch.cels], reason: 'the whole write');
      expect(appended, [SaveStretch.cels], reason: 'the append');
    });
  });

  group('the door names what it does around the write', () {
    EditorSessionManager session() {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      return s;
    }

    test('🎯a save that takes a carried file out of the project sets it '
        'aside first, and says so before the write names its own', () async {
      final s = session();
      drawOnCurrentFrame(s);
      final sound = writeIncompressible('대사.wav', 600 * 1024);
      await s.mediaPool.importMediaFiles([sound], copyIntoProject: true);
      final path = inTemp('scene.anicel');
      await s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);
      s.mediaPool.removeMediaAsset(sound);
      final told = <Object>[];

      await s.projectDoor.saveProjectToFile(
        path,
        asked: SaveAsked.byAPerson,
        onProgress: told.add,
        onStretch: told.add,
      );

      expect(
        stretchesIn(told),
        [SaveStretch.keepingLeftBehind, SaveStretch.compacting],
      );
      expectEachStretchCounted(told);
      // The copy its share of the bar, the write the rest — one bar.
      expectOneBar(told.whereType<double>().toList(), [1]);
    });

    test('a copy written for a Save As names its stretches as a save '
        'does', () async {
      final s = session();
      drawOnCurrentFrame(s);
      final stretches = <SaveStretch>[];

      await s.projectDoor.writeArchiveCopy(
        inTemp('copy.anicel'),
        asked: SaveAsked.byAPerson,
        onStretch: stretches.add,
      );

      expect(stretches, [SaveStretch.cels]);
    });
  });

  test('every stretch has its own words', () {
    final said = [
      for (final stretch in SaveStretch.values)
        AppText.strings.saveStep(stretch),
    ];

    expect(said.toSet(), hasLength(SaveStretch.values.length));
    expect(said, everyElement(isNot(AppText.strings.saveProgressRunning)));
    final strings = AppText.strings;
    expect({
      for (final stretch in SaveStretch.values)
        stretch: strings.saveStep(stretch),
    }, {
      SaveStretch.keepingLeftBehind: strings.saveStepKeepingLeftBehind,
      SaveStretch.cels: strings.saveStepCels,
      SaveStretch.checking: strings.saveStepChecking,
      SaveStretch.media: strings.saveStepMedia,
      SaveStretch.conforms: strings.saveStepConforms,
      SaveStretch.fonts: strings.saveStepFonts,
      SaveStretch.compacting: strings.saveStepCompacting,
      SaveStretch.handingBack: strings.saveStepHandingBack,
    }, reason: 'each says what it is, not its neighbour\'s');
  });
}
