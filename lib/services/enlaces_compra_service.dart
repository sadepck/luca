/// No existe una base de datos pública de proveedores chilenos por zona a
/// la que conectarse, así que esto NO busca proveedores reales por sí solo:
/// arma enlaces de búsqueda reales (Google, Mercado Libre, Google Maps)
/// filtrados por el producto y la ciudad, para que la persona cotice más
/// rápido comparando resultados reales, no simulados.
class EnlaceBusqueda {
  final String tienda;
  final String url;

  EnlaceBusqueda(this.tienda, this.url);
}

List<EnlaceBusqueda> generarEnlacesBusqueda(String producto, String? ciudad) {
  final productoLimpio = producto.trim();
  if (productoLimpio.isEmpty) return [];

  final ciudadLimpia = (ciudad ?? '').trim();
  final consulta = ciudadLimpia.isEmpty
      ? productoLimpio
      : '$productoLimpio $ciudadLimpia';
  final consultaCodificada = Uri.encodeComponent(consulta);
  final productoCodificado = Uri.encodeComponent(productoLimpio);

  return [
    EnlaceBusqueda(
      'Google',
      'https://www.google.com/search?q=$consultaCodificada',
    ),
    EnlaceBusqueda(
      'Mercado Libre',
      'https://listado.mercadolibre.cl/$productoCodificado',
    ),
    EnlaceBusqueda(
      'Google Maps',
      'https://www.google.com/maps/search/?api=1&query=$consultaCodificada',
    ),
  ];
}
