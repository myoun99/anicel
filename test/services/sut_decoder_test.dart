import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_correction.dart';
import 'package:anicel/src/models/brush_input_source.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/brush_tip_order.dart';
import 'package:anicel/src/models/separable_blend_mode.dart';
import 'package:anicel/src/services/sut/sut_decoder.dart';
import 'package:sqlite3/sqlite3.dart';
import '../helpers/temp_dir.dart';

/// The 最小値 of [s]'s ランダム row for [target], or null when it has none.
double? randomFloor(BrushSettings s, BrushPressureTarget target) =>
    s.shape.curveFor(target, BrushInputSource.random)?.minimum;

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

  tearDown(() => deleteTempQuietly(tempDirectory));

  /// An effector blob as Clip Studio writes one: a 44-byte header — the
  /// flags at `int[2]`, the four 最小値 at `int[3..6]`, the two graph
  /// blocks' byte lengths at `int[8]` and `int[9]`, 傾き's 最大値 at
  /// `int[10]` — then the 筆圧設定 block and the 傾き設定 block, each
  /// `12 · count · 16` and every one of its points, the first included.
  /// `int[1]` is the 0x1F0 the user's pencils carry; nothing reads it.
  ///
  /// 🚨**THE FOUR MINIMUM SLOTS ARE WRITTEN SEPARATELY**, at `int[3..6]` in
  /// panel order (筆圧 · 傾き · 速度 · ランダム).
  ///
  /// ⛔This used to write `minimumPercent` to `int[3]` and nothing else, so
  /// every synthetic blob had its four slots collapsed into one — and a
  /// decoder reading the WRONG slot read the right number anyway. That is
  /// exactly how the decoder once took pressure's floor as random's
  /// amplitude and no test complained. A fixture that cannot express the
  /// defect cannot catch it.
  ///
  /// 🚨**THE TWO GRAPHS GO IN WHATEVER THE FLAGS TICK**, as 鉛筆's 不透明度
  /// carries both while ticking 筆圧 alone. ↩️This wrote one curve, for
  /// the first ticked source, with its first point left implied — so it
  /// could not tell a decoder reading a graph by its RANK among the ticked
  /// sources from one reading it by its place, and could not hold a graph
  /// that starts anywhere but (0, 0) (F-456).
  Uint8List effector(
    int flags, {
    int minimumPercent = 0,
    int? tiltMinimumPercent,
    int? speedMinimumPercent,
    int? randomMinimumPercent,
    int tiltMaximumPercent = 100,
    List<(double, double)>? pressureGraph,
    List<(double, double)>? tiltGraph,
  }) {
    Uint8List block(List<(double, double)>? points) {
      if (points == null) {
        return Uint8List(0);
      }
      final bytes = ByteData(12 + points.length * 16)
        ..setInt32(0, 12)
        ..setInt32(4, points.length)
        ..setInt32(8, 16);
      for (var i = 0; i < points.length; i += 1) {
        bytes
          ..setFloat64(12 + i * 16, points[i].$1)
          ..setFloat64(20 + i * 16, points[i].$2);
      }
      return bytes.buffer.asUint8List();
    }

    final pressure = block(pressureGraph);
    final tilt = block(tiltGraph);
    final header = ByteData(44)
      ..setInt32(0, 44)
      ..setInt32(4, 0x1f0)
      ..setInt32(8, flags)
      ..setInt32(12, minimumPercent)
      ..setInt32(16, tiltMinimumPercent ?? 0)
      ..setInt32(20, speedMinimumPercent ?? 0)
      ..setInt32(24, randomMinimumPercent ?? 0)
      ..setInt32(32, pressure.length)
      ..setInt32(36, tilt.length)
      ..setInt32(40, tiltMaximumPercent);
    return Uint8List.fromList([
      ...header.buffer.asUint8List(),
      ...pressure,
      ...tilt,
    ]);
  }

  Uint8List u32(int value) =>
      (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

  Uint8List utf16le(String text) => Uint8List.fromList([
    for (final unit in text.codeUnits) ...[unit & 0xFF, unit >> 8],
  ]);

  /// A Clip Studio material array naming [entries] in order, laid out the
  /// way the user's files are (📏2026-10-18): a big-endian u32 saying where
  /// the entries start and a u32 count, then each entry led by its own
  /// length — its layer path, a name and its catalog path inside.
  Uint8List patternArrayOf(List<({String layer, String catalog})> entries) {
    final builder = BytesBuilder()
      ..add(u32(8))
      ..add(u32(entries.length));
    for (final entry in entries) {
      final layer = utf16le(entry.layer);
      final catalog = utf16le(entry.catalog);
      final body = BytesBuilder()
        ..add(u32(layer.length))
        ..add(layer)
        ..add(u32(2))
        ..add(u32(0))
        ..add(u32(catalog.length))
        ..add(catalog);
      builder
        ..add(u32(4 + body.length))
        ..add(body.toBytes());
    }
    return builder.toBytes();
  }

  /// One material's entry, its layer path under its catalog path.
  ({String layer, String catalog}) entryOf(String catalogPath) =>
      (layer: '$catalogPath:data:material_0.layer', catalog: catalogPath);

  /// The array naming one material, as most brushes' do.
  Uint8List patternArray(String catalogPath) =>
      patternArrayOf([entryOf(catalogPath)]);

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

  /// PNG bytes for a [width]x[height] image with nothing on it.
  Future<Uint8List> blankPng(int width, int height) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
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
    List<(double, double)>? sizePressureGraph,
    // F-456: the whole size effector, for a test that sets what the
    // arguments above do not reach.
    Uint8List? sizeEffector,
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
    int dualFlow = 100,
    int syncDualBrushSize = 0,
    int compositeMode = 0,
    int useWaterColor = 0,
    int mixColor = 50,
    int mixAlpha = 50,
    int mixColorExtension = 10,
    // Null stands for a file written before the column existed; 3 (強) is
    // what Clip Studio's own G펜 stores.
    int? antiAlias = 3,
    // F-176-Q3: further tips' materials, the arrays to store in place of the
    // ones naming one material alone, and the 繰り返し方法 number.
    List<({String catalogPath, String originalPath, Uint8List png})>
        moreTipMaterials = const [],
    Uint8List? tipArray,
    Uint8List? dualArray,
    int? patternOrderType,
    int? flickerReduction,
    // F-418: the rest of the 補正 group, null where the file says nothing.
    int? sharpenCorner,
    int? flickerReductionBySpeed,
    int? flickerReductionBySpeedType,
    int? useRevision,
    double? revision,
    int? revisionBySpeed,
    int? revisionByViewScale,
    int? revisionBezier,
    // The dual tip's 合成モード index, null where the file says nothing.
    int? dualCompositeMode,
    // The second tip's own way along the path — its `Brush*` columns over
    // again under `Dual`, null where the file says nothing.
    double? dualInterval,
    int? dualThickness,
    double? dualRotation,
    int? dualUseSpray,
    double? dualSpraySize,
    int? dualSprayDensity,
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
        DualSize REAL, SyncDualBrushSize INTEGER, DualFlow INTEGER,
        BrushUseWaterColor INTEGER, BrushMixColor INTEGER,
        BrushMixAlpha INTEGER, BrushMixColorExtension INTEGER,
        BrushThicknessEffector BLOB, BrushIntervalEffector BLOB,
        CompositeMode INTEGER, AntiAlias INTEGER,
        BrushPatternOrderType INTEGER, FlickerReduction INTEGER,
        BrushSharpenCorner INTEGER, FlickerReductionBySpeed INTEGER,
        FlickerReductionBySpeedType INTEGER, BrushUseRevision INTEGER,
        BrushRevision REAL, BrushRevisionBySpeed INTEGER,
        BrushRevisionByViewScale INTEGER, BrushRevisionBezier INTEGER,
        DualBrushCompositeMode INTEGER, DualInterval REAL,
        DualThickness INTEGER, DualRotation REAL, DualUseSpray INTEGER,
        DualSpraySize REAL, DualSprayDensity INTEGER);
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
      'DualPatternImageArray, DualSize, SyncDualBrushSize, DualFlow, '
      'BrushUseWaterColor, BrushMixColor, BrushMixAlpha, '
      'BrushMixColorExtension, BrushThicknessEffector, '
      'BrushIntervalEffector, CompositeMode, AntiAlias, '
      'BrushPatternOrderType, FlickerReduction, BrushSharpenCorner, '
      'FlickerReductionBySpeed, FlickerReductionBySpeedType, '
      'BrushUseRevision, BrushRevision, BrushRevisionBySpeed, '
      'BrushRevisionByViewScale, BrushRevisionBezier, '
      'DualBrushCompositeMode, DualInterval, DualThickness, DualRotation, '
      'DualUseSpray, DualSpraySize, DualSprayDensity) '
      'VALUES (9, 80, 50.0, 60, 70, 15.0, 40, 200.0, 1, ?, ?, ?, ?, '
      '?, 200.0, 4, ?, 182.0, 90, 1, -40, 30, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
      '?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
      '?, ?)',
      [
        tipArray ?? patternArray(catalogPath),
        sizeEffector ??
            effector(
              sizeEffectorFlags,
              minimumPercent: sizeEffectorMinimum,
              randomMinimumPercent: sizeEffectorRandomMinimum,
              pressureGraph: sizePressureGraph,
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
        if (dualPng == null)
          null
        else
          dualArray ?? patternArray(dualCatalogPath),
        dualSize,
        syncDualBrushSize,
        dualFlow,
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
        patternOrderType,
        flickerReduction,
        sharpenCorner,
        flickerReductionBySpeed,
        flickerReductionBySpeedType,
        useRevision,
        revision,
        revisionBySpeed,
        revisionByViewScale,
        revisionBezier,
        dualCompositeMode,
        dualInterval,
        dualThickness,
        dualRotation,
        dualUseSpray,
        dualSpraySize,
        dualSprayDensity,
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
      for (final material in moreTipMaterials) {
        database.execute(
          'INSERT INTO MaterialFile(CatalogPath, OriginalPath, FileData) '
          'VALUES (?, ?, ?)',
          [
            material.catalogPath,
            material.originalPath,
            Uint8List.fromList([
              ...ascii.encode('catalog.zip'),
              ...Uint8List(17),
              ...material.png,
              ...Uint8List(3),
            ]),
          ],
        );
      }
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

  // Board an-imported-pencil-drops-its-second-brush (2026-10-25): Clip
  // Studio's 鉛筆 · デッサン鉛筆 · ガッシュ carry each tip twice at one size,
  // a blank one first, and came in drawing nothing.
  test('🚨a blank twin of the tip\'s size is not the tip', () async {
    final path = await buildFixture(
      tipPng: await blackPng(6, 4),
      thumbnailPng: await blankPng(6, 4),
    );
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    expect(result.warnings, isEmpty);
    expect(
      result.presets.first.settings.tipMask!.alpha[1 * 6 + 2],
      255,
      reason: 'the inked image, not the blank one before it',
    );
  });

  test('a material that holds a blank image alone comes in without it, and '
      'says so', () async {
    final path = await buildFixture(tipPng: await blankPng(4, 4));
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    expect(result.presets.first.settings.tipMask, isNull);
    expect(
      result.warnings,
      contains(
        endsWith(
          'tip bitmap material holds a blank image alone; imported without '
          'it.',
        ),
      ),
    );
  });

  test('🚨every tip a brush names comes in, in its array\'s order '
      '(F-176-Q3)', () async {
    const second = '.:36:44:second-tip';
    const third = '.:36:45:third-tip';
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      moreTipMaterials: [
        (
          catalogPath: second,
          originalPath: '$second:data:material_0.layer',
          png: await blackPng(6, 6),
        ),
        (
          catalogPath: third,
          originalPath: '$third:data:material_0.layer',
          png: await blackPng(8, 8),
        ),
      ],
      tipArray: patternArrayOf([
        entryOf(third),
        entryOf('.:36:43:fixture-tip-catalog'),
        entryOf(third),
        entryOf(second),
      ]),
    );
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    expect(result.warnings, isEmpty);
    final tips = result.presets.first.settings.tips;
    expect([for (final tip in tips) tip.size], [8, 4, 8, 6]);
    const base = 'sut-0102030405060708090a0b0c0d0e0f10-tip';
    expect(
      [for (final tip in tips) tip.id],
      [base, '$base-2', base, '$base-3'],
    );
    expect(identical(tips[0], tips[2]), isTrue, reason: 'one mask, twice');
  });

  test('⚠️an installed material is found by the catalog path its entry '
      'spells — its layer path drops the Install:', () async {
    const installed = '.:Install:Paint110:fixture-installed';
    const layer = '.:Paint110:fixture-installed:data:material_0.layer';
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      moreTipMaterials: [
        (
          catalogPath: installed,
          originalPath: layer,
          png: await blackPng(6, 6),
        ),
      ],
      tipArray: patternArrayOf([(layer: layer, catalog: installed)]),
    );
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    expect(result.warnings, isEmpty);
    final tips = result.presets.first.settings.tips;
    expect([for (final tip in tips) tip.size], [6]);
  });

  test('🚨a material with an EMPTY catalog path is found by its layer path '
      '(F-456 — 색연필)', () async {
    // The user's 색연필 stores '' as the catalog path and its array spells
    // the layer path alone. ↩️Only a MISSING catalog path fell back, so the
    // tip came in as a plain circle.
    const layer = '.:Paint003:fixture-colored:data:material.layer';
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      moreTipMaterials: [
        (catalogPath: '', originalPath: layer, png: await blackPng(6, 6)),
      ],
      tipArray: patternArrayOf([(layer: layer, catalog: '')]),
    );
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    final tips = result.presets.first.settings.tips;
    expect([for (final tip in tips) tip.size], [6]);
  });

  test('繰り返し方法 comes in by the number Clip Studio stores', () async {
    // All six measured off one brush the user saved six times, the method
    // alone changed (board F-176-Q5, 2026-10-21).
    final orders = <BrushTipOrder>[];
    for (final stored in [null, 0, 1, 2, 3, 4, 5]) {
      final path = await buildFixture(
        tipPng: await blackPng(4, 4),
        patternOrderType: stored,
      );
      final result = await decodeSutBrushFile(
        filePath: path,
        sourceName: 'fixture',
      );
      expect(result.warnings, isEmpty, reason: '$stored');
      orders.add(result.presets.first.settings.tipOrder);
    }

    expect(orders, [
      BrushTipOrder.repeat,
      BrushTipOrder.repeat,
      BrushTipOrder.pingPong,
      BrushTipOrder.holdLast,
      BrushTipOrder.random,
      BrushTipOrder.oneLap,
      BrushTipOrder.shuffledLap,
    ]);
  });

  test('an unrecognised 繰り返し方法 warns and takes the tips in order', () async {
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      patternOrderType: 9,
    );
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    expect(result.presets.first.settings.tipOrder, BrushTipOrder.repeat);
    expect(result.warnings, [contains('BrushPatternOrderType 9')]);
  });

  test('a dual tip naming two images keeps the first, and says so', () async {
    const dual = '.:77:88:fixture-dual-catalog';
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      dualPng: await blackPng(10, 10),
      dualArray: patternArrayOf([
        entryOf(dual),
        entryOf('.:36:43:fixture-tip-catalog'),
      ]),
    );
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    expect(result.presets.first.settings.dualMask!.size, 10);
    expect(result.warnings, [contains('only the first is used')]);
  });

  test('the effector response curve imports as a curve', () async {
    // Clip Studio keeps the 筆압설정 graph in the effector's tail. The
    // minimum is a SEPARATE control — a slider beside the graph — so the
    // graph comes in as it is stored and the floor rides beside it
    // (F-176-Q2), landing the stored y of 0 on the minimum and 1 on full.
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      sizeEffectorMinimum: 40,
      sizePressureGraph: const [
        (0.0, 0.0),
        (0.25, 0.1),
        (0.75, 0.9),
        (1.0, 1.0),
      ],
    );
    final curve = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings.sizePressureCurve!;

    expect(curve.points, [
      const BrushCurvePoint(0.0, 0.0),
      const BrushCurvePoint(0.25, 0.1),
      const BrushCurvePoint(0.75, 0.9),
      const BrushCurvePoint(1.0, 1.0),
    ]);
    expect(curve.minimum, 0.4);
    expect(curve.evaluate(0.0), closeTo(0.4, 1e-12));
  });

  test('an untouched graph still reduces to the straight line', () async {
    // Clip Studio writes a two-point block for a brush that never edited
    // the graph; that has to stay byte-identical to the old floor line, or
    // every already-imported brush shifts underfoot.
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      sizeEffectorMinimum: 59,
      sizePressureGraph: const [(0.0, 0.0), (1.0, 1.0)],
    );
    final curve = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings.sizePressureCurve;

    expect(curve, BrushPressureCurve.linearFrom(0.59));
  });

  test('🚨a graph that does not start at the origin keeps its first point '
      '(F-456)', () async {
    // ↩️The first stored point was taken for padding that had to be (0, 0),
    // so a falling graph was not seen as a graph at all and came in as the
    // straight line up.
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      sizePressureGraph: const [(0.0, 1.0), (0.5, 0.2), (1.0, 0.0)],
    );
    final curve = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings.sizePressureCurve!;

    expect(curve.points, const [
      BrushCurvePoint(0.0, 1.0),
      BrushCurvePoint(0.5, 0.2),
      BrushCurvePoint(1.0, 0.0),
    ]);
  });

  test('a graph that does not run from 0 to 1 comes in straight — no file '
      'has one, so nothing says how to finish it', () async {
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      sizeEffectorMinimum: 59,
      sizePressureGraph: const [(0.2, 0.0), (0.7, 0.9), (1.0, 1.0)],
    );
    final curve = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings.sizePressureCurve;

    expect(curve, BrushPressureCurve.linearFrom(0.59));
  });

  group('🚨傾き (F-456 — Clip Studio\'s 影響元設定 window and the user\'s '
      'pencils)', () {
    const pressureGraph = [(0.0, 0.0), (0.5, 0.9), (1.0, 1.0)];
    // 水平 → 垂直, the way Clip Studio's 傾き設定 graph runs.
    const tiltGraph = [(0.0, 0.2), (0.4, 0.6), (1.0, 1.0)];
    // The same graph over how far the pen LEANS — mirrored.
    const leanPoints = [
      BrushCurvePoint(0.0, 1.0),
      BrushCurvePoint(0.6, 0.6),
      BrushCurvePoint(1.0, 0.2),
    ];

    Future<BrushSettings> decoded(Uint8List sizeEffector) async {
      final path = await buildFixture(
        tipPng: await blackPng(4, 4),
        sizeEffector: sizeEffector,
      );
      return (await decodeSutBrushFile(
        filePath: path,
        sourceName: 'fixture',
      )).presets.first.settings;
    }

    test('0x20 ticked alone reads the SECOND graph, as 傾き, between its '
        'own 最小値 and 最大値', () async {
      // ↩️A graph was the rank of its source among the ticked ones, so 傾き
      // ticked alone read 筆圧設定 as its own — and 0x20 was 速度.
      final s = await decoded(
        effector(
          0x20,
          minimumPercent: 70,
          tiltMinimumPercent: 30,
          tiltMaximumPercent: 300,
          pressureGraph: pressureGraph,
          tiltGraph: tiltGraph,
        ),
      );
      final tilt = s.shape.curveFor(
        BrushPressureTarget.size,
        BrushInputSource.tilt,
      )!;

      expect(tilt.points, leanPoints);
      expect(tilt.minimum, closeTo(0.3, 1e-12));
      expect(tilt.maximum, closeTo(3.0, 1e-12));
      expect(s.sizePressureCurve, isNull, reason: '筆圧 is not ticked');
    });

    test('筆圧 and 傾き ticked together each read their own graph', () async {
      final s = await decoded(
        effector(
          0x30,
          pressureGraph: pressureGraph,
          tiltGraph: tiltGraph,
        ),
      );

      expect(s.sizePressureCurve!.points, const [
        BrushCurvePoint(0.0, 0.0),
        BrushCurvePoint(0.5, 0.9),
        BrushCurvePoint(1.0, 1.0),
      ]);
      expect(
        s.shape
            .curveFor(BrushPressureTarget.size, BrushInputSource.tilt)!
            .points,
        leanPoints,
      );
    });

    test('0x40 is 速度 — a straight line from its 最小値, whatever graphs '
        'the file carries', () async {
      final s = await decoded(
        effector(
          0x40,
          speedMinimumPercent: 25,
          pressureGraph: pressureGraph,
          tiltGraph: tiltGraph,
        ),
      );

      expect(
        s.shape.curveFor(BrushPressureTarget.size, BrushInputSource.speed),
        BrushPressureCurve.linearFrom(0.25),
      );
      expect(
        s.shape.curveFor(BrushPressureTarget.size, BrushInputSource.tilt),
        isNull,
      );
    });
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
    // if the reader slips back to pressure's slot, the floors come out
    // 0.07 / 0.45 instead of 0.2 / 0.04 and this fails.
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

    // Clip Studio wanders between 최소치% and 100% — its ランダム row, which is
    // each setting's own row here, floor and all (F-176-Q2).
    expect(randomFloor(s, BrushPressureTarget.size), closeTo(0.2, 1e-9));
    // Flow has a row of its own — it used to fold into opacity's jitter.
    expect(randomFloor(s, BrushPressureTarget.flow), closeTo(0.04, 1e-9));
    expect(randomFloor(s, BrushPressureTarget.opacity), isNull);
    // The rotation effector is a bare int carrying the same 0x80 bit.
    expect(s.angleJitter, closeTo(0.45, 1e-9));
    // Thickness IS roundness, so its random source squashes the tip.
    expect(
      randomFloor(s, BrushPressureTarget.roundness),
      isNull,
      reason: 'inert without the random bit',
    );
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

  test('🚨the second tip\'s way along the path reads its `Dual` columns as '
      'the first tip\'s `Brush` ones are read', () async {
    // 鉛筆's own: `DualInterval` 10, `DualThickness` 60 — and a spray, read
    // as the first tip's 散布 is: size a percentage of the tip, density the
    // count.
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      dualPng: await blackPng(10, 10),
      dualInterval: 40.0,
      dualThickness: 60,
      dualRotation: 210.0,
      dualUseSpray: 1,
      dualSpraySize: 150.0,
      dualSprayDensity: 3,
    );
    final s = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings;

    expect(s.dualSpacing, closeTo(0.4, 1e-9));
    expect(s.dualRoundness, closeTo(0.6, 1e-9));
    expect(s.dualAngleDegrees, closeTo(30, 1e-9), reason: 'an ellipse half');
    expect(s.dualScatterRadiusRatio, closeTo(0.75, 1e-9));
    expect(s.dualScatterCount, 3);
    // The first tip's columns are the first tip's alone.
    expect(s.spacing, closeTo(0.15, 1e-9));
    expect(s.roundness, closeTo(0.4, 1e-9));
  });

  test('a brush with no second tip keeps the second tip\'s parked columns '
      'out', () async {
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      dualInterval: 40.0,
      dualThickness: 60,
      dualUseSpray: 1,
      dualSpraySize: 150.0,
      dualSprayDensity: 3,
    );
    final s = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings;

    expect(s.dualMask, isNull);
    expect(s.shape.secondTip, isNull);
    expect(s.dualSpacing, const BrushShape().dualSpacing);
    expect(s.dualScatterCount, 1);
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

  // 유저 2026-10-25 (board an-imported-pencil-drops-its-second-brush Q2):
  // 鉛筆 drawn with its dual tip at 通常 measures as the line without it.
  test('🚨a dual tip at 通常 comes in without it, and says so', () async {
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      dualPng: await blackPng(10, 10),
      dualCompositeMode: 0,
    );
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    expect(result.presets.first.settings.dualMask, isNull);
    expect(
      result.warnings,
      [
        'Brush "테스트 브러시": dual brush tip at 通常 draws as no dual tip; '
            'imported without it.',
      ],
    );
  });

  test('a dual tip at any other mode comes in, by that mode', () async {
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      dualPng: await blackPng(10, 10),
      dualCompositeMode: 1,
    );
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    expect(result.warnings, isEmpty);
    final s = result.presets.first.settings;
    expect(s.dualMask, isNotNull);
    expect(s.dualCompositeMode, SeparableBlendMode.darken);
  });

  test('🚨the dual tip arrives at the DENSITY its file gives it', () async {
    // Nobody read this before, from either importer, so every dual brush
    // landed at 1.0 — the unconditional multiply `dualDensity` was added to
    // replace. `ウェット水彩`, the one brush of twenty in the user's files
    // with a dual tip, stores `DualFlow = 30`.
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      dualPng: await blackPng(10, 10),
      dualFlow: 30,
      // ⚠️DIFFERENT FROM THE FLOW ON PURPOSE. The fixture's default dual size
      // is 30 too, so a first draft of this test passed with the decoder
      // reading `DualSize` — the mutation is what said so.
      dualSize: 80.0,
      syncDualBrushSize: 1,
    );
    final s = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings;

    expect(s.dualDensity, closeTo(0.3, 1e-9));
    expect(s.dualMaskScale, closeTo(0.8, 1e-9), reason: 'not the same column');
  });

  test('⛔a brush with NO dual tip keeps the full density its file stores '
      'anyway', () async {
    // The same trap `DualSize` has: Clip Studio parks the dual knobs on
    // brushes that never enabled a second tip, so reading them ungated would
    // fade a brush that has nothing to fade.
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      dualFlow: 30,
    );
    final s = (await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    )).presets.first.settings;

    expect(s.dualMask, isNull, reason: 'fixture premise: no dual tip');
    expect(s.dualDensity, 1.0);
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

    expect(
      randomFloor(s, BrushPressureTarget.roundness),
      closeTo(0.35, 1e-9),
    );
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

    expect(randomFloor(s, BrushPressureTarget.spacing), closeTo(0.2, 1e-9));
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

  Future<void> expectMenuIndices(Map<int, BrushBlendMode> expected) async {
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
  }

  test(
    'the composite mode index runs the whole 合成モード menu',
    () async {
      // `CompositeMode` is the index of Clip Studio's brush blend menu, which
      // is what puts 乗算 at 2 — the value real files carry.
      await expectMenuIndices(const {
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
      });
    },
    // FOURTEEN fixtures where every sibling test builds one: each is a
    // real sqlite database plus PNG encode/decode, so this case does
    // 14× the file work at the same 30s default. A loaded Windows CI
    // runner crossed that line and timed out mid-loop (which then left
    // an open handle for the teardown above to trip on). The code is
    // not slow — the case is big, so it gets a budget that says so.
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'the menu\'s entries Photoshop shares import as themselves',
    () async {
      // brush-fidelity (유저 2026-10-17 Q3: 「13개 + 클튜의 발광 둘」) — the
      // thirteen beyond the first twelve. A table of its own rather than
      // more rows above: thirteen more fixtures in one case would cross
      // the budget the case above was given for fourteen.
      await expectMenuIndices(const {
        4: BrushBlendMode.linearBurn,
        6: BrushBlendMode.subtract,
        23: BrushBlendMode.vividLight,
        24: BrushBlendMode.linearLight,
        25: BrushBlendMode.pinLight,
        26: BrushBlendMode.hardMix,
        28: BrushBlendMode.darkerColor,
        29: BrushBlendMode.lighterColor,
        30: BrushBlendMode.divide,
        31: BrushBlendMode.hue,
        32: BrushBlendMode.saturation,
        33: BrushBlendMode.chroma,
        34: BrushBlendMode.luminosity,
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('a mode with no kernel yet warns by NAME, not by number', () async {
    // 透明度置換 is a real menu entry this engine cannot composite. Saying so
    // by name is what tells you which kernel a brush would need. ↩️This was
    // 除算 until the brush learned it (brush-fidelity).
    final path = await buildFixture(
      tipPng: await blackPng(4, 4),
      compositeMode: 20,
    );
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );

    expect(result.presets.first.settings.blendMode, BrushBlendMode.color);
    expect(result.warnings.any((w) => w.contains('透明度置換')), isTrue);
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

  test("손떨림 보정 comes in as Clip Studio's own number, switched on "
      '(유저 2026-10-20 「수치를 클튜랑 맞추고싶어서」)', () async {
    const expected = <int, double>{0: 0, 4: 4, 100: 100};
    for (final entry in expected.entries) {
      final path = await buildFixture(
        tipPng: await blackPng(4, 4),
        flickerReduction: entry.key,
      );
      final result = await decodeSutBrushFile(
        filePath: path,
        sourceName: 'fixture',
      );
      expect(
        result.presets.first.settings.correction.stabilization,
        closeTo(entry.value, 1e-9),
        reason: 'FlickerReduction ${entry.key}',
      );
      expect(
        result.presets.first.settings.correction.steadies,
        isTrue,
        reason: "Clip Studio's 0 still steadies",
      );
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test("a brush whose file says nothing steadies as Clip Studio's 0 "
      '(F-418-Q6)', () async {
    final path = await buildFixture(tipPng: await blackPng(4, 4));
    final result = await decodeSutBrushFile(
      filePath: path,
      sourceName: 'fixture',
    );
    expect(result.presets, hasLength(2));
    for (final preset in result.presets) {
      expect(
        preset.settings.correction,
        const BrushCorrection(),
        reason: preset.name,
      );
    }
  });

  test('the rest of the 補正 group comes in, each column to its own part '
      '(F-418)', () async {
    Future<BrushCorrection> read(Future<String> fixture) async {
      final result = await decodeSutBrushFile(
        filePath: await fixture,
        sourceName: 'fixture',
      );
      return result.presets.first.settings.correction;
    }

    final tip = await blackPng(4, 4);
    expect(
      await read(
        buildFixture(
          tipPng: tip,
          sharpenCorner: 1,
          flickerReductionBySpeed: 1,
          flickerReductionBySpeedType: 2,
          useRevision: 1,
          revision: 37.5,
          revisionBySpeed: 0,
          revisionByViewScale: 1,
          revisionBezier: 0,
        ),
      ),
      const BrushCorrection(
        sharpenCorners: true,
        steadyingBySpeed: BrushSteadyingBySpeed.fast,
        postStrength: 37.5,
        postBySpeed: false,
      ),
    );
    expect(
      await read(
        buildFixture(
          tipPng: tip,
          sharpenCorner: 0,
          flickerReductionBySpeed: 1,
          flickerReductionBySpeedType: 1,
          useRevision: 1,
          revision: 12,
          revisionBySpeed: 1,
          revisionByViewScale: 0,
          revisionBezier: 1,
        ),
      ),
      const BrushCorrection(
        steadyingBySpeed: BrushSteadyingBySpeed.slow,
        postStrength: 12,
        postByViewScale: false,
        postBezier: true,
      ),
    );
    expect(
      await read(buildFixture(tipPng: tip, useRevision: 0, revision: 50)),
      const BrushCorrection(),
      reason: 'a 後補正 switched off takes nothing out, whatever it keeps',
    );
    expect(
      (await read(
        buildFixture(tipPng: tip, useRevision: 1, revision: 250),
      )).postStrength,
      BrushCorrection.maxPostStrength,
      reason: 'past the scale, it is the most there is',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

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
    expect(
      result.warnings,
      contains(
        allOf(
          startsWith('Brush "'),
          endsWith('tip bitmap is not embedded; imported without it.'),
        ),
      ),
      reason: 'the warning names the brush and the part it came without',
    );
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
