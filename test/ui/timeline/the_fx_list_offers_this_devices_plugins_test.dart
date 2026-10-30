import 'dart:convert';
import 'dart:io';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_library_service.dart';
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/effects_and_fx.dart' show TrackChain;
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart'
    show addEffectLabel;
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/timeline_bar_menus.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir.dart';

/// I-132: the Fx list offers the plugins this device has installed, under
/// a heading of their own after the app's kinds — each added as an effect
/// of it, and deleted off the device from its row, as the text tool's list
/// keeps this device's fonts. A device that has none shows none of either.
void main() {
  late Directory room;
  setUp(() => room = Directory.systemTemp.createTempSync('anicel_fx_list_'));
  tearDown(() => deleteTempQuietly(room));

  String describing(String id) => jsonEncode({
    'spec': 1,
    'id': id,
    'name': 'Plugin $id',
    'vendor': 'Example',
    'version': '1',
    'can': ['cpu'],
    'params': [
      {
        'id': 'amount',
        'kind': 'number',
        'label': 'Amount',
        'default': 5,
        'min': 0,
        'max': 10,
      },
    ],
  });

  // The device's plugins, its module asked through a stand-in: the
  // module is its description's text.
  Future<InstalledFxPlugins> deviceWith(List<String> ids) async {
    final plugins = InstalledFxPlugins(
      service: FxPluginLibraryService(directoryPath: '${room.path}/fx'),
      describe: (wasm) => (text: utf8.decode(wasm), refusal: null),
    );
    addTearDown(plugins.dispose);
    for (final id in ids) {
      final archive = Archive()
        ..add(ArchiveFile.bytes('plugin.wasm', utf8.encode(describing(id))));
      await plugins.install(
        ZipEncoder().encodeBytes(archive),
        confirm: (_, {required native, required replacing}) async => true,
      );
    }
    return plugins;
  }

  EditorSessionManager sessionOn(
    InstalledFxPlugins plugins, {
    List<Layer> also = const [],
  }) {
    final session = EditorSessionManager(
      fxPlugins: plugins,
      initialProject: Project(
        id: const ProjectId('fx-list'),
        name: 'Fx list',
        createdAt: DateTime.utc(2026, 10, 30),
        tracks: [
          Track(
            id: const TrackId('t1'),
            name: 'V1',
            cuts: [
              Cut(
                id: const CutId('a'),
                name: 'a',
                duration: 12,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  Layer(
                    id: const LayerId('cel'),
                    name: 'cel',
                    kind: LayerKind.animation,
                    frames: [
                      Frame(
                        id: const FrameId('cel-0'),
                        duration: 1,
                        strokes: const [],
                      ),
                    ],
                    timeline: {
                      0: const TimelineExposure.drawing(
                        FrameId('cel-0'),
                        length: 12,
                      ),
                    },
                  ),
                  ...also,
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    return session
      ..selectCut(const CutId('a'))
      ..selectLayer(const LayerId('cel'));
  }

  List<PanelFlyoutEntry> listOf(EditorSessionManager session) =>
      TimelineBarMenus(
        session: session,
        panel: TimelineToolbarPanelContext(session),
      ).effects();

  PanelFlyoutItem rowOf(EditorSessionManager session, String id) =>
      listOf(session).whereType<PanelFlyoutItem>().singleWhere(
        (item) => item.keyValue == 'add-effect-plugin-$id',
      );

  List<LayerEffect> chainOf(EditorSessionManager session) => session
      .repository
      .requireProject()
      .tracks
      .single
      .cuts
      .single
      .layers
      .single
      .effects;

  test('after the app\'s kinds, under their own heading, one row each — '
      'named as an add of it is', () async {
    final session = sessionOn(await deviceWith(['a.b', 'c.d']));
    final list = listOf(session);
    final kinds = effectKindsAddedAlone.length;

    expect(list.length, 1 + kinds + 2 + 2);
    expect(list[1 + kinds], isA<PanelFlyoutDivider>());
    expect(
      (list[2 + kinds] as PanelFlyoutHeader).label,
      AppText.strings.fxPluginsOfDevice,
    );
    expect(
      [
        for (final entry in list.skip(3 + kinds))
          (entry as PanelFlyoutItem).label,
      ],
      [
        addEffectLabel('Plugin a.b', AppText.language),
        addEffectLabel('Plugin c.d', AppText.language),
      ],
    );
    expect(rowOf(session, 'a.b').enabled, isTrue);
    expect(
      addEffectLabel('Plugin a.b', AppLanguage.ko),
      AppStrings.of(
        AppLanguage.ko,
      ).tlAddEffectTemplate.replaceAll('{name}', 'Plugin a.b'),
    );
  });

  test('a device with none shows none — no heading, no rule', () async {
    final session = sessionOn(await deviceWith([]));
    expect(listOf(session).length, 1 + effectKindsAddedAlone.length);
    expect(listOf(session).whereType<PanelFlyoutDivider>(), isEmpty);
  });

  test('its row adds an effect of it, at its own values', () async {
    final session = sessionOn(await deviceWith(['a.b']));

    rowOf(session, 'a.b').onSelected!();

    final added = chainOf(session).single;
    expect(added.kind, EffectKind.plugin);
    expect(added.plugin, session.fxPlugins.plugins.single.description);
    expect(added.parameterOf('amount').value, 5);
  });

  test('the V row takes one as it takes an app kind', () async {
    final session = sessionOn(await deviceWith(['a.b']));
    final plugin = session.fxPlugins.plugins.single.description;

    session.effectsAndFx.addEffect(
      const TrackChain(TrackId('t1')),
      EffectKind.plugin,
      plugin: plugin,
    );

    final added = session.repository.requireProject().tracks.single.effects;
    expect(added.single.plugin, plugin);
    expect(chainOf(session), isEmpty, reason: 'not the active row\'s');
  });

  test('on a row that takes no effect its rows are dimmed, as the app '
      'kinds\' are', () async {
    final session = sessionOn(
      await deviceWith(['a.b']),
      also: [
        Layer(
          id: const LayerId('camera'),
          name: 'Camera',
          kind: LayerKind.camera,
          frames: const [],
        ),
      ],
    )..selectLayer(const LayerId('camera'));

    expect(
      listOf(session)
          .whereType<PanelFlyoutItem>()
          .singleWhere((row) => row.keyValue == 'add-effect-blur')
          .enabled,
      isFalse,
      reason: '⛔전제',
    );
    expect(rowOf(session, 'a.b').enabled, isFalse);
  });

  test('its row\'s delete takes it off the device, and an effect of it '
      'keeps its lanes', () async {
    final device = await deviceWith(['a.b', 'c.d']);
    final session = sessionOn(device);
    rowOf(session, 'a.b').onSelected!();
    final delete = rowOf(session, 'a.b').actions.single;
    expect(delete.does, PanelFlyoutActionDoes.deletes);
    expect(delete.tooltip, AppText.strings.fxPluginDelete);

    delete.onPressed();
    await pumpEventQueue();

    expect([for (final p in device.plugins) p.description.id], ['c.d']);
    expect(
      listOf(session).whereType<PanelFlyoutItem>().map((i) => i.keyValue),
      isNot(contains('add-effect-plugin-a.b')),
    );
    expect(chainOf(session).single.plugin!.id, 'a.b');
    expect(chainOf(session).single.lanes, ['amount']);
  });
}
