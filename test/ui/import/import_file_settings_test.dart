import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/import/media_import_planner.dart'
    show ImportDestination;
import 'package:anicel/src/ui/import/import_file_settings.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/import/import_layer_spot.dart';

/// The per-file rules. The window used to hold ONE answer for a whole batch
/// and lie about three files at once; these are the lies, pinned as rules.
void main() {
  const defaults = ImportFileSettings();

  ImportFileSettings resolve(
    ImportFileSettings settings, {
    MediaAssetKind? kind = MediaAssetKind.image,
    bool isPsd = false,
    bool placing = true,
    bool hasActiveCut = true,
  }) => resolvedImportSettings(
    settings,
    kind: kind,
    isPsd: isPsd,
    placing: placing,
    hasActiveCut: hasActiveCut,
  );

  group('the file column is the POOL\'s question', () {
    test('two answers — carry or link. Baking is the layer\'s question now '
        '(유저 2026-09-11, 라운드 5: the one column was split in two)', () {
      expect(ImportFileMode.values, [
        ImportFileMode.reference,
        ImportFileMode.keepInside,
      ]);
    });

    test('a movie STARTS as a reference — that is a default, not a wall', () {
      expect(
        defaultImportMode(MediaAssetKind.video),
        ImportFileMode.reference,
      );
      expect(
        defaultImportMode(MediaAssetKind.audio),
        ImportFileMode.keepInside,
      );
    });

    test('and a movie the user asks for STAYS kept inside', () {
      // The ceiling that refused this was reversed on 08-14: a person who
      // wants a three-second take inside the project file gets to say so.
      final resolved = resolve(
        defaults.copyWith(mode: ImportFileMode.keepInside),
        kind: MediaAssetKind.video,
      );
      expect(resolved.mode, ImportFileMode.keepInside);
    });
  });

  group('bake — the layer\'s question', () {
    test('asked only where something is PLACED, and only of what has '
        'pictures', () {
      expect(
        importBakeAllowed(kind: MediaAssetKind.image, placing: true),
        isTrue,
      );
      expect(importBakeAllowed(kind: MediaAssetKind.pdf, placing: true), isTrue);
      expect(
        importBakeAllowed(kind: MediaAssetKind.image, placing: false),
        isFalse,
        reason: 'the pool registers; nothing is placed there to bake',
      );
      expect(
        importBakeAllowed(kind: MediaAssetKind.audio, placing: true),
        isFalse,
        reason: 'a sound has no pixels',
      );
      expect(
        importBakeAllowed(kind: MediaAssetKind.video, placing: true),
        isTrue,
        reason:
            'a movie has pictures — for a movie the answer is whether it '
            'stays a reference (「참조 여부 = 배치 창의 굽기 열」)',
      );
    });

    test('🚨a bake the file cannot give does not stick — and it does not '
        'touch the carry answer: one question never answers the other', () {
      final sound = resolve(
        defaults.copyWith(bake: true, mode: ImportFileMode.reference),
        kind: MediaAssetKind.audio,
      );
      expect(sound.bake, isFalse);
      expect(sound.mode, ImportFileMode.reference);

      final registering = resolve(defaults.copyWith(bake: true), placing: false);
      expect(registering.bake, isFalse);
    });

    test('a picture keeps the bake it was given, and its carry answer', () {
      final baked = resolve(
        defaults.copyWith(bake: true, mode: ImportFileMode.reference),
      );
      expect(baked.bake, isTrue);
      expect(baked.mode, ImportFileMode.reference);
    });

    test('bake starts off: a placed file is a reference until someone asks '
        'for its pixels', () {
      expect(defaults.bake, isFalse);
    });
  });

  group('trimming', () {
    test('a trimmed source cannot be a reference — a pointer has no '
        'in and out (until trimmed references are lifted)', () {
      final trimmed = defaults.copyWith(
        mode: ImportFileMode.reference,
        inFrame: 12,
      );
      expect(trimmed.isTrimmed, isTrue);
      expect(resolve(trimmed).mode, ImportFileMode.keepInside);
      expect(
        importModeAllowed(mode: ImportFileMode.reference, trimmed: true),
        isFalse,
      );
    });

    test('an untouched range leaves reference alone', () {
      final whole = defaults.copyWith(mode: ImportFileMode.reference);
      expect(whole.isTrimmed, isFalse);
      expect(resolve(whole).mode, ImportFileMode.reference);
    });

    test('an out point alone counts as a trim', () {
      expect(defaults.copyWith(outFrame: 40).isTrimmed, isTrue);
    });

    test('carrying is never refused', () {
      for (final trimmed in [false, true]) {
        expect(
          importModeAllowed(mode: ImportFileMode.keepInside, trimmed: trimmed),
          isTrue,
        );
      }
    });
  });

  group('the destination is ONE answer (pool-drop-picks-layer-or-cut)', () {
    test('with no cut in hand a placement has one destination — a new cut — '
        'and a new cut is 1:1 (유저 2026-09-12: 「액티브 컷이 없는 상태에서 '
        '캔버스 떨구면 새 컷 고정」)', () {
      final resolved = resolve(defaults, hasActiveCut: false);
      expect(resolved.into, ImportDestination.newCut);
      expect(resolved.fit, MediaFitMode.none);
    });

    test('a drop that answered the cut holds that answer — the row the file '
        'was let go on is in the active cut, whatever the row was answered '
        'before', () {
      final resolved = resolvedImportSettings(
        const ImportFileSettings(into: ImportDestination.newCut),
        kind: MediaAssetKind.image,
        isPsd: false,
        placing: true,
        hasActiveCut: true,
        spot: const LayerSlotSpot(1),
      );
      expect(resolved.into, ImportDestination.activeCutLayer);
    });

    test('the canvas answers no cut — what the row was answered stands', () {
      final resolved = resolvedImportSettings(
        const ImportFileSettings(into: ImportDestination.newCut),
        kind: MediaAssetKind.image,
        isPsd: false,
        placing: true,
        hasActiveCut: true,
        spot: const AboveActiveLayerSpot(),
      );
      expect(resolved.into, ImportDestination.newCut);
    });
  });

  group('psd', () {
    test('frames dropped on a row lock BAKE on and the PSD to merge — a '
        'row\'s cells are its pixels, and a row takes pictures, not a stack',
        () {
      const spot = RowFramesSpot(layerId: LayerId('a'), frameIndex: 0);
      final resolved = resolvedImportSettings(
        const ImportFileSettings(
          mode: ImportFileMode.reference,
          psd: PsdPlaceMode.expand,
        ),
        kind: MediaAssetKind.image,
        isPsd: true,
        placing: true,
        hasActiveCut: true,
        spot: spot,
      );
      expect(resolved.bake, isTrue);
      expect(resolved.psd, PsdPlaceMode.merge);
      expect(
        importBakeLocked(
          isPsd: false,
          placing: true,
          psd: PsdPlaceMode.merge,
          spot: spot,
        ),
        isTrue,
      );
      expect(importPsdLocked(spot), isTrue);
      expect(importPsdLocked(null), isFalse);
      expect(importPsdLocked(const AboveActiveLayerSpot()), isFalse);
    });

    test('expanding locks BAKE on — the stack is its pixels — and leaves the '
        'carry answer alone: the file still registers', () {
      final resolved = resolve(
        defaults.copyWith(
          psd: PsdPlaceMode.expand,
          mode: ImportFileMode.reference,
        ),
        isPsd: true,
      );
      expect(resolved.bake, isTrue);
      expect(resolved.mode, ImportFileMode.reference);
      expect(
        importBakeLocked(isPsd: true, placing: true, psd: PsdPlaceMode.expand),
        isTrue,
      );
    });

    test('merging leaves bake open', () {
      final resolved = resolve(
        defaults.copyWith(psd: PsdPlaceMode.merge),
        isPsd: true,
      );
      expect(resolved.bake, isFalse);
      expect(
        importBakeLocked(isPsd: true, placing: true, psd: PsdPlaceMode.merge),
        isFalse,
      );
    });

    test('a PSD registered into the pool is just a file — expand does not '
        'apply', () {
      final resolved = resolve(
        defaults.copyWith(psd: PsdPlaceMode.expand),
        isPsd: true,
        placing: false,
      );
      expect(resolved.bake, isFalse);
      expect(
        importBakeLocked(isPsd: true, placing: false, psd: PsdPlaceMode.expand),
        isFalse,
      );
    });

    test('both Photoshop extensions are recognised', () {
      expect(importPathIsPsd('/a/BG.psd'), isTrue);
      expect(importPathIsPsd('/a/BG.PSB'), isTrue);
      expect(importPathIsPsd('/a/BG.png'), isFalse);
      expect(importPathIsPsd('BG'), isFalse);
    });
  });

  group('a NEW cut is made at the file\'s own size — its fit is 1:1, locked '
      '(유저 2026-09-11: 「1:1로 고정시켜서 노출시키도록. 비활성화된상태로」)', () {
    test('whatever fit was pressed, a new cut resolves to 1:1', () {
      for (final fit in MediaFitMode.values) {
        final resolved = resolve(
          defaults.copyWith(into: ImportDestination.newCut, fit: fit),
        );
        expect(resolved.fit, MediaFitMode.none, reason: '$fit');
      }
      expect(
        importFitLocked(
          defaults.copyWith(into: ImportDestination.newCut),
          placing: true,
        ),
        isTrue,
      );
    });

    test('a new layer keeps the fit it was given', () {
      final resolved = resolve(defaults.copyWith(fit: MediaFitMode.stretch));
      expect(resolved.fit, MediaFitMode.stretch);
      expect(importFitLocked(defaults, placing: true), isFalse);
    });

    test('the pool places nothing, so it locks nothing', () {
      expect(
        importFitLocked(
          defaults.copyWith(into: ImportDestination.newCut),
          placing: false,
        ),
        isFalse,
      );
    });
  });

  group('labels', () {
    test('every answer has a word', () {
      for (final mode in ImportFileMode.values) {
        expect(importModeLabel(mode), isNotEmpty);
      }
      for (final fit in MediaFitMode.values) {
        expect(importFitLabel(fit), isNotEmpty);
      }
      for (final into in ImportDestination.values) {
        expect(importIntoLabel(into), isNotEmpty);
      }
      for (final psd in PsdPlaceMode.values) {
        expect(importPsdLabel(psd), isNotEmpty);
      }
      expect(importOnOffLabel(true), isNot(importOnOffLabel(false)));
    });

    test('⛔the fit never says the word the file column says for carrying — '
        '「Keep」 meant contain in one column and carry in the next', () {
      final carry = importModeLabel(ImportFileMode.keepInside);
      for (final fit in MediaFitMode.values) {
        expect(importFitLabel(fit), isNot(carry), reason: '$fit');
      }
    });
  });
}
