import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// R9 P1 — the three items whose whole point is that something happens
/// IMMEDIATELY, or stops happening at all.
void main() {
  EditorSessionManager makeSession() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    return session;
  }

  group('#16 — why the tile cache missed on every rebuild', () {
    test('a method tear-off is NOT identical to itself, but IS equal', () {
      // The defect in one assertion. The tile store took resolver closures
      // from a host that hands in `_session.exposureStateForLayer` fresh on
      // every build, and asked `identical` — which is false for two
      // tear-offs of the same method. So every visible tile went stale and
      // re-rastered one await at a time, which is the ~100ms between the
      // [+] tap and the new cel appearing.
      //
      // This test DOCUMENTS the language fact rather than guarding the fix:
      // the tile path needs the native engine, which `flutter test` does
      // not load, so the fix itself is verified by measurement on device
      // (Settings ▸ Frame Timing Overlay). What it does guard is the reasoning
      // — if Dart ever canonicalised tear-offs, `identical` would stop
      // being wrong and this test would tell us.
      final session = makeSession();

      expect(
        identical(session.exposureStateForLayer, session.exposureStateForLayer),
        isFalse,
        reason: 'Dart makes a fresh closure per tear-off — which is exactly '
            'why `identical` was the wrong question',
      );
      expect(
        session.exposureStateForLayer == session.exposureStateForLayer,
        isTrue,
        reason: 'same receiver + same method — the question we mean',
      );

      final other = makeSession();
      expect(
        session.exposureStateForLayer == other.exposureStateForLayer,
        isFalse,
        reason: 'a DIFFERENT receiver must still invalidate — `==` does not '
            'weaken the contract it replaced',
      );
    });
  });

  group('#2 — picking a brush must not repaint the palette', () {
    test('a preset never overwrites the HAND settings', () {
      const presetColor = 0xFF102030;
      const handColor = 0xFFAA3311;

      final preset = BrushToolState.defaults
          .copyWith(color: presetColor)
          .toBrushSettings();
      expect(
        BrushToolState.fromBrushSettings(preset).color,
        presetColor,
        reason: 'the premise: a preset really does carry a colour, which is '
            'why applying one could repaint the palette',
      );

      final hand = BrushToolState.defaults.copyWith(
        color: handColor,
        size: 77,
        stabilizerStrength: 0.42,
        brushBlendMode: BrushBlendMode.multiply,
      );

      final applied = hand.withPresetSettings(
        preset,
        tool: CanvasTool.brush,
      );

      expect(
        applied.color,
        handColor,
        reason: 'the palette is the hand, not the brush (R9 #2)',
      );
      expect(applied.size, 77, reason: 'R26 #10');
      expect(applied.brushBlendMode, BrushBlendMode.multiply, reason: 'R26 #10');
      expect(applied.stabilizerStrength, closeTo(0.42, 1e-9), reason: 'P7');
      expect(applied.tool, CanvasTool.brush);
    });
  });

  group('#7 — one storyboard row per cut', () {
    test('the predicate names the family', () {
      expect(layerKindIsSingletonPerCut(LayerKind.storyboard), isTrue);
      expect(layerKindIsSingletonPerCut(LayerKind.camera), isTrue);
      for (final kind in [
        LayerKind.animation,
        LayerKind.image,
        LayerKind.text,
        LayerKind.se,
        LayerKind.instruction,
        LayerKind.folder,
        LayerKind.adjustment,
      ]) {
        expect(
          layerKindIsSingletonPerCut(kind),
          isFalse,
          reason: '$kind may repeat in a cut',
        );
      }
    });

    test('Add Layer offers it once, then refuses — and says so first', () {
      final session = makeSession();
      int storyboardRows() => session.requireActiveCut.layers
          .where((l) => l.kind == LayerKind.storyboard)
          .length;

      expect(storyboardRows(), 0);
      expect(session.canAddLayerOfKind(LayerKind.storyboard), isTrue);

      session.addLayerOfKind(LayerKind.storyboard);
      expect(storyboardRows(), 1);

      expect(
        session.canAddLayerOfKind(LayerKind.storyboard),
        isFalse,
        reason: 'the menu entry greys out instead of swallowing the tap',
      );
      session.addLayerOfKind(LayerKind.storyboard);
      expect(
        storyboardRows(),
        1,
        reason: 'and the command path refuses too, not just the menu',
      );

      // The rule is per KIND, not a general freeze.
      expect(session.canAddLayerOfKind(LayerKind.animation), isTrue);
      final before = session.requireActiveCut.layers.length;
      session.addLayerOfKind(LayerKind.animation);
      expect(session.requireActiveCut.layers.length, before + 1);
    });

    test('copy/paste and duplicate cannot make a second one', () {
      final session = makeSession();
      session.addLayerOfKind(LayerKind.storyboard);
      final storyboard = session.activeLayer!;
      expect(storyboard.kind, LayerKind.storyboard);

      expect(
        session.canLinkDuplicateActiveLayer,
        isFalse,
        reason: 'a duplicate lands in the SAME cut',
      );

      session.copyActiveLayer();
      session.duplicateActiveLayer();
      session.pasteLayerFromClipboard();

      expect(
        session.requireActiveCut.layers
            .where((l) => l.kind == LayerKind.storyboard)
            .length,
        1,
        reason: 'every route that can MAKE a row is gated, not just Add Layer',
      );
    });
  });
}
