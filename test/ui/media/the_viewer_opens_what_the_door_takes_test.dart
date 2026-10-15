import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/ui/brush/canvas_floor_insets.dart';
import 'package:anicel/src/ui/dialogs/app_confirm_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';

/// F-282-Q2 (유저 2026-10-09, 가): the viewer's 「파일 열기」 stays a look —
/// nothing comes into the project through it — and it takes the kinds the
/// one door sends to the import window, SOUND included: the viewer opens a
/// sound as its waveform (09-08). ↩️Its picker left sound out, 「the one
/// deliberate absence」, a month after the viewer learned to open one.
void main() {
  Future<List<MediaViewerRequest>> pick(
    WidgetTester tester,
    String path,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 700));
    final slot = MediaViewerSlot();
    addTearDown(slot.dispose);
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final opened = <MediaViewerRequest>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasFloorInsets(
            insets: EdgeInsets.zero,
            child: MediaViewerTabHost(
              viewerId: EditorWorkspace.mediaViewerTabId,
              session: session,
              request: slot.request,
              position: slot.position,
              onRequestPicked: opened.add,
              filePicker: () async => [path],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('media-viewer-open-file-button')),
    );
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('a sound file opens — as a sound', (tester) async {
    final opened = await pick(tester, 'D:/refs/take.wav');

    expect(opened.single.path, 'D:/refs/take.wav');
    expect(opened.single.kind, MediaAssetKind.audio);
  });

  testWidgets('a movie, a picture and a PDF open as themselves', (
    tester,
  ) async {
    for (final (path, kind) in [
      ('D:/refs/take.mov', MediaAssetKind.video),
      ('D:/refs/pose.psd', MediaAssetKind.image),
      ('D:/refs/conte.pdf', MediaAssetKind.pdf),
    ]) {
      final opened = await pick(tester, path);
      expect(opened.single.kind, kind, reason: path);
    }
  });

  testWidgets('a file the viewer cannot open is named — and nothing opens', (
    tester,
  ) async {
    final opened = await pick(tester, 'D:/refs/notes.txt');

    expect(opened, isEmpty);
    expect(
      find.byKey(const ValueKey<String>('unsupported-file-notice')),
      findsOneWidget,
    );
    expect(
      tester.widget<AppConfirmDialog>(find.byType(AppConfirmDialog)).details,
      ['D:/refs/notes.txt'],
    );
  });
}
