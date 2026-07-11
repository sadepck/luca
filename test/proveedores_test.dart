import 'package:flutter_test/flutter_test.dart';
import 'package:luca/models/expense.dart';
import 'package:luca/screens/proveedores_screen.dart';

void main() {
  group('agruparPorProveedor', () {
    test('agrupa gastos por RUT emisor y suma el total gastado', () {
      final gastos = [
        Expense(
            title: 'Compra 1',
            amount: 1000,
            category: 'Otros',
            date: DateTime(2026, 1, 5),
            rutEmisor: '76.051.775-5',
            nombreEmisor: 'MCO Ingeniería'),
        Expense(
            title: 'Compra 2',
            amount: 2000,
            category: 'Otros',
            date: DateTime(2026, 2, 10),
            rutEmisor: '76.051.775-5',
            nombreEmisor: 'MCO Ingeniería'),
        Expense(
            title: 'Compra 3',
            amount: 500,
            category: 'Otros',
            date: DateTime(2026, 1, 20),
            rutEmisor: '76.602.017-8',
            nombreEmisor: 'Comercial La Bodega'),
      ];

      final proveedores = agruparPorProveedor(gastos);

      expect(proveedores.length, 2);
      // Ordenados de mayor a menor total gastado.
      expect(proveedores.first.nombre, 'MCO Ingeniería');
      expect(proveedores.first.totalGastado, 3000);
      expect(proveedores.first.cantidadCompras, 2);
      expect(proveedores.first.ultimaCompra, DateTime(2026, 2, 10));

      expect(proveedores.last.nombre, 'Comercial La Bodega');
      expect(proveedores.last.totalGastado, 500);
    });

    test('ignora gastos sin empresa identificada (ni RUT ni nombre)', () {
      final gastos = [
        Expense(title: 'Sin datos', amount: 100, category: 'Otros', date: DateTime(2026, 1, 1)),
      ];

      expect(agruparPorProveedor(gastos), isEmpty);
    });

    test('agrupa por nombre cuando no hay RUT disponible', () {
      final gastos = [
        Expense(
            title: 'Compra 1',
            amount: 300,
            category: 'Otros',
            date: DateTime(2026, 1, 1),
            nombreEmisor: 'Ferretería El Tornillo'),
        Expense(
            title: 'Compra 2',
            amount: 400,
            category: 'Otros',
            date: DateTime(2026, 1, 15),
            nombreEmisor: 'Ferretería El Tornillo'),
      ];

      final proveedores = agruparPorProveedor(gastos);

      expect(proveedores.length, 1);
      expect(proveedores.first.totalGastado, 700);
      expect(proveedores.first.cantidadCompras, 2);
    });
  });
}
