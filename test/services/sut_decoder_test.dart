import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/services/sut/sut_decoder.dart';
import 'package:sqlite3/sqlite3.dart';

/// Builds synthetic Clip Studio brush databases mirroring the real layout
/// (verified against CSP 1.x/3.x exports): `Node` tool entries, `Variant`
/// parameter rows (schema varies across versions — fixtures use a subset),
/// and `MaterialFile` rows whose FileData embeds PNGs.
void main() {
  late Directory tempDirectory;
  var fixtureIndex = 0;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('sut_decoder_test');
    fixtureIndex = 0;
  });

  tearDown(() async {
    // Windows keeps a handle on a just-closed sqlite file for a moment,
    // and a test killed mid-fixture leaves one open outright — a teardown
    // that throws there REPLACES the real failure with a confusing
    // "directory is not empty". Retry briefly, the brush-tip library's
    // pattern.
    for (var attempt = 0; ; attempt += 1) {
      try {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
        return;
      } on FileSystemException {
        if (attempt >= 20) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  });

  /// An effector blob. [curve] appends the response-curve block Clip Studio
  /// writes in the tail: a `12, <point count>, 16, 0, 0, 0, 0` marker at int
  /// 11, then one (x, y) float64 pair per point BEYOND the implied origin.
  /// 🚨**THE FOUR MINIMUM SLOTS ARE WRITTEN SEPARATELY**, at `int[3..6]` in
  /// panel order (筆圧 · 傾き · 速度 · ランダム).
  ///
  /// ⛔This used to write `minimumPercent` to `int[3]` and nothing else, so
  /// every synthetic blob had its four slots collapsed into one — and a
  /// decoder reading the WRONG slot read the right number anyway. That is
  /// exactly how `_effectorRandomJitter` took pressure's floor as random's
  /// amplitude and no test complained. A fixture that cannot express the
  /// defect cannot catch it.
  Uint8List effector(
    int flags, {
    int minimumPercent = 0,
    int? tiltMinimumPercent,
    int? speedMinimumPercent,
    int? randomMinimumPercent,
    List<(double, double)>? curve,
  }) {
    void writeMinimums(ByteData bytes) {
      bytes
        ..setInt32(12, minimumPercent)
        ..setInt32(16, tiltMinimumPercent ?? 0)
        ..setInt32(20, speedMinimumPercent ?? 0)
        ..setInt32(24, randomMinimumPercent ?? 0);
    }

    if (curve == null) {
      final bytes = ByteData(28)
        ..setInt32(0, 44)
        ..setInt32(4, 0xf0)
        ..setInt32(8, flags);
      writeMinimums(bytes);
      return bytes.buffer.asUint8List();
    }
    final length = 72 + curve.length * 16;
    final bytes = ByteData(length)
      ..setInt32(0, 44)
      ..setInt32(4, length)
      ..setInt32(8, flags)
      ..setInt32(44, 12) // marker at int 11
      ..setInt32(48, curve.length + 1) // count includes the implied origin
      ..setInt32(52, 16);
    writeMinimums(bytes);
    for (var i = 0; i < curve.length; i += 1) {
      bytes
        ..setFloat64(72 + i * 16, curve[i].$1)
        ..setFloat64(72 + i * 16 + 8, curve[i].$2);
    }
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
    int sizeEffectorRandomMinimum = 0,
    List<(double, double)>? sizeEffectorCurve,
    int flowEffectorFlags = 0x30,
    int flowEffectorMinimum = 0,
    int flowEffectorRandomMinimum = 0,
    int thicknessEffectorFlags = 0x00,
    int thicknessEffectorMinimum = 0,
    int thicknessEffectorRandomMinimum = 0,
    int intervalEffectorFlags = 0x00,
    int intervalEffectorMinimum = 0,
    int intervalEffectorRandomMinimum = 0,
    int rotationEffector = 0x03,
    int rotationRandomScale = 100,
    int useSpray = 1,
    int rotationEffectorInSpray = 0x03,
    int rotationRandomInSpray = 100,
    double dualSize = 30.0,
    int syncDualBrushSize = 0,
    int compositeMode = 0,
    int useWaterColor = 0,
    int mixColor = 50,
    int mixAlpha = 50,
    int mixColorExtension = 10,
    // Null stands for a file written before the column existed; 3 (強) is
    // what Clip Studio's own G펜 stores.
    int? antiAlias = 3,
  }) async {
    // Unique per call: a test that builds several fixtures would otherwise
    // reopen the first one and fail on its existing tables.
    fixtureIndex += 1;
    final path = '${tempDirectory.path}/fixture$fixtureIndex.sut';
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
        TextureReverseDensity INTEGER, TextureBrightness INTEGER,
        TextureContrast INTEGER,
        BrushSizeUnit INTEGER, BrushRotationEffector INTEGER,
        BrushRotationRandomScale INTEGER,
        BrushRotationEffectorInSpray INTEGER,
        BrushRotationRandomInSpray INTEGER, UseDualBrush INTEGER,
        DualUsePatternImage INTEGER, DualPatternImageArray BLOB,
        DualSize REAL, SyncDualBrushSize INTEGER,
        BrushUseWaterColor INTEGER, BrushMixColor INTEGER,
        BrushMixAlpha INTEGER, BrushMixColorExtension INTEGER,
        BrushThicknessEffector BLOB, BrushIntervalEffector BLOB,
        CompositeMode INTEGER, AntiAlias INTEGER);
      CREATE TABLE MaterialFile(_PW_ID INTEGER PRIMARY KEY,
        CatalogPath TEXT, OriginalPath TEXT, FileData BLOB);
    ''');

    // Group root: no variant -> skipped.
    database.execute(
      'INSERT INTO Node(_PW_ID, NodeUuid, NodeName, NodeVariantID) '
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
      'TextureDensity, TextureReverseDensity, TextureBrightness, '
      'TextureContrast, BrushSizeUnit, BrushRotationEffector, '
      'BrushRotationRandomScale, BrushRotationEffectorInSpray, '
      'BrushRotationRandomInSpray, UseDualBrush, DualUsePatternImage, '
      'DualPatternImageArray, DualSize, SyncDualBrushSize, '
      'BrushUseWaterColor, BrushMixColor, BrushMixAlpha, '
      'BrushMixColorExtension, BrushThicknessEffector, '
      'BrushIntervalEffector, CompositeMode, AntiAlias) '
      'VALUES (9, 80, 50.0, 60, 70, 15.0, 40, 200.0, 1, ?, ?, ?, ?, '
      '?, 200.0, 4, ?, 182.0, 90, 1, -40, 30, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
      '?, ?, ?, ?, ?, ?, ?, ?)',
      [
        patternArray(catalogPath),
        effector(
          sizeEffectorFlags,
          minimumPercent: sizeEffectorMinimum,
          randomMinimumPercent: sizeEffectorRandomMinimum,
          curve: sizeEffectorCurve,
        ),
        effector(0x00),
        effector(
          flowEffectorFlags,
          minimumPercent: flowEffectorMinimum,
          randomMinimumPercent: flowEffectorRandomMinimum,
        ),
        useSpray,
        if (texturePng == null) null else patternArray(textureCatalogPath),
        brushSizeUnit,
        rotationEffector,
        rotationRandomScale,
        rotationEffectorInSpray,
        rotationRandomInSpray,
        if (dualPng == null) 0 else 1,
        if (dualPng == null) 0 else 1,
        if (dualPng == null) null else patternArray(dualCatalogPath),
        dualSize,
        syncDualBrushSize,
        useWaterColor,
        mixColor,
        mixAlpha,
        mixColorExtension,
        effector(
          thicknessEffectorFlags,
          minimumPercent: thicknessEffectorMinimum,
          randomMinimumPercent: thicknessEffectorRandomMinimum,
        ),
        effector(
          intervalEffectorFlags,
          minimumPercent: intervalEffectorMinimum,
          randomMinimumPercent: intervalEffectorRandomMinimum,
        ),
        compositeMode,
        antiAlias,
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
    expect(s.textureMaskSource, isNotNull);
    expect(s.textureMaskSource!.size, 8);
    expect(s.textureScale, closeTo(1.82, 1e-9));
    expect(s.textureDensity, closeTo(0.9, 1e-9));
    // 🚨THE LEVELS ARE CARRIED, NOT BAKED — 濃度反転 / 明るさ / コントラスト
    // arrive as three brush settings, so the panel can show and change them.
    // Baking them into the mask on the way in was what made them unreachable.
    expect(s.textureInvert, isTrue);
    expect(s.textureBrightness, closeTo(-0.4, 1e-9));
    expect(s.textureContrast, closeTo(0.3, 1e-9));
    expect(s.textureMask, isNot(same(s.textureMaskSource)));

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

  test('the effector response curve imports as a curve', () async {
    // Clip Studio keeps the 筆압설정 graph in the effector's tail. The
    // minimum is a SEPARATE control that lifts the curve's floor, so the
    // stored y of 0 lands on the minimum and the stored 1 lands on full.
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      sizeEffectorMinimum: 40,
      sizeEffectorCurve: const [(0.25, 0.1), (0.75, 0.9), (1.0, 1.0)],
    );
    final curve = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings.sizePressureCurve!;

    expect(curve.points, [
      const BrushCurvePoint(0.0, 0.4),
      const BrushCurvePoint(0.25, 0.4 + 0.6 * 0.1),
      const BrushCurvePoint(0.75, 0.4 + 0.6 * 0.9),
      const BrushCurvePoint(1.0, 1.0),
    ]);
  });

  test('an untouched graph still reduces to the straight line', () async {
    // Clip Studio writes a two-point block for a brush that never edited
    // the graph; that has to stay byte-identical to the old floor line, or
    // every already-imported brush shifts underfoot.
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      sizeEffectorMinimum: 59,
      sizeEffectorCurve: const [(1.0, 1.0)],
    );
    final curve = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings.sizePressureCurve;

    expect(curve, BrushPressureCurve.linearFrom(0.59));
  });

  test('the effector minimum applies to opacity and flow too', () async {
    // These used to import as a bare identity curve, throwing the floor
    // away: ウェット水彩 asks for an opacity floor of 10%.
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      flowEffectorFlags: 0x10,
      flowEffectorMinimum: 10,
    );
    final s = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings;

    expect(s.flowPressureCurve, BrushPressureCurve.linearFrom(0.10));
  });

  test('random input source drives the jitters', () async {
    // 🚨THE PRESSURE SLOTS CARRY DECOY VALUES. Random's floor lives at
    // int[6] and pressure's at int[3]; before 2026-09-09 the decoder read
    // int[3] for both, and this test could not tell because the fixture
    // wrote one number into every slot. Now the two disagree on purpose —
    // if the reader slips back to pressure's slot, the amplitudes come out
    // 0.93 / 0.55 instead of 0.8 / 0.96 and this fails.
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      sizeEffectorFlags: 0x80,
      sizeEffectorMinimum: 7,
      sizeEffectorRandomMinimum: 20,
      flowEffectorFlags: 0x80,
      flowEffectorMinimum: 45,
      flowEffectorRandomMinimum: 4,
      rotationEffector: 0xC3,
      rotationRandomScale: 45,
      // The PLAIN rotation pair is what this asserts, and the plain pair is
      // what a brush without spray uses — see the two spray tests below.
      useSpray: 0,
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
    // Thickness IS roundness, so its random source squashes the tip.
    expect(s.roundnessJitter, 0.0, reason: 'inert without the random bit');
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
      useSpray: 0,
    );
    final s = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings;

    expect(s.angleJitter, 0.0);
  });

  test('🚨a SPRAY brush spins by its own pair of rotation columns', () async {
    // Measured on the user's real files (2026-09-10): the two brushes of
    // twenty with `BrushUseSpray = 1` PARK the plain pair — effector 3, no
    // random bit — and put the setting in `BrushRotationEffectorInSpray`,
    // which carries the same 0x80. `Sampled Brush 4 3` reads 69 there, and
    // reading only the plain pair imported it as a scatter brush whose
    // stamps all face the same way.
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      rotationEffector: 0x03, // parked: no random
      rotationRandomScale: 100,
      rotationEffectorInSpray: 0x81, // random
      rotationRandomInSpray: 69,
    );
    final s = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings;

    expect(s.angleJitter, closeTo(0.69, 1e-9));
    // The premise: this really is the spray path.
    expect(s.scatterCount, 4);
  });

  test('⛔a spray brush with its IN-SPRAY pair parked does not borrow the '
      'plain one', () async {
    // ウェット水彩 is exactly this: spray on, in-spray randomness 0, and
    // `BrushRotationRandomScale` sitting at its default 100. Falling back to
    // the plain scale would spin a watercolour brush a full turn per dab.
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      rotationEffector: 0xC3, // the random bit IS set on the plain pair
      rotationRandomScale: 100,
      rotationEffectorInSpray: 0x81,
      rotationRandomInSpray: 0,
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

  test('the thickness effector random source squashes the tip', () async {
    // Clip Studio's thickness IS this engine's roundness, so its random
    // input source becomes a per-dab roundness jitter (Sampled Brush 4 3
    // in the user's library carries exactly this).
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      thicknessEffectorFlags: 0x80,
      thicknessEffectorMinimum: 8,
      thicknessEffectorRandomMinimum: 35,
    );
    final s = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings;

    expect(s.roundnessJitter, closeTo(0.65, 1e-9));
  });

  test('the interval effector random source breaks up the beat', () async {
    // 水彩うろこ雲 in the user's library carries exactly this.
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      intervalEffectorFlags: 0x80,
      intervalEffectorMinimum: 8,
      intervalEffectorRandomMinimum: 20,
    );
    final s = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings;

    expect(s.spacingJitter, closeTo(0.8, 1e-9));
  });

  test('a non-normal composite mode travels with the brush', () async {
    // ウェット水彩 composites with 乗算, and Clip Studio files that on the
    // sub tool rather than the hand — so it travels with the brush.
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      compositeMode: 2,
    );
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    expect(
      result.presets.first.settings.blendMode,
      BrushBlendMode.multiply,
    );
    expect(result.warnings, isEmpty);
  });

  test('a normal composite mode imports as 通常', () async {
    // The rule both importers share: index 0 is a VALUE, not an absence —
    // the brush composites normally and says so.
    final path = await buildFixture(tipPng: await blackPng(4, 4));
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    expect(result.presets.first.settings.blendMode, BrushBlendMode.color);
  });

  test(
    'the composite mode index runs the whole 合成モード menu',
    () async {
      // `CompositeMode` is the index of Clip Studio's brush blend menu, which
      // is what puts 乗算 at 2 — the value real files carry.
      const expected = <int, BrushBlendMode>{
        1: BrushBlendMode.darken,
        2: BrushBlendMode.multiply,
        3: BrushBlendMode.colorBurn,
        7: BrushBlendMode.lighten,
        8: BrushBlendMode.screen,
        9: BrushBlendMode.colorDodge,
        12: BrushBlendMode.add,
        14: BrushBlendMode.overlay,
        15: BrushBlendMode.softLight,
        16: BrushBlendMode.hardLight,
        17: BrushBlendMode.difference,
        18: BrushBlendMode.erase,
        19: BrushBlendMode.behind,
        27: BrushBlendMode.exclusion,
      };
      for (final entry in expected.entries) {
        final path = await buildFixture(
          tipPng: await blackPng(4, 4),
          compositeMode: entry.key,
        );
        final result = await decodeSutBrushFile(
          filePath: path,
          sourceName: 'fixture',
        );
        expect(
          result.presets.first.settings.blendMode,
          entry.value,
          reason: 'menu index ${entry.key}',
        );
        expect(result.warnings, isEmpty, reason: 'menu index ${entry.key}');
      }
    },
    // FOURTEEN fixtures where every sibling test builds one: each is a
    // real sqlite database plus PNG encode/decode, so this case does
    // 14× the file work at the same 30s default. A loaded Windows CI
    // runner crossed that line and timed out mid-loop (which then left
    // an open handle for the teardown above to trip on). The code is
    // not slow — the case is big, so it gets a budget that says so.
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('a mode with no kernel yet warns by NAME, not by number', () async {
    // 除算 is a real menu entry this engine cannot composite. Saying so by
    // name is what tells you which kernel a brush would need.
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      compositeMode: 30,
    );
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    expect(result.presets.first.settings.blendMode, BrushBlendMode.color);
    expect(result.warnings.any((w) => w.contains('除算')), isTrue);
  });

  test('the four アンチエイリアス buttons import as the four levels', () async {
    // 🚨MEASURED, one real brush per level (2026-09-09, the four files the
    // user supplied): G펜 3, 質感が残るように混ぜる 2, 鉛筆R 1, 水筆 0. G펜
    // ships from Clip Studio at 強, which is what fixes 3 = strongest; the
    // rest follow the control's own order.
    const expected = <int, BrushAntiAlias>{
      0: BrushAntiAlias.none, // なし
      1: BrushAntiAlias.low, // 弱
      2: BrushAntiAlias.medium, // 中
      3: BrushAntiAlias.high, // 強
    };
    for (final entry in expected.entries) {
      final path = await buildFixture(
        tipPng: await blackPng(4, 4),
        antiAlias: entry.key,
      );
      final result = await decodeSutBrushFile(
        filePath: path,
        sourceName: 'fixture',
      );
      expect(
        result.presets.first.settings.antiAlias,
        entry.value,
        reason: 'AntiAlias ${entry.key}',
      );
      expect(result.warnings, isEmpty, reason: 'AntiAlias ${entry.key}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a file written before the column existed keeps the hard edge', () async {
    // 強 is our identity — the edge the engine already drew — so an older
    // file imports exactly as it did before this column was read.
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      antiAlias: null,
    );
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    expect(result.presets.first.settings.antiAlias, BrushAntiAlias.high);
    expect(result.warnings, isEmpty);
  });

  test('an anti-alias level outside the four warns rather than guessing', () async {
    // A fifth button would be a Clip Studio version we have not seen. Saying
    // the number beats silently drawing a different edge.
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      antiAlias: 7,
    );
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    expect(result.presets.first.settings.antiAlias, BrushAntiAlias.high);
    expect(
      result.warnings.any((w) => w.contains('anti-aliasing level 7')),
      isTrue,
    );
  });

  test('⛔DualAntiAlias is a different column and does not drive this', () async {
    // All four real files park `DualAntiAlias` at 2 while their own
    // `AntiAlias` spans 0..3 — the shape of a value nobody set. A grep
    // without a leading space matches both and reads two values per file.
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      antiAlias: 0,
    );
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    expect(result.presets.first.settings.antiAlias, BrushAntiAlias.none);
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

  test('size unit 2 stores tenths of a pixel', () async {
    // Confirmed against Clip Studio: 小さな雲 stores 15 and reads 150,
    // 水彩うろこ雲 stores 30 and reads 300, while unit-0 brushes match
    // their stored number exactly.
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      brushSizeUnit: 2,
    );
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    expect(result.presets.first.settings.size, 500.0);
    expect(result.warnings, isEmpty);
  });

  test('an unrecognised size unit warns instead of mis-scaling', () async {
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      brushSizeUnit: 7,
    );
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    expect(result.presets.first.settings.size, 50.0);
    expect(result.warnings.any((w) => w.contains('unrecognised unit')), isTrue);
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
