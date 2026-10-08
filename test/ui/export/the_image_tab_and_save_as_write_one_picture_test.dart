import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/export_size_mode.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/native/qa_image_encoder.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/frame_image_file.dart';
import 'package:anicel/src/ui/export/still_image_encoders.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';

import '../../helpers/dart_sources.dart';
import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🗣️backlog-21-Q7 (유저 2026-09-30): 「다른 이름으로 저장」's PNG · JPG is
/// 「내보내기 「이미지」와 같은 깨끗한 한 장」. The same picture because it is
/// the same code: the frame it is taken of, the ground it is drawn on, the
/// bytes it is written as and the one call that writes it are each spelled
/// once, here pinned — a behaviour test would pass two spellings that agree
/// today.
void main() {
  /// How often each file under `lib/src` calls [call] — `lib/src` spelled
  /// out, for the affected-tests selector.
  Map<String, int> callersOf(String call) => {
    for (final file in dartFilesUnder('lib/src'))
      if (call.allMatches(file.readAsStringSync()).length case final n
          when n > 0)
        libPath(file): n,
  };

  group('one spelling', () {
    test('⛔fixture premise: the scan reaches the calls it counts', () {
      expect(callersOf('ExportFrameRenderer('), isNotEmpty);
    });

    test('🚨a still file is written by two roads only: a run of many, and '
        'ONE frame', () {
      expect(callersOf('.exportImages('), {
        'lib/src/ui/export/export_dialog.dart': 1,
        'lib/src/ui/export/frame_image_file.dart': 1,
      }, reason: 'a lone frame written by hand is a copy of writeFrameImage');
    });

    test('the image tab\'s picture and Save As\'s are that one call', () {
      expect(callersOf('writeFrameImage('), {
        'lib/src/ui/export/export_dialog.dart': 1,
        'lib/src/ui/export/frame_image_file.dart': 1,
        'lib/src/ui/menu/editor_top_strip.dart': 1,
      });
    });

    test('JPG bytes are made in one place', () {
      expect(callersOf('.encodeJpg('), {
        'lib/src/ui/export/still_image_encoders.dart': 1,
      });
    });
  });

  group('the shared pieces', () {
    late EditorSessionManager session;

    setUp(() {
      session = EditorSessionManager(initialProject: createDefaultProject());
    });

    tearDown(() => session.dispose());

    ui.Color groundOf(ExportFormatSelection format, {bool alphaVideo = false}) =>
        ExportFrameRenderer.forFormat(
          session: session,
          format: format,
          applyLayerFx: true,
          alphaVideo: alphaVideo,
        ).renderService.background;

    test('the ground: none where the file keeps alpha, the format\'s colour '
        'under any other still, white under a video', () {
      const red = 0xFFFF0000;
      expect(
        groundOf(const ExportFormatSelection(kind: ExportMediaKind.still)),
        const ui.Color(0x00000000),
        reason: 'a PNG asked for RGBA',
      );
      expect(
        groundOf(
          const ExportFormatSelection(
            kind: ExportMediaKind.still,
            channels: ExportChannels.rgb,
            backgroundArgb: red,
          ),
        ),
        const ui.Color(red),
      );
      expect(
        groundOf(
          const ExportFormatSelection(
            kind: ExportMediaKind.still,
            stillFormat: ExportStillFormat.jpg,
            backgroundArgb: red,
          ),
        ),
        const ui.Color(red),
        reason: 'a JPG keeps no alpha whatever it is asked',
      );
      expect(
        groundOf(const ExportFormatSelection(backgroundArgb: red)),
        const ui.Color(0xFFFFFFFF),
        reason: 'a video stands on white, not on the still\'s colour',
      );
      expect(
        groundOf(const ExportFormatSelection(), alphaVideo: true),
        const ui.Color(0x00000000),
      );
    });

    test('the frame: the playhead\'s, held inside its cut', () {
      final cut = session.requireActiveCut;
      session.editingFrameCursor.value = cut.duration + 40;
      final task = frameUnderThePlayhead(session)!;
      expect(task.cut.id, cut.id);
      expect(task.frameIndex, cut.duration - 1);

      session.editingFrameCursor.value = 0;
      expect(frameUnderThePlayhead(session)!.frameIndex, 0);
    });

    test('the bytes: PNG is the engine\'s own, JPG has an encoder', () {
      expect(
        stillEncoderFor(const ExportFormatSelection(kind: ExportMediaKind.still)),
        isNull,
      );
      expect(
        stillEncoderFor(
          const ExportFormatSelection(
            kind: ExportMediaKind.still,
            stillFormat: ExportStillFormat.jpg,
          ),
        ),
        isNotNull,
      );
    });
  });

  group('the one call', () {
    late Directory folder;
    late EditorSessionManager session;

    setUp(() {
      folder = Directory.systemTemp.createTempSync('frame-image');
      deleteAfterSessionEnds(folder);
      session = EditorSessionManager(initialProject: createDefaultProject());
    });

    tearDown(() => session.dispose());

    const spec = ImageExportSpec(
      format: ExportFormatSelection(kind: ExportMediaKind.still),
      sizeMode: ExportSizeMode.canvas,
    );

    testWidgets('writes the one file and says how far it came', (
      tester,
    ) async {
      final told = <(int, int)>[];
      final written = await tester.runAsync(
        () => writeFrameImage(session, frameUnderThePlayhead(session)!, spec, (
          directory: folder.path,
          name: 'frame.png',
          isCancelled: null,
          onProgress: (completed, total) => told.add((completed, total)),
        )),
      );
      expect(written, isTrue);
      expect(File('${folder.path}/frame.png').existsSync(), isTrue);
      expect(told, [(1, 1)]);
    });

    testWidgets('⛔a run stopped before it writes nothing, and says so', (
      tester,
    ) async {
      final written = await tester.runAsync(
        () => writeFrameImage(session, frameUnderThePlayhead(session)!, spec, (
          directory: folder.path,
          name: 'frame.png',
          isCancelled: () => true,
          onProgress: null,
        )),
      );
      expect(written, isFalse);
      expect(File('${folder.path}/frame.png').existsSync(), isFalse);
    });

    testWidgets('the tab\'s FX switch reaches the picture: off, a row its FX '
        'hide is drawn raw', (tester) async {
      drawOnCurrentFrame(session);
      final layer = session.requireActiveCut.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation,
      );
      // Animated opacity 0 at frame 0: with its FX the row is not there.
      session.laneVerbs.updateLayerTransformTrack(
        layer.id,
        TransformTrack.empty().copyWith(
          opacity: PropertyTrack<double>().withKey(0, 0),
        ),
      );
      Future<int> dabAlpha({required bool applyLayerFx}) async {
        final name = 'fx-$applyLayerFx.png';
        final alpha = await tester.runAsync(() async {
          await writeFrameImage(
            session,
            frameUnderThePlayhead(session)!,
            ImageExportSpec(
              format: const ExportFormatSelection(kind: ExportMediaKind.still),
              sizeMode: ExportSizeMode.canvas,
              applyLayerFx: applyLayerFx,
            ),
            (
              directory: folder.path,
              name: name,
              isCancelled: null,
              onProgress: null,
            ),
          );
          final codec = await ui.instantiateImageCodec(
            File('${folder.path}/$name').readAsBytesSync(),
          );
          final image = (await codec.getNextFrame()).image;
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final at = (10 * image.width + 10) * 4 + 3;
          image.dispose();
          return data!.getUint8(at);
        });
        return alpha!;
      }

      expect(await dabAlpha(applyLayerFx: true), 0);
      expect(await dabAlpha(applyLayerFx: false), greaterThan(0));
    });
  });

  test('a picture action is named over the door it stands behind — '
      '「다른 이름으로 저장: PNG」', () {
    expect(
      saveAsImageActionLabel(ExportStillFormat.png, AppLanguage.ko),
      '다른 이름으로 저장: PNG',
    );
    expect(
      saveAsImageActionLabel(ExportStillFormat.jpg, AppLanguage.en),
      'Save as: JPG',
    );
  });

  group('what this machine writes', () {
    tearDown(() => QaImageEncoder.debugForceAbsent = false);

    test('PNG always, PSD not yet, JPG where an encoder is', () {
      expect(stillFormatWritable(ExportStillFormat.png), isTrue);
      expect(stillFormatWritable(ExportStillFormat.psd), isFalse);
      expect(
        stillFormatWritable(ExportStillFormat.jpg, jpgSupported: false),
        isFalse,
      );
      expect(
        stillFormatWritable(ExportStillFormat.jpg, jpgSupported: true),
        isTrue,
      );
      QaImageEncoder.debugForceAbsent = true;
      expect(stillFormatWritable(ExportStillFormat.jpg), isFalse);
    });

    test('and the export window grays by the same rule', () {
      final none = ExportFormatAvailability(
        jpgSupported: false,
        encoderResolver: () => null,
        ffmpegCheck: () async => false,
      );
      addTearDown(none.dispose);
      expect(none.stillAllowed(ExportStillFormat.jpg), isFalse);
      expect(none.stillAllowed(ExportStillFormat.png), isTrue);
      expect(none.stillAllowed(ExportStillFormat.psd), isFalse);
    });
  });
}
