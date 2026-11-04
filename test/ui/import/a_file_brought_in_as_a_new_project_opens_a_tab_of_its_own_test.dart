// A FILE BROUGHT IN AS A NEW PROJECT OPENS A TAB OF ITS OWN (I-156).
//
// 🗣️유저 2026-11-04: 「임포트창에서 넣을곳에 새 프로젝트도 신설」 — Q1
// 「파일마다 프로젝트 하나」 · Q2 「그 동영상의 fps」 (「아무튼 fps기준으로
// 정해짐」). The project's one cut is the file's, made as a new cut is — at
// the file's size and as long as it runs (07-29 임포트 설계 §2: 「미디어
// 크기로 새 프로젝트」) — and the project the window stands on is left as
// it was (I-7: 「새 프로젝트는 현재 프로젝트 냅두고 새로 여는거야」).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/open_projects.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/model_vocabulary.dart' show partsOf;

import '../../helpers/fake_video_backend.dart';
import '../../helpers/import_span.dart';
import '../../helpers/import_warnings.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/staged_carry.dart';
import '../../helpers/stand_in_movie.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/wait_window.dart';

void main() {
  late Directory tempDir;
  late List<EditorSessionManager> letGo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-new-project');
    letGo = [];
  });

  tearDown(() async {
    debugVideoDecodeBackend = null;
    deleteTempQuietly(tempDir);
  });

  /// The window's tabs, the one shown standing on a project of its own.
  OpenProjects tabs() {
    final projects = OpenProjects(
      first: createDefaultProject(),
      openSession: (project) => EditorSessionManager(
        initialProject: project,
        audioConformStore: soundConformStore(),
      ),
      letGo: (session) {
        letGo.add(session);
        session.playbackRig.prerenderScheduler.cancel();
        session.dispose();
      },
    );
    addTearDown(projects.dispose);
    return projects;
  }

  /// The window on [session], handed [path] by its door — or, with
  /// [fromThePool], as a pool row places it — with the tabs to open a
  /// project in, or none.
  Future<void> openWindowOn(
    WidgetTester tester,
    EditorSessionManager session,
    String path, {
    OpenProjects? projects,
    bool fromThePool = false,
  }) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: fromThePool
              ? ImportDialog(
                  session: session,
                  initialPaths: [path],
                  placeOnly: true,
                  projects: projects,
                )
              : ImportDialog(
                  session: session,
                  picked: [
                    FolderGrant.granted(path: path, kind: GrantKind.file),
                  ],
                  projects: projects,
                ),
        ),
      ),
    );
    await settleLoadedPages(tester);
  }

  /// The window on the shown tab, handed [path] by its door — or by the
  /// pool, [fromThePool].
  Future<EditorSessionManager> openWindow(
    WidgetTester tester,
    OpenProjects projects,
    String path, {
    bool fromThePool = false,
  }) async {
    final here = projects.active;
    await openWindowOn(
      tester,
      here,
      path,
      projects: projects,
      fromThePool: fromThePool,
    );
    return here;
  }

  /// [path]'s row word for its size — '' until it is read.
  String resolutionOf(WidgetTester tester, String path) => tester
      .widget<Text>(find.byKey(ValueKey<String>('import-resolution-$path')))
      .data!;

  /// `bg.png`, red at 8×8, carried by [session]'s pool — and the file on
  /// disk blue at 16×16 since, or [gone].
  Future<String> carriedThenChanged(
    WidgetTester tester,
    EditorSessionManager session, {
    bool gone = false,
  }) async {
    final path = normalizedMediaPath(
      (await tester.runAsync(
        () => writeSolidPng(tempDir, 'bg.png', rgba: 0xFF0000FF),
      ))!,
    );
    await tester.runAsync(
      () => session.mediaPool.importMediaFiles([path], copyIntoProject: true),
    );
    expect(carryIn(session, path), isNotNull, reason: '⛔전제: carried');
    await tester.runAsync(
      () => gone
          ? File(path).delete()
          : writeSolidPng(
              tempDir,
              'bg.png',
              rgba: 0x0000FFFF,
              width: 16,
              height: 16,
            ),
    );
    return path;
  }

  /// [option] pressed in [path]'s cell of [column].
  Future<void> pick(
    WidgetTester tester,
    String column,
    String path,
    String option,
  ) async {
    final cell = find.byKey(ValueKey<String>('import-cell-$column-$path'));
    await tester.ensureVisible(cell);
    await tester.pump();
    await tester.tap(cell);
    final answer = find.byKey(
      ValueKey<String>('import-option-$column-$option'),
    );
    await settleAsync(tester, () => tester.any(answer));
    await tester.tap(answer);
    await settleAsync(tester, () => !tester.any(answer));
  }

  /// The window's press, waited out — and every tab's warmer stopped, the
  /// one it opened among them.
  Future<void> pressImport(WidgetTester tester, OpenProjects projects) async {
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    await tester.pumpAndSettle();
    for (final session in projects.sessions) {
      session.playbackRig.prerenderScheduler.cancel();
    }
  }

  /// [session]'s one cut — the file's.
  Cut theCut(EditorSessionManager session) =>
      session.repository.requireProject().tracks.single.cuts.single;

  /// What [s]'s project is, in the numbers this round is about.
  ({int cuts, int steps, int pooled}) shapeOf(EditorSessionManager s) => (
    cuts: s.repository.requireProject().tracks.single.cuts.length,
    steps: s.historyManager.undoCount,
    pooled: s.mediaPool.mediaAssets.length,
  );

  Future<String> writeMovie(WidgetTester tester, String name) async =>
      (await tester.runAsync(() async {
        final file = File('${tempDir.path}${Platform.pathSeparator}$name');
        await file.writeAsBytes(standInMovieBytes);
        return file.path;
      }))!;

  testWidgets('🗣️a picture brought in as a new project: a tab of its own, '
      'after the others and shown, its one cut the picture\'s — at its '
      'size, 1:1 — and the project the window stood on as it was', (
    tester,
  ) async {
    final projects = tabs();
    final png = (await tester.runAsync(
      () => writeSolidPng(tempDir, 'board.png', width: 16, height: 8),
    ))!;
    final here = await openWindow(tester, projects, png);
    final before = shapeOf(here);

    await pick(tester, 'into', png, 'newProject');
    expect(
      find.descendant(
        of: find.byKey(ValueKey<String>('import-cell-into-$png')),
        matching: find.text(AppText.strings.imIntoNewProject),
      ),
      findsOneWidget,
    );
    await pressImport(tester, projects);

    expect(projects.sessions, hasLength(2));
    final made = projects.active;
    expect(identical(made, projects.sessions.last), isTrue);
    expect(projects.untitledNumberOf(made), isNotNull, reason: 'untitled');
    final cut = theCut(made);
    expect(cut.canvasSize, const CanvasSize(width: 16, height: 8));
    expect(
      [
        for (final layer in cut.layers)
          if (layer.mediaReference case final shown?) shown.assetPath,
      ],
      [normalizedMediaPath(png)],
    );
    expect(
      cut.layers.where(
        (layer) =>
            layer.kind == LayerKind.animation && layer.mediaReference == null,
      ),
      isEmpty,
      reason: 'the cut a new cut is: no blank row A',
    );
    expect(
      made.repository.requireProject().frameRate,
      newUntitledProject().frameRate,
      reason: 'a picture names no rate: a new project\'s own',
    );
    expect(made.mediaPool.mediaAssets.single.carried, isTrue);
    expect(shapeOf(here), before, reason: 'the window\'s project is untouched');
    expect(importWarningsButton, findsNothing);
  });

  testWidgets('🗣️a movie brought in as a new project runs at the movie\'s '
      'rate — a 23.976 take in a 24 project asks nothing of the 24 one, '
      'and its cut runs as long as the take', (tester) async {
    debugVideoDecodeBackend = FakeVideoBackend(
      frameCount: 48,
      fpsNumerator: 24000,
      fpsDenominator: 1001,
    );
    final projects = tabs();
    final movie = await writeMovie(tester, 'take.mp4');
    final here = await openWindow(tester, projects, movie);
    final before = shapeOf(here);

    await pick(tester, 'into', movie, 'newProject');
    await pressImport(tester, projects);

    expect(
      find.byKey(const ValueKey<String>('import-movie-rate-dialog')),
      findsNothing,
      reason: 'the take is not placed in this project',
    );
    expect(
      here.projectSettings.projectFrameRate,
      ProjectFrameRate.fps24,
    );
    expect(shapeOf(here), before);
    final made = projects.active;
    expect(
      made.repository.requireProject().frameRate,
      const ProjectFrameRate.ntsc(24),
    );
    final cut = theCut(made);
    expect(cut.duration, 48, reason: 'frame for frame with the take');
    expect(cut.canvasSize, const CanvasSize(width: 64, height: 36));
  });

  testWidgets('🗣️a trimmed 30 fps movie comes in on the same pictures — its '
      'span, counted on this 24 project\'s clock, moved onto the new '
      'project\'s 30', (tester) async {
    debugVideoDecodeBackend = FakeVideoBackend(
      frameCount: 60,
      fpsNumerator: 30,
    );
    final projects = tabs();
    final movie = await writeMovie(tester, 'take.mp4');
    await openWindow(tester, projects, movie);
    await pick(tester, 'into', movie, 'newProject');
    // Baked, the picture alone: the span bakes from the file through the
    // door's IN/OUT, as a row that leaves no pool entry does.
    await settleAsync(
      tester,
      () => tester.any(
        find.byKey(ValueKey<String>('import-cell-option-$movie')),
      ),
    );
    await pick(tester, 'option', movie, 'picture');
    await tester.tap(find.byKey(ValueKey<String>('import-cell-bake-$movie')));
    await tester.pump();
    // One-based: frames 10 · 29 on the 24 clock show the take's 12 · 36.
    await keepImportSpan(tester, 11, 30);

    await pressImport(tester, projects);

    final made = projects.active;
    expect(
      made.repository.requireProject().frameRate,
      const ProjectFrameRate.integer(30),
    );
    expect(
      theCut(made).duration,
      25,
      reason: 'the take\'s 12 to 36, one frame each at 30 — ↩️20 would be '
          'the 24 clock\'s count laid on the 30 one',
    );
  });

  testWidgets('a file that does not come in leaves no tab behind — the '
      'project made for it is let go, and the window says why', (
    tester,
  ) async {
    final projects = tabs();
    final broken = (await tester.runAsync(() async {
      final file = File('${tempDir.path}${Platform.pathSeparator}broken.png');
      await file.writeAsBytes([1, 2, 3, 4]);
      return file.path;
    }))!;
    final here = await openWindow(tester, projects, broken);

    await pick(tester, 'into', broken, 'newProject');
    await pressImport(tester, projects);

    expect(projects.sessions, [here]);
    expect(identical(projects.active, here), isTrue);
    expect(letGo, hasLength(1), reason: 'the one made for it, let go');
    expect(importWarningsButton, findsOneWidget);
  });

  testWidgets('a file this project carries, picked again for a new project, '
      'is not taken anew HERE — this project keeps its copy; the new one '
      'carries the file as it is (F-550-Q3 is a re-import\'s)', (
    tester,
  ) async {
    final projects = tabs();
    final png = (await tester.runAsync(
      () => writeSolidPng(tempDir, 'board.png', width: 16, height: 8),
    ))!;
    final here = projects.active;
    await tester.runAsync(
      () => here.mediaPool.importMediaFiles([png], copyIntoProject: true),
    );
    final kept = carryIn(here, png);
    expect(kept, isNotNull, reason: '⛔전제: this project carries the file');
    final before = shapeOf(here);

    await openWindow(tester, projects, png);
    await pick(tester, 'into', png, 'newProject');
    await pressImport(tester, projects);

    expect(carryIn(here, png), kept);
    expect(shapeOf(here), before);
    final made = projects.active;
    expect(identical(made, here), isFalse);
    expect(carryIn(made, png), isNotNull);
    expect(carryIn(made, png), isNot(kept), reason: 'a carry of its own');
  });

  testWidgets('a pool row bound for a new project shows what comes in — the '
      'file itself, its size read again from it, not this project\'s copy '
      '(F-550-Q3 「미리보기는 고른 파일을 보인다」; I-156-Q5 asks whether '
      'the copy should come instead)', (tester) async {
    final projects = tabs();
    final path = await carriedThenChanged(tester, projects.active);
    await openWindow(tester, projects, path, fromThePool: true);
    const step = Duration(milliseconds: 50);
    await settleAsync(
      tester,
      () => resolutionOf(tester, path) != '',
      step: step,
    );
    expect(
      resolutionOf(tester, path),
      '8×8',
      reason: 'placed here, the row is this project\'s copy',
    );

    await pick(tester, 'into', path, 'newProject');
    await settleAsync(
      tester,
      () => resolutionOf(tester, path) == '16×16',
      step: step,
    );
    expect(resolutionOf(tester, path), '16×16');
    await pressImport(tester, projects);

    expect(
      theCut(projects.active).canvasSize,
      const CanvasSize(width: 16, height: 16),
    );
  });

  testWidgets('a file this project points at, brought in as a new project, '
      'is kept as its row says — this project\'s pool does not answer for '
      'the new one\'s', (tester) async {
    final projects = tabs();
    final here = projects.active;
    final png = (await tester.runAsync(
      () => writeSolidPng(tempDir, 'board.png'),
    ))!;
    await tester.runAsync(
      () => here.mediaPool.importMediaFiles([png], copyIntoProject: false),
    );
    expect(
      here.mediaPool.mediaAssets.single.carried,
      isFalse,
      reason: '⛔전제: this project points at the file',
    );

    await openWindow(tester, projects, png);
    await pick(tester, 'into', png, 'newProject');
    await pressImport(tester, projects);

    expect(
      projects.active.mediaPool.mediaAssets.single.carried,
      isTrue,
      reason: 'the row\'s own answer, carried',
    );
    expect(here.mediaPool.mediaAssets.single.carried, isFalse);
  });

  testWidgets('a pool row whose file is gone makes no new project — the new '
      'one would hold no copy of it — and the window says it could not '
      'read it', (tester) async {
    final projects = tabs();
    final here = projects.active;
    final path = await carriedThenChanged(tester, here, gone: true);
    await openWindow(tester, projects, path, fromThePool: true);
    await pick(tester, 'into', path, 'newProject');
    await pressImport(tester, projects);

    expect(projects.sessions, [here]);
    expect(letGo, isEmpty, reason: 'no project is made for it');
    final notice = await openImportWarnings(tester);
    final name = here.repository.requireProject().shownNameOfMedia(path);
    final (:about, :says) = partsOf(
      AppText.strings.imUnreadable(name),
      about: name,
    );
    for (final words in [about!, '$says (1)']) {
      expect(
        find.descendant(of: notice, matching: find.text(words)),
        findsOneWidget,
        reason: words,
      );
    }
  });

  testWidgets('a window with no tabs to open one in offers no new project',
      (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final png = (await tester.runAsync(
      () => writeSolidPng(tempDir, 'board.png'),
    ))!;
    await openWindowOn(tester, session, png);
    await tester.tap(find.byKey(ValueKey<String>('import-cell-into-$png')));
    final newCut = find.byKey(
      const ValueKey<String>('import-option-into-newCut'),
    );
    await settleAsync(tester, () => tester.any(newCut));

    expect(
      find.byKey(const ValueKey<String>('import-option-into-newProject')),
      findsNothing,
    );
  });
}
