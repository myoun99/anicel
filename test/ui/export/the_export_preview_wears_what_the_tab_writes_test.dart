import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/export/export_preview_document.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/export_cels_alone.dart';
import '../../helpers/export_cels_board_probe.dart';
import '../../helpers/export_preview_probe.dart';

/// 🗣️F-289 (유저 2026-10-06): the export window's preview is a canvas-base
/// panel that wears what the tab's file is — the Sequence and the Image tab
/// stand on the transport (IN and OUT on the Sequence tab alone), the Conte
/// tab turns its pages on the left, and a cel is one picture — with the
/// file's name in one place whatever the tab: 「그냥 제안한대로 동영상뷰어던
/// 뭐던 해당 위치 고정으로 두자」.
///
/// The window's side of it: which document each tab hands the panel, and
/// the name it writes on the plate.
void main() {
  setUp(() => AppExport.settings.value = AppExportSettings());
  tearDown(() => AppExport.settings.value = AppExportSettings());

  const cutId = CutId('cut');
  const size = CanvasSize(width: 8, height: 8);
  const transport = ValueKey<String>('canvas-transport');
  const strip = ValueKey<String>('canvas-page-strip');

  Frame frame(String id, String name) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);

  /// One cut, 301, three frames long: a KEY row A with two cels.
  EditorSessionManager film() => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'Project',
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
              duration: 3,
              canvasSize: size,
              layers: [
                Layer(
                  id: const LayerId('a'),
                  name: 'A',
                  frames: [frame('a1', '1'), frame('a2', '2')],
                  mark: const LayerMark(process: LayerProcess.key),
                ),
                createCameraLayer(cutId: cutId),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  /// A black dot on each of A's cels, so there are pictures to show.
  void draw(EditorSessionManager session) {
    final cut = session.cutById(cutId)!;
    final pixels = Uint8List(8 * 8 * 4)..[3] = 255;
    for (final cel in ['a1', 'a2']) {
      session.renderCaches.brushFrameStore.storeBakedSurface(
        session.brushFrameKeyForCut(cut, const LayerId('a'), FrameId(cel)),
        BitmapSurface(
          canvasSize: size,
          tileSize: 8,
          tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: pixels)},
        ),
      );
    }
  }

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

  Future<void> openTab(WidgetTester tester, String tab) =>
      press(tester, 'export-tab-$tab');

  testWidgets('🚨each tab hands the panel what its file is: a run under the '
      'Sequence tab (with IN and OUT) and the Image tab (without), a book '
      'under the Conte tab, one picture under the Cels tab', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    await pumpWindow(tester, session);

    expect(tester.exportPreviewDocument!.shape, ExportPreviewShape.runs);
    expect(find.byKey(transport), findsOneWidget);
    expect(tester.exportTransport.frameCount, 3);
    expect(tester.exportTransport.range, isNotNull);
    expect(find.byKey(strip), findsNothing);

    await openTab(tester, 'image');
    expect(tester.exportPreviewDocument!.shape, ExportPreviewShape.runs);
    expect(tester.exportTransport.frameCount, 3);
    expect(
      tester.exportTransport.range,
      isNull,
      reason: 'one frame is written: there is nothing to trim',
    );

    await openTab(tester, 'conte');
    final book = tester.exportPreviewDocument!;
    expect(book.shape, ExportPreviewShape.book);
    expect(book.pageCount, greaterThan(1), reason: 'LIVENESS — pages to turn');
    expect(find.byKey(transport), findsNothing);
    expect(find.byKey(strip), findsOneWidget);

    await openTab(tester, 'cels');
    expect(tester.exportPreviewDocument!.shape, ExportPreviewShape.single);
    expect(find.byKey(transport), findsNothing);
    expect(find.byKey(strip), findsNothing);
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a page is the pixels its FILE is written at: the camera\'s, '
      'the cut\'s canvas under 캔버스, a sheet\'s paper', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    await pumpWindow(tester, session);
    expect(tester.exportPreviewPageSize, const Size(32, 18));

    await openTab(tester, 'image');
    await press(tester, 'export-size-canvas');
    expect(tester.exportPreviewPageSize, const Size(8, 8));

    await openTab(tester, 'cels');
    expect(
      tester.exportPreviewCheckered,
      isTrue,
      reason: 'a cel is open where its format says',
    );
    await press(tester, 'export-cels-stand-document-timesheet');
    expect(tester.exportPreviewPageSize, const Size(1754, 2480));
    expect(
      tester.exportPreviewCheckered,
      isFalse,
      reason: 'a document is its paper',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🚨a tab is another subject: its picture does not linger under '
      'the next tab\'s', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    draw(session);
    await pumpWindow(tester, session);
    await tester.settleExportPreview();
    final sequence = tester.exportPreviewImage;
    expect(sequence, isNotNull);
    final subject = tester.exportPreviewDocument!.subject;

    await openTab(tester, 'image');
    expect(tester.exportPreviewDocument!.subject, isNot(subject));
    // Whatever is up by now — nothing yet, or the image tab's own picture,
    // which lands when the raster says — it is not the sequence's.
    expect(identical(tester.exportPreviewImage, sequence), isFalse);
    await tester.settleExportPreview();
    expect(tester.exportPreviewImage, isNotNull);
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a setting of the tab stood on keeps the picture up until the '
      'new one lands', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    draw(session);
    await pumpWindow(tester, session);
    await tester.settleExportPreview();
    final before = tester.exportPreviewImage;
    expect(before, isNotNull);
    final shown = tester.exportPreviewDocument!;

    // The options module is folded: its head opens it.
    final options = find.textContaining(AppText.strings.exOptions);
    await tester.ensureVisible(options);
    await tester.pump();
    await tester.tap(options);
    await tester.pump();
    await press(tester, 'export-apply-fx-toggle');
    // The same thing looked at, in another look — which is what keeps the
    // picture up while the new one is on its way (the panel's own pin: a
    // landing is the raster's to time, not this test's).
    final asked = tester.exportPreviewDocument!;
    expect(asked.subject, shown.subject);
    expect(asked.look, isNot(shown.look));
    await tester.settleExportPreview();
    expect(tester.exportPreviewImage, isNotNull);
    expect(identical(tester.exportPreviewImage, before), isFalse);
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a cel\'s plate is its file — and a drawing the run does not '
      'write is named by its own name, in the ink of what is off', (
    tester,
  ) async {
    AppExport.settings.value = exportSettingsWritingCelsAlone();
    final session = film();
    addTearDown(session.dispose);
    await pumpWindow(tester, session);
    await openTab(tester, 'cels');

    expect(tester.exportPreviewLine, 'A1.png · 1 / 2');
    expect(tester.exportPreviewNameAbsent, isFalse);
    await press(tester, 'export-cels-next');
    expect(tester.exportPreviewLine, 'A2.png · 2 / 2');

    // The row switched off: its drawings are still what the panel turns
    // through, and none of them is a file.
    await tester.pressInCelsBoard(tester.celsBoardSwitch('a'));
    expect(tester.exportPreviewName, '2');
    expect(tester.exportPreviewNameAbsent, isTrue);
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('the conte: the PDF is one name whatever page is up; as '
      'pictures, the plate names the page turned to', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    await pumpWindow(tester, session);
    await openTab(tester, 'conte');

    expect(tester.exportPreviewName, 'conte.pdf');
    await press(tester, 'export-preview-next-page-button');
    expect(tester.exportPreviewName, 'conte.pdf');

    await press(tester, 'export-conteformat-png');
    expect(tester.exportPreviewName, 'conte_p2.png');
    await press(tester, 'export-preview-previous-page-button');
    expect(tester.exportPreviewName, 'conte_p1.png');
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('with nothing to write the panel says so in the tab\'s own '
      'word', (tester) async {
    AppExport.settings.value = exportSettingsWritingCelsAlone();
    final session = film();
    addTearDown(session.dispose);
    await pumpWindow(tester, session);
    await openTab(tester, 'cels');
    await press(tester, 'export-cels-kind-cel');

    expect(tester.exportPreviewDocument, isNull);
    expect(
      find.descendant(
        of: keyed('export-preview-empty'),
        matching: find.byType(Text),
      ),
      findsOneWidget,
    );
    expect(tester.exportPreviewName, isNull);
    session.playbackRig.prerenderScheduler.cancel();
  });
}
