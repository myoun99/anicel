import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/export_format_selection.dart';
import '../../native/qa_image_encoder.dart';
import '../../native/qa_video_encoder.dart';
import '../text/app_strings.dart';
import 'video_export_service.dart' show ExportVideoCodecAbi, ExportVideoContainerAbi;

/// What THIS machine can write (EX4): the OS encoder's probe per
/// container/codec pair, ffmpeg's presence as the fallback answer, and
/// the native JPG encoder for stills. The format picker grays what
/// cannot run and says why — nothing in the lineup fails only at Export.
///
/// The ffmpeg check is one `-version` run, async; until it lands the
/// pairs the OS cannot take stay pessimistically off (they pop in when
/// the answer arrives — honest at every moment).
class ExportFormatAvailability extends ChangeNotifier {
  ExportFormatAvailability({
    QaVideoEncoder? Function()? encoderResolver,
    Future<bool> Function()? ffmpegCheck,
    bool? jpgSupported,
  }) : _jpgSupported = jpgSupported ?? (QaImageEncoder.instance != null) {
    final resolve =
        encoderResolver ??
        () => Platform.environment['FLUTTER_TEST'] == 'true'
            ? null
            : QaVideoEncoder.instance;
    final encoder = resolve();
    for (final container in ExportVideoContainer.values) {
      for (final codec in ExportVideoCodec.codecsFor(container)) {
        _osPairs[(container, codec)] =
            encoder != null &&
            encoder.isSupported &&
            encoder.probe(
              container: container.abiValue,
              codec: codec.abiValue,
            );
      }
    }
    unawaited(_checkFfmpeg(ffmpegCheck ?? _defaultFfmpegCheck));
  }

  /// Every pair allowed, immediately — the widget-test default (the fake
  /// ffmpeg carries the actual run there).
  ExportFormatAvailability.permissive()
    : _jpgSupported = true,
      _ffmpegPresent = true {
    for (final container in ExportVideoContainer.values) {
      for (final codec in ExportVideoCodec.codecsFor(container)) {
        _osPairs[(container, codec)] = true;
      }
    }
  }

  final Map<(ExportVideoContainer, ExportVideoCodec), bool> _osPairs = {};
  bool? _ffmpegPresent;
  final bool _jpgSupported;
  bool _disposed = false;

  static Future<bool> _defaultFfmpegCheck() async {
    try {
      final result = await Process.run('ffmpeg', const ['-version']);
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }

  Future<void> _checkFfmpeg(Future<bool> Function() check) async {
    final present = await check();
    if (_disposed) {
      return;
    }
    _ffmpegPresent = present;
    notifyListeners();
  }

  bool get ffmpegKnown => _ffmpegPresent != null;
  bool get ffmpegPresent => _ffmpegPresent ?? false;

  bool videoAllowed(ExportVideoContainer container, ExportVideoCodec codec) =>
      (_osPairs[(container, codec)] ?? false) || ffmpegPresent;

  /// Why a pair is off; null while it is on.
  String? videoBlockedReason(
    ExportVideoContainer container,
    ExportVideoCodec codec,
  ) {
    if (videoAllowed(container, codec)) {
      return null;
    }
    return ffmpegKnown
        ? AppText.strings.exNeedsFfmpeg
        : AppText.strings.exCheckingEncoders;
  }

  bool stillAllowed(ExportStillFormat format) => switch (format) {
    ExportStillFormat.png => true,
    ExportStillFormat.jpg => _jpgSupported,
    // The PSD writer lands with the Cels/Image round that consumes it.
    ExportStillFormat.psd => false,
  };

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
