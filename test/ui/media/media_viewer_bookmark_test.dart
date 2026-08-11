import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/media_viewer_bookmark.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/fake_pdf_document.dart';

/// The viewers remember what they were looking at, WITH THE FILM (유저
/// 확정 ⑤㉑, 2026-08-12): which reference belongs beside which drawing is
/// a fact about the work, and the workspace-layout file is shared by
/// every project.
///
/// The other half of that decision is what this must NOT do: paging a
/// reference is not a document edit, so it lands with no history entry
/// and does not make the project dirty (유저 확정 ⑮). Open a reference,
/// draw nothing, close — and nothing was saved, because nothing asked to.

const _conte = MediaAsset(
  path: 'C:/work/conte.pdf',
  name: 'conte',
  kind: MediaAssetKind.pdf,
);

Project _project({MediaViewerBookmarks bookmarks = const {}}) =>
    createDefaultProject().copyWith(
      mediaAssets: const [_conte],
      mediaViewerBookmarks: bookmarks,
    );

Finder _subViewer() =>
    find.byKey(const ValueKey<String>('media-viewer-sub-panel'));

String _pageTextIn(WidgetTester tester, Finder viewer) => tester
    .widgetList<Text>(find.descendant(of: viewer, matching: find.byType(Text)))
    .map((text) => text.data ?? '')
    .firstWhere((text) => text.contains('/'), orElse: () => '');

Future<void> _pumpEditor(WidgetTester tester, Project project) async {
  await tester.binding.setSurfaceSize(const Size(1600, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: HomePage(initialProject: project)));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(
      ValueKey<String>(
        'rail-group-${EditorWorkspace.railGroupId(right: true, slot: 5)}',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    PdfRenderService.debugOpenerOverride = (path) async =>
        FakePdfDocument(pageSizes: List<Size>.filled(5, const Size(595, 842)));
  });

  tearDown(PdfRenderService.debugResetForTests);

  group('MediaViewerBookmark', () {
    test('round-trips through the project JSON', () {
      final project = _project(
        bookmarks: const {
          'media-viewer-sub': MediaViewerBookmark(
            path: 'C:/work/conte.pdf',
            kind: MediaAssetKind.pdf,
            name: 'conte',
            position: 12,
          ),
        },
      );
      final read = Project.fromJson(project.toJson());
      expect(read.mediaViewerBookmarks, project.mediaViewerBookmarks);
    });

    test('a project nobody opened a reference in writes no key at all', () {
      expect(_project().toJson().containsKey('mediaViewerBookmarks'), isFalse);
    });

    test('a bookmark this build cannot read is dropped, never the project', () {
      // A hand-edited file, or one from a build that spelled a kind
      // differently: losing a reference is a shrug, losing the film is not.
      final json = _project().toJson()
        ..['mediaViewerBookmarks'] = {
          'media-viewer': {'path': 'C:/a.png', 'kind': 'hologram'},
          'media-viewer-sub': {'kind': 'pdf'},
          'ok': {'path': 'C:/b.png', 'kind': 'image', 'position': -4},
        };
      final read = Project.fromJson(json);
      expect(read.mediaViewerBookmarks.keys, ['ok']);
      expect(
        read.mediaViewerBookmarks['ok']!.position,
        0,
        reason: 'a negative page is not a page',
      );
    });
  });

  testWidgets('a remembered pooled asset comes back, at its page', (
    tester,
  ) async {
    await _pumpEditor(
      tester,
      _project(
        bookmarks: const {
          'media-viewer-sub': MediaViewerBookmark(
            path: 'C:/work/conte.pdf',
            kind: MediaAssetKind.pdf,
            name: 'conte',
            position: 3,
          ),
        },
      ),
    );
    expect(_pageTextIn(tester, _subViewer()), '4 / 5');
  });

  testWidgets('a remembered path the app can no longer reach comes back '
      'empty, and says nothing about it', (tester) async {
    await _pumpEditor(
      tester,
      _project(
        bookmarks: const {
          'media-viewer-sub': MediaViewerBookmark(
            path: 'C:/gone/reference.png',
            kind: MediaAssetKind.image,
            position: 2,
          ),
        },
      ),
    );
    expect(_pageTextIn(tester, _subViewer()), '0 / 0');
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a loose file that is still THERE comes back too (유저 확정 ⑭)', (
    tester,
  ) async {
    // Real IO only inside runAsync — an awaited dart:io future in the
    // fake-async zone never completes.
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('anicel-bookmark'),
    ))!;
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on Object {
        // Windows keeps handles briefly.
      }
    });
    final loose = File('${dir.path}${Platform.pathSeparator}pose.pdf');
    await tester.runAsync(() async => loose.writeAsBytes(const [1, 2, 3]));

    await _pumpEditor(
      tester,
      _project(
        bookmarks: {
          'media-viewer-sub': MediaViewerBookmark(
            path: loose.path,
            kind: MediaAssetKind.pdf,
            position: 1,
          ),
        },
      ),
    );
    expect(
      _pageTextIn(tester, _subViewer()),
      '2 / 5',
      reason: 'a file opened straight from the picker is remembered by path',
    );
  });

  test('writing a bookmark is not a document edit: no undo entry, no dirty '
      'file (유저 확정 ⑮)', () {
    final session = EditorSessionManager(initialProject: _project());
    addTearDown(session.dispose);
    expect(session.canUndo, isFalse);
    expect(session.hasUnsavedChanges, isFalse);

    session.repository.updateMediaViewerBookmarks(
      (_) => const {
        'media-viewer-sub': MediaViewerBookmark(
          path: 'C:/work/conte.pdf',
          kind: MediaAssetKind.pdf,
          position: 7,
        ),
      },
    );

    expect(
      session.repository.requireProject().mediaViewerBookmarks,
      isNotEmpty,
      reason: 'it did land in the project',
    );
    expect(
      session.canUndo,
      isFalse,
      reason: 'turning a reference page must never be undoable',
    );
    expect(
      session.hasUnsavedChanges,
      isFalse,
      reason: 'and must never be the reason a save prompt appears',
    );
  });

  testWidgets('opening a reference lands in the project', (tester) async {
    ProjectRepository? repository;
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          initialProject: _project(),
          onRepositoryCreated: (created) => repository = created,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The media browser, then its row menu's "open in sub viewer".
    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'rail-group-${EditorWorkspace.railGroupId(right: true, slot: 3)}',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey<String>('media-asset-menu-${_conte.path}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-open-sub')),
    );
    await tester.pumpAndSettle();

    final bookmarks = repository!.requireProject().mediaViewerBookmarks;
    expect(bookmarks['media-viewer-sub']?.path, _conte.path);
    expect(
      bookmarks.containsKey('media-viewer'),
      isFalse,
      reason: 'the main viewer was not asked and wrote nothing',
    );
  });
}
