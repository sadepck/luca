import 'package:flutter/material.dart';
import '../models/expense.dart';
import '../services/export_service.dart';
import '../services/expenses_repository.dart';
import '../services/receipt_storage.dart';
import 'scan_screen.dart';
import 'mercado_publico_screen.dart';
import 'flujo_caja_screen.dart';
import 'expense_detail_screen.dart';
import 'ingresos_ordenes_screen.dart';
import 'ocr_telemetria_screen.dart';
import 'proveedores_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repo = ExpensesRepository.instance;

  @override
  void initState() {
    super.initState();
    _repo.cargar();
  }

  Future<void> _eliminarGasto(Expense expense) async {
    await _repo.eliminar(expense.id!);
    if (!mounted) return;
    // Solo se borra el archivo de la foto si el usuario no deshace la
    // eliminación: "Deshacer" recrea el gasto reutilizando la misma
    // imagePath, así que borrar el archivo antes de tiempo la dejaría
    // rota.
    final closedReason = await ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Gasto eliminado'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () {
            _repo.crear(Expense(
              title: expense.title,
              amount: expense.amount,
              category: expense.category,
              date: expense.date,
              imagePath: expense.imagePath,
            ));
          },
        ),
      ),
    ).closed;

    if (closedReason != SnackBarClosedReason.action) {
      await eliminarFotoTicket(expense.imagePath);
    }
  }

  double _totalThisMonth(List<Expense> expenses) {
    final now = DateTime.now();
    return expenses
        .where((e) => e.date.month == now.month && e.date.year == now.year)
        .fold(0, (sum, e) => sum + e.amount);
  }

  Map<String, double> _categoryTotals(List<Expense> expenses) {
    final Map<String, double> totals = {};
    for (final e in expenses) {
      totals[e.category] = (totals[e.category] ?? 0) + e.amount;
    }
    return totals;
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'Comida': return Colors.orange;
      case 'Transporte': return Colors.blue;
      case 'Salud': return Colors.green;
      case 'Entretenimiento': return Colors.purple;
      default: return Colors.grey;
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Comida': return Icons.restaurant;
      case 'Transporte': return Icons.directions_car;
      case 'Salud': return Icons.health_and_safety;
      case 'Entretenimiento': return Icons.movie;
      default: return Icons.receipt;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        final expenses = _repo.expenses;
        final loading = !_repo.cargado;

        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          appBar: AppBar(
            title: const Text('Luca', style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFF6C63FF),
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.show_chart),
                tooltip: 'Flujo de caja',
                onPressed: () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const FlujoCajaScreen()));
                },
              ),
              IconButton(
                icon: const Icon(Icons.storefront),
                tooltip: 'Mercado Público',
                onPressed: () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const MercadoPublicoScreen()));
                },
              ),
              IconButton(
                icon: const Icon(Icons.request_quote_outlined),
                tooltip: 'Ingresos por órdenes de compra',
                onPressed: () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const IngresosOrdenesScreen()));
                },
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (opcion) {
                  switch (opcion) {
                    case 'proveedores':
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const ProveedoresScreen()));
                      break;
                    case 'exportar':
                      if (expenses.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Aún no hay gastos que exportar')),
                        );
                      } else {
                        exportarGastosCsv(expenses);
                      }
                      break;
                    case 'calidad_ocr':
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const OcrTelemetriaScreen()));
                      break;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'proveedores',
                    child: Row(children: [
                      Icon(Icons.storefront_outlined, size: 20),
                      SizedBox(width: 12),
                      Text('Proveedores'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'exportar',
                    child: Row(children: [
                      Icon(Icons.ios_share, size: 20),
                      SizedBox(width: 12),
                      Text('Exportar gastos (CSV)'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'calidad_ocr',
                    child: Row(children: [
                      Icon(Icons.query_stats, size: 20),
                      SizedBox(width: 12),
                      Text('Calidad del escaneo (OCR)'),
                    ]),
                  ),
                ],
              ),
            ],
          ),
          body: loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _repo.cargar,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSummaryCard(_totalThisMonth(expenses)),
                        const SizedBox(height: 16),
                        _buildCategoryBreakdown(_categoryTotals(expenses)),
                        const SizedBox(height: 16),
                        const Text('Gastos recientes',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        expenses.isEmpty
                            ? _buildEmptyState()
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: expenses.length,
                                itemBuilder: (context, index) =>
                                    _buildExpenseCard(expenses[index]),
                              ),
                      ],
                    ),
                  ),
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              // No hace falta recargar manualmente al volver: guardar el
              // gasto en ExpenseReviewScreen pasa por ExpensesRepository,
              // que notifica a este ListenableBuilder solo.
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ScanScreen()));
            },
            backgroundColor: const Color(0xFF6C63FF),
            foregroundColor: Colors.white,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Escanear ticket'),
          ),
        );
      },
    );
  }

  Widget _buildSummaryCard(double totalThisMonth) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C63FF), Color(0xFF9C27B0)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Gasto este mes',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          Text('\$${totalThisMonth.toStringAsFixed(0)}',
              style: const TextStyle(
                  color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdown(Map<String, double> categoryTotals) {
    if (categoryTotals.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Por categoría',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...categoryTotals.entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(_categoryIcon(entry.key),
                      color: _categoryColor(entry.key), size: 20),
                  const SizedBox(width: 8),
                  Text(entry.key),
                  const Spacer(),
                  Text('\$${entry.value.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildExpenseCard(Expense expense) {
    return Dismissible(
      key: ValueKey(expense.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _eliminarGasto(expense),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          onTap: () {
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => ExpenseDetailScreen(expense: expense)));
          },
          leading: CircleAvatar(
            backgroundColor: _categoryColor(expense.category).withValues(alpha: 0.2),
            child: Icon(_categoryIcon(expense.category),
                color: _categoryColor(expense.category)),
          ),
          title: Text(expense.title),
          subtitle: Text('${expense.category} · ${expense.date.day}/${expense.date.month}/${expense.date.year}'),
          trailing: Text('\$${expense.amount.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 40),
          Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('No hay gastos aún',
              style: TextStyle(color: Colors.grey[600], fontSize: 16)),
          const SizedBox(height: 8),
          Text('Escanea tu primer ticket',
              style: TextStyle(color: Colors.grey[400])),
        ],
      ),
    );
  }
}
