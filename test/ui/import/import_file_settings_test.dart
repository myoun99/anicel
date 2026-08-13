import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/import/media_import_planner.dart'
    show ImportDestination;
import 'package:anicel/src/ui/import/import_file_settings.dart';

/// The per-file rules. The window used to hold ONE answer for a whole batch
/// and lie about three files at once; these are the lies, pinned as rules.
void main() {
  const defaults = ImportFileSettings();

  ImportFileSettings resolve(
    ImportFileSettings settings, {
    MediaAssetKind? kind = MediaAssetKind.image,
    bool isPsd = false,
    bool placing = true,
  }) => resolvedImportSettings(
    settings,
    kind: kind,
    isPsd: isPsd,
    placing: placing,
  );

  group('what a kind refuses', () {
    test('a movie is never kept inside, whatever the chip says', () {
      final resolved = resolve(
        defaults.copyWith(mode: ImportFileMode.keepInside),
        kind: MediaAssetKind.video,
      );
      expect(resolved.mode, ImportFileMode.reference);
    });

    test('a sound cannot be rasterized — it falls back to carried', () {
      final resolved = resolve(
        defaults.copyWith(mode: ImportFileMode.rasterize),
        kind: MediaAssetKind.audio,
      );
      expect(resolved.mode, ImportFileMode.keepInside);
    });

    test('a movie cannot be rasterized either (no decoder yet)', () {
      expect(
        importModeAllowed(
          kind: MediaAssetKind.video,
          mode: ImportFileMode.rasterize,
          psdExpanding: false,
          placing: true,
          trimmed: false,
        ),
        isFalse,
      );
    });

    test('a PDF can be rasterized: its pages are pictures', () {
      final resolved = resolve(
        defaults.copyWith(mode: ImportFileMode.rasterize),
        kind: MediaAssetKind.pdf,
      );
      expect(resolved.mode, ImportFileMode.rasterize);
    });
  });

  group('the pool', () {
    test('registering places nothing, so nothing can be absorbed', () {
      final resolved = resolve(
        defaults.copyWith(mode: ImportFileMode.rasterize),
        placing: false,
      );
      expect(resolved.mode, ImportFileMode.keepInside);
      expect(
        importModeAllowed(
          kind: MediaAssetKind.image,
          mode: ImportFileMode.rasterize,
          psdExpanding: false,
          placing: false,
          trimmed: false,
        ),
        isFalse,
      );
    });

    test('reference and keep are both on offer there', () {
      for (final mode in [
        ImportFileMode.reference,
        ImportFileMode.keepInside,
      ]) {
        expect(
          importModeAllowed(
            kind: MediaAssetKind.image,
            mode: mode,
            psdExpanding: false,
            placing: false,
            trimmed: false,
          ),
          isTrue,
        );
      }
    });
  });

  group('trimming', () {
    test('a trimmed source cannot be a reference — a pointer has no '
        'in and out', () {
      final trimmed = defaults.copyWith(
        mode: ImportFileMode.reference,
        inFrame: 12,
      );
      expect(trimmed.isTrimmed, isTrue);
      expect(resolve(trimmed).mode, ImportFileMode.keepInside);
    });

    test('an untouched range leaves reference alone', () {
      final whole = defaults.copyWith(mode: ImportFileMode.reference);
      expect(whole.isTrimmed, isFalse);
      expect(resolve(whole).mode, ImportFileMode.reference);
    });

    test('an out point alone counts as a trim', () {
      expect(defaults.copyWith(outFrame: 40).isTrimmed, isTrue);
    });
  });

  group('psd', () {
    test('expanding locks the file question: the stack is baked', () {
      final resolved = resolve(
        defaults.copyWith(
          psd: PsdPlaceMode.expand,
          mode: ImportFileMode.keepInside,
        ),
        isPsd: true,
      );
      expect(resolved.mode, ImportFileMode.rasterize);
    });

    test('merging leaves the file question open', () {
      final resolved = resolve(
        defaults.copyWith(
          psd: PsdPlaceMode.merge,
          mode: ImportFileMode.reference,
        ),
        isPsd: true,
      );
      expect(resolved.mode, ImportFileMode.reference);
    });

    test('a PSD registered into the pool is just a file — expand does not '
        'apply', () {
      final resolved = resolve(
        defaults.copyWith(
          psd: PsdPlaceMode.expand,
          mode: ImportFileMode.keepInside,
        ),
        isPsd: true,
        placing: false,
      );
      expect(resolved.mode, ImportFileMode.keepInside);
    });

    test('both Photoshop extensions are recognised', () {
      expect(importPathIsPsd('/a/BG.psd'), isTrue);
      expect(importPathIsPsd('/a/BG.PSB'), isTrue);
      expect(importPathIsPsd('/a/BG.png'), isFalse);
      expect(importPathIsPsd('BG'), isFalse);
    });
  });

  group('labels', () {
    test('every mode, fit and destination has a cell word', () {
      for (final mode in ImportFileMode.values) {
        expect(importModeLabel(mode), isNotEmpty);
      }
      for (final fit in MediaFitMode.values) {
        expect(importFitLabel(fit), isNotEmpty);
      }
      for (final into in ImportDestination.values) {
        expect(importIntoLabel(into), isNotEmpty);
      }
    });
  });
}
