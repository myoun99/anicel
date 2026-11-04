import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/export_format_selection.dart';

void main() {
  group('ExportFormatSelection', () {
    test('default serializes to an empty map and round-trips', () {
      const selection = ExportFormatSelection();
      expect(selection.toJson(), isEmpty);
      expect(ExportFormatSelection.fromJson(const {}), selection);
    });

    test('non-default fields round-trip', () {
      final selection = ExportFormatSelection.normalized(
        kind: ExportMediaKind.still,
        stillFormat: ExportStillFormat.jpg,
        channels: ExportChannels.rgb,
        backgroundArgb: 0xFF102030,
        jpgQuality: 75,
      );
      final restored = ExportFormatSelection.fromJson(selection.toJson());
      expect(restored, selection);
      expect(restored.stillFormat, ExportStillFormat.jpg);
      expect(restored.backgroundArgb, 0xFF102030);
      expect(restored.jpgQuality, 75);
    });

    test('video selection round-trips container, codec and bitrate', () {
      final selection = ExportFormatSelection.normalized(
        container: ExportVideoContainer.mov,
        videoCodec: ExportVideoCodec.proresHq,
        videoBitrateMbps: 24,
      );
      expect(ExportFormatSelection.fromJson(selection.toJson()), selection);
    });

    test('normalization snaps an illegal codec/container pair to H.264', () {
      final selection = ExportFormatSelection.normalized(
        container: ExportVideoContainer.mov,
        videoCodec: ExportVideoCodec.h265,
      );
      expect(selection.videoCodec, ExportVideoCodec.h264);

      final viaCopy = const ExportFormatSelection()
          .copyWith(container: ExportVideoContainer.mov,
              videoCodec: ExportVideoCodec.h265);
      expect(viaCopy.videoCodec, ExportVideoCodec.h264);
    });

    test('ProRes lives in MOV only, H.265 in MP4 only', () {
      expect(
        ExportVideoCodec.codecsFor(ExportVideoContainer.mp4),
        [ExportVideoCodec.h264, ExportVideoCodec.h265],
      );
      expect(ExportVideoCodec.codecsFor(ExportVideoContainer.mov), [
        ExportVideoCodec.h264,
        ExportVideoCodec.proresProxy,
        ExportVideoCodec.proresLt,
        ExportVideoCodec.prores422,
        ExportVideoCodec.proresHq,
        ExportVideoCodec.prores4444,
      ]);
    });

    test('🗣️GIF (I-152): a movie container of its own one way of packing — '
        'no other codec is held in it, and it in no other — with no sound '
        'and no bitrate, read and written by its word', () {
      expect(ExportVideoCodec.codecsFor(ExportVideoContainer.gif), [
        ExportVideoCodec.gif,
      ]);
      for (final container in [
        ExportVideoContainer.mp4,
        ExportVideoContainer.mov,
      ]) {
        expect(
          ExportVideoCodec.codecsFor(container),
          isNot(contains(ExportVideoCodec.gif)),
        );
      }
      final gif = const ExportFormatSelection().copyWith(
        container: ExportVideoContainer.gif,
      );
      expect(
        gif.videoCodec,
        ExportVideoCodec.gif,
        reason: 'H.264 snaps to the container\'s first',
      );
      expect(
        gif.copyWith(container: ExportVideoContainer.mp4).videoCodec,
        ExportVideoCodec.h264,
      );
      expect(gif.fileExtension, 'gif');
      expect(gif.carriesSound, isFalse);
      expect(const ExportFormatSelection().carriesSound, isTrue);
      expect(
        const ExportFormatSelection(kind: ExportMediaKind.still).carriesSound,
        isFalse,
      );
      expect(gif.videoCodec.takesBitrate, isFalse);
      expect(ExportVideoCodec.prores422.takesBitrate, isFalse);
      expect(ExportVideoCodec.h265.takesBitrate, isTrue);
      expect(gif.toJson(), {'container': 'gif', 'videoCodec': 'gif'});
      expect(ExportFormatSelection.fromJson(gif.toJson()), gif);
    });

    // 🗣️I-152 (유저 2026-11-03): 「색처리든 뭐든 gif에대한 세부설정가능한거
    // 두고싶어」.
    // 🗣️I-152-Q1 (유저 2026-11-04): 「채널 행을 보인다」 — ProRes 4444 too.
    test('🚨a GIF keeps a clear colour as a PNG keeps alpha: by the ONE '
        'channels choice, asked of every format that can keep alpha', () {
      final gif = const ExportFormatSelection().copyWith(
        container: ExportVideoContainer.gif,
      );
      expect(gif.copyWith(channels: ExportChannels.rgba).wantsAlpha, isTrue);
      expect(gif.copyWith(channels: ExportChannels.rgb).wantsAlpha, isFalse);
      ExportFormatSelection still(ExportStillFormat format) =>
          ExportFormatSelection.normalized(
            kind: ExportMediaKind.still,
            stillFormat: format,
          );
      ExportFormatSelection movie(ExportVideoCodec codec) =>
          ExportFormatSelection.normalized(
            container: ExportVideoContainer.values.firstWhere(codec.allowedIn),
            videoCodec: codec,
          );
      expect(
        [
          for (final format in ExportStillFormat.values)
            if (!still(format).offersAlpha) format,
        ],
        [ExportStillFormat.jpg],
      );
      expect(
        [
          for (final codec in ExportVideoCodec.values)
            if (movie(codec).offersAlpha) codec,
        ],
        [ExportVideoCodec.prores4444, ExportVideoCodec.gif],
      );
    });

    test('a GIF\'s settings: the defaults are the GIF as it first landed and '
        'are written as nothing; the rest round-trip by their words', () {
      const settings = ExportGifSettings();
      expect(settings.reduction, ExportGifReduction.octree);
      expect(settings.colors, 256);
      expect(settings.dither, ExportGifDither.floydSteinberg);
      expect(settings.plays, 0, reason: 'forever');
      expect(settings.toJson(), isEmpty);
      expect(ExportGifSettings.fromJson(null), settings);
      expect(ExportGifSettings.fromJson('junk'), settings);

      const asked = ExportGifSettings(
        reduction: ExportGifReduction.neural,
        colors: 16,
        dither: ExportGifDither.none,
        plays: 3,
      );
      expect(asked.toJson(), {
        'reduction': 'neural',
        'colors': 16,
        'dither': 'none',
        'plays': 3,
      });
      expect(ExportGifSettings.fromJson(asked.toJson()), asked);
      for (final reduction in ExportGifReduction.values) {
        expect(
          ExportGifSettings.fromJson({'reduction': reduction.jsonValue})
              .reduction,
          reduction,
        );
      }
      for (final dither in ExportGifDither.values) {
        expect(
          ExportGifSettings.fromJson({'dither': dither.jsonValue}).dither,
          dither,
        );
      }

      final selection = const ExportFormatSelection().copyWith(
        container: ExportVideoContainer.gif,
        gif: asked,
      );
      expect(selection.toJson()['gif'], asked.toJson());
      expect(ExportFormatSelection.fromJson(selection.toJson()), selection);
      expect(
        selection,
        isNot(selection.copyWith(gif: const ExportGifSettings())),
        reason: 'two GIFs asked differently are two choices',
      );
      expect(
        selection.copyWith(container: ExportVideoContainer.mp4).gif,
        asked,
        reason: 'kept whatever is chosen, as the JPG\'s quality is',
      );
    });

    test('a GIF\'s count and plays clamp on write, from the window and from '
        'a file alike', () {
      const settings = ExportGifSettings();
      expect(settings.copyWith(colors: 1).colors, 2);
      expect(settings.copyWith(colors: 999).colors, 256);
      expect(settings.copyWith(plays: -3).plays, 0);
      expect(settings.copyWith(plays: 99).plays, exportGifMostPlays);
      expect(
        ExportGifSettings.fromJson({'colors': 999, 'plays': 99}),
        settings.copyWith(colors: 256, plays: exportGifMostPlays),
      );
      expect(
        ExportFormatSelection.normalized(
          gif: const ExportGifSettings(colors: 0),
        ).gif.colors,
        2,
      );
      expect(ExportGifReduction.blackWhite.takesColorCount, isFalse);
      expect(ExportGifReduction.octree.takesColorCount, isTrue);
      expect(ExportGifReduction.neural.takesColorCount, isTrue);
    });

    test('effective channels: JPG and non-4444 video are opaque, the RGBA '
        'preference survives underneath', () {
      final jpg = ExportFormatSelection.normalized(
        kind: ExportMediaKind.still,
        stillFormat: ExportStillFormat.jpg,
        channels: ExportChannels.rgba,
      );
      expect(jpg.effectiveChannels, ExportChannels.rgb);
      expect(jpg.wantsAlpha, isFalse);
      // Switching back to PNG restores the stored RGBA preference.
      expect(
        jpg.copyWith(stillFormat: ExportStillFormat.png).effectiveChannels,
        ExportChannels.rgba,
      );

      final h264 = ExportFormatSelection.normalized(
        channels: ExportChannels.rgba,
      );
      expect(h264.effectiveChannels, ExportChannels.rgb);

      final prores4444 = ExportFormatSelection.normalized(
        container: ExportVideoContainer.mov,
        videoCodec: ExportVideoCodec.prores4444,
        channels: ExportChannels.rgba,
      );
      expect(prores4444.effectiveChannels, ExportChannels.rgba);
      expect(prores4444.wantsAlpha, isTrue);
    });

    test('quality and bitrate clamp on write', () {
      final selection = ExportFormatSelection.normalized(
        jpgQuality: 300,
        videoBitrateMbps: -5,
      );
      expect(selection.jpgQuality, 100);
      expect(selection.videoBitrateMbps, 0);
    });

    test('file extension follows the active kind', () {
      expect(const ExportFormatSelection().fileExtension, 'mp4');
      expect(
        ExportFormatSelection.normalized(
          container: ExportVideoContainer.mov,
        ).fileExtension,
        'mov',
      );
      expect(
        ExportFormatSelection.normalized(
          kind: ExportMediaKind.still,
          stillFormat: ExportStillFormat.psd,
        ).fileExtension,
        'psd',
      );
    });

    test('a PSD keeps the rows of its picture apart (I-117); no other still '
        'does, and no video, whatever still it last stood on', () {
      ExportFormatSelection still(ExportStillFormat format) =>
          ExportFormatSelection.normalized(
            kind: ExportMediaKind.still,
            stillFormat: format,
          );
      expect(
        [
          for (final format in ExportStillFormat.values)
            if (still(format).keepsRowsApart) format,
        ],
        [ExportStillFormat.psd],
      );
      expect(
        ExportFormatSelection.normalized(
          stillFormat: ExportStillFormat.psd,
        ).keepsRowsApart,
        isFalse,
        reason: 'a video\'s frames are its pictures alone',
      );
    });

    // I-117 (유저 2026-10-21): 「새 출력형식으로서 BMP TGA TIFF WEBP」.
    test('the four new stills: their name, their extension, a file that '
        'names them reads them back — and every one but JPG keeps alpha', () {
      expect(
        {
          for (final format in [
            ExportStillFormat.bmp,
            ExportStillFormat.tga,
            ExportStillFormat.tiff,
            ExportStillFormat.webp,
          ])
            format.label: format.fileExtension,
        },
        {'BMP': 'bmp', 'TGA': 'tga', 'TIFF': 'tiff', 'WEBP': 'webp'},
      );
      for (final format in ExportStillFormat.values) {
        final selection = ExportFormatSelection.normalized(
          kind: ExportMediaKind.still,
          stillFormat: format,
        );
        expect(
          ExportFormatSelection.fromJson(selection.toJson()).stillFormat,
          format,
          reason: format.label,
        );
        expect(
          format.supportsAlpha,
          format != ExportStillFormat.jpg,
          reason: format.label,
        );
      }
      expect(ExportStillFormat.fromJson('gif'), ExportStillFormat.png);
    });
  });
}
