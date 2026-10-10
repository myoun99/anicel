/// The Format module's value (출력 UI v10): one serializable object holding
/// the container+codec for video, the still format for images, and the
/// shared channel/background/quality knobs. The preset, the queue job and
/// the dialog all carry this — the module owns its own serialization.
library;

/// Whether the selection currently points at the video or the image group
/// of the picker (both groups stay visible; the chosen chip decides).
enum ExportMediaKind {
  video,
  still;

  String get jsonValue => name;

  static ExportMediaKind fromJson(Object? json) => switch (json) {
    'still' => ExportMediaKind.still,
    _ => ExportMediaKind.video,
  };
}

enum ExportVideoContainer {
  mp4,
  mov;

  String get jsonValue => name;

  String get label => switch (this) {
    ExportVideoContainer.mp4 => 'MP4',
    ExportVideoContainer.mov => 'MOV',
  };

  String get fileExtension => switch (this) {
    ExportVideoContainer.mp4 => 'mp4',
    ExportVideoContainer.mov => 'mov',
  };

  static ExportVideoContainer fromJson(Object? json) => switch (json) {
    'mov' => ExportVideoContainer.mov,
    _ => ExportVideoContainer.mp4,
  };
}

/// The confirmed lineup (v10): MP4 = H.264 · H.265, MOV = H.264(경량) +
/// ProRes Proxy/LT/422/HQ/4444(α). ProRes is MOV-only; H.265 is MP4-only.
enum ExportVideoCodec {
  h264,
  h265,
  proresProxy,
  proresLt,
  prores422,
  proresHq,
  prores4444;

  String get jsonValue => name;

  String get label => switch (this) {
    ExportVideoCodec.h264 => 'H.264',
    ExportVideoCodec.h265 => 'H.265',
    ExportVideoCodec.proresProxy => 'ProRes Proxy',
    ExportVideoCodec.proresLt => 'ProRes LT',
    ExportVideoCodec.prores422 => 'ProRes 422',
    ExportVideoCodec.proresHq => 'ProRes HQ',
    ExportVideoCodec.prores4444 => 'ProRes 4444',
  };

  bool get isProRes => switch (this) {
    ExportVideoCodec.h264 || ExportVideoCodec.h265 => false,
    _ => true,
  };

  /// Only 4444 carries alpha; every other codec is opaque.
  bool get supportsAlpha => this == ExportVideoCodec.prores4444;

  bool allowedIn(ExportVideoContainer container) => switch (this) {
    ExportVideoCodec.h264 => true,
    ExportVideoCodec.h265 => container == ExportVideoContainer.mp4,
    _ => container == ExportVideoContainer.mov,
  };

  /// The codecs the picker lists for [container], lineup order.
  static List<ExportVideoCodec> codecsFor(ExportVideoContainer container) => [
    for (final codec in ExportVideoCodec.values)
      if (codec.allowedIn(container)) codec,
  ];

  static ExportVideoCodec fromJson(Object? json) {
    for (final codec in ExportVideoCodec.values) {
      if (codec.jsonValue == json) {
        return codec;
      }
    }
    return ExportVideoCodec.h264;
  }
}

enum ExportStillFormat {
  png,
  jpg,
  psd;

  String get jsonValue => name;

  String get label => switch (this) {
    ExportStillFormat.png => 'PNG',
    ExportStillFormat.jpg => 'JPG',
    ExportStillFormat.psd => 'PSD',
  };

  String get fileExtension => jsonValue;

  /// JPG has no alpha; PNG and PSD choose via [ExportChannels].
  bool get supportsAlpha => this != ExportStillFormat.jpg;

  static ExportStillFormat fromJson(Object? json) => switch (json) {
    'jpg' => ExportStillFormat.jpg,
    'psd' => ExportStillFormat.psd,
    _ => ExportStillFormat.png,
  };
}

/// PNG·PSD = RGBA(투명)/RGB 선택 — RGB면 배경색이 깔리고 PNG 파일에 알파
/// 채널이 없다(색 형식 2, F-335). JPG = RGB 고정.
enum ExportChannels {
  rgba,
  rgb;

  String get jsonValue => name;

  static ExportChannels fromJson(Object? json) => switch (json) {
    'rgb' => ExportChannels.rgb,
    _ => ExportChannels.rgba,
  };
}

const int defaultExportBackgroundArgb = 0xFFFFFFFF;
const int defaultExportJpgQuality = 90;

class ExportFormatSelection {
  /// The const form stores the fields verbatim — the defaults are a legal
  /// combination by construction. Every mutating path ([copyWith],
  /// [fromJson]) re-normalizes, so an illegal pair (H.265+MOV, JPG+RGBA)
  /// never survives a write.
  const ExportFormatSelection({
    this.kind = ExportMediaKind.video,
    this.container = ExportVideoContainer.mp4,
    this.videoCodec = ExportVideoCodec.h264,
    this.stillFormat = ExportStillFormat.png,
    this.channels = ExportChannels.rgba,
    this.backgroundArgb = defaultExportBackgroundArgb,
    this.jpgQuality = defaultExportJpgQuality,
    this.videoBitrateMbps = 0,
  });

  final ExportMediaKind kind;
  final ExportVideoContainer container;
  final ExportVideoCodec videoCodec;
  final ExportStillFormat stillFormat;

  /// Meaningful for PNG/PSD stills and ProRes 4444 video; everything else
  /// resolves to RGB (see [effectiveChannels]).
  final ExportChannels channels;

  /// The backing color when the output has no alpha (RGB stills, JPG).
  final int backgroundArgb;

  /// 1–100 (clamped on write).
  final int jpgQuality;

  /// 0 = automatic (the encoder's own budget); otherwise a target in Mbps.
  final int videoBitrateMbps;

  bool get isVideo => kind == ExportMediaKind.video;
  bool get isStill => kind == ExportMediaKind.still;

  /// The channels the output actually gets: JPG and non-4444 video are
  /// always opaque; PNG/PSD/4444 honor the choice.
  ExportChannels get effectiveChannels {
    if (isVideo) {
      return videoCodec.supportsAlpha ? channels : ExportChannels.rgb;
    }
    return stillFormat.supportsAlpha ? channels : ExportChannels.rgb;
  }

  bool get wantsAlpha => effectiveChannels == ExportChannels.rgba;

  /// The output file extension for the current choice.
  String get fileExtension =>
      isVideo ? container.fileExtension : stillFormat.fileExtension;

  ExportFormatSelection copyWith({
    ExportMediaKind? kind,
    ExportVideoContainer? container,
    ExportVideoCodec? videoCodec,
    ExportStillFormat? stillFormat,
    ExportChannels? channels,
    int? backgroundArgb,
    int? jpgQuality,
    int? videoBitrateMbps,
  }) => normalized(
    kind: kind ?? this.kind,
    container: container ?? this.container,
    videoCodec: videoCodec ?? this.videoCodec,
    stillFormat: stillFormat ?? this.stillFormat,
    channels: channels ?? this.channels,
    backgroundArgb: backgroundArgb ?? this.backgroundArgb,
    jpgQuality: jpgQuality ?? this.jpgQuality,
    videoBitrateMbps: videoBitrateMbps ?? this.videoBitrateMbps,
  );

  /// Legalizes a combination: a codec outside its container snaps to H.264
  /// (legal in both), quality/bitrate clamp to their ranges. Channel
  /// legality lives in [effectiveChannels] so the RGBA preference survives
  /// a round trip through JPG and back to PNG.
  static ExportFormatSelection normalized({
    ExportMediaKind kind = ExportMediaKind.video,
    ExportVideoContainer container = ExportVideoContainer.mp4,
    ExportVideoCodec videoCodec = ExportVideoCodec.h264,
    ExportStillFormat stillFormat = ExportStillFormat.png,
    ExportChannels channels = ExportChannels.rgba,
    int backgroundArgb = defaultExportBackgroundArgb,
    int jpgQuality = defaultExportJpgQuality,
    int videoBitrateMbps = 0,
  }) => ExportFormatSelection(
    kind: kind,
    container: container,
    videoCodec: videoCodec.allowedIn(container)
        ? videoCodec
        : ExportVideoCodec.h264,
    stillFormat: stillFormat,
    channels: channels,
    backgroundArgb: backgroundArgb,
    jpgQuality: jpgQuality.clamp(1, 100),
    videoBitrateMbps: videoBitrateMbps < 0 ? 0 : videoBitrateMbps,
  );

  Map<String, dynamic> toJson() => {
    if (kind != ExportMediaKind.video) 'kind': kind.jsonValue,
    if (container != ExportVideoContainer.mp4)
      'container': container.jsonValue,
    if (videoCodec != ExportVideoCodec.h264)
      'videoCodec': videoCodec.jsonValue,
    if (stillFormat != ExportStillFormat.png)
      'stillFormat': stillFormat.jsonValue,
    if (channels != ExportChannels.rgba) 'channels': channels.jsonValue,
    if (backgroundArgb != defaultExportBackgroundArgb)
      'backgroundArgb': backgroundArgb,
    if (jpgQuality != defaultExportJpgQuality) 'jpgQuality': jpgQuality,
    if (videoBitrateMbps != 0) 'videoBitrateMbps': videoBitrateMbps,
  };

  static ExportFormatSelection fromJson(Map<String, dynamic> json) =>
      normalized(
        kind: ExportMediaKind.fromJson(json['kind']),
        container: ExportVideoContainer.fromJson(json['container']),
        videoCodec: ExportVideoCodec.fromJson(json['videoCodec']),
        stillFormat: ExportStillFormat.fromJson(json['stillFormat']),
        channels: ExportChannels.fromJson(json['channels']),
        backgroundArgb:
            (json['backgroundArgb'] as num?)?.toInt() ??
            defaultExportBackgroundArgb,
        jpgQuality:
            (json['jpgQuality'] as num?)?.round() ?? defaultExportJpgQuality,
        videoBitrateMbps: (json['videoBitrateMbps'] as num?)?.round() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportFormatSelection &&
          other.kind == kind &&
          other.container == container &&
          other.videoCodec == videoCodec &&
          other.stillFormat == stillFormat &&
          other.channels == channels &&
          other.backgroundArgb == backgroundArgb &&
          other.jpgQuality == jpgQuality &&
          other.videoBitrateMbps == videoBitrateMbps;

  @override
  int get hashCode => Object.hash(
    kind,
    container,
    videoCodec,
    stillFormat,
    channels,
    backgroundArgb,
    jpgQuality,
    videoBitrateMbps,
  );

  @override
  String toString() =>
      'ExportFormatSelection('
      '${isVideo ? '${container.label} ${videoCodec.label}' : stillFormat.label}'
      ')';
}
