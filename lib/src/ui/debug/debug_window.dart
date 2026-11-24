import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:gpu_engine/gpu_engine.dart'
    show GpuHeldChains, GpuScreen;

import '../../native/app_gpu_engine.dart' show appGpuEngineOpen;
import '../../native/engine_tile_ledger.dart';
import '../../native/qa_memory.dart';
import '../../services/runtime_path_report.dart';
import '../diagnostics/memory_census.dart';
import '../editor_session_manager.dart';
import '../layout/device_grid_audit.dart';
import '../raster_watch.dart';
import '../screen_canary.dart';
import '../widgets/app_icon_button.dart';
import 'engine_stages.dart';
import 'frame_stats.dart';
import 'frame_stats_readout.dart';
import 'measurement_mode.dart';
import 'repaint_cause.dart';
import 'screen_asked.dart';
import 'screen_check.dart';
import 'stroke_steps.dart';

/// Hosts the debug window above the whole app.
///
/// Installed from `MaterialApp.builder`, which is the only level that is
/// above every route AND below the `Navigator` — dialogs, popovers and
/// dropdown routes live in the Navigator's overlay, so a wrapper under
/// [HomePage] would be covered by exactly the surfaces a measurement run
/// wants to see past.
///
/// The app itself is passed through as a captured child, so this widget
/// rebuilding never rebuilds the app under it: `Element.updateChild`
/// short-circuits on an identical child widget instance.
class DebugWindowHost extends StatelessWidget {
  const DebugWindowHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      children: <Widget>[
        child,
        // Below the top strip on purpose: an instrument that covers the
        // SETTINGS button is one the user cannot switch off.
        Positioned.fill(
          top: 44,
          child: RepaintBoundary(
            child: ValueListenableBuilder<bool>(
              valueListenable: MeasurementMode.debugWindow,
              builder: (context, visible, _) => visible
                  ? const DebugWindow()
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

/// 🔬EVERYTHING THE APP MEASURES, ON ONE SCREEN (Settings ▸ Debug ▸ Debug
/// Window): a head that names the bottleneck, then the frame's time, the
/// app's memory, the pointer and the strokes, the engine's places, the
/// shaders and what the app runs on.
///
/// 🗣️유저 2026-11-24 (card one-debug-window-shows-everything): 「하나하나
/// 추가할 빠에 뭐든 화면에 보이게 싹 다 넣은 디버그 창을 만드는 게 확실하지
/// 않나 — 측정 빠졌네가 반복되는 게 훤히 보인다」 and 「그냥 프로들 하는
/// 것처럼 디버그창 만들면 안되나? 입력인스펙터랑 엔진 그리기 확인창 싹
/// 합치면서 알기쉽게」; Q1 the draft (a head line, graphs and bars, one
/// screen), Q2 one switch.
///
/// ★EVERY SUM SHOWS ITS PARTS AND THE REST — a frame's time and the app's
/// memory alike. What no part names stands as 「rest」, so the first photo
/// says where to cut next, instead of a build that adds the line that was
/// missing.
///
/// Pointer events pass through all but its head, so the canvas under it
/// is drawn on while it measures.
class DebugWindow extends StatefulWidget {
  const DebugWindow({super.key});

  /// Every open project, for the census — pushed by the editor that holds
  /// them (`HomePage`), as a viewer pushes its bytes: the window sits above
  /// every route, where no project is in reach. None before it does.
  static Iterable<EditorSessionManager> Function()? openSessions;

  @override
  State<DebugWindow> createState() => _DebugWindowState();
}

class _DebugWindowState extends State<DebugWindow> {
  /// What the window shows while paused — null while it follows.
  DebugReading? _held;

  DebugReading _read(FrameStatsSnapshot? stats) => (
    stats: stats,
    census: collectMemoryCensus(
      DebugWindow.openSessions?.call() ?? const <EditorSessionManager>[],
    ),
    stages: EngineStages.summary,
    clocked: appGpuEngineOpen.value?.clocked ?? false,
    paths: collectRuntimePathReport(),
    engine: [...engineLines(), RepaintCause.bakeLine()],
  );

  void _pause(DebugReading now) =>
      setState(() => _held = _held == null ? now : null);

  void _reset() {
    FrameStats.reset();
    EngineStages.forget();
    RepaintCause.forget();
    setState(() => _held = null);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FrameStatsSnapshot?>(
      valueListenable: FrameStats.latest,
      builder: (context, stats, _) {
        final reading = _held ?? _read(stats);
        return DefaultTextStyle(
          style: _DebugText.style,
          child: Column(
            key: const ValueKey<String>('debug-window'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Head(
                reading: reading,
                paused: _held != null,
                onPause: () => _pause(reading),
                onReset: _reset,
              ),
              Expanded(
                child: IgnorePointer(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _TimeColumn(reading: reading)),
                      Expanded(child: _MemoryColumn(reading: reading)),
                      SizedBox(
                        width: _DebugText.inputWidth,
                        child: _SystemColumn(reading: reading),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One reading of everything the window shows — held whole while paused.
typedef DebugReading = ({
  FrameStatsSnapshot? stats,
  MemoryCensus census,
  EngineStagesSummary? stages,
  bool clocked,
  List<RuntimePathEntry> paths,
  List<String> engine,
});

/// The window's type and colours: white on near-black, theme-independent,
/// because it has to stay legible over the canvas, over a panel, and in a
/// photo someone reads numbers off. Tabular figures so the columns do not
/// dance between republishes.
abstract final class _DebugText {
  static const TextStyle style = TextStyle(
    color: Color(0xFFFFFFFF),
    fontSize: 11,
    height: 1.3,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );
  static const TextStyle heading = TextStyle(
    color: Color(0xFF80D8FF),
    fontWeight: FontWeight.w600,
  );
  static const Color panel = Color(0xC0101112);
  static const Color rest = Color(0xFF616161);
  static const Color budget = Color(0xFFFF5252);
  static const List<Color> parts = <Color>[
    Color(0xFF4FC3F7),
    Color(0xFFFFB74D),
    Color(0xFF81C784),
    Color(0xFFE57373),
    Color(0xFFBA68C8),
    Color(0xFFFFF176),
    Color(0xFF4DB6AC),
    Color(0xFFA1887F),
  ];

  /// The input column's width: the inspector's panel, whose width is its
  /// own (`InputInspectorPanel`).
  static const double inputWidth = 560;

  static String ms(double millis) => millis.toStringAsFixed(1);
  static String mb(int bytes) => (bytes / (1 << 20)).toStringAsFixed(1);
}

/// One named part of a sum, in its unit.
typedef DebugPart = ({String name, double value});

/// The head: what the bottleneck is, against the frame's budget, and the
/// window's own controls.
class _Head extends StatelessWidget {
  const _Head({
    required this.reading,
    required this.paused,
    required this.onPause,
    required this.onReset,
  });

  final DebugReading reading;
  final bool paused;
  final VoidCallback onPause;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _DebugText.panel,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                bottleneckWords(reading.stats),
                style: _DebugText.heading,
                maxLines: 1,
                overflow: TextOverflow.clip,
              ),
            ),
            AppIconButton(
              keyValue: 'debug-window-pause',
              tooltip: paused ? 'Follow' : 'Pause',
              size: AppIconButtonSize.micro,
              isSelected: paused,
              onPressed: onPause,
              icon: Icon(paused ? Icons.play_arrow : Icons.pause),
            ),
            AppIconButton(
              keyValue: 'debug-window-reset',
              tooltip: 'Reset',
              size: AppIconButtonSize.micro,
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt),
            ),
            // ⛔Not a file: the app's container holds three tenants and
            // the memory tab explains each (memory_census.dart's record);
            // a fourth for a dump would be a tenant nobody accounts for.
            // The clipboard carries it to a message as well.
            AppIconButton(
              keyValue: 'debug-window-copy',
              tooltip: 'Copy',
              size: AppIconButtonSize.micro,
              onPressed: () => Clipboard.setData(
                ClipboardData(text: everyLine(reading).join('\n')),
              ),
              icon: const Icon(Icons.copy),
            ),
            // The repaint tint rides the window's head (Q2).
            ValueListenableBuilder<bool>(
              valueListenable: MeasurementMode.showRepaints,
              builder: (context, tinted, _) => AppIconButton(
                keyValue: 'debug-window-repaints',
                tooltip: 'Show Repaints',
                size: AppIconButtonSize.micro,
                isSelected: tinted,
                onPressed: () => MeasurementMode.showRepaints.value = !tinted,
                icon: const Icon(Icons.flare_outlined),
              ),
            ),
            AppIconButton(
              keyValue: 'debug-window-close',
              tooltip: 'Close',
              size: AppIconButtonSize.micro,
              onPressed: () => MeasurementMode.debugWindow.value = false,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

/// A frame's parts on average, in milliseconds: Flutter's four, which add
/// to its latency's mean ([FrameStatsSnapshot.frameMean]).
List<DebugPart> framePartsOf(FrameStatsSnapshot stats) => [
  (name: 'build wait', value: stats.frameMean.buildWait),
  (name: 'UI build', value: stats.frameMean.build),
  (name: 'raster wait', value: stats.frameMean.rasterWait),
  (name: 'raster', value: stats.frameMean.raster),
];

/// An engine screen frame's parts on average, in milliseconds — its draw,
/// its finish told part by part where the finishes said theirs, and its
/// show ([FrameStatsSnapshot.screenMean]).
List<DebugPart> screenPartsOf(FrameStatsSnapshot stats) {
  final screen = stats.screenMean;
  if (screen == null) {
    return const [];
  }
  return [
    (name: 'engine draw', value: screen.draw),
    (name: 'engine finish', value: screen.finish),
    (name: 'engine show', value: screen.show),
  ];
}

/// A finish's parts on average, in milliseconds, and what none of them
/// names ([FrameStatsSnapshot.finishMean]).
List<DebugPart> finishPartsOf(FrameStatsSnapshot stats) {
  final finish = stats.finishMean;
  if (finish == null) {
    return const [];
  }
  final named =
      finish.queued + finish.polled + finish.heard + finish.together;
  return [
    (name: 'engine queue', value: finish.queued),
    (name: 'GPU', value: finish.polled),
    (name: 'heard', value: finish.heard),
    (name: 'together', value: finish.together),
    (name: 'rest', value: math.max(0, finish.whole - named)),
  ];
}

/// The head's line: the part that takes most of a frame, against the
/// display's budget — every part of a frame's latency and of an engine
/// frame's way up, the finish by its own parts where they were said.
String bottleneckWords(FrameStatsSnapshot? stats) {
  if (stats == null) {
    return 'BOTTLENECK  — no frames yet';
  }
  final finish = finishPartsOf(stats);
  final parts = [
    ...framePartsOf(stats),
    for (final part in screenPartsOf(stats))
      if (part.name != 'engine finish' || finish.isEmpty) part,
    ...finish.map((part) => (name: 'finish ${part.name}', value: part.value)),
  ];
  final most = parts.reduce((a, b) => b.value > a.value ? b : a);
  final budget = 1000 / math.max(1, stats.displayHertz);
  final times = most.value / budget;
  return 'BOTTLENECK  ${most.name} ${_DebugText.ms(most.value)} ms — '
      '${times.toStringAsFixed(1)}× the ${_DebugText.ms(budget)} ms budget '
      'at ${stats.displayHertz.toStringAsFixed(0)} Hz';
}

/// The census's lines: the RAM's sum, each holder with its parts, and the
/// rest — then the GPU's memory, where it is apart.
List<String> memoryLines(MemoryCensus census) => [
  'MEMORY  app ${_DebugText.mb(census.footprintBytes)} MB  '
      'counted ${_DebugText.mb(census.trackedBytes)}  '
      'rest ${_DebugText.mb(census.untrackedBytes)}',
  for (final item in census.items) ...itemLines(item),
  'VRAM    ${switch (census.videoMemory) {
    null => '—',
    (:final used, :final budget, total: _) =>
      'used ${_DebugText.mb(used)} MB'
          '${budget == null ? '' : ' / ${_DebugText.mb(budget)}'}  '
          'counted ${_DebugText.mb(census.videoTrackedBytes)}  '
          'rest ${_DebugText.mb(census.videoUntrackedBytes ?? 0)}',
  }}',
  for (final item in census.videoItems) ...itemLines(item),
  // ⏳The GPU allocator's blocks: the engine has no export of them yet
  // (브러시/렌더링 2026-11-24 — one is to come, read on the engine's
  // thread); the row stands meanwhile, saying none.
  'GPU blocks  —',
];

/// A holder's lines: its sum, then its parts [partsALine] to a line under
/// it — as many lines as it has parts for, whatever they hold, so its rows
/// stand where they stood (⛔없다가 생기는 UI 금지) and none runs past its
/// column on the Galaxy Tab's screen (관제 2026-11-24: 「잘림 없음」).
List<String> itemLines(MemoryCensusItem item) => [
  '  ${item.id} ${_DebugText.mb(item.bytes)}',
  for (var at = 0; at < item.parts.length; at += partsALine)
    '      ${[
      for (final part in item.parts.skip(at).take(partsALine))
        '${part.name} ${_DebugText.mb(part.bytes)}',
    ].join(' · ')}',
];

/// How many of a holder's parts a line of [itemLines] says.
const int partsALine = 3;

/// What the engine says of itself and keeps count of that no other line
/// shows: its adapter, whether its device went and why, the waits past
/// their limit, the submits not finished; what it says the frames'
/// pictures hold by its own count — their pages made, every screen, every
/// chain held — beside the census's holders of them; the slots of the
/// app's ledger, the strokes' dabs and the screens' shows in all, the OS's
/// ceiling for the app; and the watches: the raster thread, the screen's
/// pixel, the surfaces on the device grid. 🗣️관제 2026-11-24 (the card's
/// list of what nothing showed): 「기본이 싣는 것」 — every one is loaded,
/// and only the test seams of one thread's contract stay out.
List<String> engineLines() {
  final engine = appGpuEngineOpen.value;
  final unfinished = engine?.unfinishedSubmits ?? '';
  final limit = QaMemory.appMemoryLimitBytes;
  final grid = DeviceGridAudit.sweep();
  String mb(int? bytes) => bytes == null ? '—' : _DebugText.mb(bytes);
  return [
    if (engine == null) 'ENGINE  —',
    if (engine != null) ...[
      'ENGINE  ${engine.adapterName}',
      ' state  gone ${engine.isGone ? engine.wentBy.name : 'no'}  '
          'late waits ${engine.waitsPastTheirLimit}  '
          'unfinished '
          '${unfinished.isEmpty ? 0 : unfinished.split('\n').length}',
    ],
    ' says   picture pages ${mb(engine?.pictureBytes)}  '
        'screens ${mb(GpuScreen.liveBytes)}  '
        'chains held ${mb(GpuHeldChains.liveBytes)} MB',
    ' ledger slots ${EngineTileLedger.opened?.slotCount ?? '—'}  '
        'dabs ${StrokeSteps.dabsCounted}  '
        'screens shown ${ScreenAsked.shows}  '
        'app limit ${limit == null ? '—' : '${mb(limit)} MB'}',
    ' watch  raster ${RasterWatch.stood.value == null ? 'drawing' : 'stood'}  '
        'pixel ${ScreenCanary.notSaid.value == null ? 'said' : 'not said'}  '
        'grid on ${grid.onGrid} off ${grid.violations.length} '
        'unmeasured ${grid.unmeasurable}',
  ];
}

/// Every line the window shows, as text — what its copy button takes.
List<String> everyLine(DebugReading reading) {
  final stats = reading.stats;
  return [
    bottleneckWords(stats),
    if (stats == null) ...FrameStatsLines.none,
    if (stats != null) ...[
      ...FrameStatsLines.frame(stats),
      ...FrameStatsLines.screen(stats),
      ...FrameStatsLines.gpu(stats),
    ],
    ...EngineStages.lines(reading.stages, clocked: reading.clocked),
    ...reading.engine,
    ...memoryLines(reading.census),
    if (stats != null) ...[
      ...FrameStatsLines.stroke(stats),
      ...FrameStatsLines.caches(stats),
    ],
    ...systemLines(reading.paths),
  ];
}

/// What the app runs on: the report Preferences ▸ System shows
/// ([collectRuntimePathReport] — the same code), a line each.
List<String> systemLines(List<RuntimePathEntry> paths) => [
  'SYSTEM',
  for (final entry in paths)
    '  ${entry.subsystem}: ${entry.active}'
        '${entry.isPrimary ? '' : '  (fallback)'}',
];

/// A column's backdrop and margins.
class _Column extends StatelessWidget {
  const _Column({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: ColoredBox(
        color: _DebugText.panel,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// Lines of text, each its own row.
class _Lines extends StatelessWidget {
  const _Lines(this.lines);

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Text(line, maxLines: 1, overflow: TextOverflow.clip, softWrap: false),
      ],
    );
  }
}

/// The frame's time: the graph of the window's frames, a frame's parts as
/// bars that add up, the frame clock's and the screens' lines, the GPU and
/// the shaders, and the engine's places.
class _TimeColumn extends StatelessWidget {
  const _TimeColumn({required this.reading});

  final DebugReading reading;

  @override
  Widget build(BuildContext context) {
    final stats = reading.stats;
    final budget = stats == null ? 0.0 : 1000 / math.max(1, stats.displayHertz);
    return _Column(
      children: [
        SizedBox(
          height: 64,
          width: double.infinity,
          child: CustomPaint(
            painter: _FrameGraph(
              frames: stats?.frameTotals ?? const [],
              screens: stats?.screenTotals ?? const [],
              budget: budget,
            ),
          ),
        ),
        _SumBar(title: 'FRAME', parts: stats == null ? const [] : framePartsOf(stats), budget: budget),
        _SumBar(title: 'SCREEN', parts: stats == null ? const [] : screenPartsOf(stats), budget: budget),
        _SumBar(title: 'FINISH', parts: stats == null ? const [] : finishPartsOf(stats), budget: budget),
        _Lines([
          if (stats == null) ...FrameStatsLines.none,
          if (stats != null) ...[
            ...FrameStatsLines.frame(stats),
            ...FrameStatsLines.screen(stats),
            ...FrameStatsLines.gpu(stats),
          ],
          ...EngineStages.lines(reading.stages, clocked: reading.clocked),
          ...reading.engine,
        ]),
      ],
    );
  }
}

/// The app's memory: the census, every holder with its parts and the rest,
/// as a bar and as lines — then the pointer, the strokes and the caches.
class _MemoryColumn extends StatelessWidget {
  const _MemoryColumn({required this.reading});

  final DebugReading reading;

  @override
  Widget build(BuildContext context) {
    final census = reading.census;
    final stats = reading.stats;
    return _Column(
      children: [
        _BytesBar(
          items: census.items,
          whole: census.footprintBytes,
        ),
        _Lines([
          ...memoryLines(census),
          if (stats != null) ...[
            ...FrameStatsLines.stroke(stats),
            ...FrameStatsLines.caches(stats),
          ],
        ]),
      ],
    );
  }
}

/// What the platform delivered, and what the app runs on — with the probe
/// of whether Flutter shows the bytes the engine wrote.
class _SystemColumn extends StatelessWidget {
  const _SystemColumn({required this.reading});

  final DebugReading reading;

  @override
  Widget build(BuildContext context) {
    return _Column(
      children: [
        _Lines(systemLines(reading.paths)),
        const ScreenCheck(),
      ],
    );
  }
}

/// A sum as a bar of its parts, against the frame's budget, and its parts
/// in words under it — the row always there, its parts none till said.
class _SumBar extends StatelessWidget {
  const _SumBar({
    required this.title,
    required this.parts,
    required this.budget,
  });

  final String title;
  final List<DebugPart> parts;
  final double budget;

  @override
  Widget build(BuildContext context) {
    final whole = parts.fold(0.0, (sum, part) => sum + part.value);
    final words = parts.isEmpty
        ? '—'
        : '${_DebugText.ms(whole)} ms = ${[
            for (final part in parts) '${part.name} ${_DebugText.ms(part.value)}',
          ].join(' + ')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$title  $words', maxLines: 1, overflow: TextOverflow.clip, softWrap: false),
        SizedBox(
          height: 8,
          width: double.infinity,
          child: CustomPaint(
            painter: _BarPainter(
              values: [for (final part in parts) part.value],
              scale: math.max(whole, budget) * 1.1,
              mark: budget,
            ),
          ),
        ),
        const SizedBox(height: 3),
      ],
    );
  }
}

/// The RAM's sum as a bar of its holders, the rest grey at its end.
class _BytesBar extends StatelessWidget {
  const _BytesBar({required this.items, required this.whole});

  final List<MemoryCensusItem> items;
  final int whole;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: SizedBox(
        height: 8,
        width: double.infinity,
        child: CustomPaint(
          painter: _BarPainter(
            values: [for (final item in items) item.bytes.toDouble()],
            scale: whole.toDouble(),
            restUpTo: whole.toDouble(),
          ),
        ),
      ),
    );
  }
}

/// Parts laid end to end, coloured in turn: past them, up to [restUpTo],
/// the rest in grey; across them at [mark], the budget.
class _BarPainter extends CustomPainter {
  const _BarPainter({
    required this.values,
    required this.scale,
    this.mark,
    this.restUpTo,
  });

  final List<double> values;
  final double scale;
  final double? mark;
  final double? restUpTo;

  @override
  void paint(Canvas canvas, Size size) {
    if (scale <= 0) {
      return;
    }
    double x(double value) => size.width * value / scale;
    var at = 0.0;
    for (var i = 0; i < values.length; i++) {
      final paint = Paint()
        ..color = _DebugText.parts[i % _DebugText.parts.length];
      canvas.drawRect(
        Rect.fromLTWH(x(at), 0, x(values[i]), size.height),
        paint,
      );
      at += values[i];
    }
    final rest = restUpTo;
    if (rest != null && rest > at) {
      canvas.drawRect(
        Rect.fromLTRB(x(at), 0, x(rest), size.height),
        Paint()..color = _DebugText.rest,
      );
    }
    final budget = mark;
    if (budget != null && budget > 0) {
      canvas.drawRect(
        Rect.fromLTWH(x(budget) - 1, 0, 2, size.height),
        Paint()..color = _DebugText.budget,
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.scale != scale ||
      old.mark != mark ||
      old.restUpTo != restUpTo ||
      !_same(old.values, values);
}

/// The window's frames, oldest first: each frame's latency a bar, each
/// engine screen frame's way up a line over them, the budget across.
class _FrameGraph extends CustomPainter {
  const _FrameGraph({
    required this.frames,
    required this.screens,
    required this.budget,
  });

  final List<double> frames;
  final List<double> screens;
  final double budget;

  @override
  void paint(Canvas canvas, Size size) {
    final top = [budget * 2, ...frames, ...screens].reduce(math.max);
    if (top <= 0) {
      return;
    }
    double y(double millis) => size.height * (1 - millis / top);
    if (frames.isNotEmpty) {
      final width = size.width / frames.length;
      final bar = Paint()..color = _DebugText.parts[0];
      for (var i = 0; i < frames.length; i++) {
        canvas.drawRect(
          Rect.fromLTRB(i * width, y(frames[i]), (i + 1) * width, size.height),
          bar,
        );
      }
    }
    if (screens.length > 1) {
      final step = size.width / (screens.length - 1);
      final line = Path()..moveTo(0, y(screens.first));
      for (var i = 1; i < screens.length; i++) {
        line.lineTo(i * step, y(screens[i]));
      }
      canvas.drawPath(
        line,
        Paint()
          ..color = _DebugText.parts[1]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(0, y(budget) - 0.5, size.width, 1),
      Paint()..color = _DebugText.budget,
    );
  }

  @override
  bool shouldRepaint(_FrameGraph old) =>
      old.budget != budget ||
      !_same(old.frames, frames) ||
      !_same(old.screens, screens);
}

bool _same(List<double> a, List<double> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
