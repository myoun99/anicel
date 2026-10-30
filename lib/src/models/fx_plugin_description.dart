import 'dart:convert';

import 'effect_parameter_spec.dart';

/// What an fx plugin says of itself — its description (anicel_fx_plugin.h),
/// read STRICTLY: a description that is not whole is no plugin, because
/// what it declares is a lane, a key and a value of the project for good.
///
/// Its parameters ARE the app's own ([EffectParameterSpec]): 🗣️I-132-Q29
/// (유저 2026-10-29) — the kinds the app's effects have, keyed, graphed and
/// linked the same way — so the lanes, the keys and the values answer a
/// plugin's from the code they answer the app's from.
///
/// ⛔Nothing a description leaves out is made up here: a number or an angle
/// without its range, a menu without its words is refused, not given one.
final class FxPluginDescription {
  FxPluginDescription({
    required this.id,
    required this.name,
    required this.vendor,
    required this.version,
    required this.can,
    required this.parameters,
  });

  /// The spec version this app's host speaks (`ANICEL_FX_SPEC_VERSION`).
  static const int specVersion = 1;

  /// Reverse-DNS, the plugin's for every version — what a project names it
  /// by.
  final String id;
  final String name;
  final String vendor;
  final String version;

  /// What the plugin can do (spec 1: `cpu`) — the list a later host offers
  /// more by (a GPU route), so an older plugin still runs.
  final List<String> can;

  /// Its parameters, in its order — the order of its values in a frame.
  final List<EffectParameterSpec> parameters;

  /// [text] read as a description — null where it is not a whole one of
  /// [specVersion] that this app can run.
  static FxPluginDescription? read(String text) {
    try {
      return fromJson(jsonDecode(text));
    } on FormatException {
      return null;
    }
  }

  /// [json] read as [read] reads its text.
  static FxPluginDescription? fromJson(Object? json) {
    if (json case {
      'spec': specVersion,
      'id': final String id,
      'name': final String name,
      'vendor': final String vendor,
      'version': final String version,
      'can': final List<dynamic> can,
      'params': final List<dynamic> params,
    } when _isName(id)) {
      final canDo = can.whereType<String>().toList();
      if (canDo.length != can.length || !canDo.contains('cpu')) {
        return null;
      }
      final parameters = <EffectParameterSpec>[];
      for (final param in params) {
        final spec = _parameterOf(param);
        if (spec == null || parameters.any((seen) => seen.id == spec.id)) {
          return null;
        }
        parameters.add(spec);
      }
      return FxPluginDescription(
        id: id,
        name: name,
        vendor: vendor,
        version: version,
        can: List.unmodifiable(canDo),
        parameters: List.unmodifiable(parameters),
      );
    }
    return null;
  }

  /// The description as the plugin gave it — what a project keeps of a
  /// plugin, so a machine without it still shows its lanes, values and
  /// keys (🗣️I-132-Q28 「fx 줄은 남기고, 걸리지 않은 채
  /// 「플러그인 없음」으로 둔다」).
  Map<String, Object?> toJson() => {
    'spec': specVersion,
    'id': id,
    'name': name,
    'vendor': vendor,
    'version': version,
    'can': can,
    'params': [for (final spec in parameters) _jsonOf(spec)],
  };

  /// The description as one text — what tells two apart: an effect keeps
  /// its plugin's ([LayerEffect.plugin]), so a project read back must hold
  /// the effect it saved, and the composite's caches compare it.
  late final String _said = jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FxPluginDescription && other._said == _said;

  @override
  int get hashCode => _said.hashCode;

  /// An id, a parameter's or a plugin's: letters, digits and `_ . -` —
  /// nothing a lane's address (`fx:<id>:<parameter>`) or a file name
  /// would read otherwise.
  static bool _isName(String name) =>
      RegExp(r'^[A-Za-z0-9_.\-]+$').hasMatch(name);

  static EffectParameterSpec? _parameterOf(Object? json) {
    if (json case final Map<Object?, Object?> fields && {
      'id': final String id,
      'kind': final String kind,
      'label': final String label,
    } when _isName(id)) {
      return _specOfKind(kind, id, label, fields);
    }
    return null;
  }

  /// The spec a parameter of [kind] describes with the rest of its
  /// [fields] — null where the fields its kind needs are not there, or not
  /// in range.
  static EffectParameterSpec? _specOfKind(
    String kind,
    String id,
    String label,
    Map<Object?, Object?> fields,
  ) => switch ((kind, fields)) {
    ('number' || 'angle', {
      'default': final num initial,
      'min': final num low,
      'max': final num high,
    }) when low <= initial && initial <= high =>
      EffectParameterSpec(
        id: id,
        label: label,
        ownWords: true,
        defaultValue: initial.toDouble(),
        minimum: low.toDouble(),
        maximum: high.toDouble(),
        unit: kind == 'angle'
            ? EffectParameterUnit.degrees
            : EffectParameterUnit.number,
      ),
    ('color', {'default': [
      final num r,
      final num g,
      final num b,
      final num a,
    ]}) when [r, g, b, a].every((c) => 0 <= c && c <= 1) =>
      EffectParameterSpec.color(
        id: id,
        label: label,
        ownWords: true,
        defaultValue: _argbOf(r, g, b, a),
      ),
    ('point', _) => EffectParameterSpec.point(
      id: id,
      label: label,
      ownWords: true,
    ),
    ('checkbox', {'default': final bool on}) => EffectParameterSpec.flag(
      id: id,
      label: label,
      on: on,
      ownWords: true,
    ),
    ('menu', {
      'choices': final List<dynamic> words,
      'default': final int initial,
    }) =>
      _menuOf(id, label, words, initial),
    ('layer', _) => EffectParameterSpec.layer(
      id: id,
      label: label,
      ownWords: true,
    ),
    _ => null,
  };

  static EffectParameterSpec? _menuOf(
    String id,
    String label,
    List<dynamic> words,
    int initial,
  ) {
    final choices = <EffectChoice>[];
    for (final word in words) {
      if (word case {
        'id': final String choice,
        'label': final String said,
      } when _isName(choice)) {
        choices.add(EffectChoice(id: choice, label: said, ownWords: true));
      } else {
        return null;
      }
    }
    if (initial < 0 || initial >= choices.length) {
      return null;
    }
    return EffectParameterSpec.choice(
      id: id,
      label: label,
      ownWords: true,
      choices: List.unmodifiable(choices),
      defaultValue: initial,
    );
  }

  static int _argbOf(num r, num g, num b, num a) {
    int byte(num channel) => (channel * 255).round();
    return byte(a) << 24 | byte(r) << 16 | byte(g) << 8 | byte(b);
  }

  static Map<String, Object?> _jsonOf(EffectParameterSpec spec) {
    final head = {'id': spec.id, 'label': spec.label};
    return switch (spec.unit) {
      EffectParameterUnit.number || EffectParameterUnit.pixels => {
        ...head,
        'kind': 'number',
        'default': spec.defaultValue,
        'min': spec.minimum,
        'max': spec.maximum,
      },
      EffectParameterUnit.degrees => {
        ...head,
        'kind': 'angle',
        'default': spec.defaultValue,
        'min': spec.minimum,
        'max': spec.maximum,
      },
      EffectParameterUnit.color => {
        ...head,
        'kind': 'color',
        'default': channelsOf(spec.defaultValue.toInt()),
      },
      EffectParameterUnit.point => {...head, 'kind': 'point'},
      EffectParameterUnit.flag => {
        ...head,
        'kind': 'checkbox',
        'default': effectFlagIsOn(spec.defaultValue),
      },
      EffectParameterUnit.choice => {
        ...head,
        'kind': 'menu',
        'choices': [
          for (final choice in spec.choices)
            {'id': choice.id, 'label': choice.label},
        ],
        'default': spec.defaultValue.toInt(),
      },
      EffectParameterUnit.layer => {...head, 'kind': 'layer'},
    };
  }

  /// [argb] as the spec says a colour: r, g, b, a from 0 to 1 — a
  /// description's default, and a frame's value (anicel_fx_value).
  static List<double> channelsOf(int argb) => [
    for (final shift in const [16, 8, 0, 24]) ((argb >> shift) & 0xFF) / 255,
  ];
}
