import 'dart:math' as math;

import '../models/reorder_target.dart';
import 'persistence/settings_file.dart';
import 'persistence/versioned_settings_file.dart';

import 'persistence/app_support_path.dart';

/// One named palette (I-131 — Procreate's palettes, I-131-Q1): its places
/// in order, each a colour or empty.
class NamedPalette {
  const NamedPalette({
    required this.id,
    required this.name,
    required this.slots,
    this.folded = false,
    this.locked = false,
  });

  /// A palette's places — Procreate's thirty (I-131-Q2).
  static const int slotCount = 30;

  /// Who the palette is through a rename: what [ColorPaletteState.defaultId]
  /// holds it by.
  final String id;
  final String name;

  /// [slotCount] long, null where a place is empty.
  final List<int?> slots;

  /// Folded in the palette panel: its name alone stands there (I-131,
  /// 유저 2026-10-28: 「이름 탭하면 접기」).
  final bool folded;

  /// Locked: it shows its colours alone, packed with no empty place, and
  /// takes no edit — a press only picks (I-131, 유저 2026-10-28: 「빈 칸
  /// 없애서 fit하게 컴팩트하게 … 색끼리 드래그도 안되고 그런 편집기능 다
  /// 잠금」). The places keep where they stand, so it unlocks as it was.
  final bool locked;

  bool holds(int color) => slots.contains(color);

  /// The places a locked palette shows: its colours, in order.
  List<int> get colors => [...slots.nonNulls];

  NamedPalette _with({
    String? id,
    String? name,
    List<int?>? slots,
    bool? folded,
    bool? locked,
  }) => NamedPalette(
    id: id ?? this.id,
    name: name ?? this.name,
    slots: slots ?? this.slots,
    folded: folded ?? this.folded,
    locked: locked ?? this.locked,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'slots': slots,
    'folded': folded,
    'locked': locked,
  };

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
      folded: json['folded'] == true,
      locked: json['locked'] == true,
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

  /// Palette [id]'s place [index] emptied — that one place, where the −
  /// empties every place holding the current colour (I-131: the delete in
  /// a colour's double-click window).
  ColorPaletteState cleared(String id, int index) => _changing(
    id,
    (palette) => palette._with(slots: [...palette.slots]..[index] = null),
  );

  /// Palette [id] moved to stand before palette [beforeId] — last where
  /// that is null (I-131: 「위치관계 바꿀수있게」, by the brush groups'
  /// own move).
  ColorPaletteState moved(String id, String? beforeId) {
    NamedPalette? byId(String? wanted) =>
        palettes.where((palette) => palette.id == wanted).firstOrNull;
    final palette = byId(id);
    if (palette == null) {
      return this;
    }
    return _with(
      palettes: movedBefore(palettes, moved: palette, anchor: byId(beforeId)),
    );
  }

  ColorPaletteState withFolded(String id, {required bool folded}) =>
      _changing(id, (palette) => palette._with(folded: folded));

  ColorPaletteState withLocked(String id, {required bool locked}) =>
      _changing(id, (palette) => palette._with(locked: locked));

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

  /// [brought] on top in their order, each under an id of its own — a
  /// palette file read (I-142), added as a brush or a shortcut file is.
  /// ⚠️MY READING: the default stays — what the wheel shows under it does
  /// not change because a file came in.
  ColorPaletteState withBrought(List<NamedPalette> brought) {
    var state = this;
    for (final palette in brought.reversed) {
      state = state._with(
        palettes: [palette._with(id: state._freeId()), ...state.palettes],
      );
    }
    return state;
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

  /// Its document's name in a settings file ([paletteSettingsFile]): its
  /// file's in the settings room. ⚠️Spelled out again below on purpose —
  /// the room's scan reads the store's call as written
  /// (`settings_live_in_one_room_test`); a test holds the two together.
  static const String fileName = 'color_palette.json';

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

/// [palette] alone as a settings file (I-142): the palette store's own
/// document, holding just it.
String paletteSettingsFile(NamedPalette palette) => encodeSettingsFile({
  ColorPaletteFileService.fileName: versionedSettingsDocument(
    ColorPaletteFileService.version,
    ColorPaletteState(palettes: [palette], defaultId: palette.id).toJson(),
  ),
});

/// The palettes the settings file [source] holds, read as the palette store
/// reads its own file — null where it holds none.
List<NamedPalette>? palettesInSettingsFile(String source) {
  final document = decodeSettingsFile(
    source,
  )?[ColorPaletteFileService.fileName];
  if (document == null) {
    return null;
  }
  try {
    return liftVersionedSettingsDocument(
      document,
      version: ColorPaletteFileService.version,
      fromJson: ColorPaletteState.fromJson,
    )?.palettes;
  } on Object {
    return null;
  }
}
