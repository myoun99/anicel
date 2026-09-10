import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_preset.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/layer_clipboard.dart';
import 'package:anicel/src/ui/session/layer_stack.dart';

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

  // 🚨THE TWO COLLABORATORS R9 #7 LIVES IN, HELD BY THEIR OWN TYPES
  // (2026-09-08). `tool/mutation_run.dart` picks a file's witnesses by
  // which tests IMPORT it, so a collaborator only ever spelled
  // `session.layerStack` / `session.layerClipboard` is one the campaign
  // reports UNNAMED and never runs a mutant against.
  LayerStack stackOf(EditorSessionManager session) => session.layerStack;
  LayerClipboard boardOf(EditorSessionManager session) =>
      session.layerClipboard;

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
        blendMode: BrushBlendMode.multiply,
      );

      final applied = hand.withPreset(
        BrushPreset(
          id: const BrushPresetId('carries-a-colour'),
          name: 'carries a colour',
          settings: preset,
        ),
        tool: CanvasTool.brush,
      );

      expect(
        applied.color,
        handColor,
        reason: 'the palette is the hand, not the brush (R9 #2)',
      );
      // 🚨H25 (2026-08-23) took SIZE off this list: a brush wears its own
      // size now, and only a value the hand set ON THAT BRUSH overrides it.
      // The preset here carries the default, so the applied size is the
      // brush's — the point of THIS test (the palette) is untouched.
      expect(
        applied.size,
        BrushToolState.defaults.size,
        reason: 'H25 supersedes R26 #10 for size',
      );
      // ⛔And 유저 2026-09-08 took the BLEND off it too: the preset's blend
      // is the brush's, so applying one brings 通常 with it. Same reasoning
      // as size — the point of THIS test is the palette.
      expect(
        applied.blendMode,
        BrushBlendMode.color,
        reason: 'the preset carries 通常 and the brush wears it',
      );
      expect(applied.stabilizerStrength, closeTo(0.42, 1e-9), reason: 'P7');
      expect(applied.tool, CanvasTool.brush);
    });
  });

  group('#7 — one storyboard row per cut', () {
    test('the predicate names the family', () {
      expect(LayerKind.storyboard.isSingletonPerCut, isTrue);
      expect(LayerKind.camera.isSingletonPerCut, isTrue);
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
          kind.isSingletonPerCut,
          isFalse,
          reason: '$kind may repeat in a cut',
        );
      }
    });

    test('Add Layer offers it once, then refuses — and says so first', () {
      final session = makeSession();
      final stack = stackOf(session);
      int storyboardRows() => session.requireActiveCut.layers
          .where((l) => l.kind == LayerKind.storyboard)
          .length;

      expect(storyboardRows(), 0);
      expect(stack.canAddLayerOfKind(LayerKind.storyboard), isTrue);

      stack.addLayerOfKind(LayerKind.storyboard);
      expect(storyboardRows(), 1);

      expect(
        stack.canAddLayerOfKind(LayerKind.storyboard),
        isFalse,
        reason: 'the menu entry greys out instead of swallowing the tap',
      );
      stack.addLayerOfKind(LayerKind.storyboard);
      expect(
        storyboardRows(),
        1,
        reason: 'and the command path refuses too, not just the menu',
      );

      // The rule is per KIND, not a general freeze.
      expect(stack.canAddLayerOfKind(LayerKind.animation), isTrue);
      final before = session.requireActiveCut.layers.length;
      stack.addLayerOfKind(LayerKind.animation);
      expect(session.requireActiveCut.layers.length, before + 1);
    });

    test('copy/paste and duplicate cannot make a second one', () {
      final session = makeSession();
      session.layerStack.addLayerOfKind(LayerKind.storyboard);
      final storyboard = session.activeLayer!;
      expect(storyboard.kind, LayerKind.storyboard);

      expect(
        session.layerVerbs.canLinkDuplicateActiveLayer,
        isFalse,
        reason: 'a duplicate lands in the SAME cut',
      );

      // ⚠️THE PASTE ARM IS REACHED FROM HERE, and only from here — see
      // [LayerClipboard.pasteLayerFromClipboard]'s R9 #7 guard.
      final board = boardOf(session);
      board.copyActiveLayer();
      session.layerVerbs.duplicateActiveLayer();
      board.pasteLayerFromClipboard();

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
