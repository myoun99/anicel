import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/export_cel_naming.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/export_preset.dart';
import 'package:anicel/src/models/export_size_mode.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';

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
    test('defaults: canvas size, 원화 label, 「최신」 take, paper applied, no '
        'art, 기준 preset — and the JSON carries none of them', () {
      const spec = CelsExportSpec();
      expect(spec.sizeMode, ExportSizeMode.canvas);
      expect(spec.label, const LayerMark(process: LayerProcess.key));
      expect(spec.take, isNull);
      expect(spec.applyPaper, isTrue);
      expect(spec.addArt, isFalse);
      expect(spec.addDirection, isFalse);
      expect(spec.base, isTrue);
      expect(spec.attach, isTrue);
      expect(spec.sheetOnly, isFalse);
      expect(spec.toJson().keys, unorderedEquals(['format', 'naming']));
      expect(CelsExportSpec.fromJson(spec.toJson()), spec);
    });

    test('the one-day-old preset spelling reads as the filters it meant', () {
      CelsExportSpec read(String preset) =>
          CelsExportSpec.fromJson({'selection': preset});
      final attach = read('attach');
      expect((attach.base, attach.attach, attach.sheetOnly), (false, true, false));
      final sheet = read('sheet');
      expect((sheet.base, sheet.attach, sheet.sheetOnly), (true, true, true));
      final direction = read('direction');
      expect((direction.base, direction.attach, direction.addDirection), (false, false, true));
      expect(read('base'), const CelsExportSpec());
    });

    test('non-default fields round-trip', () {
      final spec = const CelsExportSpec().copyWith(
        sizeMode: ExportSizeMode.camera,
        naming: const ExportCelNaming(
          frameDigits: 4,
          projectFolder: true,
          cutFolder: true,
        ),
        label: const LayerMark(
          process: LayerProcess.layout,
          revise: LayerRevise.animationDirector,
        ),
        take: 3,
        applyPaper: false,
        addArt: true,
        addDirection: true,
        base: false,
        sheetOnly: true,
        scope: ExportScopeKind.project,
      );
      final restored = CelsExportSpec.fromJson(spec.toJson());
      expect(restored, spec);
      expect(restored.take, 3);
      expect(restored.base, isFalse);
      expect(restored.attach, isTrue);
      expect(restored.naming.projectFolder, isTrue);
    });

    test('the label stores its stage and revise only — a take riding the '
        'stored label is dropped on read, since the take is its own field',
        () {
      final json = const CelsExportSpec(
        label: LayerMark(process: LayerProcess.layout, take: 4),
      ).toJson();
      final restored = CelsExportSpec.fromJson(json);
      expect(restored.label, const LayerMark(process: LayerProcess.layout));
      expect(restored.take, isNull);
    });

    test('copyWith clears the take with an explicit null and keeps it when '
        'omitted', () {
      const spec = CelsExportSpec(take: 2);
      expect(spec.copyWith(take: null).take, isNull);
      expect(spec.copyWith().take, 2);
      expect(spec.copyWith(addArt: true).take, 2);
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
          .withSpec(const CelsExportSpec(take: 2));
      expect(
        (updated.specFor(ExportTab.sequence) as SequenceExportSpec).inFrame,
        1,
      );
      expect(updated.cels.take, 2);
      expect(updated.image, specs.image);
      expect(ExportTabSpecs.fromJson(updated.toJson()), updated);
    });
  });

  group('ExportPreset', () {
    test('round-trips through the tab discriminator', () {
      const preset = ExportPreset(
        id: ExportPresetId('preset-1'),
        name: '러시 체크 MP4',
        spec: SequenceExportSpec(applyLayerFx: false),
      );
      final restored = ExportPreset.fromJson(preset.toJson());
      expect(restored, preset);
      expect(restored.tab, ExportTab.sequence);
      expect((restored.spec as SequenceExportSpec).applyLayerFx, isFalse);
    });

    test('cels preset restores as a cels spec', () {
      const preset = ExportPreset(
        id: ExportPresetId('preset-2'),
        name: '납품 셀',
        spec: CelsExportSpec(addArt: true),
      );
      final restored = ExportPreset.fromJson(preset.toJson());
      expect(restored.spec, isA<CelsExportSpec>());
      expect((restored.spec as CelsExportSpec).addArt, isTrue);
    });
  });
}
