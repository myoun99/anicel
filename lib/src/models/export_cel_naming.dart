import 'package:flutter/foundation.dart' show mapEquals;

import 'export_cel_kind.dart';

/// How cel files are named and foldered (CSP-style cel export options).
///
/// The name is `[prefix][project_][cut_][layer]<cel>[suffix].png`: the
/// kind's prefix leads ([prefixOf]), project/cut names join with '_', the
/// layer name sits directly against the cel number (layer 'A' + cel '1' =
/// 'A1'). The cel number is [Frame.celNumber] — the frame's name; an
/// unnamed frame is the in-between mark and has no file, so nothing here
/// ever invents a number.
///
/// Folders nest `[project/][cut/][layer/]`, outermost first — the same
/// three names the file can carry, as two groups the user reads top to
/// bottom (유저 2026-09-09: 「폴더 생성 → 이름 지정 → 자릿수/접미사」).
class ExportCelNaming {
  const ExportCelNaming({
    this.includeProjectName = false,
    this.includeCutName = false,
    this.includeLayerName = true,
    this.frameDigits = 0,
    this.suffix = '',
    this.projectFolder = false,
    this.cutFolder = false,
    this.layerFolder = false,
    this.prefixes = const {},
    this.projectFolderName = const ExportNameAffix(),
    this.cutFolderName = const ExportNameAffix(),
  });

  /// What the project's and the cut's folders wear around their names
  /// ([projectFolder] · [cutFolder]) — `csm_14_` + the cut + `_lo`.
  ///
  /// 🗣️I-153 (유저 2026-11-04): 「csm_14_컷이름_lo 이런식으로 출력하고 …
  /// 그래서 폴더생성에서 컷이나 프로젝트 누르면 아래에 접두 접미사 텍스트
  /// 지정할수있도록」 — the work folders' own shape, title_episode_cut_process.
  final ExportNameAffix projectFolderName;
  final ExportNameAffix cutFolderName;

  /// What each kind's files start with, WHERE THE USER SAID SO — a kind not
  /// here starts with its own default ([ExportCelKind.defaultPrefix]).
  /// Read through [prefixOf].
  ///
  /// 🗣️F-289 (유저 2026-10-06): 「_ 접두사는 … 종류마다 … 접두사는 각각
  /// _로하거나 커스텀으로 텍스트 지정가능」, as one text field a kind — empty
  /// is none ([[F-289-Q9]], 「접두사는 추천대로」). The folders do not wear it.
  final Map<ExportCelKind, String> prefixes;

  /// What [kind]'s files start with.
  String prefixOf(ExportCelKind kind) => prefixes[kind] ?? kind.defaultPrefix;

  /// This naming with [kind]'s files starting with [prefix] — kept only
  /// where it is not the kind's own default, so 「default」 has one spelling.
  ExportCelNaming withPrefix(ExportCelKind kind, String prefix) => copyWith(
    prefixes: {
      for (final entry in prefixes.entries)
        if (entry.key != kind) entry.key: entry.value,
      if (prefix != kind.defaultPrefix) kind: prefix,
    },
  );

  final bool includeProjectName;
  final bool includeCutName;
  final bool includeLayerName;

  /// 0 = off; otherwise the first digit run in the cel number is left-padded
  /// with zeros to this width ('1' → '0001' at 4). Numbers without any
  /// digits are left alone.
  final int frameDigits;

  /// Appended right before '.png' (TVPaint's 後ろ文字付け).
  final String suffix;

  /// Per-project / per-cut / per-layer subfolders under the export
  /// directory, nested in that order.
  final bool projectFolder;
  final bool cutFolder;
  final bool layerFolder;

  ExportCelNaming copyWith({
    bool? includeProjectName,
    bool? includeCutName,
    bool? includeLayerName,
    int? frameDigits,
    String? suffix,
    bool? projectFolder,
    bool? cutFolder,
    bool? layerFolder,
    Map<ExportCelKind, String>? prefixes,
    ExportNameAffix? projectFolderName,
    ExportNameAffix? cutFolderName,
  }) => ExportCelNaming(
    includeProjectName: includeProjectName ?? this.includeProjectName,
    includeCutName: includeCutName ?? this.includeCutName,
    includeLayerName: includeLayerName ?? this.includeLayerName,
    frameDigits: frameDigits ?? this.frameDigits,
    suffix: suffix ?? this.suffix,
    projectFolder: projectFolder ?? this.projectFolder,
    cutFolder: cutFolder ?? this.cutFolder,
    layerFolder: layerFolder ?? this.layerFolder,
    prefixes: prefixes ?? this.prefixes,
    projectFolderName: projectFolderName ?? this.projectFolderName,
    cutFolderName: cutFolderName ?? this.cutFolderName,
  );

  Map<String, dynamic> toJson() => {
    if (includeProjectName) 'includeProjectName': true,
    if (includeCutName) 'includeCutName': true,
    if (!includeLayerName) 'includeLayerName': false,
    if (frameDigits != 0) 'frameDigits': frameDigits,
    if (suffix.isNotEmpty) 'suffix': suffix,
    if (projectFolder) 'projectFolder': true,
    if (cutFolder) 'cutFolder': true,
    if (layerFolder) 'layerFolder': true,
    if (prefixes.isNotEmpty)
      'prefixes': {
        for (final entry in prefixes.entries)
          entry.key.jsonValue: entry.value,
      },
    if (!projectFolderName.isBare)
      'projectFolderName': projectFolderName.toJson(),
    if (!cutFolderName.isBare) 'cutFolderName': cutFolderName.toJson(),
  };

  static ExportCelNaming fromJson(Map<String, dynamic> json) =>
      ExportCelNaming(
        includeProjectName: json['includeProjectName'] as bool? ?? false,
        includeCutName: json['includeCutName'] as bool? ?? false,
        includeLayerName: json['includeLayerName'] as bool? ?? true,
        frameDigits: (json['frameDigits'] as num?)?.round() ?? 0,
        suffix: json['suffix'] as String? ?? '',
        projectFolder: json['projectFolder'] as bool? ?? false,
        cutFolder: json['cutFolder'] as bool? ?? false,
        layerFolder: json['layerFolder'] as bool? ?? false,
        prefixes: switch (json['prefixes']) {
          final Map<String, dynamic> named => {
            for (final entry in named.entries)
              if (ExportCelKind.fromJson(entry.key) case final kind?
                  when entry.value is String &&
                      entry.value != kind.defaultPrefix)
                kind: entry.value as String,
          },
          _ => const {},
        },
        projectFolderName: ExportNameAffix.fromJson(json['projectFolderName']),
        cutFolderName: ExportNameAffix.fromJson(json['cutFolderName']),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportCelNaming &&
          other.includeProjectName == includeProjectName &&
          other.includeCutName == includeCutName &&
          other.includeLayerName == includeLayerName &&
          other.frameDigits == frameDigits &&
          other.suffix == suffix &&
          other.projectFolder == projectFolder &&
          other.cutFolder == cutFolder &&
          other.layerFolder == layerFolder &&
          mapEquals(other.prefixes, prefixes) &&
          other.projectFolderName == projectFolderName &&
          other.cutFolderName == cutFolderName;

  @override
  int get hashCode => Object.hash(
    includeProjectName,
    includeCutName,
    includeLayerName,
    frameDigits,
    suffix,
    projectFolder,
    cutFolder,
    layerFolder,
    Object.hashAllUnordered([
      for (final entry in prefixes.entries) Object.hash(entry.key, entry.value),
    ]),
    projectFolderName,
    cutFolderName,
  );
}

/// What a name wears around it: [prefix] before, [suffix] after — empty
/// for none. ⚠️Not trimmed: what was typed is the name (the files'
/// prefixes are kept so).
class ExportNameAffix {
  const ExportNameAffix({this.prefix = '', this.suffix = ''});

  final String prefix;
  final String suffix;

  /// Whether it wears nothing: the name as it is.
  bool get isBare => prefix.isEmpty && suffix.isEmpty;

  /// [name] with this around it.
  String around(String name) => '$prefix$name$suffix';

  ExportNameAffix copyWith({String? prefix, String? suffix}) =>
      ExportNameAffix(
        prefix: prefix ?? this.prefix,
        suffix: suffix ?? this.suffix,
      );

  Map<String, dynamic> toJson() => {
    if (prefix.isNotEmpty) 'prefix': prefix,
    if (suffix.isNotEmpty) 'suffix': suffix,
  };

  static ExportNameAffix fromJson(Object? json) => switch (json) {
    final Map<String, dynamic> map => ExportNameAffix(
      prefix: map['prefix'] is String ? map['prefix'] as String : '',
      suffix: map['suffix'] is String ? map['suffix'] as String : '',
    ),
    _ => const ExportNameAffix(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportNameAffix &&
          other.prefix == prefix &&
          other.suffix == suffix;

  @override
  int get hashCode => Object.hash(prefix, suffix);
}
