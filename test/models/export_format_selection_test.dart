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
  });
}
