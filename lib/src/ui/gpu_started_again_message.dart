import 'package:gpu_engine/gpu_engine.dart' show GpuDeviceWent;

import 'text/app_strings.dart';

/// What the common window says once the app stands on another engine, the
/// device of its last gone by [by]: that the graphics device started
/// again, and why — the cause where something named one, else the causes
/// that are likely.
///
/// 🗣️유저 2026-11-11 (a-lost-gpu-device-keeps-the-unsaved-tiles-Q1):
/// 「그래픽 장치가 다시 시작되었다고 알린다」 · 「그래픽장치가 왜
/// 다시시작되었는지는 알수있게. 사용자는 앱 원인인지 다른건지 모르니까
/// 어느정도는 투명하게. 물론 확실하게 모를 가능성 높으니 그 경우
/// 가능성높은 원인을 알려주도록」.
String gpuStartedAgainMessage(AppStrings strings, GpuDeviceWent by) {
  final why = switch (by) {
    GpuDeviceWent.unsaid => strings.gpuWentUnsaid,
    GpuDeviceWent.memory => strings.gpuWentByMemory,
    GpuDeviceWent.thisApp => strings.gpuWentByThisApp,
    GpuDeviceWent.removal => strings.gpuWentByRemoval,
    GpuDeviceWent.reset => strings.gpuWentByReset,
    GpuDeviceWent.driver => strings.gpuWentByDriver,
  };
  return '${strings.gpuStartedAgainNotice}\n\n$why';
}
