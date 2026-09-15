import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_kind.dart';

void main() {
  group('LayerKind', () {
    test('serializes stable strings', () {
      expect(LayerKind.animation.toJson(), 'animation');
      expect(LayerKind.storyboard.toJson(), 'storyboard');
      expect(LayerKind.se.toJson(), 'se');
      expect(LayerKind.camera.toJson(), 'camera');
    });

    test('deserializes stable strings', () {
      expect(LayerKind.fromJson('animation'), LayerKind.animation);
      expect(LayerKind.fromJson('storyboard'), LayerKind.storyboard);
      expect(LayerKind.fromJson('image'), LayerKind.image);
      expect(LayerKind.fromJson('text'), LayerKind.text);
      expect(LayerKind.fromJson('se'), LayerKind.se);
      expect(LayerKind.fromJson('camera'), LayerKind.camera);
    });

    test('the retired ART kind loads as animation (it always behaved as '
        'one — only the icon differed)', () {
      expect(LayerKind.fromJson('art'), LayerKind.animation);
    });

    test('throws for invalid JSON values', () {
      expect(() => LayerKind.fromJson('panel'), throwsArgumentError);
      expect(() => LayerKind.fromJson(0), throwsArgumentError);
      expect(() => LayerKind.fromJson(null), throwsArgumentError);
    });

    test('the COVERING kinds (storyboard, image) are the gapless ones, and '
        'the only ones that refuse repeat regions (design E)', () {
      for (final kind in [LayerKind.storyboard, LayerKind.image]) {
        expect(kind.coversWithoutGaps, isTrue, reason: '$kind');
        expect(kind.acceptsRepeatRegions, isFalse, reason: '$kind');
      }

      expect(LayerKind.animation.coversWithoutGaps, isFalse);
      expect(LayerKind.animation.acceptsRepeatRegions, isTrue);

      // Rows that hold no drawings at all take no repeat regions either —
      // the predicate answers for every kind, not just the two it names.
      for (final kind in [LayerKind.camera, LayerKind.folder]) {
        expect(kind.acceptsRepeatRegions, isFalse, reason: '$kind');
      }
    });

    test('the TEXT row (R5, §6-s): the drawing sibling that refuses the '
        'brush — frames/exposure like animation, attach base, cel export, '
        'no timesheet column, typed picture instead of penned', () {
      expect(LayerKind.text.toJson(), 'text');
      expect(LayerKind.text.holdsDrawings, isTrue);
      expect(LayerKind.text.isDrawingCel, isTrue);
      expect(
        LayerKind.text.acceptsBrushInput,
        isFalse,
        reason: 'the alias split: a text cel is typed, never penned',
      );
      expect(LayerKind.text.composites, isTrue);
      expect(LayerKind.text.paintsArtwork, isTrue);
      expect(LayerKind.text.exportsCels, isTrue);
      expect(LayerKind.text.isClipboardCopyable, isTrue);
      expect(LayerKind.text.coversWithoutGaps, isFalse);
      expect(LayerKind.text.holdsSingleCel, isFalse);
      expect(LayerKind.text.isFixed, isFalse);
      // Every OTHER drawing-cel kind still takes the brush — the split
      // must not widen.
      for (final kind in LayerKind.values) {
        if (kind == LayerKind.text) {
          continue;
        }
        expect(
          kind.acceptsBrushInput,
          kind.isDrawingCel,
          reason: '$kind',
        );
      }
    });

    test('the IMAGE row: one cel by definition, no timesheet column, an '
        'attach-base drawing cel that still takes the brush at kind level',
        () {
      expect(LayerKind.image.holdsSingleCel, isTrue);
      expect(LayerKind.image.isDrawingCel, isTrue);
      expect(LayerKind.image.acceptsBrushInput, isTrue);
      expect(LayerKind.image.exportsCels, isTrue);
      for (final kind in LayerKind.values) {
        if (kind != LayerKind.image) {
          expect(kind.holdsSingleCel, isFalse, reason: '$kind');
        }
      }
    });

    _theCapabilityTable();
  });
}

/// 🚨THE TABLE, COLUMN BY COLUMN.
///
/// COMPLETENESS is not a test: the capabilities are REQUIRED named
/// parameters, so a kind that fails to answer one is a compile error — the
/// same protection the twenty-six exhaustive switches gave and the reason
/// the table has that shape (audit round 8, 2026-09-07).
///
/// What a test still has to catch is a WRONG column. Each entry below names
/// the kinds that answer TRUE, and every other kind must answer false — so
/// flipping one cell in `layer_kind.dart` turns exactly one case red, and
/// the case says which capability and which kind.
///
/// ⛔The three columns that match today are listed three times ON PURPOSE.
/// `composites`, `hasPictureOpacity` and `hasLayerEffects` hold the same
/// trues, and R27 #16 is the standing proof that a shared answer is not a
/// shared question: whoever splits them later changes ONE list here.
void _theCapabilityTable() {
  void column(
    String capability,
    bool Function(LayerKind kind) read,
    Set<LayerKind> trueFor,
  ) {
    test('$capability answers ${trueFor.length} kinds true', () {
      for (final kind in LayerKind.values) {
        expect(
          read(kind),
          trueFor.contains(kind),
          reason: '$capability / ${kind.name}',
        );
      }
    });
  }

  // ---- declared columns (required constructor parameters) ----------------
  column('holdsDrawings', (kind) => kind.holdsDrawings, {
    LayerKind.animation,
    LayerKind.storyboard,
    LayerKind.image,
    LayerKind.text,
    LayerKind.se,
  });
  column('isDrawingCel', (kind) => kind.isDrawingCel, {
    LayerKind.animation,
    LayerKind.storyboard,
    LayerKind.image,
    LayerKind.text,
    LayerKind.instruction,
  });
  column('acceptsBrushInput', (kind) => kind.acceptsBrushInput, {
    LayerKind.animation,
    LayerKind.storyboard,
    LayerKind.image,
    LayerKind.instruction,
  });
  column('coversWithoutGaps', (kind) => kind.coversWithoutGaps, {
    LayerKind.storyboard,
    LayerKind.image,
  });
  column('holdsSingleCel', (kind) => kind.holdsSingleCel, {LayerKind.image});
  column('groupsLayers', (kind) => kind.groupsLayers, {LayerKind.folder});
  column('filtersBelow', (kind) => kind.filtersBelow, {LayerKind.adjustment});
  column('composites', (kind) => kind.composites, {
    LayerKind.animation,
    LayerKind.storyboard,
    LayerKind.image,
    LayerKind.text,
    LayerKind.se,
    LayerKind.instruction,
    LayerKind.folder,
    LayerKind.adjustment,
  });
  column('hasPictureOpacity', (kind) => kind.hasPictureOpacity, {
    LayerKind.animation,
    LayerKind.storyboard,
    LayerKind.image,
    LayerKind.text,
    LayerKind.se,
    LayerKind.instruction,
    LayerKind.folder,
    LayerKind.adjustment,
  });
  column('hasLayerTransform', (kind) => kind.hasLayerTransform, {
    LayerKind.animation,
    LayerKind.storyboard,
    LayerKind.image,
    LayerKind.text,
    LayerKind.se,
    LayerKind.instruction,
    LayerKind.folder,
  });
  column('hasTransformFxSwitch', (kind) => kind.hasTransformFxSwitch, {
    LayerKind.animation,
    LayerKind.storyboard,
    LayerKind.image,
    LayerKind.text,
    LayerKind.se,
    LayerKind.instruction,
    LayerKind.folder,
    LayerKind.camera,
  });
  column('hasLayerEffects', (kind) => kind.hasLayerEffects, {
    LayerKind.animation,
    LayerKind.storyboard,
    LayerKind.image,
    LayerKind.text,
    LayerKind.se,
    LayerKind.instruction,
    LayerKind.folder,
    LayerKind.adjustment,
  });
  column('carriesInstructions', (kind) => kind.carriesInstructions, {
    LayerKind.instruction,
    LayerKind.transition,
  });
  column('exportsCels', (kind) => kind.exportsCels, {
    LayerKind.animation,
    LayerKind.storyboard,
    LayerKind.image,
    LayerKind.text,
    LayerKind.instruction,
  });
  column('linksIntoLinkedCut', (kind) => kind.linksIntoLinkedCut, {
    LayerKind.animation,
    LayerKind.storyboard,
    LayerKind.image,
    LayerKind.text,
    LayerKind.folder,
    LayerKind.camera,
    LayerKind.adjustment,
  });
  column('isSingletonPerCut', (kind) => kind.isSingletonPerCut, {
    LayerKind.storyboard,
    LayerKind.camera,
  });
  column('isClipboardCopyable', (kind) => kind.isClipboardCopyable, {
    LayerKind.animation,
    LayerKind.storyboard,
    LayerKind.image,
    LayerKind.text,
    LayerKind.instruction,
  });
  column('isReadOnlyInCut', (kind) => kind.isReadOnlyInCut, {
    LayerKind.transition,
  });
  column('reordersInCut', (kind) => kind.reordersInCut, {
    LayerKind.animation,
    LayerKind.storyboard,
    LayerKind.image,
    LayerKind.text,
    LayerKind.se,
    LayerKind.instruction,
    LayerKind.folder,
    LayerKind.adjustment,
  });
  // F-115: every kind but SE — an SE entry's name is its dialogue, and the
  // same line may repeat on a sheet.
  column('celNameIsIdentity', (kind) => kind.celNameIsIdentity, {
    LayerKind.animation,
    LayerKind.storyboard,
    LayerKind.image,
    LayerKind.folder,
    LayerKind.text,
    LayerKind.instruction,
    LayerKind.transition,
    LayerKind.camera,
    LayerKind.adjustment,
  });

  // ---- derived columns ---------------------------------------------------
  // Each of these is a composition the file states as a law of its own, and
  // its own test pins the derivation; the lists here pin the RESULT, so a
  // wrong cell in a declared column above cannot pass unnoticed here.
  column('paintsArtwork', (kind) => kind.paintsArtwork, {
    LayerKind.animation,
    LayerKind.storyboard,
    LayerKind.image,
    LayerKind.text,
    LayerKind.se,
    LayerKind.instruction,
  });
  column('joinsLinkedCutConvert', (kind) => kind.joinsLinkedCutConvert, {
    LayerKind.animation,
    LayerKind.storyboard,
    LayerKind.image,
    LayerKind.text,
    LayerKind.folder,
    LayerKind.camera,
  });
  column('mirrorsEffects', (kind) => kind.mirrorsEffects, {
    LayerKind.adjustment,
  });
  column('bandIsInstructionsOnly', (kind) => kind.bandIsInstructionsOnly, {
    LayerKind.transition,
  });
  column('takesAuthoredCels', (kind) => kind.takesAuthoredCels, {
    LayerKind.animation,
    LayerKind.storyboard,
    LayerKind.image,
    LayerKind.text,
    LayerKind.se,
    LayerKind.instruction,
  });
  column('isFixed', (kind) => kind.isFixed, {
    LayerKind.folder,
    LayerKind.camera,
    LayerKind.adjustment,
  });
  column('acceptsRepeatRegions', (kind) => kind.acceptsRepeatRegions, {
    LayerKind.animation,
    LayerKind.text,
    LayerKind.se,
  });
}
