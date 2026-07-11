import 'package:workmanager/workmanager.dart';
import 'oportunidades_watcher.dart';

const String kTareaVerificarOportunidades = 'verificar_oportunidades_mp';

/// Punto de entrada que Android ejecuta en un isolate separado, sin la
/// app abierta. Debe ser una función top-level (no un método de clase).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == kTareaVerificarOportunidades) {
      await verificarNuevasOportunidades();
    }
    return true;
  });
}

/// Nota: en iOS el background fetch es controlado por el sistema operativo
/// y no está garantizado a correr con esta frecuencia; esta función está
/// pensada principalmente para Android.
Future<void> activarVerificacionPeriodica() async {
  await Workmanager().registerPeriodicTask(
    kTareaVerificarOportunidades,
    kTareaVerificarOportunidades,
    frequency: const Duration(hours: 6),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

Future<void> desactivarVerificacionPeriodica() async {
  await Workmanager().cancelByUniqueName(kTareaVerificarOportunidades);
}
