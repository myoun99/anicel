import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/media/media_asset_drag_data.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/fake_pdf_document.dart';

/// The SECOND viewer (유저 확정 2026-08-12): the same panel docked like
/// any other, so a reference can sit beside the drawing while the floor's
/// viewer is free to be looked at large. What is pinned here is the part
/// that is NOT "the same panel twice" — which viewer each entrance opens,
/// that the two never share a document, that a page survives the rail
/// being folded away, and that the swap is symmetric.

const _conte = MediaAsset(
  path: 'C:/work/conte.pdf',
  name: 'conte',
  kind: MediaAssetKind.pdf,
);
const _layout = MediaAsset(
  path: 'C:/work/layout.pdf',
  name: 'layout',
  kind: MediaAssetKind.pdf,
);

Project _projectWithAssets() =>
    createDefaultProject().copyWith(mediaAssets: const [_conte, _layout]);

/// What a viewer with nothing in it reads — the pill is always there,
/// counting a document of no pages.
const _emptyReadout = '0 / 0';

Finder _mainViewer() =>
    find.byKey(const ValueKey<String>('media-viewer-panel'));
Finder _subViewer() =>
    find.byKey(const ValueKey<String>('media-viewer-sub-panel'));

/// The page readout of ONE viewer — the finder has to be scoped, because
/// two viewers on screen both draw one.
Finder _readoutIn(Finder viewer) =>
    find.descendant(of: viewer, matching: find.byType(Text));

String _pageTextIn(WidgetTester tester, Finder viewer) => tester
    .widgetList<Text>(_readoutIn(viewer))
    .map((text) => text.data ?? '')
    .firstWhere((text) => text.contains('/'), orElse: () => '');

Future<void> _pumpEditor(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1600, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _projectWithAssets())),
  );
  await tester.pumpAndSettle();
}

Future<void> _openRail(WidgetTester tester, int slot) async {
  await tester.tap(
    find.byKey(
      ValueKey<String>(
        'rail-group-${EditorWorkspace.railGroupId(right: true, slot: slot)}',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The media browser lives on right rail 3, the sub viewer on right rail
/// 5 — both ship closed (유저 확정 ⑥).
Future<void> _openMediaBrowser(WidgetTester tester) => _openRail(tester, 3);
Future<void> _openSubViewer(WidgetTester tester) => _openRail(tester, 5);


/// Presses a control in a viewer's PILL.
///
/// The pill is a measured, scrolling bar (`_CanvasViewportBottomBar`): it
/// budgets for the host's own controls and scrolls rather than overflow,
/// and this viewer now puts four of them in there. In a rail-width panel
/// the tail of that row is scrolled out of view, so a plain tap lands on
/// the canvas behind it and quietly does nothing.
Future<void> _tapPill(WidgetTester tester, String keyValue) async {
  final control = find.byKey(ValueKey<String>(keyValue));
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  await tester.tap(control);
  await tester.pumpAndSettle();
}

Future<void> _openRowMenu(WidgetTester tester, MediaAsset asset) async {
  await tester.tap(
    find.byKey(ValueKey<String>('media-asset-menu-${asset.path}')),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // Two documents of different lengths: a readout can then never be
    // mistaken for the other viewer's.
    PdfRenderService.debugOpenerOverride = (path) async => FakePdfDocument(
      pageSizes: List<Size>.filled(
        path.endsWith('layout.pdf') ? 5 : 2,
        const Size(595, 842),
      ),
    );
  });

  tearDown(PdfRenderService.debugResetForTests);

  testWidgets('the sub viewer ships on the right rail, closed', (tester) async {
    await _pumpEditor(tester);
    expect(_subViewer(), findsNothing, reason: 'its rail group ships closed');

    await _openSubViewer(tester);
    expect(_subViewer(), findsOneWidget);
    // And it is BESIDE the drawing, not instead of it — which is the
    // whole reason it exists.
    expect(_mainViewer(), findsNothing, reason: 'the floor still draws');
  });

  testWidgets('the row menu opens each viewer, and the two never share a '
      'document', (tester) async {
    await _pumpEditor(tester);
    await _openMediaBrowser(tester);
    await _openSubViewer(tester);

    // 유저 확정 ①: the plain "open in viewer" is still the MAIN one, which
    // is the floor — so it swaps the drawing away.
    await _openRowMenu(tester, _conte);
    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-open')),
    );
    await tester.pumpAndSettle();
    expect(_mainViewer(), findsOneWidget);
    expect(_pageTextIn(tester, _mainViewer()), '1 / 2');
    expect(
      _pageTextIn(tester, _subViewer()),
      _emptyReadout,
      reason: 'the sub viewer was not asked and did not follow',
    );

    // The second entry opens the OTHER one, and the first keeps its file.
    await _openRowMenu(tester, _layout);
    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-open-sub')),
    );
    await tester.pumpAndSettle();
    expect(_pageTextIn(tester, _subViewer()), '1 / 5');
    expect(
      _pageTextIn(tester, _mainViewer()),
      '1 / 2',
      reason: 'opening a reference in one viewer must not disturb the other',
    );
  });

  testWidgets('a viewer takes a dropped browser row (유저 확정 ⑬)', (
    tester,
  ) async {
    // The panel and ONE draggable row, so the drop is the only thing
    // under test. Driving the same drag through the real rail is a
    // hands-on check, not this one: the row lifts and the target is
    // there, but the pointer has a dock shell, a rail scroller and a
    // floating pill between it and the panel.
    final slot = MediaViewerSlot();
    addTearDown(slot.dispose);
    final session = EditorSessionManager(initialProject: _projectWithAssets());
    addTearDown(session.dispose);
    final dropped = <MediaAssetDragData>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Draggable<MediaAssetDragData>(
                data: MediaAssetDragData(
                  path: _layout.path,
                  name: _layout.name,
                ),
                feedback: const SizedBox(width: 40, height: 20),
                // PAINTED on purpose: a bare SizedBox has nothing to hit
                // test, so the pointer would land on the page behind it
                // and the lift would never happen.
                child: const ColoredBox(
                  color: Color(0xFF404040),
                  child: SizedBox(width: 80, height: 40),
                ),
              ),
              Expanded(
                child: MediaViewerTabHost(
                  viewerId: 'media-viewer-sub',
                  session: session,
                  request: slot.request,
                  onAssetDropped: dropped.add,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final destination = tester.getCenter(_subViewer());
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Draggable<MediaAssetDragData>)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    // Past the touch slop first, or the lift never happens and the whole
    // gesture is just a tap on a box.
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.moveTo(destination);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(dropped.map((data) => data.path), [_layout.path]);
  });

  testWidgets('swapping trades the files AND their pages, and reveals where '
      'the file went', (tester) async {
    await _pumpEditor(tester);
    await _openMediaBrowser(tester);
    await _openSubViewer(tester);

    await _openRowMenu(tester, _conte);
    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-open-sub')),
    );
    await tester.pumpAndSettle();

    // Turn to page 3 of 5 in the sub viewer... (a conte you are reading
    // is never on page 1)
    await _tapPill(tester, 'media-viewer-sub-next-page-button');
    expect(_pageTextIn(tester, _subViewer()), '2 / 2');

    // ...then ask for it large. 유저 확정 ⑰: the page travels WITH the
    // file, or "show me this bigger" would land on page 1 and the trip
    // would be wasted.
    await _tapPill(tester, 'media-viewer-sub-swap-button');

    // 유저 확정 ⑳: the receiving viewer is REVEALED — the floor was
    // showing the canvas, and a swap into a panel nobody can see reads as
    // "my file just vanished".
    expect(_mainViewer(), findsOneWidget);
    expect(_pageTextIn(tester, _mainViewer()), '2 / 2');

    // 유저 확정 ⑯: no exception for an empty other side. The sub viewer
    // traded its document away and is now empty, because a button whose
    // result depends on what the other side happened to hold is a button
    // nobody can predict.
    expect(_pageTextIn(tester, _subViewer()), _emptyReadout);
  });

  testWidgets('the page survives the rail folding away', (tester) async {
    // 유저 확정 ④: a rail group the user closes UNMOUNTS the panel inside
    // it, so a page kept in the panel's own State would come back as page
    // 1 of a hundred-page conte.
    await _pumpEditor(tester);
    await _openMediaBrowser(tester);
    await _openSubViewer(tester);

    await _openRowMenu(tester, _layout);
    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-open-sub')),
    );
    await tester.pumpAndSettle();
    await _tapPill(tester, 'media-viewer-sub-next-page-button');
    expect(_pageTextIn(tester, _subViewer()), '2 / 5');

    await _openSubViewer(tester); // folds it away
    expect(_subViewer(), findsNothing);
    await _openSubViewer(tester); // and back
    await tester.pumpAndSettle();

    expect(_pageTextIn(tester, _subViewer()), '2 / 5');
  });

  testWidgets('the promote button is offered for a loose file and goes quiet '
      'once the file is in the pool (유저 확정 ⑱)', (tester) async {
    final slot = MediaViewerSlot();
    addTearDown(slot.dispose);
    final session = EditorSessionManager(initialProject: _projectWithAssets());
    addTearDown(session.dispose);
    final registered = <String>[];
    final pool = <String>{_conte.path, _layout.path};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaViewerTabHost(
            viewerId: 'media-viewer-sub',
            session: session,
            request: slot.request,
            onRegisterAsset: (path) {
              registered.add(path);
              pool.add(path);
            },
            isPathRegistered: pool.contains,
          ),
        ),
      ),
    );
    await tester.pump();

    // Asserted by PRESSING rather than by reading the widget's enabled
    // flag: what matters is whether an import happens, and the pill's
    // button is the app's own control rather than a Material IconButton.
    Future<void> press() async {
      final button = find.byKey(
        const ValueKey<String>('media-viewer-sub-register-asset-button'),
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button, warnIfMissed: false);
      await tester.pumpAndSettle();
    }

    // Nothing on screen: there is nothing to add.
    await press();
    expect(registered, isEmpty);

    // A file already in the pool: the button has no work to do.
    slot.open(MediaViewerRequest(path: _conte.path, kind: MediaAssetKind.pdf));
    await tester.pumpAndSettle();
    await press();
    expect(registered, isEmpty);

    // A LOOSE file — the one case the button exists for. Its path is
    // remembered as an absolute path and breaks on another machine;
    // pressing this is how a person promotes it to one that travels with
    // the project.
    slot.open(
      const MediaViewerRequest(
        path: 'D:/refs/pose.png',
        kind: MediaAssetKind.image,
      ),
    );
    await tester.pumpAndSettle();
    await press();
    expect(registered, ['D:/refs/pose.png']);

    // And it goes quiet: the file is in the pool now, so a second press
    // must not stack a second import.
    await press();
    expect(registered, ['D:/refs/pose.png']);
  });

  group('MediaViewerSlot', () {
    test('open() starts a new document at its beginning', () {
      final slot = MediaViewerSlot();
      addTearDown(slot.dispose);
      slot.position.value = 12;
      slot.open(
        const MediaViewerRequest(
          path: 'C:/work/a.pdf',
          kind: MediaAssetKind.pdf,
        ),
      );
      expect(
        slot.position.value,
        0,
        reason: 'page 12 of the file you left means nothing in the new one',
      );
    });

    test('swapWith trades documents and pages, and leaves the viewports '
        'where they are', () {
      final main = MediaViewerSlot();
      final sub = MediaViewerSlot();
      addTearDown(main.dispose);
      addTearDown(sub.dispose);

      main.open(
        const MediaViewerRequest(
          path: 'C:/work/a.pdf',
          kind: MediaAssetKind.pdf,
        ),
      );
      sub.open(
        const MediaViewerRequest(
          path: 'C:/work/b.pdf',
          kind: MediaAssetKind.pdf,
        ),
      );
      main.position.value = 3;
      sub.position.value = 7;

      main.swapWith(sub);

      expect(main.request.value?.path, 'C:/work/b.pdf');
      expect(main.position.value, 7);
      expect(sub.request.value?.path, 'C:/work/a.pdf');
      expect(sub.position.value, 3);
    });

    test('swapping with an empty viewer empties this one — no exception', () {
      final main = MediaViewerSlot();
      final sub = MediaViewerSlot();
      addTearDown(main.dispose);
      addTearDown(sub.dispose);

      sub.open(
        const MediaViewerRequest(
          path: 'C:/work/b.pdf',
          kind: MediaAssetKind.pdf,
        ),
      );
      sub.position.value = 4;

      sub.swapWith(main);

      expect(main.request.value?.path, 'C:/work/b.pdf');
      expect(main.position.value, 4);
      expect(sub.request.value, isNull);
      expect(sub.position.value, 0);
    });
  });

  test('a drag payload names the pool key the drop resolves', () {
    // The viewer's drop handler looks the path up in the pool, so the
    // payload has to carry the POOL KEY and not a display name.
    const data = MediaAssetDragData(path: 'C:/work/conte.pdf', name: 'conte');
    expect(_projectWithAssets().mediaAssetByPath(data.path), _conte);
  });
}

