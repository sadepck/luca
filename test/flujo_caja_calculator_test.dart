import 'package:flutter_test/flutter_test.dart';
import 'package:luca/models/expense.dart';
import 'package:luca/models/ingreso_esperado.dart';
import 'package:luca/models/orden_compra_generada.dart';
import 'package:luca/services/flujo_caja_calculator.dart';

void main() {
  group('calcularProyeccion con órdenes de compra', () {
    test('suma el ingreso de una orden en su fecha esperada de pago', () {
      final fechaPago = DateTime.now().add(const Duration(days: 5));
      final orden = OrdenCompraGenerada(
        codigoOportunidad: 'OC-1',
        nombreOportunidad: 'Suministro de prueba',
        montoCompra: 100000,
        montoIngreso: 250000,
        fecha: DateTime.now(),
        fechaPagoEsperada: fechaPago,
      );

      final proyeccion = calcularProyeccion(
        saldoInicial: 1000,
        gastosRecurrentes: const [],
        ingresos: const [],
        ordenesCompra: [orden],
        dias: 10,
      );

      // Antes del día del pago, el saldo se mantiene en el inicial.
      expect(proyeccion[4].saldo, 1000);
      // El día del pago (y de ahí en adelante), el saldo sube en el
      // monto del ingreso de la orden.
      expect(proyeccion[5].saldo, 251000);
      expect(proyeccion[9].saldo, 251000);
    });

    test('una orden sin fecha esperada de pago no se suma a la proyección '
        'día a día (queda como pendiente sin fecha)', () {
      final orden = OrdenCompraGenerada(
        codigoOportunidad: 'OC-2',
        nombreOportunidad: 'Suministro sin fecha',
        montoCompra: 50000,
        montoIngreso: 120000,
        fecha: DateTime.now(),
      );

      final proyeccion = calcularProyeccion(
        saldoInicial: 1000,
        gastosRecurrentes: const [],
        ingresos: const [],
        ordenesCompra: [orden],
        dias: 10,
      );

      expect(proyeccion.every((p) => p.saldo == 1000), true);
    });
  });

  group('calcularResumenMensual', () {
    test(
        'agrega ingresos y gastos recurrentes por mes, encadenando el '
        'saldo final de un mes como saldo inicial del siguiente', () {
      final ingreso =
          IngresoEsperado(descripcion: 'Arriendo', monto: 500000, diaDelMes: 10);
      final gasto = GastoRecurrente(
          titulo: 'Insumos', categoria: 'Otros', montoPromedio: 200000, diaDelMes: 15);

      final resumen = calcularResumenMensual(
        saldoInicial: 1000000,
        gastosRecurrentes: [gasto],
        ingresos: [ingreso],
        meses: 3,
      );

      expect(resumen.length, 3);
      // El mes siguiente al actual cae completo dentro de la proyección
      // (a diferencia del mes actual, que puede tener días ya pasados).
      final mesSiguiente = resumen[1];
      expect(mesSiguiente.ingresosEsperados, 500000);
      expect(mesSiguiente.gastosRecurrentes, 200000);
      expect(mesSiguiente.totalIngresos, 500000);
      expect(mesSiguiente.totalEgresos, 200000);
      expect(mesSiguiente.flujoNeto, 300000);
      expect(mesSiguiente.saldoInicial, resumen[0].saldoFinal);
      expect(mesSiguiente.saldoFinal, mesSiguiente.saldoInicial + 300000);
    });

    test(
        'suma el cobro de una orden de compra en el mes de su fecha '
        'esperada de pago', () {
      final hoy = DateTime.now();
      final mesSiguiente = DateTime(hoy.year, hoy.month + 1, 15);
      final orden = OrdenCompraGenerada(
        codigoOportunidad: 'OC-3',
        nombreOportunidad: 'Prueba mensual',
        montoCompra: 100000,
        montoIngreso: 400000,
        fecha: hoy,
        fechaPagoEsperada: mesSiguiente,
      );

      final resumen = calcularResumenMensual(
        saldoInicial: 0,
        gastosRecurrentes: const [],
        ingresos: const [],
        ordenesCompra: [orden],
        meses: 3,
      );

      expect(resumen[0].cobroOrdenes, 0);
      expect(resumen[1].cobroOrdenes, 400000);
      expect(resumen[1].saldoFinal, 400000);
    });
  });

  group('gastosRealesDelMes', () {
    test('suma solo los gastos reales que caen en el mes indicado', () {
      final mes = DateTime(2026, 3);
      final gastos = [
        Expense(title: 'A', amount: 1000, category: 'Otros', date: DateTime(2026, 3, 5)),
        Expense(title: 'B', amount: 2000, category: 'Otros', date: DateTime(2026, 3, 20)),
        Expense(title: 'C', amount: 5000, category: 'Otros', date: DateTime(2026, 4, 1)),
      ];

      expect(gastosRealesDelMes(gastos, mes), 3000);
    });
  });
}
