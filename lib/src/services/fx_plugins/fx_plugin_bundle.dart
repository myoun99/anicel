/// An fx plugin's file (fx spec 2, an-endless-plugin-stalls-the-app-Q4 —
/// 「플러그인을 GPU 커널(WGSL)로」): a zip of the plugin's WGSL and what it
/// says of itself, the one build every device runs on its GPU.
///
/// ↩️Spec 1's file held a WebAssembly module and native builds beside it,
/// and its description was asked of the module; no host here reads one any
/// more (design ①: 「spec 1 파일은 안 읽는다」).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../models/fx_plugin_description.dart';

/// The extension of an fx plugin's file — one of the app's own, named as
/// its others are (`anibrush` · `anipalette`).
const String anicelFxPluginExtension = 'anifx';

/// What an fx plugin's file holds: its WGSL, and its description.
typedef FxPluginBundle = ({String source, FxPluginDescription description});

/// Where a plugin's file keeps its WGSL.
const String fxPluginSourceEntry = 'plugin.wgsl';

/// Where a plugin's file keeps its description.
const String fxPluginDescriptionEntry = 'plugin.json';

/// [bytes] read as a plugin's file — null where they are no zip, one
/// without either entry, an entry that is no UTF-8, or a description that
/// is not a whole one ([FxPluginDescription.read]).
FxPluginBundle? readFxPluginBundle(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on Object {
    return null;
  }
  String? text(String name) {
    final entry = archive.findFile(name)?.readBytes();
    if (entry == null) {
      return null;
    }
    try {
      return utf8.decode(entry);
    } on FormatException {
      return null;
    }
  }

  final source = text(fxPluginSourceEntry);
  final said = text(fxPluginDescriptionEntry);
  final description = said == null ? null : FxPluginDescription.read(said);
  if (source == null || description == null) {
    return null;
  }
  return (source: source, description: description);
}
