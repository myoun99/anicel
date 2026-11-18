// The device the engine opened, said where a run's log can read it.
//
// 🧭Card windows-arm64-runner-engine-tests-stall-on-a-software-gpu (관제
// 2026-11-16, again for round 1093 on 2026-11-18): on the Windows ARM64
// release runner the engine's tests stand past the job's hour — GPU work
// past 30 s, one core test committing 8 GB — and the guess is a runner with
// no GPU, the engine on a software device. Three runs' logs named no
// device, so this says it: the adapter's name and what the OS says of its
// memory. It imports `src/native/`, so every release workflow that runs the
// engine's tests prints it (tool/native_parity_tests.sh), and the ARM64 one
// runs it first, in a step of its own, before the hour can run out.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';

void main() {
  test('the engine names the device it opened', () {
    final name = appGpuEngine.adapterName;
    final memory = appGpuEngine.videoMemory;
    String mb(int? bytes) => bytes == null ? '-' : '${bytes >> 20} MB';
    // ignore: avoid_print — printing is what this test is for.
    print(
      'engine device: $name · integrated ${memory.integrated} · '
      'used ${mb(memory.used)} · budget ${mb(memory.budget)} · '
      'in system ${mb(memory.inSystem)} · total ${mb(memory.total)}',
    );
    expect(name, isNotEmpty);
  });
}
