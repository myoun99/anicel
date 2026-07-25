import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/controllers/default_project_helpers.dart';
import 'package:quick_animaker_v2/src/models/onion_skin_settings.dart';
import 'package:quick_animaker_v2/src/ui/editor_session_manager.dart';
import 'package:quick_animaker_v2/src/ui/home_page.dart';
import 'package:quick_animaker_v2/src/ui/panels/onion_skin_panel.dart';

/// P2 wiring: the session's onion requests, the O shortcut and the panel.
void main() {
  test('onion requests target the ACTIVE layer cels at the playhead with '
      'peg opacities and tints; disabled = empty', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    // Two drawings on the default layer: cel at 0, cel at 1.
    s.createDrawingAtCurrentFrame();
    s.selectFrameIndex(1);
    s.createDrawingAtCurrentFrame();

    expect(s.onionSkinCanvasRequests(), isEmpty, reason: 'master off');

    s.toggleOnionSkin();
    final requests = s.onionSkinCanvasRequests();
    expect(requests, hasLength(1), reason: 'one unique drawing before');
    expect(requests.single.opacity, 0.4);
    expect(requests.single.tint, const OnionSkinSettings().tintBefore);
    expect(requests.single.frameKey.layerId, s.activeLayer!.id);

    // Images mode drops the tint, keeps the ghost.
    s.onionSkinSettings.value = s.onionSkinSettings.value.copyWith(
      mode: OnionSkinMode.images,
    );
    expect(s.onionSkinCanvasRequests().single.tint, isNull);
  });

  testWidgets('O toggles the ACTIVE layer onion (UI-R17 #5 — the master '
      'switch is gone); the panel strip and mode drive the settings', (
    tester,
  ) async {
    // R26 #31: the left dock stacks Tool Library over Tool Settings, so
    // each section gets about half the dock — on the 800×600 default
    // surface the onion panel's strip falls outside its section's clip.
    // A realistic window keeps them reachable.
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    // Open the Onion Skin tab in the left dock (Ahem-wide tab labels can
    // push it out of the strip's viewport in tests).
    final tab = find.byKey(const ValueKey<String>('panel-tab-onion-skin'));
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();

    // The panel only shapes ghosts now — no master switch.
    expect(
      find.byKey(const ValueKey<String>('onion-skin-master-toggle')),
      findsNothing,
    );

    // The O key toggles the ACTIVE layer's row button (tooltip carries
    // the state).
    final rowToggle = find.byKey(
      const ValueKey<String>('timeline-layer-onion-default-layer-1'),
    );
    expect(rowToggle, findsOneWidget);
    expect(tester.widget<IconButton>(rowToggle).tooltip, 'Onion skin');

    // The row button toggles the layer on.
    await tester.tap(rowToggle);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(rowToggle).tooltip, 'Onion skin (on)');

    // The O key toggles the ACTIVE layer back off.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(rowToggle).tooltip, 'Onion skin');

    // Peg 1 (before) silences through the panel's light-table strip — the
    // bar's tooltip carries its state.
    final peg1 = find.byKey(const ValueKey<String>('onion-peg-before-1'));
    expect(tester.widget<Tooltip>(peg1).message, '1 back · 40%');
    await tester.tap(peg1);
    await tester.pumpAndSettle();
    expect(tester.widget<Tooltip>(peg1).message, '1 back · off');

    // Mode switch to Images through the panel's picker.
    await tester.tap(find.byKey(const ValueKey<String>('onion-mode-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('onion-mode-images')));
    await tester.pumpAndSettle();
    expect(find.byType(OnionSkinPanel), findsOneWidget);
    expect(find.text('Images'), findsOneWidget);
  });
}
