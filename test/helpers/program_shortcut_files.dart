import 'dart:io';
import 'dart:typed_data';

import '../services/import/clip_test_builder.dart' show clipDatabaseBytes;

/// A CLIP STUDIO PAINT shortcut set (`.khc`) in the program's own table,
/// holding [rows]: a menu command, its key as the set names it (`NULL` for
/// none), and the set's modifier bits.
Uint8List clipShortcutSetBytes(
  Directory folder,
  List<(String, String, int?)> rows,
) => clipDatabaseBytes(folder, (db) {
  db.execute(
    'CREATE TABLE shortcutmenu(_PW_ID INTEGER PRIMARY KEY AUTOINCREMENT, '
    'menucommandtype TEXT DEFAULT NULL, menucommand TEXT DEFAULT NULL, '
    'shortcut TEXT DEFAULT NULL, modifier INTEGER DEFAULT NULL)',
  );
  for (final (command, key, modifiers) in rows) {
    db.execute(
      'INSERT INTO shortcutmenu(menucommandtype, menucommand, shortcut, '
      'modifier) VALUES (?, ?, ?, ?)',
      ['advancedcommand', command, key, modifiers],
    );
  }
});

/// A CLIP STUDIO PAINT tool palette (`.todb`) in the program's own table,
/// holding [nodes]: a node's name, its key as the palette numbers it (0 for
/// none), and the kind of tool it is (0 for a sub tool).
Uint8List clipToolPaletteBytes(
  Directory folder,
  List<(String, int, int)> nodes,
) => clipDatabaseBytes(folder, (db) {
  db.execute(
    'CREATE TABLE Node(_PW_ID INTEGER PRIMARY KEY AUTOINCREMENT, '
    'NodeName TEXT DEFAULT NULL, NodeShortCutKey INTEGER DEFAULT NULL, '
    'NodeDefaultIdentifier INTEGER DEFAULT NULL)',
  );
  for (final (name, key, kind) in nodes) {
    db.execute(
      'INSERT INTO Node(NodeName, NodeShortCutKey, NodeDefaultIdentifier) '
      'VALUES (?, ?, ?)',
      [name, key, kind],
    );
  }
});
