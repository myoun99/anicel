import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show LayerNestingArrowCell;
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart'
    show layerRailNestingSlotWidth;
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';

/// R27 #23~#29 asked for a folder row that reads exactly like a layer row.
/// It IS one now — the same widget, so parity is by construction and these
/// tests check the folder-shaped parts of it (the glyph, the fold twirl,
/// the structural menu) plus the session verbs.
void main() {
  Layer folder({
    bool collapsed = false,
    double opacity = 1,
    LayerBlendMode blend = LayerBlendMode.passThrough,
  }) => createFolderLayer(id: const LayerId('f'), name: 'F').copyWith(
    collapsed: collapsed,
    opacity: opacity,
    blendMode: blend,
  );

  Widget host(
    Layer value, {
    bool active = false,
    void Function(LayerId, double)? onOpacity,
    void Function(LayerId, LayerBlendMode)? onBlend,
    ValueChanged<LayerId>? onSelect,
    ValueChanged<LayerId>? onToggleFx,
    ValueChanged<LayerId>? onToggleFold,
    ValueChanged<LayerId>? onToggleLanes,
    int depth = 0,
    AttachedPlacement? attachArrow,
  }) => MaterialApp(
    home: Scaffold(
      body: TimelineLayerControlsRow(
        layer: value,
        active: active,
        depth: depth,
        attachArrowPlacement: attachArrow,
        metrics: TimelineGridMetrics.defaults,
        onSelectLayer: onSelect ?? (_) {},
        onToggleLayerVisibility: (_) {},
        onLayerOpacityChanged: onOpacity ?? (_, _) {},
        onLayerOpacityChangeEnd: onOpacity,
        onToggleLayerTimesheet: (_) {},
        onLayerMarkSelected: (_, _) {},
        hasLanes: true,
        onToggleLanes: onToggleLanes ?? (_) {},
        hasGroupFold: true,
        groupFoldExpanded: !value.collapsed,
        onToggleGroupFold: onToggleFold ?? (_) {},
        onToggleLayerFx: onToggleFx ?? (_) {},
        onLayerBlendModeSelected: onBlend,

      ),
    ),
  );

  testWidgets('the folder row carries the LAYER columns — one widget, so '
      'the columns cannot drift apart', (tester) async {
    await tester.pumpWidget(host(folder(), onBlend: (_, _) {}));

    for (final key in [
      'timeline-folder-row-f',
      'timeline-folder-twirl-f',
      'timeline-folder-icon-f',
      'timeline-lane-toggle-f',
      'timeline-layer-fx-f',
      'timeline-layer-visibility-f',
      'timeline-layer-opacity-f',
      'timeline-layer-blend-f',
    ]) {
      expect(
        find.byKey(ValueKey<String>(key)),
        findsOneWidget,
        reason: '$key must be present',
      );
    }
    expect(find.text('fx'), findsOneWidget);
    expect(
      find.text('Pass Through'),
      findsOneWidget,
      reason: 'a fresh folder buffers nothing — PS/CSP\'s default',
    );
  });

  testWidgets('a folder prints nothing, so its sheet toggle stays an empty '
      'reserved slot', (tester) async {
    await tester.pumpWidget(host(folder()));
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-timesheet-f')),
      findsNothing,
    );
  });

  testWidgets('R28 #13: fx BYPASSES, the leading twirl opens the lanes, and '
      'the fold twirl sits right of the name', (tester) async {
    final fxToggles = <LayerId>[];
    final laneToggles = <LayerId>[];
    final foldToggles = <LayerId>[];

    await tester.pumpWidget(
      host(
        folder(),
        onToggleFx: fxToggles.add,
        onToggleLanes: laneToggles.add,
        onToggleFold: foldToggles.add,
      ),
    );

    // The fx button is a SWITCH — it must not open anything.
    await tester.tap(find.byKey(const ValueKey<String>('timeline-layer-fx-f')));
    await tester.pump();
    expect(fxToggles, [const LayerId('f')]);
    expect(
      laneToggles,
      isEmpty,
      reason: 'R28 #13: fx no longer twirls the Transform lanes open — that '
          'is what made folders read as wired differently from layers',
    );

    // The LEADING twirl opens the lanes, like a layer row's.
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-lane-toggle-f')),
    );
    await tester.pump();
    expect(laneToggles, [const LayerId('f')]);

    // The fold twirl sits RIGHT of the name (the attach-group twirl's
    // position — they are one control).
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-folder-twirl-f')),
    );
    await tester.pump();
    expect(foldToggles, [const LayerId('f')]);
    expect(
      tester
          .getRect(find.byKey(const ValueKey<String>('timeline-folder-twirl-f')))
          .left,
      greaterThan(
        tester
            .getRect(find.byKey(const ValueKey<String>('timeline-lane-toggle-f')))
            .right,
      ),
      reason: 'the fold moved out of the leading slot to beside the name',
    );
  });

  testWidgets('the row selects, and the selected row wears the layer rows\' '
      'selection background', (tester) async {
    LayerId? selected;
    await tester.pumpWidget(host(folder(), onSelect: (id) => selected = id));
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-folder-row-f')),
    );
    await tester.pump();
    expect(selected, const LayerId('f'));

    Color? rowColor(WidgetTester tester) {
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(const ValueKey<String>('timeline-folder-row-f')),
              matching: find.byType(Container),
            )
            .first,
      );
      return (container.decoration! as BoxDecoration).color;
    }

    final resting = rowColor(tester);
    await tester.pumpWidget(host(folder(), active: true));
    expect(rowColor(tester), isNot(resting));
  });

  testWidgets('R27 #29: the blend flyout commits the folder\'s mode', (
    tester,
  ) async {
    LayerBlendMode? picked;
    await tester.pumpWidget(
      host(folder(), onBlend: (_, mode) => picked = mode),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-layer-blend-f')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-layer-blend-option-multiply')),
    );
    await tester.pumpAndSettle();
    expect(picked, LayerBlendMode.multiply);
  });

  test('R27 #24: folding a folder whose member is active selects the '
      'FOLDER — one selection, because a folder is a layer', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.createDrawingAtCurrentFrame();
    final layerId = s.activeLayer!.id;
    s.groupActiveLayerIntoFolder();
    final folderId = s.activeCutOrNull!.layers.folderLayers.single.id;
    expect(s.activeLayerId, layerId);

    s.toggleLayerCollapsed(folderId);
    expect(s.activeLayerId, folderId);

    s.selectLayer(layerId);
    expect(s.activeLayerId, layerId);
  });

  test('R27 #29: the folder blend rides the LAYER blend commit', () {
    final plain = folder();
    expect(
      plain.toJson()['blendMode'],
      'passThrough',
      reason: 'a folder always writes its mode — its default is not the '
          'omitted-from-JSON `normal`',
    );
    final blended = plain.copyWith(blendMode: LayerBlendMode.screen);
    expect(
      Layer.fromJson(blended.toJson()).blendMode,
      LayerBlendMode.screen,
    );

    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.createDrawingAtCurrentFrame();
    s.groupActiveLayerIntoFolder();
    final folderId = s.activeCutOrNull!.layers.folderLayers.single.id;
    s.setLayerBlendMode(folderId, LayerBlendMode.multiply);
    expect(
      s.activeCutOrNull!.layers.folderById(folderId)!.blendMode,
      LayerBlendMode.multiply,
    );
  });

  // R5 #18. Nesting is a COUNT OF COLUMNS now, not an amount of blank.
  group('folder nesting spends whole cells', () {
    double nameLeft(WidgetTester tester) => tester
        .getRect(find.byKey(const ValueKey<String>('timeline-layer-name-f')))
        .left;

    testWidgets('one blank cell per level, and exactly one arrow however '
        'deep', (tester) async {
      await tester.pumpWidget(host(folder()));
      final flat = nameLeft(tester);
      expect(find.byType(LayerNestingArrowCell), findsNothing);

      await tester.pumpWidget(host(folder(), depth: 1));
      expect(find.byType(LayerNestingArrowCell), findsOneWidget);
      expect(
        nameLeft(tester) - flat,
        moreOrLessEquals(2 * layerRailNestingSlotWidth, epsilon: 0.5),
        reason: 'one blank cell plus the arrow cell',
      );

      await tester.pumpWidget(host(folder(), depth: 2));
      expect(
        find.byType(LayerNestingArrowCell),
        findsOneWidget,
        reason: 'depth is counted in blanks; the arrow says it once',
      );
      expect(
        nameLeft(tester) - flat,
        moreOrLessEquals(3 * layerRailNestingSlotWidth, epsilon: 0.5),
      );
    });

    testWidgets('a row that already carries an ATTACH arrow keeps the cell '
        'and gives up the glyph', (tester) async {
      await tester.pumpWidget(host(folder(), depth: 1));
      final nested = nameLeft(tester);

      await tester.pumpWidget(
        host(folder(), depth: 1, attachArrow: AttachedPlacement.below),
      );
      expect(
        find.byType(LayerNestingArrowCell),
        findsNothing,
        reason: 'two arrows a column apart would answer one question twice',
      );
      expect(
        nameLeft(tester),
        moreOrLessEquals(nested, epsilon: 0.5),
        reason: 'the CELL stays reserved, so the name does not start early',
      );
    });
  });

  // R5 #2. The test above asks the REPOSITORY and passes; the rails do not
  // render the repository's folder, they render its band clone — so every
  // test that stopped at the repo was blind to a whole row's worth of dead
  // controls. These ask the display the same questions.
  test('R5 #2: the folder BAND clone follows the folder itself, not only '
      'its members\' exposures', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.createDrawingAtCurrentFrame();
    s.groupActiveLayerIntoFolder();
    final folderId = s.activeCutOrNull!.layers.folderLayers.single.id;

    // Exactly the read the rail hosts do (`_displayLayers`).
    Layer band() => s.folderBandLayerFor(
      s.layers.firstWhere((layer) => layer.id == folderId),
    );

    expect(band().collapsed, isFalse);
    s.toggleLayerCollapsed(folderId);
    expect(
      band().collapsed,
      isTrue,
      reason: 'folding moves no member exposure, so a union-only cache key '
          'handed back the pre-fold clone and the twirl read as dead',
    );

    expect(band().blendMode, LayerBlendMode.passThrough);
    s.setLayerBlendMode(folderId, LayerBlendMode.multiply);
    expect(band().blendMode, LayerBlendMode.multiply);

    s.renameLayer(folderId, 'Renamed');
    expect(band().name, 'Renamed');

    s.toggleLayerVisibility(folderId);
    expect(band().isVisible, isFalse);

    // …and the identity the cache exists for still holds: no edit, same
    // instance, so nothing downstream re-records for free.
    final resting = band();
    expect(identical(band(), resting), isTrue);
  });
}
