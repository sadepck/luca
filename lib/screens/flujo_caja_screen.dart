import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ingreso_esperado.dart';
import '../models/orden_compra_generada.dart';
import '../services/database_service.dart';
import '../services/flujo_caja_calculator.dart';
import 'ingresos_ordenes_screen.dart';

const String kSaldoActualPrefKey = 'flujo_saldo_actual';
const int kDiasProyeccion = 30;

class FlujoCajaScreen extends StatefulWidget {
  const FlujoCajaScreen({super.key});

  @override
  State<FlujoCajaScreen> createState() => _FlujoCajaScreenState();
}

class _FlujoCajaScreenState extends State<FlujoCajaScreen> {
  static const _mesesResumen = 6;
  static const _nombresMeses = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  bool _loading = true;
  double _saldoActual = 0;
  List<IngresoEsperado> _ingresos = [];
  List<GastoRecurrente> _recurrentes = [];
  List<OrdenCompraGenerada> _ordenesCompra = [];
  List<PuntoProyeccion> _proyeccion = [];
  List<ResumenMensual> _resumenMensual = [];
  double _gastosRealesMesActual = 0;

  double get _totalPendientePorOrdenes =>
      _ordenesCompra.fold(0, (sum, o) => sum + o.montoIngreso);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    final saldo = prefs.getDouble(kSaldoActualPrefKey) ?? 0;
    final ingresos = await DatabaseService.instance.getIngresos();
    final gastos = await DatabaseService.instance.getAllExpenses();
    final ordenesCompra = await DatabaseService.instance.getOrdenesCompra();
    final recurrentes = detectarGastosRecurrentes(gastos);
    final proyeccion = calcularProyeccion(
      saldoInicial: saldo,
      gastosRecurrentes: recurrentes,
      ingresos: ingresos,
      ordenesCompra: ordenesCompra,
      dias: kDiasProyeccion,
    );
    final resumenMensual = calcularResumenMensual(
      saldoInicial: saldo,
      gastosRecurrentes: recurrentes,
      ingresos: ingresos,
      ordenesCompra: ordenesCompra,
      meses: _mesesResumen,
    );
    final gastosRealesMesActual = gastosRealesDelMes(gastos, DateTime.now());

    if (!mounted) return;
    setState(() {
      _saldoActual = saldo;
      _ingresos = ingresos;
      _recurrentes = recurrentes;
      _ordenesCompra = ordenesCompra;
      _proyeccion = proyeccion;
      _resumenMensual = resumenMensual;
      _gastosRealesMesActual = gastosRealesMesActual;
      _loading = false;
    });
  }

  Future<void> _editarSaldo() async {
    final controller =
        TextEditingController(text: _saldoActual.toStringAsFixed(0));
    final nuevoSaldo = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Saldo actual'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(prefixText: '\$ '),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text) ?? 0),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF)),
            child:
                const Text('Guardar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (nuevoSaldo != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(kSaldoActualPrefKey, nuevoSaldo);
      _cargar();
    }
  }

  Future<void> _agregarIngreso() async {
    final descController = TextEditingController();
    final montoController = TextEditingController();
    final diaController = TextEditingController();

    final guardar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo ingreso esperado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: descController,
              decoration:
                  const InputDecoration(labelText: 'Descripción (ej: Sueldo)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: montoController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Monto'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: diaController,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Día del mes (1-28)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF)),
            child:
                const Text('Guardar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (guardar != true) return;

    final monto = double.tryParse(montoController.text);
    final dia = int.tryParse(diaController.text);
    if (descController.text.trim().isEmpty || monto == null || dia == null) {
      return;
    }

    await DatabaseService.instance.crearIngreso(IngresoEsperado(
      descripcion: descController.text.trim(),
      monto: monto,
      diaDelMes: dia.clamp(1, 28),
    ));
    _cargar();
  }

  Future<void> _eliminarIngreso(IngresoEsperado ingreso) async {
    await DatabaseService.instance.eliminarIngreso(ingreso.id!);
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final saldoMinimo = _proyeccion.isEmpty
        ? _saldoActual
        : _proyeccion.map((p) => p.saldo).reduce((a, b) => a < b ? a : b);
    final enRiesgo = saldoMinimo < 0;
    PuntoProyeccion? primerNegativo;
    for (final p in _proyeccion) {
      if (p.saldo < 0) {
        primerNegativo = p;
        break;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Flujo de caja'),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSaldoCard(),
                    const SizedBox(height: 16),
                    if (enRiesgo && primerNegativo != null)
                      _buildAvisoNegativo(primerNegativo),
                    const Text('Proyección próximos 30 días',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 220,
                      child: _buildChart(enRiesgo),
                    ),
                    const SizedBox(height: 24),
                    _buildResumenMensual(),
                    const SizedBox(height: 24),
                    _buildSeccionIngresos(),
                    const SizedBox(height: 24),
                    _buildSeccionOrdenesCompra(),
                    const SizedBox(height: 24),
                    _buildSeccionRecurrentes(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSaldoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C63FF), Color(0xFF9C27B0)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Saldo actual',
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                Text('\$${_saldoActual.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          IconButton(
            onPressed: _editarSaldo,
            icon: const Icon(Icons.edit, color: Colors.white),
            tooltip: 'Editar saldo',
          ),
        ],
      ),
    );
  }

  Widget _buildAvisoNegativo(PuntoProyeccion punto) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tu saldo proyectado podría quedar en negativo el '
              '${punto.fecha.day}/${punto.fecha.month} '
              '(\$${punto.saldo.toStringAsFixed(0)}).',
              style: const TextStyle(fontSize: 13, color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(bool enRiesgo) {
    if (_proyeccion.isEmpty) return const SizedBox();

    final spots = _proyeccion
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.saldo))
        .toList();
    final color = enRiesgo ? Colors.red : const Color(0xFF6C63FF);

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              getTitlesWidget: (value, meta) => Text(
                '\$${(value / 1000).toStringAsFixed(0)}k',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 5,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= _proyeccion.length) {
                  return const SizedBox();
                }
                final fecha = _proyeccion[index].fecha;
                return Text('${fecha.day}/${fecha.month}',
                    style: const TextStyle(fontSize: 10));
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                    '\$${s.y.toStringAsFixed(0)}',
                    const TextStyle(color: Colors.white)))
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumenMensual() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Resumen mensual',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'Saldo inicial + ingresos − egresos = saldo final, mes a mes '
          '(basado en tus ingresos esperados, gastos recurrentes detectados '
          'y órdenes de compra con fecha de pago).',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        if (_gastosRealesMesActual > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Gastos reales de este mes hasta hoy: '
              '\$${_gastosRealesMesActual.toStringAsFixed(0)} (según boletas escaneadas).',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6C63FF)),
            ),
          ),
        SizedBox(
          height: 236,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _resumenMensual.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) =>
                _buildTarjetaMes(_resumenMensual[index], esMesActual: index == 0),
          ),
        ),
      ],
    );
  }

  Widget _buildTarjetaMes(ResumenMensual r, {required bool esMesActual}) {
    final negativo = r.saldoFinal < 0;
    return Container(
      width: 190,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: negativo ? Colors.red.withValues(alpha: 0.4) : Colors.grey.shade300,
          width: negativo ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_nombresMeses[r.mes.month - 1]} ${r.mes.year}'
            '${esMesActual ? ' (actual)' : ''}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const Divider(height: 16),
          _filaResumen('Saldo inicial', r.saldoInicial),
          const SizedBox(height: 6),
          _filaResumen('(+) Ingresos esp.', r.ingresosEsperados, color: Colors.green),
          _filaResumen('(+) Cobro órdenes', r.cobroOrdenes, color: Colors.green),
          _filaResumen('(-) Gastos recur.', r.gastosRecurrentes, color: Colors.red),
          const Divider(height: 16),
          _filaResumen('Flujo neto', r.flujoNeto,
              color: r.flujoNeto >= 0 ? Colors.green : Colors.red, negrita: true),
          const SizedBox(height: 4),
          _filaResumen('Saldo final', r.saldoFinal,
              color: negativo ? Colors.red : null, negrita: true),
        ],
      ),
    );
  }

  Widget _filaResumen(String label, double valor, {Color? color, bool negrita = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(
            '\$${valor.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: negrita ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionIngresos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Ingresos esperados',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            TextButton.icon(
              onPressed: _agregarIngreso,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Agregar'),
            ),
          ],
        ),
        if (_ingresos.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Agrega tu ingreso esperado (ej. tu sueldo) para ver tu '
                  'flujo de caja completo. Como luca no se conecta a tu '
                  'banco, esto se carga a mano.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _agregarIngreso,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Agregar ingreso esperado'),
                ),
              ],
            ),
          )
        else
          ..._ingresos.map((ingreso) => Card(
                margin: const EdgeInsets.only(top: 8),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0x1A6C63FF),
                    child: Icon(Icons.arrow_downward, color: Colors.green),
                  ),
                  title: Text(ingreso.descripcion),
                  subtitle: Text('Día ${ingreso.diaDelMes} de cada mes'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('\$${ingreso.monto.toStringAsFixed(0)}',
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _eliminarIngreso(ingreso),
                      ),
                    ],
                  ),
                ),
              )),
      ],
    );
  }

  Widget _buildSeccionOrdenesCompra() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Ingresos por órdenes de compra',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            TextButton(
              onPressed: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const IngresosOrdenesScreen()));
                _cargar();
              },
              child: const Text('Ver todas'),
            ),
          ],
        ),
        if (_ordenesCompra.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Aún no has generado ninguna orden de compra con ingreso registrado.',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${_ordenesCompra.length} orden(es) pendiente(s)',
                    style: const TextStyle(fontSize: 13)),
                Text('\$${_totalPendientePorOrdenes.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _ordenesCompra.any((o) => o.fechaPagoEsperada != null)
                ? 'Las que tienen fecha esperada de pago ya están sumadas en '
                    'la proyección de arriba.'
                : 'Ninguna tiene fecha esperada de pago aún — no se están '
                    'sumando a la proyección de arriba. Edítalas desde "Ver todas".',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ],
    );
  }

  Widget _buildSeccionRecurrentes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Gastos recurrentes detectados',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'Basado en boletas que escaneaste con el mismo título en más '
          'de un mes.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        if (_recurrentes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Aún no detectamos gastos que se repitan mes a mes.',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          ..._recurrentes.map((gasto) => Card(
                margin: const EdgeInsets.only(top: 8),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0x1AFF6C63),
                    child: Icon(Icons.repeat, color: Colors.deepOrange),
                  ),
                  title: Text(gasto.titulo),
                  subtitle: Text(
                      '${gasto.categoria} · día ${gasto.diaDelMes} aprox.'),
                  trailing: Text('\$${gasto.montoPromedio.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              )),
      ],
    );
  }
}
