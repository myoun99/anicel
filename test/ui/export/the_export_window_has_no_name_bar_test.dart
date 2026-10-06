import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/export_preview_probe.dart';
import '../../helpers/files_written_under.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🗣️F-289 · F-221 (유저 2026-10-06): the bar across the export window's top
/// is gone — 「이름줄 없는거 맘에들고」. A file a hand names is named at the
/// head of the settings column, its extension standing beside the field
/// (「확장자는 따로 나눠서 편집불가하게 그냥 띄우기만하고, 이름만 딱
/// 있도록」), and the footer spreads: 「큐에 추가를 왼쪽정렬로 왼쪽에 붙이고,
/// 내보내기는 지금위치로하고 그 왼쪽에 붙여서 위치 지정하고 출력합니다라는
/// 텍스트」, with the progress of a run between them 「출력때만 보이게」.
void main() {
  late Directory temp;

  setUp(() {
    AppExport.settings.value = AppExportSettings();
    temp = Directory.systemTemp.createTempSync('qa-export-no-name-bar');
    deleteAfterSessionEnds(temp);
  });
  tearDown(() => AppExport.settings.value = AppExportSettings());

  const cutId = CutId('cut');

  EditorSessionManager film() => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'Film',
      cameraSize: const CanvasSize(width: 32, height: 18),
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Track',
          cuts: [
            Cut(
              id: cutId,
              name: '301',
              duration: 2,
              canvasSize: const CanvasSize(width: 8, height: 8),
              layers: [
                Layer(
                  id: const LayerId('a'),
                  name: 'A',
                  frames: [
                    Frame(
                      id: const FrameId('a1'),
                      duration: 1,
                      strokes: const [],
                    ),
                  ],
                ),
                createCameraLayer(cutId: cutId),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  Future<ExportDialogState> pumpWindow(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session,
            exportDirectoryPicker: () async => temp.path,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.state<ExportDialogState>(find.byType(ExportDialog));
  }

  Finder keyed(String value) => find.byKey(ValueKey<String>(value));

  Future<void> press(WidgetTester tester, String key) async {
    await tester.ensureVisible(keyed(key));
    await tester.pump();
    await tester.tap(keyed(key), warnIfMissed: false);
    await tester.pump();
  }

  String nameTyped(WidgetTester tester) => tester
      .widget<TextField>(keyed('export-file-name-field'))
      .controller!
      .text;

  String extensionShown(WidgetTester tester) =>
      tester.widget<Text>(keyed('export-file-extension')).data!;

  group('a lone file is named at the head of the settings column', () {
    testWidgets('🚨the field holds the name alone, and the extension stands '
        'beside it — the format\'s, changing with the format', (tester) async {
      final session = film();
      addTearDown(session.dispose);
      await pumpWindow(tester, session);

      expect(nameTyped(tester), 'Film');
      expect(extensionShown(tester), '.mp4');
      expect(tester.exportFirstFileName, 'Film.mp4');

      await press(tester, 'export-format-container-mov');
      expect(nameTyped(tester), 'Film', reason: 'the name is not retyped');
      expect(extensionShown(tester), '.mov');
      expect(tester.exportFirstFileName, 'Film.mov');
      session.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('a name typed is the file written — and an extension typed '
        'after it is not doubled', (tester) async {
      final session = film();
      addTearDown(session.dispose);
      final state = await pumpWindow(tester, session);
      await press(tester, 'export-tab-image');
      expect(extensionShown(tester), '.png');

      await tester.enterText(keyed('export-file-name-field'), 'shot');
      await tester.pump();
      expect(tester.exportFirstFileName, 'shot.png');
      expect(tester.exportPreviewName, 'shot.png');

      await tester.enterText(keyed('export-file-name-field'), 'shot.png');
      await tester.pump();
      expect(tester.exportFirstFileName, 'shot.png');

      await tester.runAsync(state.export);
      await tester.pump();
      expect(filesWrittenUnder(temp), ['shot.png']);
      session.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('an empty field is the project\'s name', (tester) async {
      final session = film();
      addTearDown(session.dispose);
      await pumpWindow(tester, session);
      await tester.enterText(keyed('export-file-name-field'), '  ');
      await tester.pump();
      expect(tester.exportFirstFileName, 'Film.mp4');
      session.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('the Sequence tab\'s first module is ALWAYS its name: a '
        'video\'s one name, and in the same place the rule its stills are '
        'named by', (tester) async {
      final session = film();
      addTearDown(session.dispose);
      await pumpWindow(tester, session);
      final strings = AppText.strings;
      double topOf(String title) =>
          tester.getTopLeft(find.textContaining(title).first).dy;
      final formatTop = topOf(strings.exFormat);

      expect(keyed('export-file-name-field'), findsOneWidget);
      expect(keyed('export-naming-base-field'), findsNothing);
      expect(topOf(strings.commonNameField), lessThan(formatTop));

      await press(tester, 'export-format-still-png');
      expect(keyed('export-file-name-field'), findsNothing);
      expect(tester.exportFirstFileName, 'frame_0001.png');
      expect(
        topOf(strings.exNaming),
        lessThan(topOf(strings.exFormat)),
        reason: 'the rule stands where the name stood',
      );
      session.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('the conte keeps ONE name in either format: the PDF\'s, and '
        'the base of its pages as pictures', (tester) async {
      final session = film();
      addTearDown(session.dispose);
      final state = await pumpWindow(tester, session);
      await press(tester, 'export-tab-conte');

      expect(nameTyped(tester), 'conte');
      expect(extensionShown(tester), '.pdf');
      expect(tester.exportFirstFileName, 'conte.pdf');

      await tester.enterText(keyed('export-file-name-field'), 'board');
      await tester.pump();
      expect(tester.exportPreviewName, 'board.pdf');
      await tester.runAsync(state.export);
      await tester.pump();
      expect(filesWrittenUnder(temp), ['board.pdf']);

      await press(tester, 'export-conteformat-png');
      expect(
        keyed('export-file-name-field'),
        findsOneWidget,
        reason: 'the module keeps its place when the format changes',
      );
      expect(nameTyped(tester), 'board');
      expect(extensionShown(tester), '.png');
      expect(tester.exportPreviewName, 'board_p1.png');

      await tester.runAsync(state.export);
      await tester.pump();
      expect(
        filesWrittenUnder(temp),
        contains('board_p1.png'),
        reason: 'the pages are written under the name typed',
      );
      session.playbackRig.prerenderScheduler.cancel();
    });
  });

  testWidgets('a queued job brought back to the window brings its NAME '
      'back — the field does not take the extension in', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    await pumpWindow(tester, session);
    await tester.enterText(keyed('export-file-name-field'), 'take2');
    await tester.pump();
    await press(tester, 'export-queue-add-button');
    await tester.pump();
    await tester.enterText(keyed('export-file-name-field'), 'other');
    await tester.pump();

    await press(tester, 'export-queue-job-1');

    expect(nameTyped(tester), 'take2');
    expect(tester.exportFirstFileName, 'take2.mp4');
    session.playbackRig.prerenderScheduler.cancel();
  });

  group('the footer spreads', () {
    testWidgets('🚨큐에 추가 holds the left end and 내보내기 the right; the '
        'order this export takes stands against Export\'s left', (tester) async {
      final session = film();
      addTearDown(session.dispose);
      await pumpWindow(tester, session);

      final window = tester.getRect(keyed('export-dialog'));
      final queue = tester.getRect(keyed('export-queue-add-button'));
      final export = tester.getRect(keyed('export-run-button'));
      final order = tester.getRect(keyed('export-order-line'));

      // Each holds its end: the two stand as far in from the window's
      // edges as each other, and nothing of the footer stands outside them.
      expect(
        queue.left - window.left,
        moreOrLessEquals(window.right - export.right, epsilon: 0.5),
      );
      expect(queue.left, lessThan(order.left));
      expect(queue.left - window.left, lessThan(window.width / 10));
      expect(queue.width, lessThan(window.width / 4), reason: 'its own width');
      expect(export.width, lessThan(window.width / 4));
      expect(order.right, lessThanOrEqualTo(export.left));
      expect(export.left - order.right, lessThan(24));
      expect(
        tester.widget<Text>(keyed('export-order-line')).data,
        AppText.strings.exOrderAsksFirst,
      );
      session.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('the progress of a run stands between them for the length of '
        'the run and at no other time — with Cancel against Export', (
      tester,
    ) async {
      final session = film();
      addTearDown(session.dispose);
      final state = await pumpWindow(tester, session);
      await press(tester, 'export-format-still-png');

      expect(keyed('export-progress'), findsNothing);
      expect(keyed('export-cancel-button'), findsNothing);
      expect(keyed('export-status'), findsOneWidget);

      // Under the test's faked clock a frame never finishes rendering: the
      // run stays under way for as long as the test looks at it.
      unawaited(state.export());
      await tester.pump();
      await tester.pump();

      expect(keyed('export-progress'), findsOneWidget);
      expect(keyed('export-status'), findsNothing);
      final queue = tester.getRect(keyed('export-queue-add-button'));
      final bar = tester.getRect(keyed('export-progress'));
      final order = tester.getRect(keyed('export-order-line'));
      final cancel = tester.getRect(keyed('export-cancel-button'));
      final export = tester.getRect(keyed('export-run-button'));
      expect(bar.left, greaterThanOrEqualTo(queue.right));
      expect(bar.right, lessThanOrEqualTo(order.left));
      expect(order.right, lessThanOrEqualTo(cancel.left));
      expect(cancel.right, lessThanOrEqualTo(export.left));
      session.playbackRig.prerenderScheduler.cancel();
    });
  });
}
