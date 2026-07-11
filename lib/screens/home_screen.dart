import 'package:flutter/material.dart';
import '../models/expense.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';
import 'scan_screen.dart';
import 'mercado_publico_screen.dart';
import 'flujo_caja_screen.dart';
import 'expense_detail_screen.dart';
import 'ingresos_ordenes_screen.dart';
import 'proveedores_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Expense> _expenses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    final expenses = await DatabaseService.instance.getAllExpenses();
    setState(() {
      _expenses = expenses;
      _loading = false;
    });
  }

  Future<void> _eliminarGasto(Expense expense) async {
    setState(() => _expenses.removeWhere((e) => e.id == expense.id));
    await DatabaseService.instance.deleteExpense(expense.id!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Gasto eliminado'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () async {
            await DatabaseService.instance.createExpense(Expense(
              title: expense.title,
              amount: expense.amount,
              category: expense.category,
              date: expense.date,
              imagePath: expense.imagePath,
            ));
            _loadExpenses();
          },
        ),
      ),
    );
  }

  double get _totalThisMonth {
    final now = DateTime.now();
    return _expenses
        .where((e) => e.date.month == now.month && e.date.year == now.year)
        .fold(0, (sum, e) => sum + e.amount);
  }

  Map<String, double> get _categoryTotals {
    final Map<String, double> totals = {};
    for (final e in _expenses) {
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
                  if (_expenses.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Aún no hay gastos que exportar')),
                    );
                  } else {
                    exportarGastosCsv(_expenses);
                  }
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
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadExpenses,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSummaryCard(),
                    const SizedBox(height: 16),
                    _buildCategoryBreakdown(),
                    const SizedBox(height: 16),
                    const Text('Gastos recientes',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _expenses.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _expenses.length,
                            itemBuilder: (context, index) =>
                                _buildExpenseCard(_expenses[index]),
                          ),
                  ],
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ScanScreen()));
          _loadExpenses();
        },
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.camera_alt),
        label: const Text('Escanear ticket'),
      ),
    );
  }

  Widget _buildSummaryCard() {
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
          Text('\$${_totalThisMonth.toStringAsFixed(0)}',
              style: const TextStyle(
                  color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdown() {
    if (_categoryTotals.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Por categoría',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ..._categoryTotals.entries.map((entry) => Padding(
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
