import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_conform_runner.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/media/project_media_sources.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/temp_dir.dart';

/// 🚨AN OPEN READS ITS FILE'S DIRECTORY ONCE FOR ALL ITS SOUNDS
/// (`ProjectFile.withOneReadOfTheFile`).
///
/// 🔬card anicel-open-stands-still-while-it-settles (Surface, 2026-11-20,
/// a 393 MB project of 678 entries, the app's own workers): the warm of
/// each sound asked where its bytes are and whether the file carries its
/// conform, and each question read the whole directory again on the thread
/// that draws — 5–13 ms a read, 22–30 ms of the open's 51–69 ms stall for
/// two sounds.
void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('anicel-one-read');
  });

  tearDown(() => deleteTempQuietly(directory));

  String conformNameOf(Project project, String sound) => anicelConformEntryName(
    sound,
    sampleRate: project.audioSampleRate,
    speedNumerator: project.audioSpeedNumerator,
    speedDenominator: project.audioSpeedDenominator,
  );

  /// A project file of its own carrying the three sounds of one folder,
  /// written [length] bytes long that do not compress — the first with its
  /// conform beside it.
  Future<
    ({String path, Project project, List<String> sounds, Set<String> media})
  >
  saved(String name, {int length = 300}) async {
    final folder = Directory('${directory.path}/sounds')
      ..createSync(recursive: true);
    String write(String file, int length, int seed) {
      final path = normalizedMediaPath('${folder.path}/$file');
      var state = seed;
      File(path).writeAsBytesSync([
        for (var index = 0; index < length; index += 1)
          (state = (state * 1103515245 + 12345) & 0x7FFFFFFF) >> 16 & 0xFF,
      ], flush: true);
      return path;
    }

    final sounds = [
      for (var index = 0; index < 3; index += 1)
        write('s$index.wav', length + index, index + 1),
    ];
    final project = createDefaultProject().copyWith(
      mediaAssets: [
        for (final sound in sounds)
          MediaAsset(
            path: sound,
            name: 's',
            carriedAs: (token: mediaCarryNamed(sound, 'c1'), modified: null),
          ),
      ],
    );
    final path = normalizedMediaPath('${directory.path}/$name.anicel');
    await const AnicelFileService().save(
      project: project,
      brushFrameStore: BrushFrameStore(),
      filePath: path,
      mediaToStore: {
        for (final asset in project.mediaAssets)
          ?asset.carry: MediaFileBytes(asset.path),
      },
      conforms: ProjectConforms({
        conformNameOf(project, sounds.first): MediaFileBytes(
          write('s0.conform', 900, 7),
        ),
      }),
    );
    return (
      path: path,
      project: project,
      sounds: sounds,
      media: {
        for (final entry in parseAnicelZipLayoutFile(path).entries)
          if (entry.name.startsWith(anicelMediaEntryPrefix)) entry.name,
      },
    );
  }

  /// A session of [project] whose conforms are only recorded, in [asked] —
  /// each with the bytes its session resolved for it.
  EditorSessionManager sessionHearing(
    Project project,
    List<ConformRequest> asked,
  ) {
    late final EditorSessionManager session;
    return session = EditorSessionManager(
      initialProject: project,
      audioConformStore: AudioConformStore(
        resolveConformPath: (_) => null,
        resolveByteSource: (path) =>
            session.projectFile.mediaByteSourceFor(path),
        resolveCarriedConform: (path) =>
            session.projectFile.carriedConformFor(path),
        resolveCarry: (path) => session.projectFile.mediaCarryFor(path),
        runner: (request) async {
          asked.add(request);
          return const ConformResult(
            outcome: ConformOutcome.undecodable,
            error: 'test stub',
          );
        },
        log: (_) {},
      ),
    );
  }

  test('🚨an open\'s warm reads the directory once — and each sound is '
      'still told its own entry, and its own conform', () async {
    final file = await saved('one');
    final asked = <ConformRequest>[];
    final session = sessionHearing(file.project, asked);
    addTearDown(session.dispose);
    session.projectFile.bindToOpenedFile(
      file.path,
      mediaInFile: file.media,
      fontsInFile: const {},
      unsaved: false,
    );
    debugLayoutReadsOnThisIsolate = 0;

    session.projectDoor.warmAudioConforms();

    expect(
      debugLayoutReadsOnThisIsolate,
      1,
      reason: '🪦two a sound — where its bytes are, and its conform',
    );
    final layout = parseAnicelZipLayoutFile(file.path);
    int offsetOf(String? name) => layout.entryNamed(name!)!.dataOffset;
    expect(
      {
        for (final request in asked)
          request.sourcePath: (
            request.source?.span?.path,
            request.source?.span?.offset,
            request.carriedConform?.span?.offset,
          ),
      },
      {
        for (final sound in file.sounds)
          sound: (
            file.path,
            offsetOf(
              mediaEntryNameIn(file.media, wholeCarryOf(file.project, sound)),
            ),
            sound == file.sounds.first
                ? offsetOf(conformNameOf(file.project, sound))
                : null,
          ),
      },
    );
  });

  test('a batch whose session moves to another file reads that one anew — '
      'offsets belong to one layout', () async {
    final first = await saved('first');
    final second = await saved('second', length: 20000);
    final sound = first.sounds.first;
    final session = sessionHearing(first.project, []);
    addTearDown(session.dispose);
    void bindTo(String path, Set<String> media) =>
        session.projectFile.bindToOpenedFile(
          path,
          mediaInFile: media,
          fontsInFile: const {},
          unsaved: false,
        );
    int offsetIn(String path) => parseAnicelZipLayoutFile(
      path,
    ).entryNamed(conformNameOf(first.project, sound))!.dataOffset;
    expect(
      offsetIn(second.path),
      isNot(offsetIn(first.path)),
      reason: 'the premise: the two files hold the conform at two offsets',
    );
    bindTo(first.path, first.media);

    final (before, after) = session.projectFile.withOneReadOfTheFile(() {
      final before = session.projectFile.carriedConformFor(sound);
      bindTo(second.path, second.media);
      return (before, session.projectFile.carriedConformFor(sound));
    });

    expect(
      (before?.span?.path, before?.span?.offset),
      (first.path, offsetIn(first.path)),
    );
    expect(
      (after?.span?.path, after?.span?.offset),
      (second.path, offsetIn(second.path)),
    );
  });
}

/// The carry [project]'s pool names at [sound].
MediaCarry wholeCarryOf(Project project, String sound) =>
    project.mediaAssetByPath(sound)!.carry!;
