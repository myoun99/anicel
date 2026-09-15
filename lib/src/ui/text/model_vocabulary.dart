import '../../models/app_language.dart';
import '../../models/brush_blend_mode.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_effect.dart';
import '../../models/separable_blend_mode.dart';
import '../../services/canvas_selection_region.dart';
import 'app_strings.dart';
import '../../models/import/cut_folder_parse.dart' show ExclusionReason;
import '../../models/import/import_warning.dart';

/// The names the models own, in a language — I-4's contract
/// ([AppStrings.layerProcessName]): the enum keeps its English `label` and a
/// stable key, and every other language lives in the string tables.
///
/// 🚨유저 2026-09-15 (blend-mode-names-language-Q1): 「블렌드 모드도 모든
/// 언어로 번역」, after F-37-Q1's 「ae도 애초에 언어설정따라서 트랜스폼이나 싹
/// 다 번역되있잖아. 그러니 법 하나로 다 번역」. Until then five enums each
/// carried an inline Japanese table under the 07-22 rule (ja localized first,
/// every other language the shared English): a second copy of the law the
/// tables already keep, and one `models/` could never grow to five languages.
/// ⛔A sixth inline table turns `vocabulary_lives_in_the_string_tables_test`
/// red.
///
/// ⚠️Extensions rather than functions, so every surface keeps the door it
/// already used — `mode.labelFor(language)` — and none has a second way to
/// ask.
extension LayerBlendModeWords on LayerBlendMode {
  String labelFor(AppLanguage language) =>
      AppStrings.of(language).blendModeName(name, label);
}

extension BrushBlendModeWords on BrushBlendMode {
  String labelFor(AppLanguage language) =>
      AppStrings.of(language).blendModeName(name, label);
}

/// The dual tip's composite: the separable twelve alone, under the same keys
/// the layer and brush blends read — which is what keeps the three lists
/// from drifting ([SeparableBlendMode]).
extension SeparableBlendModeWords on SeparableBlendMode {
  String labelFor(AppLanguage language) =>
      AppStrings.of(language).blendModeName(name, label);
}

extension EffectKindWords on EffectKind {
  String labelFor(AppLanguage language) =>
      AppStrings.of(language).effectKindName(jsonValue, label);
}

extension SelectionCombineModeWords on SelectionCombineMode {
  String labelFor(AppLanguage language) =>
      AppStrings.of(language).selectionModeName(name, label);
}

/// An import's warning, said in a language — the same contract the names
/// above keep: the model owns the English wording and the key, the tables
/// own every other language ([AppStrings.importWarning]).
extension ImportWarningWords on ImportWarning {
  String textFor(AppLanguage language) =>
      fill(AppStrings.of(language).importWarning(key, template));
}

/// Why a cut folder's parse dropped a file, in a language.
extension ExclusionReasonWords on ExclusionReason {
  String labelFor(AppLanguage language) =>
      AppStrings.of(language).exclusionReason(name, label);
}
