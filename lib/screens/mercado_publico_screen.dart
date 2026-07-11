import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/compra_agil.dart';
import '../models/licitacion.dart';
import '../services/compra_agil_service.dart';
import '../services/database_service.dart';
import '../services/mercado_publico_service.dart';
import 'mercado_publico_config_screen.dart';
import 'oportunidad_detalle_screen.dart';

class MercadoPublicoScreen extends StatefulWidget {
  const MercadoPublicoScreen({super.key});

  @override
  State<MercadoPublicoScreen> createState() => _MercadoPublicoScreenState();
}

class _MercadoPublicoScreenState extends State<MercadoPublicoScreen> {
  final _service = MercadoPublicoService();
  final _compraAgilService = CompraAgilService();
  final _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  String _ticket = '';
  List<String> _palabrasClave = [];
  List<Licitacion> _todas = [];
  Set<String> _codigosNuevos = {};
  bool _soloCompraAgil = false;

  List<CompraAgil> _compraAgil = [];
  bool _loadingCompraAgil = false;
  String? _errorCompraAgil;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final prefs = await SharedPreferences.getInstance();
    _ticket = prefs.getString(kMpTicketPrefKey) ?? '';
    _palabrasClave = (prefs.getString(kMpKeywordsPrefKey) ?? '')
        .split(',')
        .map((p) => p.trim().toLowerCase())
        .where((p) => p.isNotEmpty)
        .toList();

    if (_ticket.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'ticket_faltante';
      });
      return;
    }

    try {
      final resultados = await _service.buscarActivas(_ticket);
      final codigos = resultados.map((l) => l.codigo).toList();
      final nuevos = await DatabaseService.instance.filtrarNoVistas(codigos);
      await DatabaseService.instance.marcarComoVistas(codigos);
      setState(() {
        _todas = resultados;
        _codigosNuevos = nuevos.toSet();
        _loading = false;
      });
    } on MercadoPublicoException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Ocurrió un error inesperado al consultar Mercado Público.';
        _loading = false;
      });
    }
  }

  /// Trae Compras Ágiles reales desde el API dedicado (distinto del de
  /// licitaciones) solo la primera vez que se activa el filtro — para no
  /// gastar cuota del ticket en cargas que el usuario nunca pide ver.
  Future<void> _cargarCompraAgil() async {
    if (_compraAgil.isNotEmpty || _loadingCompraAgil || _ticket.isEmpty) return;
    setState(() {
      _loadingCompraAgil = true;
      _errorCompraAgil = null;
    });
    try {
      final resultados = await _compraAgilService.buscarActivas(_ticket);
      if (!mounted) return;
      setState(() {
        _compraAgil = resultados;
        _loadingCompraAgil = false;
      });
    } on MercadoPublicoException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorCompraAgil = e.message;
        _loadingCompraAgil = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorCompraAgil = 'Ocurrió un error inesperado al consultar Compra Ágil.';
        _loadingCompraAgil = false;
      });
    }
  }

  List<Licitacion> get _fuenteActual =>
      _soloCompraAgil ? _compraAgil.map((ca) => ca.toLicitacion()).toList() : _todas;

  List<Licitacion> get _filtradas {
    final texto = _searchController.text.trim().toLowerCase();
    return _fuenteActual.where((l) {
      final contenido = '${l.nombre} ${l.descripcion ?? ''}'.toLowerCase();

      if (texto.isNotEmpty && !contenido.contains(texto)) return false;

      if (texto.isEmpty && _palabrasClave.isNotEmpty) {
        return _palabrasClave.any((p) => contenido.contains(p));
      }
      return true;
    }).toList();
  }

  Future<void> _abrirConfig() async {
    final cambiado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const MercadoPublicoConfigScreen()),
    );
    if (cambiado == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Mercado Público'),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _abrirConfig,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error == 'ticket_faltante'
              ? _buildSinTicket()
              : _error != null
                  ? _buildError(_error!)
                  : _buildLista(),
    );
  }

  Widget _buildSinTicket() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.storefront, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'Configura tu ticket del API de Mercado Público para ver '
              'licitaciones y oportunidades de Compra Ágil activas.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _abrirConfig,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
              ),
              child: const Text('Configurar ahora'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(String mensaje) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(mensaje, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _cargar,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
              ),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLista() {
    final lista = _filtradas;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Buscar por palabra clave',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('Solo Compra Ágil'),
                      selected: _soloCompraAgil,
                      onSelected: (v) {
                        setState(() => _soloCompraAgil = v);
                        if (v) _cargarCompraAgil();
                      },
                    ),
                    const SizedBox(width: 8),
                    if (_soloCompraAgil && _loadingCompraAgil)
                      const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      Text(
                          '${lista.length} de '
                          '${_soloCompraAgil ? _compraAgil.length : _todas.length}',
                          style: TextStyle(color: Colors.grey[600])),
                    if (_codigosNuevos.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('${_codigosNuevos.length} nuevas',
                            style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (_soloCompraAgil && _errorCompraAgil == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Datos oficiales del API dedicado de Compra Ágil de ChileCompra.',
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
              ),
            ),
          if (_soloCompraAgil && _errorCompraAgil != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_errorCompraAgil!,
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                  TextButton(
                    onPressed: () {
                      setState(() => _compraAgil = []);
                      _cargarCompraAgil();
                    },
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: lista.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 60),
                      Center(child: Text('No hay oportunidades para mostrar')),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: lista.length,
                    itemBuilder: (context, index) =>
                        _buildCard(lista[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Licitacion l) {
    final dias = l.diasParaCierre;
    final urgente = dias != null && dias <= 3 && dias >= 0;
    final esNueva = _codigosNuevos.contains(l.codigo);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (l.esCompraAgil ? Colors.orange : const Color(0xFF6C63FF))
              .withValues(alpha: 0.15),
          child: Icon(
            l.esCompraAgil ? Icons.bolt : Icons.description,
            color: l.esCompraAgil ? Colors.orange : const Color(0xFF6C63FF),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(l.nombre,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            if (esNueva)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Nuevo',
                    style: TextStyle(color: Colors.white, fontSize: 10)),
              ),
          ],
        ),
        subtitle: Text(
          l.organismo ?? l.codigo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: dias == null
            ? null
            : Text(
                dias >= 0 ? '${dias}d' : 'Cerrada',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: urgente ? Colors.red : Colors.grey[600],
                ),
              ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OportunidadDetalleScreen(licitacion: l),
            ),
          );
        },
      ),
    );
  }
}
