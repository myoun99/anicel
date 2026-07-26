import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/brush_pressure_curve.dart';
import 'package:quick_animaker_v2/src/services/sut/sut_decoder.dart';
import 'package:sqlite3/sqlite3.dart';

/// Builds synthetic Clip Studio brush databases mirroring the real layout
/// (verified against CSP 1.x/3.x exports): `Node` tool entries, `Variant`
/// parameter rows (schema varies across versions — fixtures use a subset),
/// and `MaterialFile` rows whose FileData embeds PNGs.
void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('sut_decoder_test');
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Uint8List effector(int flags, {int minimumPercent = 0}) {
    final bytes = ByteData(16)
      ..setInt32(0, 44)
      ..setInt32(4, 0xf0)
      ..setInt32(8, flags)
      ..setInt32(12, minimumPercent);
    return bytes.buffer.asUint8List();
  }

  /// UTF-16LE catalog reference blob, as CSP writes pattern arrays.
  Uint8List patternArray(String catalogPath) {
    final builder = BytesBuilder();
    builder.add(Uint8List(16)); // framing header (ignored by the decoder)
    for (final unit in catalogPath.codeUnits) {
      builder.addByte(unit & 0xFF);
      builder.addByte(unit >> 8);
    }
    builder.add(Uint8List(6));
    return builder.toBytes();
  }

  /// PNG bytes for a [width]x[height] opaque black rectangle.
  Future<Uint8List> blackPng(int width, int height) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF000000),
    );
    final image = await recorder.endRecording().toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  Future<String> buildFixture({
    required Uint8List tipPng,
    Uint8List? thumbnailPng,
    Uint8List? texturePng,
    Uint8List? dualPng,
    String catalogPath = '.:36:43:fixture-tip-catalog',
    String textureCatalogPath = '.:25:01:fixture-texture-catalog',
    String dualCatalogPath = '.:77:88:fixture-dual-catalog',
    bool includeMaterial = true,
    int brushSizeUnit = 0,
    int sizeEffectorFlags = 0x10,
    int sizeEffectorMinimum = 59,
    int flowEffectorFlags = 0x30,
    int flowEffectorMinimum = 0,
    int rotationEffector = 0x03,
    int rotationRandomScale = 100,
    double dualSize = 30.0,
    int syncDualBrushSize = 0,
    int useWaterColor = 0,
    int mixColor = 50,
    int mixAlpha = 50,
    int mixColorExtension = 10,
  }) async {
    final path = '${tempDirectory.path}/fixture.sut';
    final database = sqlite3.open(path);
    database.execute('''
      CREATE TABLE Node(_PW_ID INTEGER PRIMARY KEY, NodeUuid BLOB,
        NodeName TEXT, NodeVariantID INTEGER);
      CREATE TABLE Variant(_PW_ID INTEGER PRIMARY KEY, VariantID INTEGER,
        Opacity INTEGER, BrushSize REAL, BrushFlow INTEGER,
        BrushHardness INTEGER, BrushInterval REAL, BrushThickness INTEGER,
        BrushRotation REAL, BrushUsePatternImage INTEGER,
        BrushPatternImageArray BLOB, BrushSizeEffector BLOB,
        BrushOpacityEffector BLOB, BrushFlowEffector BLOB,
        BrushUseSpray INTEGER, BrushSpraySize REAL,
        BrushSprayDensity INTEGER, TextureImage BLOB,
        TextureScale2 REAL, TextureDensity INTEGER,
        BrushSizeUnit INTEGER, BrushRotationEffector INTEGER,
        BrushRotationRandomScale INTEGER, UseDualBrush INTEGER,
        DualUsePatternImage INTEGER, DualPatternImageArray BLOB,
        DualSize REAL, SyncDualBrushSize INTEGER,
        BrushUseWaterColor INTEGER, BrushMixColor INTEGER,
        BrushMixAlpha INTEGER, BrushMixColorExtension INTEGER);
      CREATE TABLE MaterialFile(_PW_ID INTEGER PRIMARY KEY,
        CatalogPath TEXT, OriginalPath TEXT, FileData BLOB);
    ''');

    // Group root: no variant -> skipped.
    database.execute(
      "INSERT INTO Node(_PW_ID, NodeUuid, NodeName, NodeVariantID) "
      "VALUES (1, x'00', '', NULL)",
    );
    // Sampled brush.
    database.execute(
      'INSERT INTO Node(_PW_ID, NodeUuid, NodeName, NodeVariantID) '
      'VALUES (2, ?, ?, 9)',
      [Uint8List.fromList(List<int>.generate(16, (i) => i + 1)), '테스트 브러시'],
    );
    database.execute(
      'INSERT INTO Variant(VariantID, Opacity, BrushSize, BrushFlow, '
      'BrushHardness, BrushInterval, BrushThickness, BrushRotation, '
      'BrushUsePatternImage, BrushPatternImageArray, BrushSizeEffector, '
      'BrushOpacityEffector, BrushFlowEffector, BrushUseSpray, '
      'BrushSpraySize, BrushSprayDensity, TextureImage, TextureScale2, '
      'TextureDensity, BrushSizeUnit, BrushRotationEffector, '
      'BrushRotationRandomScale, UseDualBrush, DualUsePatternImage, '
      'DualPatternImageArray, DualSize, SyncDualBrushSize, '
      'BrushUseWaterColor, BrushMixColor, BrushMixAlpha, '
      'BrushMixColorExtension) '
      'VALUES (9, 80, 50.0, 60, 70, 15.0, 40, 200.0, 1, ?, ?, ?, ?, '
      '1, 200.0, 4, ?, 182.0, 90, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        patternArray(catalogPath),
        effector(sizeEffectorFlags, minimumPercent: sizeEffectorMinimum),
        effector(0x00),
        effector(flowEffectorFlags, minimumPercent: flowEffectorMinimum),
        texturePng == null ? null : patternArray(textureCatalogPath),
        brushSizeUnit,
        rotationEffector,
        rotationRandomScale,
        dualPng == null ? 0 : 1,
        dualPng == null ? 0 : 1,
        dualPng == null ? null : patternArray(dualCatalogPath),
        dualSize,
        syncDualBrushSize,
        useWaterColor,
        mixColor,
        mixAlpha,
        mixColorExtension,
      ],
    );
    // Round brush without pattern data.
    database.execute(
      'INSERT INTO Node(_PW_ID, NodeUuid, NodeName, NodeVariantID) '
      'VALUES (3, ?, ?, 12)',
      [Uint8List.fromList(List<int>.generate(16, (i) => 40 + i)), 'Round Pen'],
    );
    database.execute(
      'INSERT INTO Variant(VariantID, Opacity, BrushSize, BrushHardness, '
      'BrushInterval) VALUES (12, 100, 8.0, 90, 8.0)',
    );

    if (includeMaterial) {
      // FileData: junk + a small thumbnail PNG + the (larger) tip PNG.
      final fileData = BytesBuilder();
      fileData.add(ascii.encode('catalog.zip'));
      fileData.add(Uint8List(21));
      if (thumbnailPng != null) {
        fileData.add(thumbnailPng);
        fileData.add(Uint8List(9));
      }
      fileData.add(tipPng);
      fileData.add(Uint8List(15));
      database.execute(
        'INSERT INTO MaterialFile(CatalogPath, OriginalPath, FileData) '
        'VALUES (?, ?, ?)',
        [catalogPath, '$catalogPath:data:material_0.layer', fileData.toBytes()],
      );
      if (dualPng != null) {
        final dualData = BytesBuilder();
        dualData.add(ascii.encode('catalog.zip'));
        dualData.add(Uint8List(11));
        dualData.add(dualPng);
        dualData.add(Uint8List(5));
        database.execute(
          'INSERT INTO MaterialFile(CatalogPath, OriginalPath, FileData) '
          'VALUES (?, ?, ?)',
          [
            dualCatalogPath,
            '$dualCatalogPath:data:material_0.layer',
            dualData.toBytes(),
          ],
        );
      }
      if (texturePng != null) {
        final textureData = BytesBuilder();
        textureData.add(ascii.encode('catalog.zip'));
        textureData.add(Uint8List(13));
        textureData.add(texturePng);
        textureData.add(Uint8List(7));
        database.execute(
          'INSERT INTO MaterialFile(CatalogPath, OriginalPath, FileData) '
          'VALUES (?, ?, ?)',
          [
            textureCatalogPath,
            '$textureCatalogPath:data:material_0.layer',
            textureData.toBytes(),
          ],
        );
      }
    }
    database.close();
    return path;
  }

  test('imports sampled and round brushes with mapped parameters', () async {
    final path = await buildFixture(
      tipPng: await blackPng(6, 4),
      thumbnailPng: await blackPng(2, 2),
      texturePng: await blackPng(8, 8),
    );
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    expect(result.warnings, isEmpty);
    expect(result.presets, hasLength(2));

    final sampled = result.presets.first;
    expect(sampled.id.value, 'sut-0102030405060708090a0b0c0d0e0f10');
    expect(sampled.name, '테스트 브러시');
    final s = sampled.settings;
    expect(s.size, 50.0);
    expect(s.opacity, closeTo(0.8, 1e-9));
    expect(s.flow, closeTo(0.6, 1e-9));
    expect(s.hardness, closeTo(0.7, 1e-9));
    expect(s.spacing, closeTo(0.15, 1e-9));
    expect(s.roundness, closeTo(0.4, 1e-9));
    expect(s.angleDegrees, closeTo(20.0, 1e-9)); // 200 normalized into 0-180
    // BB-3 curve mapping: size effector 0x10 with minimum 59% becomes the
    // line (0, 0.59)-(1, 1); the flow effector's 0x30 now lands on its OWN
    // flow channel (it used to be OR-merged into opacity); the opacity
    // effector (0x00) stays pressure-free.
    expect(s.sizePressureCurve, BrushPressureCurve.linearFrom(0.59));
    expect(s.opacityPressureCurve, isNull);
    expect(s.flowPressureCurve, BrushPressureCurve.identity());
    // Spray maps to scatter: 200% spray size -> radius ratio 1.0.
    expect(s.scatterRadiusRatio, closeTo(1.0, 1e-9));
    expect(s.scatterCount, 4);
    // Paper texture joins its own material; scale 182% and density 90%.
    expect(s.textureMask, isNotNull);
    expect(s.textureMask!.size, 8);
    expect(s.textureScale, closeTo(1.82, 1e-9));
    expect(s.textureDensity, closeTo(0.9, 1e-9));

    // The larger PNG is the tip (the 2x2 one is a thumbnail); 6x4 pads to
    // a centered 6x6 square, black-opaque pixels become full coverage.
    final mask = s.tipMask!;
    expect(mask.size, 6);
    expect(mask.alpha[0], 0); // padded top row
    expect(mask.alpha[1 * 6 + 2], 255);
    expect(mask.alpha[5 * 6 + 2], 0); // padded bottom row

    final round = result.presets[1];
    expect(round.name, 'Round Pen');
    expect(round.settings.tipMask, isNull);
    expect(round.settings.size, 8.0);
    expect(round.settings.hardness, closeTo(0.9, 1e-9));
    expect(round.settings.sizePressureCurve, isNull);
  });

  test('random input source drives the jitters', () async {
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      sizeEffectorFlags: 0x80,
      sizeEffectorMinimum: 20,
      flowEffectorFlags: 0x80,
      flowEffectorMinimum: 4,
      rotationEffector: 0xC3,
      rotationRandomScale: 45,
    );
    final s = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings;

    // Clip Studio wanders between 최소치% and 100%; the engine shakes
    // downward, so the amplitude is the complement of the floor.
    expect(s.sizeJitter, closeTo(0.8, 1e-9));
    // No flow jitter on the engine — flow randomness folds into opacity.
    expect(s.opacityJitter, closeTo(0.96, 1e-9));
    // The rotation effector is a bare int carrying the same 0x80 bit.
    expect(s.angleJitter, closeTo(0.45, 1e-9));
    // The random bit does not imply a pressure curve.
    expect(s.sizePressureCurve, isNull);
  });

  test('rotation random scale stays inert without the random bit', () async {
    // Real brushes park BrushRotationRandomScale at its default 100 while
    // never randomising, so reading it ungated would spin every tip.
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      rotationEffector: 0x13, // pressure, no random
      rotationRandomScale: 100,
    );
    final s = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings;

    expect(s.angleJitter, 0.0);
  });

  test('imports the dual brush tip with a synced size ratio', () async {
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      dualPng: await blackPng(10, 10),
      dualSize: 250.0,
      syncDualBrushSize: 1,
    );
    final s = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings;

    expect(s.dualMask, isNotNull);
    expect(s.dualMask!.size, 10);
    // Synced: DualSize is a percentage of the brush size.
    expect(s.dualMaskScale, closeTo(2.5, 1e-9));
  });

  test('unsynced dual size divides against the brush size', () async {
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      dualPng: await blackPng(10, 10),
      dualSize: 25.0, // absolute, against the fixture's 50px brush
    );
    final s = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings;

    expect(s.dualMaskScale, closeTo(0.5, 1e-9));
  });

  test('dual ratio stays neutral when no dual tip arrived', () async {
    // Brushes that never enabled a dual tip still carry a stored DualSize.
    final path = await buildFixture(tipPng: await blackPng(4, 4));
    final s = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings;

    expect(s.dualMask, isNull);
    expect(s.dualMaskScale, 1.0);
  });

  test('ground-colour mixing imports behind its gate', () async {
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      useWaterColor: 1,
      mixColor: 90,
      mixAlpha: 100,
      mixColorExtension: 30,
    );
    final s = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings;

    expect(s.mixesGroundColor, isTrue);
    expect(s.paintAmount, closeTo(0.9, 1e-9));
    expect(s.paintDensity, closeTo(1.0, 1e-9));
    expect(s.colorStretch, closeTo(0.3, 1e-9));
  });

  test('mixing knobs stay inert when the gate is off', () async {
    // Real brushes park mixing values with the gate off (鉛筆R sits at
    // 물감량 50 while never mixing), so the gate has to win.
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      mixColor: 50,
      mixAlpha: 50,
      mixColorExtension: 10,
    );
    final s = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings;

    expect(s.mixesGroundColor, isFalse);
  });

  test('non-pixel brush size warns instead of mis-scaling', () async {
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      brushSizeUnit: 2,
    );
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    expect(result.presets.first.settings.size, 50.0);
    expect(
      result.warnings.any((w) => w.contains('non-pixel unit')),
      isTrue,
    );
  });

  test('missing material degrades to a round tip with a warning', () async {
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      includeMaterial: false,
    );
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    expect(result.presets, hasLength(2));
    expect(result.presets.first.settings.tipMask, isNull);
    expect(result.warnings, isNotEmpty);
  });

  test('rejects non-sqlite and non-brush files with clear errors', () async {
    final bogus = '${tempDirectory.path}/bogus.sut';
    await File(bogus).writeAsString('not a database at all');
    expect(
      () => decodeSutBrushFile(filePath: bogus, sourceName: 'bogus'),
      throwsA(isA<SutDecodeException>()),
    );

    final empty = '${tempDirectory.path}/empty.sut';
    final database = sqlite3.open(empty);
    database.execute('CREATE TABLE Unrelated(a INTEGER)');
    database.close();
    expect(
      () => decodeSutBrushFile(filePath: empty, sourceName: 'empty'),
      throwsA(isA<SutDecodeException>()),
    );
  });

  test('oversized tips are downscaled to the mask cap', () async {
    final path = await buildFixture(tipPng: await blackPng(320, 100));
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    final mask = result.presets.first.settings.tipMask!;
    expect(mask.size, 256); // 320 -> capped at 256, padded square
    // The 100px side scales to 80 and centers vertically: rows well above
    // and below the band stay empty, the middle is full coverage.
    expect(mask.alpha[(128 * 256) + 128], 255);
    expect(mask.alpha[(20 * 256) + 128], 0);
    expect(mask.alpha[(235 * 256) + 128], 0);
  });
}
