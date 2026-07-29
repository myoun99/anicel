import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';
import 'package:anicel/src/ui/home_page.dart';

/// The top menu bar (W2): every submenu lists its commands, enablement
/// tracks the session's `can*` gates, the Window menu keeps the retired
/// Panels menu's item keys, and Reset Workspace Layout restores the
/// factory docks.
void main() {
  Future<ProjectRepository> pumpHome(WidgetTester tester) async {
    late ProjectRepository repository;
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(onRepositoryCreated: (repo) => repository = repo),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> openMenu(WidgetTester tester, String menuKey) async {
    // The strip scrolls horizontally on narrow windows — bring the menu
    // button into view first.
    await tester.ensureVisible(find.byKey(ValueKey<String>(menuKey)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>(menuKey)));
    await tester.pumpAndSettle();
  }

  testWidgets('the strip replaces the AppBar and keeps the quick-action '
      'keys', (tester) async {
    await pumpHome(tester);

    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const ValueKey<String>('undo-button')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('redo-button')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('export-png-button')),
      findsOneWidget,
    );
    for (final menu in ['file', 'edit', 'cut', 'layer', 'playback', 'help']) {
      expect(
        find.byKey(ValueKey<String>('menu-$menu')),
        findsOneWidget,
        reason: 'the $menu menu must be on the bar',
      );
    }
    expect(
      find.byKey(const ValueKey<String>('panels-menu-button')),
      findsOneWidget,
    );
  });

  testWidgets('File: export opens; the persistence entries are live (P3)', (
    tester,
  ) async {
    await pumpHome(tester);
    await openMenu(tester, 'menu-file');

    for (final slot in ['file-open', 'file-save', 'file-save-as']) {
      final item = tester.widget<MenuItemButton>(
        find.byKey(ValueKey<String>('menu-$slot')),
      );
      expect(item.onPressed, isNotNull, reason: '$slot is live since P3');
    }

    await tester.tap(find.byKey(const ValueKey<String>('menu-file-export')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('export-run-button')),
      findsOneWidget,
    );
  });

  testWidgets('Layer: Link Duplicate creates a linked copy (badge shows), '
      'Unlink arms only then and forks it back out', (tester) async {
    await pumpHome(tester);

    await openMenu(tester, 'menu-layer');
    expect(
      tester
          .widget<MenuItemButton>(
            find.byKey(const ValueKey<String>('menu-layer-link-duplicate')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<MenuItemButton>(
            find.byKey(const ValueKey<String>('menu-layer-unlink')),
          )
          .onPressed,
      isNull,
      reason: 'nothing is linked yet',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('menu-layer-link-duplicate')),
    );
    await tester.pumpAndSettle();

    // Both members carry the link badge now.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Icon &&
            widget.key != null &&
            '${widget.key}'.contains('timeline-layer-link-badge'),
      ),
      findsNWidgets(2),
    );

    await openMenu(tester, 'menu-layer');
    await tester.tap(find.byKey(const ValueKey<String>('menu-layer-unlink')));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Icon &&
            widget.key != null &&
            '${widget.key}'.contains('timeline-layer-link-badge'),
      ),
      findsNothing,
      reason: 'unlinking dissolves the badge on every member',
    );
  });

  testWidgets('Layer: Group into Folder grows a folder row whose twirl '
      'collapses the members into the aggregate header', (tester) async {
    final repository = await pumpHome(tester);

    await openMenu(tester, 'menu-layer');
    await tester.tap(
      find.byKey(const ValueKey<String>('menu-layer-group-into-folder')),
    );
    await tester.pumpAndSettle();

    final cut = repository.requireProject().tracks.first.cuts.first;
    expect(cut.layers.folderLayers, hasLength(1));
    final folderId = cut.layers.folderLayers.single.id;
    expect(
      find.byKey(ValueKey<String>('timeline-folder-row-$folderId')),
      findsOneWidget,
    );
    expect(find.text('Folder 1'), findsOneWidget);

    // Collapse: the member (layer A) row hides — A is ACTIVE, so it
    // stays; select nothing else is possible with one drawing layer, so
    // just verify the twirl writes the model.
    await tester.tap(
      find.byKey(ValueKey<String>('timeline-folder-twirl-$folderId')),
    );
    await tester.pumpAndSettle();
    expect(
      repository
          .requireProject()
          .tracks
          .first
          .cuts
          .first
          .layers
          .folderLayers
          .single
          .collapsed,
      isTrue,
    );

    // The folder eye is the LAYER eye — same button, same key.
    await tester.tap(
      find.byKey(ValueKey<String>('timeline-layer-visibility-$folderId')),
    );
    await tester.pumpAndSettle();
    expect(
      repository
          .requireProject()
          .tracks
          .first
          .cuts
          .first
          .layers
          .folderLayers
          .single
          .isVisible,
      isFalse,
    );
  });

  testWidgets('Cut: Create Linked Cut adds a linked cut; Convert arms only '
      'with another cut available', (tester) async {
    final repository = await pumpHome(tester);
    final track = repository.requireProject().tracks.first;
    final cutsBefore = track.cuts.length;

    await openMenu(tester, 'menu-cut');
    expect(
      tester
          .widget<MenuItemButton>(
            find.byKey(const ValueKey<String>('menu-cut-convert-linked')),
          )
          .onPressed,
      isNull,
      reason: 'a single-cut project has no conversion target',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('menu-cut-create-linked')),
    );
    await tester.pumpAndSettle();
    expect(
      repository.requireProject().tracks.first.cuts.length,
      cutsBefore + 1,
    );
    expect(
      repository.requireProject().linkRegistry.isEmpty,
      isFalse,
      reason: 'the linked cut registered link groups',
    );

    await openMenu(tester, 'menu-cut');
    expect(
      tester
          .widget<MenuItemButton>(
            find.byKey(const ValueKey<String>('menu-cut-convert-linked')),
          )
          .onPressed,
      isNotNull,
      reason: 'a second cut exists now',
    );
  });

  testWidgets('Edit: undo enablement tracks history and the item undoes', (
    tester,
  ) async {
    final repository = await pumpHome(tester);
    final cutsBefore = repository.requireProject().tracks.first.cuts.length;

    await openMenu(tester, 'menu-edit');
    expect(
      tester
          .widget<MenuItemButton>(
            find.byKey(const ValueKey<String>('menu-edit-undo')),
          )
          .onPressed,
      isNull,
      reason: 'nothing to undo on a fresh project',
    );
    expect(
      tester
          .widget<MenuItemButton>(
            find.byKey(const ValueKey<String>('menu-edit-keyboard-shortcuts')),
          )
          .onPressed,
      isNotNull,
      reason: 'the shortcuts editor is live (P1)',
    );
    // Close the menu, make an undoable edit through the Cut menu.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await openMenu(tester, 'menu-cut');
    await tester.tap(find.byKey(const ValueKey<String>('menu-cut-new')));
    await tester.pumpAndSettle();
    expect(
      repository.requireProject().tracks.first.cuts.length,
      cutsBefore + 1,
    );

    await openMenu(tester, 'menu-edit');
    await tester.tap(find.byKey(const ValueKey<String>('menu-edit-undo')));
    await tester.pumpAndSettle();
    expect(repository.requireProject().tracks.first.cuts.length, cutsBefore);
  });

  testWidgets('Layer: add layer lands in the project', (tester) async {
    final repository = await pumpHome(tester);
    final layersBefore = repository
        .requireProject()
        .tracks
        .first
        .cuts
        .first
        .layers
        .length;

    await openMenu(tester, 'menu-layer');
    await tester.tap(find.byKey(const ValueKey<String>('menu-layer-add')));
    await tester.pumpAndSettle();

    expect(
      repository.requireProject().tracks.first.cuts.first.layers.length,
      layersBefore + 1,
    );
  });

  testWidgets('Window: the panel checkboxes keep the retired Panels-menu '
      'keys and toggle panels', (tester) async {
    await pumpHome(tester);

    // Close a panel by its tab X, reopen it from Window (the old flow).
    await tester.tap(find.byKey(const ValueKey<String>('panel-close-brushes')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('panel-tab-brushes')),
      findsNothing,
    );

    await openMenu(tester, 'panels-menu-button');
    await tester.tap(
      find.byKey(const ValueKey<String>('panels-menu-item-brushes')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('panel-tab-brushes')),
      findsOneWidget,
    );
  });

  testWidgets('Window: Reset Workspace Layout restores closed panels', (
    tester,
  ) async {
    await pumpHome(tester);

    await tester.tap(find.byKey(const ValueKey<String>('panel-close-brushes')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('panel-tab-brushes')),
      findsNothing,
    );

    await openMenu(tester, 'panels-menu-button');
    // The Window menu grew past the test viewport (one checkbox per
    // panel) — the reset item at the bottom needs scrolling into view,
    // the long-Edit-menu pattern.
    final resetItem = find.byKey(
      const ValueKey<String>('menu-window-reset-layout'),
    );
    await tester.ensureVisible(resetItem);
    await tester.pumpAndSettle();
    await tester.tap(resetItem);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('panel-tab-brushes')),
      findsOneWidget,
    );
  });

  testWidgets('Help: About opens the framework about dialog', (tester) async {
    await pumpHome(tester);

    await openMenu(tester, 'menu-help');
    await tester.tap(find.byKey(const ValueKey<String>('menu-help-about')));
    await tester.pumpAndSettle();

    expect(find.byType(AboutDialog), findsOneWidget);
  });

  testWidgets('Edit: Input Inspector toggles the diagnosis overlay (PEN-1)', (
    tester,
  ) async {
    addTearDown(InputInspector.reset);
    await pumpHome(tester);

    // The Edit menu is long — the inspector entry sits at the bottom and
    // needs scrolling into the menu panel's view first.
    Future<void> tapInspectorItem() async {
      final item = find.byKey(
        const ValueKey<String>('menu-edit-input-inspector'),
      );
      await tester.ensureVisible(item);
      await tester.pumpAndSettle();
      await tester.tap(item);
      await tester.pumpAndSettle();
    }

    await openMenu(tester, 'menu-edit');
    await tapInspectorItem();
    expect(
      find.byKey(const ValueKey<String>('input-inspector-card')),
      findsOneWidget,
    );

    await openMenu(tester, 'menu-edit');
    await tapInspectorItem();
    expect(
      find.byKey(const ValueKey<String>('input-inspector-card')),
      findsNothing,
    );
  });

  testWidgets('Edit: Frame Timing Overlay toggles the measurement switch', (
    tester,
  ) async {
    addTearDown(MeasurementMode.reset);
    await pumpHome(tester);

    Future<void> tapOverlayItem() async {
      final item = find.byKey(
        const ValueKey<String>('menu-edit-frame-timing-overlay'),
      );
      await tester.ensureVisible(item);
      await tester.pumpAndSettle();
      await tester.tap(item);
      await tester.pumpAndSettle();
    }

    expect(MeasurementMode.frameTimingOverlay.value, isFalse);

    await openMenu(tester, 'menu-edit');
    await tapOverlayItem();
    expect(
      MeasurementMode.frameTimingOverlay.value,
      isTrue,
      reason: 'the menu entry drives the switch MaterialApp reads',
    );

    await openMenu(tester, 'menu-edit');
    await tapOverlayItem();
    expect(MeasurementMode.frameTimingOverlay.value, isFalse);
  });
}
