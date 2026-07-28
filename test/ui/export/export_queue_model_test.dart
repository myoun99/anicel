import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/ui/export/export_job.dart';

void main() {
  group('ExportQueueModel', () {
    test('enqueue assigns increasing ids and notifies', () {
      final queue = ExportQueueModel();
      var notifications = 0;
      queue.addListener(() => notifications += 1);

      final first = queue.enqueue(
        spec: const SequenceExportSpec(),
        outputDirectory: 'D:/out',
        fileName: 'a.mp4',
        now: () => DateTime.utc(2026),
      );
      final second = queue.enqueue(
        spec: const CelsExportSpec(),
        outputDirectory: 'D:/out',
        now: () => DateTime.utc(2026),
      );

      expect(first.id, 1);
      expect(second.id, 2);
      expect(second.fileName, isNull);
      expect(queue.jobs.map((job) => job.tab), [
        ExportTab.sequence,
        ExportTab.cels,
      ]);
      expect(notifications, 2);
    });

    test('nextQueued walks enqueue order and skips finished jobs', () {
      final queue = ExportQueueModel();
      final first = queue.enqueue(
        spec: const SequenceExportSpec(),
        outputDirectory: 'D:/out',
      );
      final second = queue.enqueue(
        spec: const ImageExportSpec(),
        outputDirectory: 'D:/out',
      );
      expect(queue.nextQueued?.id, first.id);

      queue.update(
        first.id,
        (job) => job.copyWith(status: ExportJobStatus.succeeded),
      );
      expect(queue.nextQueued?.id, second.id);
      expect(queue.hasRunning, isFalse);
    });

    test('update reports progress and a missing id is a no-op', () {
      final queue = ExportQueueModel();
      final job = queue.enqueue(
        spec: const SequenceExportSpec(),
        outputDirectory: 'D:/out',
      );
      queue.update(
        job.id,
        (current) => current.copyWith(
          status: ExportJobStatus.running,
          completed: 19,
          total: 72,
        ),
      );
      expect(queue.jobById(job.id)?.completed, 19);
      expect(queue.hasRunning, isTrue);
      queue.update(999, (current) => current.copyWith(completed: 1));
      expect(queue.jobById(job.id)?.completed, 19);
    });

    test('remove refuses a running job and clearFinished sweeps', () {
      final queue = ExportQueueModel();
      final running = queue.enqueue(
        spec: const SequenceExportSpec(),
        outputDirectory: 'D:/out',
      );
      queue.update(
        running.id,
        (job) => job.copyWith(status: ExportJobStatus.running),
      );
      final done = queue.enqueue(
        spec: const ImageExportSpec(),
        outputDirectory: 'D:/out',
      );
      queue.update(
        done.id,
        (job) => job.copyWith(status: ExportJobStatus.failed, message: 'x'),
      );

      expect(queue.remove(running.id), isFalse);
      expect(queue.jobs, hasLength(2));
      queue.clearFinished();
      expect(queue.jobs.map((job) => job.id), [running.id]);
    });
  });
}
