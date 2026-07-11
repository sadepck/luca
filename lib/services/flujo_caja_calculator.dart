import '../models/expense.dart';
import '../models/ingreso_esperado.dart';
import '../models/orden_compra_generada.dart';

/// Gasto que se repite mes a mes, inferido del historial de boletas
/// escaneadas (mismo título en al menos dos meses distintos).
class GastoRecurrente {
  final String titulo;
  final String categoria;
  final double montoPromedio;
  final int diaDelMes;

  GastoRecurrente({
    required this.titulo,
    required this.categoria,
    required this.montoPromedio,
    required this.diaDelMes,
  });
}

class PuntoProyeccion {
  final DateTime fecha;
  final double saldo;

  PuntoProyeccion(this.fecha, this.saldo);
}

/// Un mes del flujo de caja, con la misma estructura de un reporte
/// contable clásico: saldo inicial + ingresos − egresos = saldo final.
class ResumenMensual {
  /// Primer día del mes que resume (año/mes son lo relevante).
  final DateTime mes;
  final double saldoInicial;
  final double ingresosEsperados;
  final double cobroOrdenes;
  final double gastosRecurrentes;
  final double saldoFinal;

  ResumenMensual({
    required this.mes,
    required this.saldoInicial,
    required this.ingresosEsperados,
    required this.cobroOrdenes,
    required this.gastosRecurrentes,
    required this.saldoFinal,
  });

  double get totalIngresos => ingresosEsperados + cobroOrdenes;
  double get totalEgresos => gastosRecurrentes;
  double get flujoNeto => totalIngresos - totalEgresos;
}

/// Detecta gastos que se repiten en al menos dos meses distintos con el
/// mismo título (mismo comercio/producto), para poder proyectarlos hacia
/// adelante sin que el usuario tenga que configurar nada.
List<GastoRecurrente> detectarGastosRecurrentes(List<Expense> gastos) {
  final porTitulo = <String, List<Expense>>{};
  for (final gasto in gastos) {
    final clave = gasto.title.trim().toLowerCase();
    if (clave.isEmpty) continue;
    porTitulo.putIfAbsent(clave, () => []).add(gasto);
  }

  final recurrentes = <GastoRecurrente>[];
  porTitulo.forEach((clave, lista) {
    if (lista.length < 2) return;
    final meses = lista.map((g) => '${g.date.year}-${g.date.month}').toSet();
    if (meses.length < 2) return;

    final montoPromedio =
        lista.fold<double>(0, (s, g) => s + g.amount) / lista.length;
    final diaPromedio =
        (lista.fold<int>(0, (s, g) => s + g.date.day) / lista.length).round();

    recurrentes.add(GastoRecurrente(
      titulo: lista.first.title,
      categoria: lista.first.category,
      montoPromedio: montoPromedio,
      diaDelMes: diaPromedio.clamp(1, 28),
    ));
  });

  return recurrentes;
}

/// Proyecta el saldo día a día durante [dias] a partir de [saldoInicial],
/// sumando los ingresos esperados y restando los gastos recurrentes
/// detectados que caigan en cada fecha. [ordenesCompra] con
/// `fechaPagoEsperada` definida se suman como ingresos puntuales en esa
/// fecha exacta (a diferencia de [ingresos], que son mensuales y
/// recurrentes) — las que no tienen fecha definida quedan fuera de la
/// proyección día a día, pero se pueden seguir viendo como pendientes en
/// la pantalla de Flujo de Caja.
List<PuntoProyeccion> calcularProyeccion({
  required double saldoInicial,
  required List<GastoRecurrente> gastosRecurrentes,
  required List<IngresoEsperado> ingresos,
  List<OrdenCompraGenerada> ordenesCompra = const [],
  int dias = 30,
}) {
  final puntos = <PuntoProyeccion>[];
  double saldo = saldoInicial;
  final hoy = DateTime.now();
  final inicio = DateTime(hoy.year, hoy.month, hoy.day);

  for (int i = 0; i <= dias; i++) {
    final fecha = inicio.add(Duration(days: i));

    for (final ingreso in ingresos) {
      if (ingreso.diaDelMes == fecha.day) saldo += ingreso.monto;
    }
    for (final gasto in gastosRecurrentes) {
      if (gasto.diaDelMes == fecha.day) saldo -= gasto.montoPromedio;
    }
    for (final orden in ordenesCompra) {
      final pago = orden.fechaPagoEsperada;
      if (pago != null &&
          pago.year == fecha.year &&
          pago.month == fecha.month &&
          pago.day == fecha.day) {
        saldo += orden.montoIngreso;
      }
    }

    puntos.add(PuntoProyeccion(fecha, saldo));
  }

  return puntos;
}

/// Igual que [calcularProyeccion], pero agregado por MES en vez de por
/// día — la estructura clásica de un reporte de flujo de caja (saldo
/// inicial, ingresos, egresos, saldo final por período). Empieza en el
/// mes actual y proyecta [meses] hacia adelante a partir de
/// [saldoInicial]; los días del mes actual anteriores a hoy no se vuelven
/// a contar (ya están reflejados en el saldo inicial).
List<ResumenMensual> calcularResumenMensual({
  required double saldoInicial,
  required List<GastoRecurrente> gastosRecurrentes,
  required List<IngresoEsperado> ingresos,
  List<OrdenCompraGenerada> ordenesCompra = const [],
  int meses = 6,
}) {
  final resumen = <ResumenMensual>[];
  double saldo = saldoInicial;
  final hoy = DateTime.now();
  final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);

  for (int m = 0; m < meses; m++) {
    final mesFecha = DateTime(hoy.year, hoy.month + m, 1);
    final diasEnMes = DateTime(mesFecha.year, mesFecha.month + 1, 0).day;
    final saldoInicialMes = saldo;

    double ingresosEsperadosMes = 0;
    double gastosRecurrentesMes = 0;
    for (int d = 1; d <= diasEnMes; d++) {
      final fecha = DateTime(mesFecha.year, mesFecha.month, d);
      // En el mes actual, los días ya pasados no se proyectan de nuevo
      // (ese movimiento, si ocurrió, ya está reflejado en el saldo
      // inicial actual que el usuario mantiene al día).
      if (fecha.isBefore(hoySinHora)) continue;
      for (final ingreso in ingresos) {
        if (ingreso.diaDelMes == d) ingresosEsperadosMes += ingreso.monto;
      }
      for (final gasto in gastosRecurrentes) {
        if (gasto.diaDelMes == d) gastosRecurrentesMes += gasto.montoPromedio;
      }
    }

    double cobroOrdenesMes = 0;
    for (final orden in ordenesCompra) {
      final pago = orden.fechaPagoEsperada;
      if (pago != null && pago.year == mesFecha.year && pago.month == mesFecha.month) {
        cobroOrdenesMes += orden.montoIngreso;
      }
    }

    final saldoFinalMes = saldoInicialMes +
        ingresosEsperadosMes +
        cobroOrdenesMes -
        gastosRecurrentesMes;

    resumen.add(ResumenMensual(
      mes: mesFecha,
      saldoInicial: saldoInicialMes,
      ingresosEsperados: ingresosEsperadosMes,
      cobroOrdenes: cobroOrdenesMes,
      gastosRecurrentes: gastosRecurrentesMes,
      saldoFinal: saldoFinalMes,
    ));
    saldo = saldoFinalMes;
  }

  return resumen;
}

/// Suma de los gastos REALES (no proyectados) registrados en un mes
/// específico — a diferencia del resto de este archivo, que proyecta
/// hacia el futuro, esto mira el historial real de boletas escaneadas
/// para comparar "lo proyectado" contra "lo que de verdad pasó".
double gastosRealesDelMes(List<Expense> gastos, DateTime mes) {
  return gastos
      .where((g) => g.date.year == mes.year && g.date.month == mes.month)
      .fold(0, (sum, g) => sum + g.amount);
}
