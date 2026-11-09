import 'dart:convert';
import 'dart:io';

class ProductLookupResult {
  const ProductLookupResult({
    required this.name,
    this.category,
    this.brand,
  });

  final String name;
  final String? category;
  final String? brand;
}

/// Service to lookup product information from Open Food Facts API
/// when scanning a barcode. Requires no API keys.
class BarcodeService {
  BarcodeService._();
  static final BarcodeService instance = BarcodeService._();

  /// Looks up a product by [barcode]. Returns null if not found or on network error.
  Future<ProductLookupResult?> lookupOnline(String barcode) async {
    final cleanCode = barcode.trim();
    if (cleanCode.isEmpty) return null;

    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4);

      final uri = Uri.parse(
        'https://world.openfoodfacts.org/api/v2/product/$cleanCode.json'
        '?fields=product_name,product_name_en,brands,categories_tags',
      );

      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'ExpiredApp/1.1.0 (Flutter; Android/iOS)');
      request.headers.set('Accept', 'application/json');

      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) {
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (json['status'] != 1 || json['product'] == null) {
        return null;
      }

      final product = json['product'] as Map<String, dynamic>;
      final rawName = (product['product_name'] as String?)?.trim() ??
          (product['product_name_en'] as String?)?.trim();
      final brand = (product['brands'] as String?)?.split(',').firstOrNull?.trim();

      if (rawName == null || rawName.isEmpty) {
        return null;
      }

      final fullName = (brand != null && brand.isNotEmpty && !rawName.toLowerCase().contains(brand.toLowerCase()))
          ? '$brand $rawName'
          : rawName;

      final categoriesTags = (product['categories_tags'] as List<dynamic>?)
              ?.map((e) => e.toString().toLowerCase())
              .toList() ??
          const [];

      final mappedCategory = _mapCategory(categoriesTags);

      return ProductLookupResult(
        name: fullName,
        category: mappedCategory,
        brand: brand,
      );
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  String? _mapCategory(List<String> tags) {
    for (final tag in tags) {
      if (tag.contains('dairy') ||
          tag.contains('milk') ||
          tag.contains('cheese') ||
          tag.contains('yogurt') ||
          tag.contains('butter')) {
        return 'Dairy';
      }
      if (tag.contains('meat') ||
          tag.contains('fish') ||
          tag.contains('seafood') ||
          tag.contains('poultry') ||
          tag.contains('beef') ||
          tag.contains('pork') ||
          tag.contains('chicken')) {
        return 'Meat & Seafood';
      }
      if (tag.contains('fruit') ||
          tag.contains('vegetable') ||
          tag.contains('salad') ||
          tag.contains('produce')) {
        return 'Fruits & Vegetables';
      }
      if (tag.contains('bread') ||
          tag.contains('bakery') ||
          tag.contains('pastr') ||
          tag.contains('cake') ||
          tag.contains('biscuit')) {
        return 'Bakery';
      }
      if (tag.contains('beverage') ||
          tag.contains('drink') ||
          tag.contains('juice') ||
          tag.contains('tea') ||
          tag.contains('coffee') ||
          tag.contains('soda')) {
        return 'Beverages';
      }
      if (tag.contains('frozen') || tag.contains('ice-cream')) {
        return 'Frozen Foods';
      }
      if (tag.contains('snack') ||
          tag.contains('chip') ||
          tag.contains('candy') ||
          tag.contains('chocolate')) {
        return 'Snacks';
      }
      if (tag.contains('sauce') ||
          tag.contains('condiment') ||
          tag.contains('spread') ||
          tag.contains('dressing') ||
          tag.contains('oil')) {
        return 'Sauces & Condiments';
      }
    }
    return null;
  }
}

