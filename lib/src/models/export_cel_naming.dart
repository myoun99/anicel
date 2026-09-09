/// How cel files are named and foldered (CSP-style cel export options).
///
/// The name is `[project_][cut_][layer]<cel>[suffix].png`: project/cut
/// prefixes join with '_', the layer name sits directly against the cel
/// number (layer 'A' + cel '1' = 'A1'). The cel number is [Frame.celNumber]
/// — the frame's name; an unnamed frame is the in-between mark and has no
/// file, so nothing here ever invents a number.
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
  });

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
  }) => ExportCelNaming(
    includeProjectName: includeProjectName ?? this.includeProjectName,
    includeCutName: includeCutName ?? this.includeCutName,
    includeLayerName: includeLayerName ?? this.includeLayerName,
    frameDigits: frameDigits ?? this.frameDigits,
    suffix: suffix ?? this.suffix,
    projectFolder: projectFolder ?? this.projectFolder,
    cutFolder: cutFolder ?? this.cutFolder,
    layerFolder: layerFolder ?? this.layerFolder,
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
          other.layerFolder == layerFolder;

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
  );
}
