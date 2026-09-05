import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/ui/export/export_job.dart';
import 'package:anicel/src/ui/export/export_queue_column.dart';

/// The export window's render queue drawer — nothing named it
/// (2026-09-05).
///
/// 🚨It renders whatever the MODEL holds and listens to it, so a job
/// arriving while the drawer is open shows up without the window
/// rebuilding around it.
void main() {
  ({ExportQueueModel queue, List<ExportJob> removed, List<ExportJob> restored})
  open() {
    final queue = ExportQueueModel();
    addTearDown(queue.dispose);
    return (queue: queue, removed: <ExportJob>[], restored: <ExportJob>[]);
  }

  Future<void> pump(
    WidgetTester tester,
    ({
      ExportQueueModel queue,
      List<ExportJob> removed,
      List<ExportJob> restored,
    })
    session, {
    bool enabled = true,
    VoidCallback? onRenderAll,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 240,
          height: 400,
          child: ExportQueueColumn(
            queue: session.queue,
            enabled: enabled,
            onRemove: session.removed.add,
            onRestore: session.restored.add,
            onRenderAll: onRenderAll,
          ),
        ),
      ),
    ),
  );

  ExportJob enqueue(ExportQueueModel queue, {String? name}) => queue.enqueue(
    spec: const ImageExportSpec(),
    outputDirectory: '/out',
    fileName: name,
    now: () => DateTime.utc(2026, 9, 5),
  );

  testWidgets('an empty queue says so rather than showing a bare column', (
    tester,
  ) async {
    final session = open();
    await pump(tester, session);

    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('🚨a job ADDED while the drawer is open shows up — the column '
      'listens to the model rather than being handed a snapshot', (
    tester,
  ) async {
    final session = open();
    await pump(tester, session);

    enqueue(session.queue, name: 'take-01');
    await tester.pumpAndSettle();

    expect(find.textContaining('Job 1'), findsOneWidget);
  });

  testWidgets('every queued job gets a row', (tester) async {
    final session = open();
    enqueue(session.queue, name: 'one');
    enqueue(session.queue, name: 'two');
    await pump(tester, session);

    expect(find.textContaining('Job 1'), findsOneWidget);
    expect(find.textContaining('Job 2'), findsOneWidget);
  });

  testWidgets('🚨a job REMOVED from the model leaves the drawer', (
    tester,
  ) async {
    final session = open();
    final job = enqueue(session.queue, name: 'one');
    await pump(tester, session);
    expect(find.textContaining('Job 1'), findsOneWidget);

    session.queue.remove(job.id);
    await tester.pumpAndSettle();

    expect(find.textContaining('Job 1'), findsNothing);
  });

  test('the model keeps its own numbering, and hands out the next queued '
      'job in order', () {
    final queue = ExportQueueModel();
    addTearDown(queue.dispose);

    final first = queue.enqueue(
      spec: const ImageExportSpec(),
      outputDirectory: '/out',
      now: () => DateTime.utc(2026),
    );
    final second = queue.enqueue(
      spec: const ImageExportSpec(),
      outputDirectory: '/out',
      now: () => DateTime.utc(2026),
    );

    expect(second.id, greaterThan(first.id));
    expect(queue.nextQueued?.id, first.id, reason: 'first in, first out');
    expect(queue.isEmpty, isFalse);
    expect(queue.hasRunning, isFalse);
  });
}
