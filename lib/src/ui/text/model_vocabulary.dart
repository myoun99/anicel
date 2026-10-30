import 'package:file_selector/file_selector.dart' show XTypeGroup;

import '../../models/app_language.dart';
import '../../models/brush_blend_mode.dart';
import '../../models/key_path.dart' show KeyPathKind;
import '../../models/key_side.dart' show KeySideKind;
import '../../models/layer_blend_mode.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../../models/separable_blend_mode.dart';
import '../../services/canvas_selection_region.dart';
import '../../services/reference_move_carried.dart' show ReferenceWait;
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

/// The dual tip's composite: the separable modes alone, under the same keys
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

/// An effect's name — its kind's, or a plugin's in its own words
/// ([EffectParameterSpec.ownWords]'s reason).
extension LayerEffectWords on LayerEffect {
  String labelFor(AppLanguage language) =>
      plugin?.name ?? kind.labelFor(language);
}

/// A key side's kind — the key window's choices (I-89 ②).
extension KeySideKindWords on KeySideKind {
  String labelFor(AppLanguage language) =>
      AppStrings.of(language).keySideKindName(name, label);
}

extension KeyPathKindWords on KeyPathKind {
  String labelFor(AppLanguage language) =>
      AppStrings.of(language).keyPathKindName(name, label);
}

/// A row kind's name. Its words are rows of their own in the tables
/// (`tlKind*`) rather than one keyed lookup, so this is the one place that
/// pairs a kind with its row — `layerKindDisplayName` asks here in the
/// program's language.
extension LayerKindWords on LayerKind {
  String labelFor(AppLanguage language) {
    final strings = AppStrings.of(language);
    return switch (this) {
      LayerKind.animation => strings.tlKindAnimation,
      LayerKind.storyboard => strings.tlKindStoryboard,
      LayerKind.image => strings.tlKindImage,
      LayerKind.se => strings.tlKindSe,
      LayerKind.instruction => strings.tlKindInstruction,
      LayerKind.transition => strings.tlKindTransition,
      LayerKind.camera => strings.tlKindCamera,
      LayerKind.folder => strings.tlKindFolder,
      LayerKind.adjustment => strings.tlKindAdjustment,
    };
  }
}

/// A colour label's unabbreviated reading — its stage, and its correction
/// after it — empty for no label. `layerMarkLabel` asks here in the
/// program's language; a key's name asks in the language it is shown in
/// (I-40: the legend's colour solos as actions).
extension LayerMarkWords on LayerMark {
  String labelFor(AppLanguage language) {
    final stage = process;
    if (stage == null) {
      return '';
    }
    final strings = AppStrings.of(language);
    final name = strings.layerProcessName(stage.jsonValue, stage.displayName);
    final correction = revise;
    return correction == null
        ? name
        : '$name '
              '${strings.layerReviseName(correction.jsonValue, correction.displayName)}';
  }
}

/// An effect parameter's lane name, by the id its spec carries — the spec
/// holds its English for the reason the kinds do. F-37 (유저 2026-09-15,
/// F-37-Q1): 「전부 번역 — 레인 이름도 한국어로」.
/// A plugin's parameter is named in its own words ([EffectParameterSpec
/// .ownWords]).
extension EffectParameterSpecWords on EffectParameterSpec {
  String labelFor(AppLanguage language) => ownWords
      ? label
      : AppStrings.of(language).effectParameterName(id, label);
}

/// A word of a menu parameter (I-132-Q6) — a plugin's in its own.
extension EffectChoiceWords on EffectChoice {
  String labelFor(AppLanguage language) => ownWords
      ? label
      : AppStrings.of(language).effectChoiceName(id, label);
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

  /// The warning in a language as a list says it ([partsOf]) — about the
  /// value its sentence opens with (`{name}: …`), if it opens with one.
  WarningLine partsFor(AppLanguage language) {
    final words = AppStrings.of(language).importWarning(key, template);
    final opening = _opensWithOne.firstMatch(words);
    return partsOf(
      fill(words),
      about: opening == null ? null : values[opening.group(1)],
    );
  }
}

/// A warning as a list says it: what it is [about], and what it [says] of
/// that — a sentence of its own.
typedef WarningLine = ({String? about, String says});

/// [sentence] as a list says it: when it opens with [about] and its
/// language's colon (`a.png: …`, `a.png : …`, `a.png：…`), what it says
/// after them, said of [about]; otherwise the whole sentence, about no one
/// thing.
///
/// 🗣️F-370 (유저 2026-10-16: 「줄이 너무 한줄로되있어서 알기힘듬 … 줄
/// 나누거나 해서 항목화하도록」): a notice lists each thing said once, with
/// what it was said of under it — a layer named by a whole paragraph had
/// buried what was said of it.
WarningLine partsOf(String sentence, {String? about}) {
  final colon = about == null || !sentence.startsWith(about)
      ? null
      : _colon.matchAsPrefix(sentence, about.length);
  if (colon == null) {
    return (about: null, says: sentence);
  }
  final says = sentence.substring(colon.end);
  return (
    about: about,
    says: says.isEmpty ? says : says[0].toUpperCase() + says.substring(1),
  );
}

/// A language's colon, and the space around it — ` : ` in French, `：` in
/// Chinese.
final _colon = RegExp(r'\s*[:：]\s*');

/// A sentence that opens with one placeholder — `{name}…`; whether its
/// colon follows is [partsOf]'s to say.
final _opensWithOne = RegExp(r'^\{(\w+)\}');

/// Why a cut folder's parse dropped a file, in a language.
extension ExclusionReasonWords on ExclusionReason {
  String labelFor(AppLanguage language) =>
      AppStrings.of(language).exclusionReason(name, label);
}

/// Why a rasterize left a row the reference it is, and what gets it past,
/// in a language (F-374-Q11).
extension ReferenceWaitWords on ReferenceWait {
  String labelFor(AppLanguage language) =>
      AppStrings.of(language).referenceWait(name, label);
}

/// A save window's file type, its name said in a language — the group keeps
/// its English `label` (`file_type_groups.dart`), the tables the rest.
///
/// ⚠️Keyed by EVERY extension the group names, joined, so a group of
/// several is never answered by the row of one of them.
extension FileTypeGroupWords on XTypeGroup {
  XTypeGroup labelledFor(AppLanguage language) {
    final english = label;
    if (english == null) {
      return this;
    }
    return XTypeGroup(
      label: AppStrings.of(
        language,
      ).fileTypeLabel((extensions ?? const []).join(','), english),
      extensions: extensions,
      mimeTypes: mimeTypes,
      uniformTypeIdentifiers: uniformTypeIdentifiers,
      webWildCards: webWildCards,
    );
  }
}
