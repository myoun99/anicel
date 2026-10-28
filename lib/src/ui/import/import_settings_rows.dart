part of 'import_dialog.dart';

/// The Into answer that puts a settings file's row in place: the settings,
/// in place of what is there (🗣️I-142-Q3: 「전부 갈아끼운다」 · Q7:
/// 「남기지 않는다」).
final class _IntoTheSettings {
  const _IntoTheSettings();

  /// What its popup row is keyed by.
  @override
  String toString() => 'settings';
}

/// A row a settings file brought: the file at [path], what it holds, and
/// which row of it.
typedef _HeldSettingsRow = ({String path, SettingsFile file, SettingsRow row});

/// What settings files bring to the import window — a row for each setting
/// a file holds ([settingsRows]), asked one question: the settings, or
/// nowhere.
///
/// 🗣️I-142-Q6 (유저 2026-10-29): 「임포트 창에 설정 파일의 행으로」 —
/// 「옵션같은게 있을테니 사용가능해질거고 최대한 통일하고싶은게 이유」. The
/// rows ride the columns every file is asked ([alsoOfThem]), as a cut
/// folder's do.
final class _SettingsRowsOfTheWindow {
  _SettingsRowsOfTheWindow(this._changed);

  /// The window's own redraw, around a change an answer makes.
  final void Function(VoidCallback change) _changed;

  final Map<String, _HeldSettingsRow> _rows = {};

  /// The rows answered 「제외」.
  final Set<String> _leftOut = {};

  /// Every row's key, in the order the table lists them.
  Iterable<String> get keys => _rows.keys;

  bool holds(String key) => _rows.containsKey(key);

  /// Takes the settings file at [path], holding [text], as its rows — false
  /// where it brings none: no settings file this build reads, or one that
  /// holds no setting of a row.
  bool take(String path, String text) {
    final file = readSettingsFile(text);
    if (file == null) {
      return false;
    }
    final held = [
      for (final row in settingsRows)
        if (row.heldBy(file)) row,
    ];
    for (final row in held) {
      _rows['$path#${row.id}'] = (path: path, file: file, row: row);
    }
    return held.isNotEmpty;
  }

  /// The files the rows came in, each once.
  Iterable<String> get files => {for (final held in _rows.values) held.path};

  /// The answers [key]'s row is asked: the settings, or nowhere — nowhere
  /// alone, locked, for a row this build cannot read.
  List<Object> answersFor(String key) => [
    if (_reads(key)) const _IntoTheSettings(),
    const _LeftOut(),
  ];

  Object answerOf(String key) =>
      _reads(key) && !_leftOut.contains(key)
          ? const _IntoTheSettings()
          : const _LeftOut();

  /// What [key]'s row says for [value]: why it goes nowhere, where it
  /// cannot be read.
  String? wordOf(String key, Object? value) =>
      value is _LeftOut && !_reads(key)
          ? AppText.strings.imSettingsUnreadable
          : null;

  void pick(Iterable<String> keys, Object? value) => _changed(() {
    for (final key in keys) {
      if (value is _LeftOut) {
        _leftOut.add(key);
      } else if (value is _IntoTheSettings) {
        _leftOut.remove(key);
      }
    }
  });

  bool _reads(String key) {
    final held = _rows[key]!;
    return held.row.readsIn(held.file);
  }

  /// The rows a run puts in place.
  List<String> get inPlace => [
    for (final key in _rows.keys)
      if (answerOf(key) is _IntoTheSettings) key,
  ];

  /// [key]'s row as the table lists it: the setting by its name, from the
  /// file of its [modified] day.
  ImportFileRow tableRow(String key, String modified) {
    final held = _rows[key]!;
    return ImportFileRow(
      path: key,
      name: held.row.label(AppText.strings),
      extension: anicelSettingsExtension,
      modified: modified,
      size: '',
      resolution: '',
    );
  }

  /// The file [key]'s row came in.
  String fileOf(String key) => _rows[key]!.path;

  /// [column] as the settings rows answer it too: the Into column — which
  /// [asked] says — asks them the settings or nowhere, and every other is
  /// a dash on their rows. A press speaks for the selection of both kinds.
  ImportColumn<Object?> alsoOfThem(
    ImportColumn<Object?> column, {
    bool asked = false,
  }) {
    List<Object> answers(String key) => asked ? answersFor(key) : const [];
    return ImportColumn<Object?>(
      id: column.id,
      label: column.label,
      help: column.help,
      style: column.style,
      values: [
        ...column.values,
        if (asked && _rows.isNotEmpty) const _IntoTheSettings(),
      ],
      labelOf: (value) => value is _IntoTheSettings
          ? AppText.strings.imIntoSettings
          : column.labelOf(value),
      valuesFor: (key) => holds(key) ? answers(key) : column.answersFor(key),
      wordOf: (key, value) =>
          holds(key) ? wordOf(key, value) : column.wordOf?.call(key, value),
      valueOf: (key) => holds(key) ? answerOf(key) : column.valueOf(key),
      appliesTo: (key) =>
          holds(key) ? answers(key).isNotEmpty : column.appliesTo(key),
      enabledFor: (key, value) =>
          holds(key) ? answers(key).contains(value) : column.enabledFor(key, value),
      onPick: (keys, value) {
        // An answer the files are never asked — the settings — is not theirs
        // to take.
        if (column.values.contains(value)) {
          column.onPick([
            for (final key in keys)
              if (!holds(key)) key,
          ], value);
        }
        pick([
          for (final key in keys)
            if (holds(key) && answers(key).contains(value)) key,
        ], value);
      },
    );
  }

  /// Puts the rows answered the settings in place by [put], file by file,
  /// into [tally] — each row done, or the file's failure said of it.
  Future<void> putInPlace(
    Future<void> Function(SettingsFile file, List<SettingsRow> rows) put,
    _ImportTally tally,
  ) async {
    final byFile = <String, List<String>>{};
    for (final key in inPlace) {
      (byFile[_rows[key]!.path] ??= []).add(key);
    }
    for (final MapEntry(key: path, value: keys) in byFile.entries) {
      try {
        await put(_rows[keys.first]!.file, [
          for (final key in keys) _rows[key]!.row,
        ]);
        tally
          ..imported += keys.length
          ..done.addAll(keys);
      } on Object catch (error) {
        tally.warnOf(mediaFileName(path), '$error');
      }
    }
  }

  /// The rows a run put in place leave the table, as a file that landed
  /// leaves it.
  void landed(Iterable<String> done) {
    _rows.removeWhere((key, _) => done.contains(key));
    _leftOut.removeWhere(done.contains);
  }
}
