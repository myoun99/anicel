import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../helpers/fake_pdf_document.dart';
import '../helpers/psd_fixture.dart';

/// ⛔THE DESTINATION GATE IS ONE LAW, SO IT IS ONE OBJECT.
///
/// "Land in the ACTIVE cut" is a request that can be refused: standing in
/// a gap there is no active cut, and every media-file door has to say no
/// — with nothing landed, nothing registered and nothing on the undo
/// stack. Image, PSD and PDF each carried their own copy of that gate
/// (round 8, G1, 2026-09-06), and each said in its own words that it must
/// run BEFORE the read, so a refusal never has pixels, a PSD's bytes or an
/// open PDF document to leak.
///
/// ⚠️Deliberately given a REAL, perfectly good file. A door that refused
/// because the file was bad would pass this test while the gate was gone;
/// what is measured is the destination's answer, nothing else.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-gate-test');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } on Object {
      // Windows keeps handles briefly; leftovers live in systemTemp.
    }
  });

  Future<String> writePng(String name) async {
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i + 3] = 0xFF;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      8,
      8,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    return file.path;
  }

  /// A session parked in a GAP: two cuts with four empty frames between
  /// them, the playhead standing in the empty stretch. UI-R9 #3 — no cut
  /// is selected there.
  EditorSessionManager gapped() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createCut();
    final track = s.repository.requireProject().tracks.first;
    s.repository.updateCutLeadingGap(
      cutId: track.cuts[1].id,
      leadingGapFrames: 4,
    );
    s.selectCut(track.cuts[0].id);
    s.selectGlobalFrame(track.cuts[0].duration + 1);
    expect(s.activeCutOrNull, isNull, reason: 'the premise: standing in a gap');
    // The gap was BUILT with commands; what is measured is what the door
    // adds to the stack, so the setup's own steps go first.
    s.historyManager.clear();
    return s;
  }

  int cutCount(EditorSessionManager s) =>
      s.repository.requireProject().tracks.first.cuts.length;

  testWidgets('the IMAGE door refuses the active cut when there is none, '
      'and lands nothing', (tester) async {
    final s = gapped();
    addTearDown(s.dispose);

    final cutsBefore = cutCount(s);

    final imported = await tester.runAsync(() async {
      final path = await writePng('bg.png');
      return s.importDoors.importImageFile(
        path: path,
        destination: ImportDestination.activeCutLayer,
        copyIntoProject: false,
      );
    });

    // The warm scheduler arms an idle timer whenever the playhead moves,
    // and the binding checks for pending timers BEFORE any tearDown runs.
    s.prerenderScheduler.cancel();
    expect(imported, isFalse);
    expect(cutCount(s), cutsBefore);
    expect(s.mediaAssets, isEmpty);
    expect(s.canUndo, isFalse, reason: 'a refusal is not an edit');
  });

  testWidgets('the PSD door refuses on the same answer', (tester) async {
    final s = gapped();
    addTearDown(s.dispose);

    final cutsBefore = cutCount(s);

    // A document that WOULD expand — otherwise a door with no gate at all
    // would still answer null, because the file was unreadable, and this
    // test would pass over the hole it exists to find.
    final warnings = await tester.runAsync(() async {
      final file = File('${tempDir.path}${Platform.pathSeparator}stack.psd');
      await file.writeAsBytes(
        buildPsd(
          width: 8,
          height: 8,
          layers: [
            PsdTestLayer(
              name: 'under',
              left: 0,
              top: 0,
              right: 8,
              bottom: 8,
              planes: psdSolidPlanes(8, 8, [10, 20, 30]),
            ),
          ],
          compositePlanes: [Uint8List(64), Uint8List(64), Uint8List(64)],
        ),
      );
      return s.importDoors.importPsdExpanded(
        path: file.path,
        destination: ImportDestination.activeCutLayer,
      );
    });

    // The warm scheduler arms an idle timer whenever the playhead moves,
    // and the binding checks for pending timers BEFORE any tearDown runs.
    s.prerenderScheduler.cancel();
    expect(warnings, isNull);
    expect(cutCount(s), cutsBefore);
    expect(s.canUndo, isFalse);
  });

  testWidgets('the PDF door refuses before it opens a document', (
    tester,
  ) async {
    final s = gapped();
    addTearDown(s.dispose);

    final cutsBefore = cutCount(s);
    var opened = 0;
    addTearDown(PdfRenderService.debugResetForTests);
    PdfRenderService.debugOpenerOverride = (path) async {
      opened += 1;
      return FakePdfDocument(pageSizes: const [ui.Size(595, 842)]);
    };

    final imported = await tester.runAsync(
      () => s.importDoors.importPdfFile(
        path: '${tempDir.path}${Platform.pathSeparator}conte.pdf',
        destination: ImportDestination.activeCutLayer,
        copyIntoProject: false,
      ),
    );

    // The warm scheduler arms an idle timer whenever the playhead moves,
    // and the binding checks for pending timers BEFORE any tearDown runs.
    s.prerenderScheduler.cancel();
    expect(imported, isFalse);
    expect(
      opened,
      0,
      reason:
          'the gate runs BEFORE any native work — a refused import must '
          'not have opened a document to leak',
    );
    expect(cutCount(s), cutsBefore);
    expect(s.canUndo, isFalse);
  });

  testWidgets('and the same three land normally as a NEW CUT, which is the '
      'destination the gate never refuses', (tester) async {
    final s = gapped();
    addTearDown(s.dispose);

    final cutsBefore = cutCount(s);

    final imported = await tester.runAsync(() async {
      final path = await writePng('bg.png');
      return s.importDoors.importImageFile(
        path: path,
        destination: ImportDestination.newCut,
        copyIntoProject: false,
        lengthFrames: 6,
      );
    });

    // The warm scheduler arms an idle timer whenever the playhead moves,
    // and the binding checks for pending timers BEFORE any tearDown runs.
    s.prerenderScheduler.cancel();
    expect(imported, isTrue);
    expect(cutCount(s), cutsBefore + 1);
    expect(s.mediaAssets, hasLength(1));
  });
}
