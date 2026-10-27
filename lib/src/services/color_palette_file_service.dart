import 'dart:math' as math;

import 'persistence/versioned_settings_file.dart';

import 'persistence/app_support_path.dart';

/// One named palette (I-131 — Procreate's palettes, I-131-Q1): its places
/// in order, each a colour or empty.
class NamedPalette {
  const NamedPalette({
    required this.id,
    required this.name,
    required this.slots,
  });

  /// A palette's places — Procreate's thirty (I-131-Q2).
  static const int slotCount = 30;

  /// Who the palette is through a rename: what [ColorPaletteState.defaultId]
  /// holds it by.
  final String id;
  final String name;

  /// [slotCount] long, null where a place is empty.
  final List<int?> slots;

  bool holds(int color) => slots.contains(color);

  NamedPalette _with({String? id, String? name, List<int?>? slots}) =>
      NamedPalette(
        id: id ?? this.id,
        name: name ?? this.name,
        slots: slots ?? this.slots,
      );

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'slots': slots};

  static NamedPalette? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final (id, name, slots) = (json['id'], json['name'], json['slots']);
    if (id is! String || name is! String || slots is! List) {
      return null;
    }
    return NamedPalette(
      id: id,
      name: name,
      slots: placed([
        for (final slot in slots)
          if (slot is int) slot else null,
      ]),
    );
  }

  /// [colors] laid on a palette's places from the first, the rest empty.
  static List<int?> placed(List<int?> colors) => [
    for (var i = 0; i < slotCount; i += 1)
      if (i < colors.length) colors[i] else null,
  ];
}

/// How the palette panel lays every palette's places — ten small ones to a
/// row, or three big ones with their hex (I-131-Q2).
enum PaletteView { compact, cards }

/// The editor's colour palettes (P4 → I-131): named palettes, one of them
/// the default the wheel and the RGB bars show under them, and the recent
/// colours. Editor/app state like brush presets — an app-support JSON file,
/// never project data.
class ColorPaletteState {
  const ColorPaletteState({
    required this.palettes,
    required this.defaultId,
    this.view = PaletteView.compact,
    this.recent = const [],
  });

  /// What a machine with no palette saved starts on: one palette, [name],
  /// holding the quick swatches the single pinned row started with.
  factory ColorPaletteState.starter(String name) => ColorPaletteState(
    palettes: [
      NamedPalette(
        id: 'p1',
        name: name,
        slots: NamedPalette.placed(starterColors),
      ),
    ],
    defaultId: 'p1',
  );

  /// Black, red, blue, white.
  static const List<int> starterColors = [
    0xFF000000,
    0xFFE53935,
    0xFF1E88E5,
    0xFFFFFFFF,
  ];

  static const int maxRecent = 10;

  /// Never empty: a palette is deleted only while another is left.
  final List<NamedPalette> palettes;

  /// The palette shown under the wheel and the RGB bars.
  final String defaultId;
  final PaletteView view;
  final List<int> recent;

  NamedPalette get defaultPalette => palettes.firstWhere(
    (palette) => palette.id == defaultId,
    orElse: () => palettes.first,
  );

  ColorPaletteState _with({
    List<NamedPalette>? palettes,
    String? defaultId,
    PaletteView? view,
    List<int>? recent,
  }) => ColorPaletteState(
    palettes: palettes ?? this.palettes,
    defaultId: defaultId ?? this.defaultId,
    view: view ?? this.view,
    recent: recent ?? this.recent,
  );

  ColorPaletteState _changing(
    String id,
    NamedPalette Function(NamedPalette palette) change,
  ) => _with(
    palettes: [
      for (final palette in palettes)
        if (palette.id == id) change(palette) else palette,
    ],
  );

  /// [color] promoted to the newest recent (deduped, capped).
  ColorPaletteState withRecentColor(int color) {
    if (recent.isNotEmpty && recent.first == color) {
      return this;
    }
    return _with(
      recent: [
        color,
        ...recent.where((entry) => entry != color),
      ].take(maxRecent).toList(),
    );
  }

  /// [color] in place [index] of palette [id] — a colour the palette
  /// already holds goes in all the same (I-131-Q2).
  ColorPaletteState filled(String id, int index, int color) => _changing(
    id,
    (palette) => palette._with(slots: [...palette.slots]..[index] = color),
  );

  /// Palette [id]'s places [from] and [to] traded: a move where [to] was
  /// empty.
  ColorPaletteState traded(String id, int from, int to) =>
      _changing(id, (palette) {
        final slots = [...palette.slots];
        final moving = slots[from];
        slots[from] = slots[to];
        slots[to] = moving;
        return palette._with(slots: slots);
      });

  /// Every place of palette [id] that holds [color], emptied — the places
  /// stay where they are.
  ColorPaletteState emptied(String id, int color) => _changing(
    id,
    (palette) => palette._with(
      slots: [
        for (final slot in palette.slots)
          if (slot == color) null else slot,
      ],
    ),
  );

  /// Palette [id] called [name]; a blank name keeps the one it had.
  ColorPaletteState renamed(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return this;
    }
    return _changing(id, (palette) => palette._with(name: trimmed));
  }

  /// A new empty palette called [name] on top, and the default — as
  /// Procreate makes one (I-131-Q2).
  ColorPaletteState withNewPalette(String name) {
    final id = _freeId();
    return _with(
      palettes: [
        NamedPalette(id: id, name: name, slots: NamedPalette.placed(const [])),
        ...palettes,
      ],
      defaultId: id,
    );
  }

  /// A copy of palette [id], called [name], right after it.
  ColorPaletteState duplicated(String id, String name) {
    final at = palettes.indexWhere((palette) => palette.id == id);
    if (at < 0) {
      return this;
    }
    return _with(
      palettes: [...palettes]
        ..insert(at + 1, palettes[at]._with(id: _freeId(), name: name)),
    );
  }

  /// Without palette [id] — never the last one. Deleting the default makes
  /// the top palette left the default (I-131-Q2).
  ColorPaletteState deleted(String id) {
    if (palettes.length < 2) {
      return this;
    }
    final left = [
      for (final palette in palettes)
        if (palette.id != id) palette,
    ];
    return _with(
      palettes: left,
      defaultId: id == defaultId ? left.first.id : defaultId,
    );
  }

  ColorPaletteState withDefault(String id) => _with(defaultId: id);

  ColorPaletteState withView(PaletteView view) => _with(view: view);

  /// An id no palette has: one past the highest number among them.
  String _freeId() {
    var highest = 0;
    for (final palette in palettes) {
      highest = math.max(highest, int.tryParse(palette.id.substring(1)) ?? 0);
    }
    return 'p${highest + 1}';
  }

  Map<String, Object?> toJson() => {
    'palettes': [for (final palette in palettes) palette.toJson()],
    'default': defaultId,
    'view': view.name,
    'recent': recent,
  };

  /// Null where the document holds no palette — the single pinned row the
  /// file held before I-131 among them: no file from before is read
  /// (no-production-data, 유저 10-06).
  static ColorPaletteState? fromJson(Map<String, dynamic> json) {
    final listed = json['palettes'];
    final palettes = [
      if (listed is List)
        for (final entry in listed) ?NamedPalette.fromJson(entry),
    ];
    if (palettes.isEmpty) {
      return null;
    }
    final defaultId = json['default'];
    final recent = json['recent'];
    return ColorPaletteState(
      palettes: palettes,
      defaultId: palettes.any((palette) => palette.id == defaultId)
          ? defaultId as String
          : palettes.first.id,
      view: PaletteView.values.asNameMap()[json['view']] ?? PaletteView.compact,
      recent: [
        if (recent is List)
          for (final color in recent)
            if (color is int) color,
      ].take(maxRecent).toList(),
    );
  }
}

/// Loads and saves [ColorPaletteState] (brush-preset file pattern; a
/// missing or corrupt file yields the starter).
class ColorPaletteFileService {
  ColorPaletteFileService({String? filePath})
    : filePath = filePath ?? defaultColorPaletteFilePath();

  final String filePath;

  static String defaultColorPaletteFilePath() =>
      appSettingsFilePath('color_palette.json');

  /// 2 = named palettes (I-131); 1 was the single pinned row.
  static const int version = 2;

  /// [starterName] names the one palette a machine with none saved starts
  /// on. The words belong to the UI, which this layer may not import, so
  /// the caller hands them in; the default keeps the English.
  Future<ColorPaletteState> loadOrDefaults({
    String starterName = 'Palette 1',
  }) async =>
      await loadVersionedSettings(
        filePath: filePath,
        version: version,
        fromJson: ColorPaletteState.fromJson,
      ) ??
      ColorPaletteState.starter(starterName);

  Future<void> save(ColorPaletteState state) => saveVersionedSettings(
    filePath: filePath,
    version: version,
    json: state.toJson(),
  );
}
