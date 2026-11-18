import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_bundle.dart';
import 'package:archive/archive.dart';

/// A plugin's WGSL the engine's own tests open (fx_wgsl's fixtures):
/// `invert`, `blur`, `layer`, `endless`, `float` and the rest — one copy,
/// read where it lies.
String fxPluginFixture(String name) => File(
  'packages/gpu_engine/rust/native/fx_wgsl/fixtures/$name.wgsl',
).readAsStringSync();

/// A plugin's file as fx spec 2 has it: [source] and [description]'s text,
/// either left out where told [withoutSource] or [withoutDescription].
Uint8List fxPluginFileOf(
  FxPluginDescription description, {
  String source = '',
  bool withoutSource = false,
  bool withoutDescription = false,
}) {
  final archive = Archive();
  if (!withoutSource) {
    archive.add(ArchiveFile.bytes(fxPluginSourceEntry, utf8.encode(source)));
  }
  if (!withoutDescription) {
    archive.add(
      ArchiveFile.bytes(
        fxPluginDescriptionEntry,
        utf8.encode(jsonEncode(description.toJson())),
      ),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

/// A description of the spec this app speaks for [id] — named [name], or
/// its id, made by [vendor] — its [params] as the file says them.
FxPluginDescription fxPluginDescriptionOf(
  String id, {
  String? name,
  String vendor = 'Test',
  String version = '1',
  List<Object?> params = const [],
}) => FxPluginDescription.fromJson({
  'spec': FxPluginDescription.specVersion,
  'id': id,
  'name': name ?? id,
  'vendor': vendor,
  'version': version,
  'can': ['gpu'],
  'params': params,
})!;
