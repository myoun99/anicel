import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/envelope/cut_envelope_paper.dart';
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
    test('defaults: canvas size, the 셀 · 미술 · 타임시트 kinds, 원화 label, '
        '「최신」 take, paper applied, 기준 preset — and the JSON carries none '
        'of them', () {
      const spec = CelsExportSpec();
      expect(spec.sizeMode, ExportSizeMode.canvas);
      // 유저 2026-10-06: 「기본값은 셀/미술/시트 체크 나머진 해제」.
      expect(spec.kinds, {
        ExportCelKind.cel,
        ExportCelKind.art,
        ExportCelKind.timesheet,
      });
      expect(spec.label, const LayerMark(process: LayerProcess.key));
      expect(spec.take, isNull);
      expect(spec.applyPaper, isTrue);
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
      expect((direction.base, direction.attach), (false, false));
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
        kinds: const {ExportCelKind.conte, ExportCelKind.direction},
        take: 3,
        applyPaper: false,
        base: false,
        sheetOnly: true,
        scope: ExportScopeKind.project,
      );
      final restored = CelsExportSpec.fromJson(spec.toJson());
      expect(restored, spec);
      expect(restored.kinds, {ExportCelKind.conte, ExportCelKind.direction});
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
      expect(spec.copyWith(applyPaper: false).take, 2);
    });

    test('a kind is turned on or off one at a time, and a kind the JSON '
        'names that nobody knows is dropped', () {
      const spec = CelsExportSpec();
      expect(spec.withKind(ExportCelKind.art, false).kinds, {
        ExportCelKind.cel,
        ExportCelKind.timesheet,
      });
      expect(spec.withKind(ExportCelKind.direction, true).kinds, {
        ExportCelKind.cel,
        ExportCelKind.art,
        ExportCelKind.timesheet,
        ExportCelKind.direction,
      });
      expect(spec.withKind(ExportCelKind.timesheet, false).kinds, {
        ExportCelKind.cel,
        ExportCelKind.art,
      });
      expect(spec.withKind(ExportCelKind.cel, true), spec);
      expect(
        const CelsExportSpec(kinds: {}),
        isNot(spec),
        reason: 'no kind at all is a spec of its own, not the default',
      );
      expect(
        CelsExportSpec.fromJson(const CelsExportSpec(kinds: {}).toJson()).kinds,
        isEmpty,
      );
      expect(
        CelsExportSpec.fromJson({
          'kinds': ['conte', 'hologram'],
        }).kinds,
        {ExportCelKind.conte},
      );
    });

    test('🗣️a kind\'s prefix is its own until the naming says otherwise, '
        'and is kept only where it differs — the default has one spelling',
        () {
      // 유저 2026-10-06: 「기본값은 셀:없음, 미술:_, 디렉션:_, 시트:_,
      // 컷봉투:_」 · 「콘티레이어는 다만 기본값 없음으로」.
      const naming = ExportCelNaming();
      expect(
        {for (final kind in ExportCelKind.values) kind: naming.prefixOf(kind)},
        {
          ExportCelKind.cel: '',
          ExportCelKind.conte: '',
          ExportCelKind.art: '_',
          ExportCelKind.direction: '_',
          ExportCelKind.timesheet: '_',
          ExportCelKind.envelope: '_',
        },
      );
      final typed = naming
          .withPrefix(ExportCelKind.cel, 'k')
          .withPrefix(ExportCelKind.art, '');
      expect(typed.prefixOf(ExportCelKind.cel), 'k');
      expect(typed.prefixOf(ExportCelKind.art), '');
      expect(typed.prefixOf(ExportCelKind.direction), '_');
      expect(typed, isNot(naming));
      expect(ExportCelNaming.fromJson(typed.toJson()), typed);
      expect(
        typed
            .withPrefix(ExportCelKind.cel, '')
            .withPrefix(ExportCelKind.art, '_'),
        naming,
        reason: 'typing a kind\'s own prefix back is the default again',
      );
      expect(
        ExportCelNaming.fromJson({
          'prefixes': {'art': '_', 'cel': 'k', 'hologram': 'x'},
        }).prefixes,
        {ExportCelKind.cel: 'k'},
        reason: 'a default spelled out, and a kind nobody knows, are dropped',
      );
    });
  });

  group('the cut\'s documents are kinds of the Cels tab (F-289)', () {
    test('the timesheet and the cut envelope are documents; the rows\' '
        'kinds are not — and both start behind an underscore (유저 '
        '2026-10-06: 「기본값은 셀:없음, 미술:_, 디렉션:_, 시트:_, '
        '컷봉투:_」)', () {
      expect(
        [
          for (final kind in ExportCelKind.values)
            if (kind.isDocument) kind,
        ],
        [ExportCelKind.timesheet, ExportCelKind.envelope],
      );
      expect(ExportCelKind.timesheet.defaultPrefix, '_');
      expect(ExportCelKind.envelope.defaultPrefix, '_');
    });

    test('타임시트 형식 and 컷봉투 형식 are the cels spec\'s: pictures by '
        'default, the envelope on the cut\'s own pixels — and the JSON '
        'carries none of it until one moves', () {
      const spec = CelsExportSpec();
      expect(spec.sheetFormat, ExportTimesheetFormat.sheetImage);
      expect(spec.sheetImage, paperDocumentFormat);
      expect(spec.envelopePaper, CutEnvelopePaperMode.cut);
      expect(spec.envelopeImage, paperDocumentFormat);
      expect(
        spec.toJson().keys,
        isNot(
          anyOf(
            contains('sheetFormat'),
            contains('sheetImage'),
            contains('envelopePaper'),
            contains('envelopeImage'),
          ),
        ),
      );

      final jpg = paperDocumentFormat.copyWith(
        stillFormat: ExportStillFormat.jpg,
        jpgQuality: 72,
      );
      final moved = spec.copyWith(
        sheetFormat: ExportTimesheetFormat.xdts,
        sheetImage: jpg,
        envelopePaper: CutEnvelopePaperMode.sheet,
        envelopeImage: jpg,
      );
      expect(moved, isNot(spec));
      final restored = CelsExportSpec.fromJson(moved.toJson());
      expect(restored, moved);
      expect(restored.sheetFormat, ExportTimesheetFormat.xdts);
      expect(restored.sheetImage.jpgQuality, 72);
      expect(restored.envelopePaper, CutEnvelopePaperMode.sheet);
      expect(restored.envelopeImage.stillFormat, ExportStillFormat.jpg);
      // Each of the four is its own field: one moved is a different spec.
      for (final one in [
        spec.copyWith(sheetFormat: ExportTimesheetFormat.xdts),
        spec.copyWith(sheetImage: jpg),
        spec.copyWith(envelopePaper: CutEnvelopePaperMode.sheet),
        spec.copyWith(envelopeImage: jpg),
      ]) {
        expect(one, isNot(spec));
        expect(one.hashCode, isNot(spec.hashCode));
        expect(CelsExportSpec.fromJson(one.toJson()), one);
      }
    });

    test('a paper document is a still on its paper: PNG or JPG, never a '
        'format with no paper under it — and one the file names wrongly '
        'reads as PNG', () {
      expect(paperDocumentFormat.isStill, isTrue);
      expect(paperDocumentFormat.wantsAlpha, isFalse);
      expect(paperDocumentFormat.stillFormat, ExportStillFormat.png);
      expect(paperDocumentFormatFromJson(null), paperDocumentFormat);
      final psd = const ExportFormatSelection(
        kind: ExportMediaKind.still,
        stillFormat: ExportStillFormat.psd,
        jpgQuality: 55,
      ).toJson();
      final read = paperDocumentFormatFromJson(psd);
      expect(read.stillFormat, ExportStillFormat.png);
      expect(read.wantsAlpha, isFalse);
      expect(read.jpgQuality, 55, reason: 'the quality is kept for a JPG');
    });

    test('🚨F-294: a paper document goes out at its paper\'s own pixels — '
        'a scale a file of an older build names is not read (유저 '
        '2026-10-06: 「시트 이미지는 배율 없앰. 늘 용지 그대로」)', () {
      expect(
        ConteExportSpec.fromJson(const {'sheetScale': 3}),
        const ConteExportSpec(),
      );
      expect(const ConteExportSpec().toJson(), isEmpty);
    });
  });

  group('ExportTabSpecs', () {
    test('round-trips per-tab and withSpec routes by type', () {
      const specs = ExportTabSpecs();
      final updated = specs
          .withSpec(const SequenceExportSpec(inFrame: 1))
          .withSpec(const CelsExportSpec(take: 2))
          .withSpec(const ConteExportSpec(format: ExportConteFormat.pageImage));
      expect(
        (updated.specFor(ExportTab.sequence) as SequenceExportSpec).inFrame,
        1,
      );
      expect(updated.cels.take, 2);
      expect(updated.conte.format, ExportConteFormat.pageImage);
      expect(updated.image, specs.image);
      expect(ExportTabSpecs.fromJson(updated.toJson()), updated);
    });

    test('the tabs are four — the timesheet and the cut envelope are no '
        'tab, and what a file of an older build kept for them is left '
        'unread', () {
      expect(ExportTab.values, [
        ExportTab.sequence,
        ExportTab.image,
        ExportTab.cels,
        ExportTab.conte,
      ]);
      expect(ExportTab.fromJsonOrNull('timesheet'), isNull);
      expect(ExportTab.fromJsonOrNull('envelope'), isNull);
      expect(ExportTab.fromJsonOrNull('cels'), ExportTab.cels);
      expect(
        ExportTabSpecs.fromJson(const {
          'timesheet': {'format': 'xdts', 'scope': 'project'},
          'envelope': {'paperMode': 'sheet'},
        }),
        const ExportTabSpecs(),
      );
    });
  });

  group('ExportPreset', () {
    test('round-trips through the tab discriminator', () {
      const preset = ExportPreset(
        id: ExportPresetId('preset-1'),
        name: '러시 체크 MP4',
        spec: SequenceExportSpec(applyLayerFx: false),
      );
      final restored = ExportPreset.fromJson(preset.toJson())!;
      expect(restored, preset);
      expect(restored.tab, ExportTab.sequence);
      expect((restored.spec as SequenceExportSpec).applyLayerFx, isFalse);
    });

    test('cels preset restores as a cels spec', () {
      const preset = ExportPreset(
        id: ExportPresetId('preset-2'),
        name: '납품 셀',
        spec: CelsExportSpec(kinds: {ExportCelKind.conte}),
      );
      final restored = ExportPreset.fromJson(preset.toJson())!;
      expect(restored.spec, isA<CelsExportSpec>());
      expect((restored.spec as CelsExportSpec).kinds, {ExportCelKind.conte});
    });

    test('a preset saved for a tab that is one no longer is no preset', () {
      const preset = ExportPreset(
        id: ExportPresetId('preset-3'),
        name: 'sheets',
        spec: CelsExportSpec(),
      );
      expect(
        ExportPreset.fromJson({...preset.toJson(), 'tab': 'timesheet'}),
        isNull,
      );
      expect(
        ExportPreset.fromJson({...preset.toJson(), 'tab': 'envelope'}),
        isNull,
      );
    });
  });
}
