import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/playback/cut_frame_composite_signature.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_action_toolbar.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// R26 #30/#30-1: the layer's composite blend mode — model round-trip,
/// the shared composite visit, cache identity, the session commit and
/// the toolbar's PS/CSP-style blend dropdown (user rule 07-22: the type
/// button went back to function-TBD).
void main() {
  test('JSON: normal is omitted (pre-blend files read back unchanged); a '
      'non-normal blend round-trips', () {
    final plain = Layer(id: const LayerId('a'), name: 'A', frames: const []);
    expect(plain.toJson().containsKey('blendMode'), isFalse);
    expect(Layer.fromJson(plain.toJson()).blendMode, LayerBlendMode.normal);

    final multiplied = plain.copyWith(blendMode: LayerBlendMode.multiply);
    expect(multiplied.toJson()['blendMode'], 'multiply');
    expect(
      Layer.fromJson(multiplied.toJson()).blendMode,
      LayerBlendMode.multiply,
    );
    expect(multiplied == plain, isFalse, reason: 'blend joins equality');
  });

  test('the session commit lands on the layer and the shared composite '
      'visit carries it', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createDrawingAtCurrentFrame();
    final layerId = s.activeLayer!.id;

    s.setLayerBlendMode(layerId, LayerBlendMode.screen);
    expect(s.activeLayer!.blendMode, LayerBlendMode.screen);

    final entries = resolveCutFrameCompositeEntries(
      cut: s.activeCutOrNull!,
      frameIndex: 0,
    );
    final entry = entries.singleWhere((e) => e.layer.id == layerId);
    expect(entry.blendMode, LayerBlendMode.screen);
  });

  test('a blend change changes the composite cache identity', () {
    const base = CompositeLayerSignature(
      layerId: LayerId('a'),
      frameId: FrameId('f1'),
      opacity: 1,
      sourceRevision: 3,
    );
    const blended = CompositeLayerSignature(
      layerId: LayerId('a'),
      frameId: FrameId('f1'),
      opacity: 1,
      sourceRevision: 3,
      blendMode: LayerBlendMode.multiply,
    );
    expect(base == blended, isFalse);
    expect(
      base ==
          const CompositeLayerSignature(
            layerId: LayerId('a'),
            frameId: FrameId('f1'),
            opacity: 1,
            sourceRevision: 3,
          ),
      isTrue,
    );
  });

  testWidgets('R27 #6: the blend dropdown lives in the LAYER LABEL — it '
      'reads the row\'s own mode, commits a pick, speaks CSP Japanese in '
      'ja, and the toolbar no longer carries one', (tester) async {
    var committed = <(LayerId, LayerBlendMode)>[];
    Widget rowHost(Layer layer, AppLanguage language) => MaterialApp(
      home: Material(
        child: TimelineLayerControlsRow(
          layer: layer,
          active: false,
          metrics: TimelineGridMetrics.defaults,
          onSelectLayer: (_) {},
          onToggleLayerVisibility: (_) {},
          onLayerOpacityChanged: (_, _) {},
          onToggleLayerTimesheet: (_) {},
          onLayerMarkSelected: (_, _) {},
          blendLanguage: language,
          onLayerBlendModeSelected: (id, mode) =>
              committed.add((id, mode)),
        ),
      ),
    );

    final drawing = Layer(
      id: const LayerId('a'),
      name: 'A',
      kind: LayerKind.animation,
      frames: const [],
    );
    const chipKey = ValueKey<String>('timeline-layer-blend-a');

    await tester.pumpWidget(rowHost(drawing, AppLanguage.en));
    expect(find.byKey(chipKey), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);

    await tester.tap(find.byKey(chipKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('timeline-layer-blend-option-multiply'),
      ),
    );
    await tester.pumpAndSettle();
    expect(committed, [(const LayerId('a'), LayerBlendMode.multiply)]);

    // The chip prints the row's OWN mode.
    await tester.pumpWidget(
      rowHost(drawing.copyWith(blendMode: LayerBlendMode.multiply),
          AppLanguage.en),
    );
    expect(find.text('Multiply'), findsOneWidget);

    // ja: Clip Studio's terms (user rule 07-22 — ja localized first).
    await tester.pumpWidget(
      rowHost(drawing.copyWith(blendMode: LayerBlendMode.multiply),
          AppLanguage.ja),
    );
    expect(find.text('乗算'), findsOneWidget);

    // A non-compositing row (CAM) reserves the slot but shows no chip.
    await tester.pumpWidget(
      rowHost(
        Layer(
          id: const LayerId('a'),
          name: 'CAM',
          kind: LayerKind.camera,
          frames: const [],
        ),
        AppLanguage.en,
      ),
    );
    expect(find.byKey(chipKey), findsNothing);

    // ...and the toolbar's dropdown is gone for good.
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TimelineActionToolbar(
            session: s,
            onAddLayer: () {},
            onRenameLayer: () {},
            onDeleteLayer: () {},
            onEditInstance: () {},
            onCreateInstance: () {},
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-blend-menu-button')),
      findsNothing,
    );
  });

  testWidgets('R28 #2: the row blend control IS the tool-settings button — '
      'shared widget, no caret, centered in the blend slot', (tester) async {
    final drawing = Layer(
      id: const LayerId('a'),
      name: 'A',
      kind: LayerKind.animation,
      frames: const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: TimelineLayerControlsRow(
              layer: drawing,
              active: false,
              metrics: TimelineGridMetrics.defaults,
              onSelectLayer: (_) {},
              onToggleLayerVisibility: (_) {},
              onLayerOpacityChanged: (_, _) {},
              onToggleLayerTimesheet: (_) {},
              onLayerMarkSelected: (_, _) {},
              onLayerBlendModeSelected: (_, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const chipKey = ValueKey<String>('timeline-layer-blend-a');
    // The SHARED control, not a bespoke label: the same widget the brush
    // panel's blend row mounts.
    expect(
      find.byKey(chipKey),
      findsOneWidget,
      reason: 'the blend control keeps its key across the widget swap',
    );
    expect(tester.widget(find.byKey(chipKey)), isA<PanelFlyoutButton>());

    // The user asked for the caret to go — text-only button.
    expect(
      find.descendant(
        of: find.byKey(chipKey),
        matching: find.byIcon(Icons.arrow_drop_down),
      ),
      findsNothing,
      reason: 'R28 #2: the layer rail drops the dropdown caret',
    );

    // ...and the label sits CENTERED in the reserved slot, so the button
    // lines up under the legend's BLND header instead of hugging the
    // opacity bar on its left.
    final slot = find.ancestor(
      of: find.byKey(chipKey),
      matching: find.byType(SizedBox),
    );
    final slotCenter = tester.getCenter(slot.first).dx;
    final buttonCenter = tester.getCenter(find.byKey(chipKey)).dx;
    expect(
      (buttonCenter - slotCenter).abs(),
      lessThan(1.0),
      reason: 'R28 #2: the blend button is centered in its column',
    );
  });

  test('R27 #6: the legend bulk sets every DISPLAYED compositing row and '
      'leaves the rest alone', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final camera = s.layers.firstWhere((l) => l.kind == LayerKind.camera);
    final drawing = s.layers.firstWhere(
      (l) => l.kind == LayerKind.animation,
    );

    s.setBlendModeForLayers({drawing.id, camera.id}, LayerBlendMode.screen);

    expect(
      s.layers.firstWhere((l) => l.id == drawing.id).blendMode,
      LayerBlendMode.screen,
    );
    expect(
      s.layers.firstWhere((l) => l.id == camera.id).blendMode,
      LayerBlendMode.normal,
      reason: 'the camera row does not composite artwork',
    );
  });
}
