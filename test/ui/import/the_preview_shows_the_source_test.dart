import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/media/viewer_document.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_preview.dart';
import 'package:anicel/src/ui/media/document_preview_panel.dart';
import 'package:anicel/src/ui/media/open_viewer_document.dart';
import 'package:anicel/src/ui/widgets/empty_state_text.dart';
import 'package:anicel/src/ui/widgets/transport_bar.dart';

import '../../helpers/fake_video_backend.dart';
import '../../helpers/import_preview_probe.dart';
import '../../helpers/project_scratch_folder.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/the_file_itself.dart';

/// The import window's preview zone — nothing named it (2026-09-05).
///
/// What is reachable without a decoder is the zone's own two decisions,
/// and they are the ones with a stated reason:
///
/// ⛔The file stands in the export window's preview panel and nothing else
/// is drawn — no canvas outline, no placement rectangle. What this shows is
/// the SOURCE; the composition is what Fit answers in the row. (F-282 ④,
/// 유저 2026-10-09: 「임포트창 미리보기도 출력창 미리보기 개편한것처럼
/// 공용화된거 쓰는거 잊지말고」 — ↩️a 16:9 well with no zoom.)
///
/// ⛔「A range that changes nothing is a control that lies」 — the IN/OUT
/// ends appear only where they bite: a multi-frame source being PLACED.
///
/// And what the viewer's door refuses, the well says, as the viewer does.
void main() {
  late EditorSessionManager session;

  setUp(
    () => session = EditorSessionManager(
      initialProject: createDefaultProject(),
    ),
  );
  tearDown(() => session.dispose());

  Future<void> pump(
    WidgetTester tester, {
    String? path,
    bool rangeEditable = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 240,
            child: ImportPreview(
              session: session,
              path: path,
              inFrame: 0,
              outFrame: null,
              rangeEditable: rangeEditable,
              onRangeChanged: (_, _) {},
              soundPeaks: (_) async => null,
              holdBytes: theFileItself,
              frameRate: ProjectFrameRate.fps24,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('nothing selected draws nothing, and does not fall over', (
    tester,
  ) async {
    await pump(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('🚨the zone is the export window\'s preview panel and it holds '
      'ONLY the picture — no canvas outline, no placement rectangle, because '
      'this shows the SOURCE and the composition is the row\'s answer', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('anicel-preview'),
    );
    deleteAfterSessionEnds(dir!);
    final png = await tester.runAsync(
      () => writeSolidPng(dir, 'a.png', width: 4, height: 6),
    );
    await pump(tester, path: png);
    await settleLoadedPages(tester);

    expect(find.byType(DocumentPreviewPanel), findsOneWidget);
    expect(
      [for (final page in tester.importPreviewPage!.pages) page.rect],
      [Offset.zero & const Size(4, 6)],
      reason: 'the file\'s one page, where the file is — nothing beside it',
    );
  });

  testWidgets('the file\'s name stands on the panel\'s plate, as the export '
      'window\'s preview writes its file\'s', (tester) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('anicel-preview'),
    );
    deleteAfterSessionEnds(dir!);
    final png = await tester.runAsync(
      () => writeSolidPng(dir, 'BG_a12.png', width: 4, height: 4),
    );
    await pump(tester, path: png);
    await settleLoadedPages(tester);

    expect(
      tester.widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel)).documentName,
      'BG_a12.png',
    );
  });

  testWidgets('⛔a source with ONE frame keeps its IN/OUT row, OFF — a range '
      'that changes nothing is a control that lies, and a row that came and '
      'went with the file would move the picture over it', (tester) async {
    await pump(tester);

    final range = tester.widget<TransportBar>(find.byType(TransportBar)).range;
    expect(range, isNotNull, reason: 'the window trims, so the row is here');
    expect(range!.onChanged, isNull, reason: 'and here it acts on nothing');
  });

  testWidgets('⛔and so does one that is not being PLACED', (tester) async {
    await pump(tester, rangeEditable: false);

    final range = tester.widget<TransportBar>(find.byType(TransportBar)).range;
    expect(range, isNotNull);
    expect(range!.onChanged, isNull);
  });

  testWidgets('the bar is the SHARED transport — a video will need nothing '
      'here beyond a frame supplier the day there is a decoder', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byType(TransportBar), findsOneWidget);
  });

  // 🗣️F-315 (유저 2026-10-08): 「뷰어패널기반들 임포트/익스포트/뷰어패널 다
  // 똑같은데, 준비안된상태면 … 로딩창같은거 해당패널중앙에 위젯 띄우도록」.
  testWidgets('🗣️a file still opening stands the loading widget in the '
      'well, and its picture drawn takes it down — nothing selected loads '
      'nothing', (tester) async {
    final loading = find.byKey(
      const ValueKey<String>('import-preview-loading'),
    );
    await pump(tester);
    expect(loading, findsNothing, reason: 'nothing was asked for');

    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('anicel-preview'),
    );
    deleteAfterSessionEnds(dir!);
    final png = await tester.runAsync(
      () => writeSolidPng(dir, 'a.png', width: 4, height: 4),
    );
    await pump(tester, path: png);
    expect(loading, findsOneWidget, reason: '↩️the well stood empty');
    expect(
      tester.importPreviewImage,
      isNull,
      reason: 'premise: its picture is not up yet',
    );

    await settleLoadedPages(tester);
    expect(loading, findsNothing);
    expect(tester.importPreviewImage, isNotNull, reason: 'its picture is up');
  });

  testWidgets('🐞a movie the decoder will not open says so in the well, '
      'with the decoder\'s reason, as the viewer does — and the next file '
      'takes the sentence down', (tester) async {
    // 유저 2026-10-30 (Galaxy Tab, build 1084): a black well counting
    // 1 / 1, and nothing said why until Import was pressed.
    debugVideoDecodeBackend = FakeVideoBackend(
      refusal: 'could not open the container',
    );
    addTearDown(() => debugVideoDecodeBackend = null);
    final refused = find.byKey(
      const ValueKey<String>('import-preview-refused'),
    );
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('anicel-preview'),
    );
    deleteAfterSessionEnds(dir!);
    final movie = '${dir.path}/take.mp4';
    await tester.runAsync(() => File(movie).writeAsBytes(const [0, 0, 0, 0]));
    await pump(tester, path: movie);
    await settleLoadedPages(tester);
    expect(refused, findsOneWidget);
    expect(
      tester.widget<EmptyStateText>(refused).text,
      viewerCouldNotOpen(
        const ViewerDocumentException('could not open the container'),
      ),
      reason: 'the media viewer\'s sentence for the same open, the '
          'decoder\'s words under it',
    );

    final png = await tester.runAsync(
      () => writeSolidPng(dir, 'a.png', width: 4, height: 4),
    );
    await pump(tester, path: png);
    await settleLoadedPages(tester);
    expect(tester.importPreviewImage, isNotNull, reason: 'premise');
    expect(refused, findsNothing);

    await pump(tester, path: movie);
    await settleLoadedPages(tester);
    expect(refused, findsOneWidget, reason: 'premise');
    await pump(tester);
    expect(refused, findsNothing, reason: 'nothing selected says nothing');
  });

  testWidgets('a build with no movie reader says which absence, as the '
      'viewer does', (tester) async {
    debugVideoDecodeBackend = FakeVideoBackend(supported: false);
    addTearDown(() => debugVideoDecodeBackend = null);
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('anicel-preview'),
    );
    deleteAfterSessionEnds(dir!);
    final movie = '${dir.path}/take.mp4';
    await tester.runAsync(() => File(movie).writeAsBytes(const [0, 0, 0, 0]));
    await pump(tester, path: movie);
    await settleLoadedPages(tester);
    expect(
      tester
          .widget<EmptyStateText>(
            find.byKey(const ValueKey<String>('import-preview-refused')),
          )
          .text,
      viewerNothingOpens(MediaAssetKind.video),
    );
  });
}
