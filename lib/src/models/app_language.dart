/// The languages the app speaks (UI-R10 #7) — used TWICE, independently:
/// the PROGRAM language (menus, panels, labels) and the NOTATION language
/// (what prints on submission artifacts like the timesheet). An American
/// studio working on Japanese anime runs the program in English and
/// prints the sheet in Japanese — hence two settings, not one.
enum AppLanguage {
  en,
  ja,
  ko,
  fr,
  zhHans;

  String toJson() => name;

  static AppLanguage fromJson(Object? value) => switch (value) {
    'en' => AppLanguage.en,
    'ja' => AppLanguage.ja,
    'ko' => AppLanguage.ko,
    'fr' => AppLanguage.fr,
    'zhHans' => AppLanguage.zhHans,
    _ => throw FormatException('Unknown app language: $value'),
  };

  /// The language's own name (settings dropdowns show every language in
  /// itself, the universal convention).
  String get displayName => switch (this) {
    AppLanguage.en => 'English',
    AppLanguage.ja => '日本語',
    AppLanguage.ko => '한국어',
    AppLanguage.fr => 'Français',
    AppLanguage.zhHans => '简体中文',
  };

  /// The language a device that prefers [languageCodes] — in its own order,
  /// ISO 639 codes — reads the app in: the first of them the app speaks, or
  /// the program default when it speaks none of them.
  ///
  /// 🚨F-157 (유저 2026-09-17): 「앱 기본 언어 설정값, 디바이스? 의 언어 설정
  /// 기준으로」. ⚠️Every Chinese reads 简体: it is the one Chinese the app
  /// speaks, and a reader of either script reads it better than English —
  /// my call, on the user's 「그런부분은 알아서 맡기고」.
  static AppLanguage forDevice(Iterable<String> languageCodes) {
    for (final code in languageCodes) {
      final spoken = switch (code.toLowerCase()) {
        'en' => AppLanguage.en,
        'ja' => AppLanguage.ja,
        'ko' => AppLanguage.ko,
        'fr' => AppLanguage.fr,
        'zh' => AppLanguage.zhHans,
        _ => null,
      };
      if (spoken != null) {
        return spoken;
      }
    }
    return const AppLanguageSettings().programLanguage;
  }
}

/// The two language settings together (UI-R10 #7). Defaults follow the
/// user's rule: program = English, notation = Japanese.
///
/// ↩️F-157 (유저 2026-09-17): 「앱 기본 언어 설정값, 디바이스? 의 언어 설정
/// 기준으로. 즉 앱컨테이너 설정에 language_settings.json 파일이 없을때 …
/// 표기언어 기본값은 지금처럼 일본어 그대로」. With no settings file the
/// PROGRAM reads the device's language ([AppLanguage.forDevice]); English
/// stays the answer for a device the app does not speak, and for a host
/// with no settings store at all.
class AppLanguageSettings {
  const AppLanguageSettings({
    this.programLanguage = AppLanguage.en,
    this.notationLanguage = AppLanguage.ja,
  });

  /// What the APP UI reads in (coverage rolls out incrementally — strings
  /// not yet tabled stay English).
  final AppLanguage programLanguage;

  /// What SUBMISSION artifacts print in (the timesheet header labels, the
  /// repeat word, …).
  final AppLanguage notationLanguage;

  AppLanguageSettings copyWith({
    AppLanguage? programLanguage,
    AppLanguage? notationLanguage,
  }) => AppLanguageSettings(
    programLanguage: programLanguage ?? this.programLanguage,
    notationLanguage: notationLanguage ?? this.notationLanguage,
  );

  Map<String, dynamic> toJson() => {
    'program': programLanguage.toJson(),
    'notation': notationLanguage.toJson(),
  };

  factory AppLanguageSettings.fromJson(Map<String, dynamic> json) =>
      AppLanguageSettings(
        programLanguage: AppLanguage.fromJson(json['program']),
        notationLanguage: AppLanguage.fromJson(json['notation']),
      );

  @override
  bool operator ==(Object other) =>
      other is AppLanguageSettings &&
      other.programLanguage == programLanguage &&
      other.notationLanguage == notationLanguage;

  @override
  int get hashCode => Object.hash(programLanguage, notationLanguage);

  @override
  String toString() =>
      'AppLanguageSettings(program: ${programLanguage.name}, '
      'notation: ${notationLanguage.name})';
}
