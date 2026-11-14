import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/envelope/cut_envelope_paper.dart';
import 'package:anicel/src/models/export_cel_naming.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/export_preset.dart';
import 'package:anicel/src/models/export_size_mode.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/timesheet_sheet_kind.dart';
import 'package:anicel/src/models/xdts_viewer_sheet.dart';

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
        layerFx: ExportLayerFx.basic,
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
        layerFx: ExportLayerFx.off,
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
        ExportCelKind.image,
        ExportCelKind.timesheet,
      });
      expect(spec.label, const LayerMark(process: LayerProcess.key));
      expect(spec.take, isNull);
      expect(spec.applyPaper, isTrue);
      expect(spec.base, isTrue);
      expect(spec.attach, isTrue);
      expect(spec.sheetOnly, isFalse);
      expect(spec.sheetInk, isFalse, reason: 'a plain XDTS (I-161)');
      expect(spec.viewerSheet, isNull, reason: 'each cut its own sheet\'s');
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
        sheetInk: true,
        viewerSheet: XdtsViewerSheet.ponocSixSeconds,
      );
      final restored = CelsExportSpec.fromJson(spec.toJson());
      expect(restored, spec);
      expect(restored.sheetInk, isTrue);
      expect(restored.viewerSheet, XdtsViewerSheet.ponocSixSeconds);
      expect(restored.kinds, {ExportCelKind.conte, ExportCelKind.direction});
      expect(restored.take, 3);
      expect(restored.base, isFalse);
      expect(restored.attach, isTrue);
      expect(restored.naming.projectFolder, isTrue);
    });

    test('🗣️I-161-Q7: the ink is written with the digital sheet that asks '
        'for it, in a project of the viewer\'s 24 frames a second alone', () {
      const inked = CelsExportSpec(
        sheetFormat: ExportTimesheetFormat.xdts,
        sheetInk: true,
      );
      expect(inked.writesSheetInk(fps: 24), isTrue);
      expect(inked.writesSheetInk(fps: 25), isFalse);
      expect(inked.writesSheetInk(fps: 30), isFalse);
      expect(
        inked.copyWith(sheetInk: false).writesSheetInk(fps: 24),
        isFalse,
      );
      expect(
        inked
            .copyWith(sheetFormat: ExportTimesheetFormat.sheetImage)
            .writesSheetInk(fps: 24),
        isFalse,
        reason: 'pictures carry their ink on the page',
      );
    });

    test('🗣️I-161-Q8: the viewer sheet picked here, else the cut\'s own '
        'sheet\'s', () {
      const spec = CelsExportSpec();
      expect(
        spec.viewerSheetFor(TimesheetSheetKind.threeSeconds),
        XdtsViewerSheet.a3SixSeconds,
      );
      expect(
        spec
            .copyWith(viewerSheet: XdtsViewerSheet.b4ThreeSeconds)
            .viewerSheetFor(TimesheetSheetKind.sixSeconds),
        XdtsViewerSheet.b4ThreeSeconds,
      );
    });

    test('🗣️I-153: the folders\' names keep what they wear, and a bare one '
        'is not written', () {
      const naming = ExportCelNaming(
        projectFolderName: ExportNameAffix(prefix: 'csm_'),
        cutFolderName: ExportNameAffix(prefix: 'csm_14_', suffix: '_lo'),
      );
      final json = naming.toJson();
      expect(json, {
        'projectFolderName': {'prefix': 'csm_'},
        'cutFolderName': {'prefix': 'csm_14_', 'suffix': '_lo'},
      });
      expect(ExportCelNaming.fromJson(json), naming);
      expect(const ExportCelNaming().toJson(), isEmpty);
      expect(
        ExportCelNaming.fromJson({
          'cutFolderName': {'prefix': 7, 'suffix': '_lo'},
          'projectFolderName': 'csm_',
        }),
        const ExportCelNaming(
          cutFolderName: ExportNameAffix(suffix: '_lo'),
        ),
        reason: 'what is not a string is no affix',
      );
      expect(naming.cutFolderName.around('085'), 'csm_14_085_lo');
      expect(naming, isNot(const ExportCelNaming()));
      expect(
        naming.copyWith(cutFolderName: const ExportNameAffix()),
        isNot(const ExportCelNaming()),
        reason: 'the project folder\'s name is still worn',
      );
      for (final one in const [
        ExportCelNaming(projectFolderName: ExportNameAffix(prefix: 'csm_')),
        ExportCelNaming(cutFolderName: ExportNameAffix(suffix: '_lo')),
      ]) {
        expect(one, isNot(const ExportCelNaming()));
        expect(one.hashCode, isNot(const ExportCelNaming().hashCode));
      }
      for (final other in const [
        ExportNameAffix(prefix: 'csm_14_'),
        ExportNameAffix(suffix: '_lo'),
        ExportNameAffix(prefix: 'csm_14_', suffix: '_LO'),
      ]) {
        expect(other, isNot(naming.cutFolderName));
        expect(other.hashCode, isNot(naming.cutFolderName.hashCode));
      }
    });

    test('🗣️I-153: a project-wide export makes the cut\'s folder whatever its '
        'pill says, and keeps the pill as the user left it', () {
      // 유저 2026-11-04: 「범위에서 프로젝트 고르면 이름규칙 폴더생성에서
      // 컷 체크 고정되도록」.
      const off = ExportCelNaming(layerFolder: true);
      const project = CelsExportSpec(
        scope: ExportScopeKind.project,
        naming: off,
      );
      expect(project.cutFolderHeld, isTrue);
      expect(project.namingInForce, off.copyWith(cutFolder: true));
      expect(project.naming, off);
      expect(
        CelsExportSpec.fromJson(project.toJson()).naming.cutFolder,
        isFalse,
      );
      const cut = CelsExportSpec(naming: off);
      expect(cut.cutFolderHeld, isFalse);
      expect(cut.namingInForce, off);
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
      expect(spec.withKind(ExportCelKind.image, false).kinds, {
        ExportCelKind.cel,
        ExportCelKind.timesheet,
      });
      expect(spec.withKind(ExportCelKind.direction, true).kinds, {
        ExportCelKind.cel,
        ExportCelKind.image,
        ExportCelKind.timesheet,
        ExportCelKind.direction,
      });
      expect(spec.withKind(ExportCelKind.timesheet, false).kinds, {
        ExportCelKind.cel,
        ExportCelKind.image,
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
          ExportCelKind.image: '_',
          ExportCelKind.direction: '_',
          ExportCelKind.timesheet: '_',
          ExportCelKind.envelope: '_',
          ExportCelKind.video: '_',
        },
      );
      final typed = naming
          .withPrefix(ExportCelKind.cel, 'k')
          .withPrefix(ExportCelKind.image, '');
      expect(typed.prefixOf(ExportCelKind.cel), 'k');
      expect(typed.prefixOf(ExportCelKind.image), '');
      expect(typed.prefixOf(ExportCelKind.direction), '_');
      expect(typed, isNot(naming));
      expect(ExportCelNaming.fromJson(typed.toJson()), typed);
      expect(
        typed
            .withPrefix(ExportCelKind.cel, '')
            .withPrefix(ExportCelKind.image, '_'),
        naming,
        reason: 'typing a kind\'s own prefix back is the default again',
      );
      expect(
        ExportCelNaming.fromJson({
          'prefixes': {'image': '_', 'cel': 'k', 'hologram': 'x'},
        }).prefixes,
        {ExportCelKind.cel: 'k'},
        reason: 'a default spelled out, and a kind nobody knows, are dropped',
      );
    });
  });

  group('the cut\'s documents are kinds of the Cels tab (F-289)', () {
    test('the timesheet, the cut envelope and the film are documents; the '
        'rows\' kinds are not — and all start behind an underscore (유저 '
        '2026-10-06: 「기본값은 셀:없음, 미술:_, 디렉션:_, 시트:_, '
        '컷봉투:_」; the film\'s is my call, I-151)', () {
      expect(
        [
          for (final kind in ExportCelKind.values)
            if (kind.isDocument) kind,
        ],
        [ExportCelKind.timesheet, ExportCelKind.envelope, ExportCelKind.video],
      );
      expect(ExportCelKind.timesheet.defaultPrefix, '_');
      expect(ExportCelKind.envelope.defaultPrefix, '_');
      expect(ExportCelKind.video.defaultPrefix, '_');
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

    test('a paper document is a still on its paper: any still format, never '
        'one with no paper under it', () {
      expect(paperDocumentFormat.isStill, isTrue);
      expect(paperDocumentFormat.wantsAlpha, isFalse);
      expect(paperDocumentFormat.stillFormat, ExportStillFormat.png);
      expect(paperDocumentFormatFromJson(null), paperDocumentFormat);
      // I-117 (유저 2026-10-21): 「새 출력형식으로서 BMP TGA TIFF WEBP」 —
      // a sheet is written in each — and 「타임시트는 알듯이 층
      // 나눠져있는대로 출력」: a PSD of its strata.
      for (final format in ExportStillFormat.values) {
        final named = const ExportFormatSelection(
          kind: ExportMediaKind.still,
          jpgQuality: 55,
        ).copyWith(stillFormat: format).toJson();
        final read = paperDocumentFormatFromJson(named);
        expect(read.stillFormat, format, reason: format.label);
        expect(read.wantsAlpha, isFalse, reason: format.label);
        expect(read.jpgQuality, 55, reason: 'the quality is kept for a JPG');
      }
    });

    test('🗣️I-151: the film\'s format and its sound are the cels spec\'s — an '
        'MP4 with its sound by default, carried by the JSON once one moves, '
        'and a movie however its JSON says otherwise', () {
      const spec = CelsExportSpec();
      expect(spec.videoFormat, const ExportFormatSelection());
      expect(spec.videoAudio, isTrue);
      expect(
        spec.toJson().keys,
        isNot(anyOf(contains('videoFormat'), contains('videoAudio'))),
      );

      const gif = ExportFormatSelection(
        container: ExportVideoContainer.gif,
        videoCodec: ExportVideoCodec.gif,
      );
      for (final one in [
        spec.copyWith(videoFormat: gif),
        spec.copyWith(videoAudio: false),
      ]) {
        expect(one, isNot(spec));
        expect(one.hashCode, isNot(spec.hashCode));
        expect(CelsExportSpec.fromJson(one.toJson()), one);
      }

      final still = const ExportFormatSelection(
        kind: ExportMediaKind.still,
      ).toJson();
      expect(
        CelsExportSpec.fromJson({'videoFormat': still}).videoFormat.kind,
        ExportMediaKind.video,
      );
    });

    test('I-117: the conte is ONE file as a PDF or as a Photoshop document — '
        '「콘티용지탭 psd 출력시 … 한 파일안에 여러 페이지 그룹」 — and a '
        'file a page as any other picture', () {
      ConteExportSpec pages(ExportStillFormat format) => ConteExportSpec(
        format: ExportConteFormat.pageImage,
        image: paperDocumentFormat.copyWith(stillFormat: format),
      );
      expect(const ConteExportSpec().documentExtension, 'pdf');
      expect(
        ConteExportSpec(
          image: paperDocumentFormat.copyWith(
            stillFormat: ExportStillFormat.psd,
          ),
        ).documentExtension,
        'pdf',
        reason: 'the PDF is vector: the picture format is not asked',
      );
      expect(pages(ExportStillFormat.psd).documentExtension, 'psd');
      for (final format in ExportStillFormat.values) {
        if (format != ExportStillFormat.psd) {
          expect(pages(format).documentExtension, isNull, reason: format.label);
        }
      }
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

    test('the AE Script tab\'s camera path switch is kept, on unless turned '
        'off (ae-script-export-Q3)', () {
      const on = AeScriptExportSpec();
      expect(on.guideCamera, isTrue);
      expect(on.toJson(), isNot(contains('guideCamera')));
      final off = on.copyWith(guideCamera: false);
      expect(off, isNot(on));
      expect(AeScriptExportSpec.fromJson(off.toJson()), off);
      expect(AeScriptExportSpec.fromJson(on.toJson()), on);
    });

    test('the tabs are five — the timesheet and the cut envelope are no '
        'tab, and what a file of an older build kept for them is left '
        'unread', () {
      expect(ExportTab.values, [
        ExportTab.sequence,
        ExportTab.image,
        ExportTab.cels,
        ExportTab.conte,
        ExportTab.aeScript,
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
        spec: SequenceExportSpec(layerFx: ExportLayerFx.off),
      );
      final restored = ExportPreset.fromJson(preset.toJson())!;
      expect(restored, preset);
      expect(restored.tab, ExportTab.sequence);
      expect((restored.spec as SequenceExportSpec).layerFx, ExportLayerFx.off);
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
