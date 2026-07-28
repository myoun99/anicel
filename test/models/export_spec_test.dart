import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/export_cel_naming.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/export_preset.dart';
import 'package:anicel/src/models/export_size_mode.dart';
import 'package:anicel/src/models/export_spec.dart';

void main() {
  group('SequenceExportSpec', () {
    test('default round-trips and omits defaults', () {
      const spec = SequenceExportSpec();
      final json = spec.toJson();
      expect(json.keys, unorderedEquals(['format', 'naming']));
      expect(json['format'], isEmpty);
      expect(json['naming'], isEmpty);
      expect(SequenceExportSpec.fromJson(json), spec);
    });

    test('non-default fields round-trip', () {
      final spec = const SequenceExportSpec().copyWith(
        format: ExportFormatSelection.normalized(
          kind: ExportMediaKind.still,
          stillFormat: ExportStillFormat.jpg,
        ),
        scope: ExportScopeKind.project,
        sizeMode: ExportSizeMode.canvas,
        inFrame: 23,
        outFrame: 94,
        naming: const ExportSequenceNaming(baseName: 'r012', digits: 5),
        applyLayerFx: false,
        includeAudio: false,
      );
      expect(SequenceExportSpec.fromJson(spec.toJson()), spec);
    });

    test('copyWith clears in/out with explicit null', () {
      const spec = SequenceExportSpec(inFrame: 3, outFrame: 9);
      final cleared = spec.copyWith(inFrame: null, outFrame: null);
      expect(cleared.inFrame, isNull);
      expect(cleared.outFrame, isNull);
      // Omitting keeps.
      expect(spec.copyWith().inFrame, 3);
    });
  });

  group('ImageExportSpec', () {
    test('round-trips', () {
      final spec = const ImageExportSpec().copyWith(
        format: ExportFormatSelection.normalized(
          kind: ExportMediaKind.still,
          stillFormat: ExportStillFormat.psd,
        ),
        sizeMode: ExportSizeMode.canvas,
        applyLayerFx: false,
      );
      expect(ImageExportSpec.fromJson(spec.toJson()), spec);
    });
  });

  group('CelsExportSpec', () {
    test('defaults: canvas size, instruction layers on, attach gates on', () {
      const spec = CelsExportSpec();
      expect(spec.sizeMode, ExportSizeMode.canvas);
      expect(spec.includeInstructionLayers, isTrue);
      expect(spec.includeSyncedAttach, isTrue);
      expect(spec.includeFreeAttach, isTrue);
      expect(spec.includeFolderMembers, isFalse);
      expect(CelsExportSpec.fromJson(spec.toJson()), spec);
    });

    test('non-default fields round-trip, mark slots included', () {
      final spec = const CelsExportSpec().copyWith(
        sizeMode: ExportSizeMode.camera,
        naming: const ExportCelNaming(frameDigits: 4, cutFolder: true),
        onTimesheetOnly: true,
        includeInstructionLayers: false,
        includeSyncedAttach: false,
        includeFolderMembers: true,
        markFilterA: 'red',
        scope: ExportScopeKind.project,
      );
      final restored = CelsExportSpec.fromJson(spec.toJson());
      expect(restored, spec);
      expect(restored.markFilterA, 'red');
      expect(restored.markFilterB, isNull);
    });
  });

  group('TimesheetExportSpec', () {
    test('round-trips and clamps scale', () {
      final spec = const TimesheetExportSpec().copyWith(
        format: ExportTimesheetFormat.xdts,
        scope: ExportScopeKind.project,
        sheetScale: 9,
      );
      expect(spec.sheetScale, 4);
      expect(TimesheetExportSpec.fromJson(spec.toJson()), spec);
    });
  });

  group('ExportTabSpecs', () {
    test('round-trips per-tab and withSpec routes by type', () {
      const specs = ExportTabSpecs();
      final updated = specs
          .withSpec(const SequenceExportSpec(inFrame: 1))
          .withSpec(const CelsExportSpec(onTimesheetOnly: true));
      expect(
        (updated.specFor(ExportTab.sequence) as SequenceExportSpec).inFrame,
        1,
      );
      expect(updated.cels.onTimesheetOnly, isTrue);
      expect(updated.image, specs.image);
      expect(ExportTabSpecs.fromJson(updated.toJson()), updated);
    });
  });

  group('ExportPreset', () {
    test('round-trips through the tab discriminator', () {
      final preset = ExportPreset(
        id: const ExportPresetId('preset-1'),
        name: '러시 체크 MP4',
        spec: const SequenceExportSpec(applyLayerFx: false),
      );
      final restored = ExportPreset.fromJson(preset.toJson());
      expect(restored, preset);
      expect(restored.tab, ExportTab.sequence);
      expect((restored.spec as SequenceExportSpec).applyLayerFx, isFalse);
    });

    test('cels preset restores as a cels spec', () {
      final preset = ExportPreset(
        id: const ExportPresetId('preset-2'),
        name: '납품 셀',
        spec: const CelsExportSpec(includeFolderMembers: true),
      );
      final restored = ExportPreset.fromJson(preset.toJson());
      expect(restored.spec, isA<CelsExportSpec>());
      expect((restored.spec as CelsExportSpec).includeFolderMembers, isTrue);
    });
  });
}
