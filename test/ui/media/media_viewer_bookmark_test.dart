import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/media_viewer_bookmark.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';

import '../../helpers/device_viewport.dart';
import '../../helpers/fake_pdf_document.dart';
import '../../helpers/project_scratch_folder.dart';
import '../../helpers/rail_group_button.dart';

/// The viewers remember what they were looking at, WITH THE FILM (유저
/// 확정 ⑤㉑, 2026-08-12): which reference belongs beside which drawing is
/// a fact about the work, and the workspace-layout file is shared by
/// every project.
///
/// The other half of that decision is what this must NOT do: opening a
/// reference is not a document edit, so it lands with no history entry
/// and does not make the project dirty (유저 확정 ⑮). Open a reference,
/// draw nothing, close — and nothing was saved, because nothing asked to.
///
/// How far into it the viewer was is the FILE's since F-382 — kept beside
/// the project, with the framing (`MediaFileViews`).

final _conte = MediaAsset(
  path: 'C:/work/conte.pdf',
  name: 'conte',
  kind: MediaAssetKind.pdf,
);

Project _project({MediaViewerBookmarks bookmarks = const {}}) =>
    createDefaultProject().copyWith(
      mediaAssets: [_conte],
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
    railGroupButton(EditorWorkspace.railGroupId(right: true, slot: 5)),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    PdfRenderService.debugOpenerOverride = (_) async =>
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
          'ok': {'path': 'C:/b.png', 'kind': 'image'},
        };
      final read = Project.fromJson(json);
      expect(read.mediaViewerBookmarks.keys, ['ok']);
    });
  });

  testWidgets('a remembered pooled asset comes back — at the page its FILE '
      'was left at, when its project comes on screen (F-382)', (tester) async {
    await _pumpEditor(
      tester,
      _project(
        bookmarks: const {
          'media-viewer-sub': MediaViewerBookmark(
            path: 'C:/work/conte.pdf',
            kind: MediaAssetKind.pdf,
          ),
        },
      ),
    );
    expect(_pageTextIn(tester, _subViewer()), '1 / 5', reason: '⛔fixture');
    final projects = tester
        .widget<EditorTopStrip>(find.byType(EditorTopStrip))
        .projects;
    final first = projects.active;
    // What an open puts back of a file a save kept (`ProjectResume`).
    first.mediaFileViews.rememberPage(_conte.path, 3);

    // Another project comes on screen, and then this one again.
    await _tapKey(tester, 'top-strip-project-button');
    await _tapKey(tester, 'menu-file-new');
    await _tapKey(tester, 'project-tab-0');

    expect(identical(projects.active, first), isTrue, reason: '⛔fixture');
    expect(_pageTextIn(tester, _subViewer()), '4 / 5');
  });

  testWidgets('🚨a file opened again after another comes back as it was left '
      '— at its page, at its zoom (F-382, 유저 2026-10-17: 「다른 파일 '
      '열엇다가 돌아오면 그대로 열리도록」)', (tester) async {
    final layout = MediaAsset(
      path: 'C:/work/layout.pdf',
      name: 'layout',
      kind: MediaAssetKind.pdf,
    );
    await _pumpEditor(
      tester,
      _project(
        bookmarks: const {
          'media-viewer-sub': MediaViewerBookmark(
            path: 'C:/work/conte.pdf',
            kind: MediaAssetKind.pdf,
          ),
        },
      ).copyWith(mediaAssets: [_conte, layout]),
    );
    final view = tester
        .widget<MediaViewerTabHost>(
          find.byWidgetPredicate(
            (widget) =>
                widget is MediaViewerTabHost &&
                widget.viewerId == EditorWorkspace.mediaViewerSubTabId,
          ),
        )
        .viewportController!;
    // The user reads the conte at a scale of their own, two pages on.
    view.value = seedFromRender(tester, CanvasViewport(zoom: 1));
    await tester.pumpAndSettle();
    for (var turn = 0; turn < 2; turn += 1) {
      await _tapKey(tester, 'media-viewer-sub-next-page-button');
    }
    expect(_pageTextIn(tester, _subViewer()), '3 / 5', reason: '⛔fixture');
    final kept = renderOf(tester, view.value!);

    /// The pool row's 「open in the sub viewer」.
    Future<void> openInTheSubViewer(MediaAsset asset) async {
      final menu = find.byKey(
        ValueKey<String>('media-asset-menu-${asset.path}'),
      );
      if (menu.evaluate().isEmpty) {
        await _tapKey(
          tester,
          railGroupButtonKey(EditorWorkspace.railGroupId(right: true, slot: 3)),
        );
      }
      await _tapKey(tester, 'media-asset-menu-${asset.path}');
      await _tapKey(tester, 'media-asset-menu-open-sub');
    }

    await openInTheSubViewer(layout);
    expect(
      _pageTextIn(tester, _subViewer()),
      '1 / 5',
      reason: '⛔fixture: the other file, at its own first page',
    );
    await openInTheSubViewer(_conte);

    expect(_pageTextIn(tester, _subViewer()), '3 / 5');
    final back = renderOf(tester, view.value!);
    expect(back.zoom, closeTo(kept.zoom, 1e-6), reason: 'not fitted');
    expect(back.panX, closeTo(kept.panX, 1e-6));
    expect(back.panY, closeTo(kept.panY, 1e-6));
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
          ),
        },
      ),
    );
    // Empty reads as EMPTY, not as '0 / 0' — 유저 확정 ⑥ (2026-08-13) gave
    // the page cluster its own seat and a condition to appear under, so a
    // viewer with nothing in it has nothing to turn and shows no turner.
    expect(_pageTextIn(tester, _subViewer()), '');
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
    deleteAfterSessionEnds(dir);
    final loose = File('${dir.path}${Platform.pathSeparator}pose.pdf');
    await tester.runAsync(() async => loose.writeAsBytes(const [1, 2, 3]));

    await _pumpEditor(
      tester,
      _project(
        bookmarks: {
          'media-viewer-sub': MediaViewerBookmark(
            path: loose.path,
            kind: MediaAssetKind.pdf,
          ),
        },
      ),
    );
    expect(
      _pageTextIn(tester, _subViewer()),
      '1 / 5',
      reason: 'a file opened straight from the picker is remembered by path',
    );
  });

  test('writing a bookmark is not a document edit: no undo entry, no dirty '
      'file (유저 확정 ⑮)', () {
    final session = EditorSessionManager(initialProject: _project());
    addTearDown(session.dispose);
    expect(session.canUndo, isFalse);
    expect(session.projectFile.hasUnsavedChanges, isFalse);

    session.repository.updateMediaViewerBookmarks(
      (_) => const {
        'media-viewer-sub': MediaViewerBookmark(
          path: 'C:/work/conte.pdf',
          kind: MediaAssetKind.pdf,
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
      reason: 'opening a reference must never be undoable',
    );
    expect(
      session.projectFile.hasUnsavedChanges,
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

    // The media pool, then its row menu's "open in sub viewer".
    await tester.tap(
      railGroupButton(EditorWorkspace.railGroupId(right: true, slot: 3)),
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
