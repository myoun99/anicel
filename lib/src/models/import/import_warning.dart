/// Something an import could not do, in words any language can say: the
/// stable [key] a string table answers, the ENGLISH wording this layer owns,
/// and the values its placeholders take.
///
/// 🚨THE CONTRACT THE MODELS' OTHER WORDS ALREADY KEEP (I-4; blend modes,
/// effect kinds and the built-in brush names since 2026-09-15): `models` and
/// `services` may not import the UI's string tables, so the English lives at
/// the call site and every other language is a lookup by key —
/// `ImportWarningWords.textFor` in `ui/text/model_vocabulary.dart`.
///
/// ⛔NOT A BARE `String` (F-124, 2026-09-16). A sentence built where it is
/// raised is built in whatever language the developer typed: the import
/// warnings were English, three of them Korean, and neither could be said in
/// the language the reader had actually set.
class ImportWarning {
  const ImportWarning(this.key, this.template, [this.values = const {}]);

  /// What a table answers, without its `importWarning.` prefix.
  final String key;

  /// The English sentence, `{placeholder}`s and all — and the fallback for a
  /// language that has not tabled [key].
  final String template;

  /// What the placeholders stand for.
  final Map<String, String> values;

  /// [template] filled in: what an English reader sees.
  String get english => fill(template);

  /// [text] with this warning's values put in.
  ///
  /// ⚠️ONE PASS OVER THE KEYS, so a value that happens to contain braces —
  /// a file named `{name}.psd` — names nothing and is copied as it is.
  String fill(String text) {
    var out = text;
    for (final entry in values.entries) {
      out = out.replaceAll('{${entry.key}}', entry.value);
    }
    return out;
  }

  @override
  bool operator ==(Object other) {
    if (other is! ImportWarning ||
        other.key != key ||
        other.template != template ||
        other.values.length != values.length) {
      return false;
    }
    for (final entry in values.entries) {
      if (other.values[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(key, template, values.length);

  /// The English sentence — so a log line, a test failure and a `'$warning'`
  /// read the way the plain string they replaced did.
  @override
  String toString() => english;
}
