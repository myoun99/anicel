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

/// A layer of a kind this app does not carry, named — every decoder's one
/// word for it, the layer itself left out.
///
/// 🗣️유저 10-09 (보드 `tvpp-unknown-layer-kinds-come-in-unguarded-Q1`, 1번 —
/// 「미래에 어떤 모르는 레이어가 추가될지도 몰라서 … 이건 클튜나 다른 모든
/// 디코드가 똑같음」): 「이 레이어 종류는 아직 지원되지 않습니다 라고 하는게
/// 정확할듯. 다른 디코드 마찬가지 통일해서」 — then 「아직 이라하면 언젠가
/// 지원할것처럼 보이니까 그 단어는 빼자」: no language says 「yet」. ⛔A
/// decoder does not word its own: the TVPaint parser's unknown header,
/// CLIP STUDIO's text, fill, paper and unknown layers and Photoshop's
/// adjustment layers all say this.
ImportWarning unsupportedLayerKind(String name) => ImportWarning(
  'unsupportedLayerKind',
  '{name}: this kind of layer is not supported.',
  {'name': name},
);
