import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const ExpiredApp());
}

class ExpiredApp extends StatelessWidget {
  const ExpiredApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expired',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const ProductDashboardPage(),
    );
  }
}

class ProductDashboardPage extends StatefulWidget {
  const ProductDashboardPage({super.key});

  @override
  State<ProductDashboardPage> createState() => _ProductDashboardPageState();
}

class _ProductDashboardPageState extends State<ProductDashboardPage> {
  final List<ProductItem> _products = <ProductItem>[];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('expired_products');
    if (raw == null || raw.isEmpty) {
      return;
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    setState(() {
      _products
        ..clear()
        ..addAll(
          decoded.map(
            (item) => ProductItem.fromJson(item as Map<String, dynamic>),
          ),
        );
    });
  }

  Future<void> _saveProducts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'expired_products',
      jsonEncode(_products.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> _openAddProductSheet() async {
    final navigator = Navigator.of(context);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(bottomSheetContext).viewInsets.bottom + 16,
          ),
          child: ProductForm(
            onSave: (product) async {
              setState(() {
                _products.add(product);
                _products.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
              });
              await _saveProducts();
              if (mounted) {
                navigator.pop();
              }
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final expiringSoon = _products
        .where((product) => product.daysUntilExpiry <= 7)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expired'),
        actions: [
          IconButton(
            onPressed: _openAddProductSheet,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Keep track of products that are close to expiry.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      title: 'Products',
                      value: '${_products.length}',
                      accent: Colors.teal,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SummaryCard(
                      title: 'Expiring in 7 days',
                      value: '$expiringSoon',
                      accent: Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Dashboard', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Expanded(
                child: _products.isEmpty
                    ? const Center(
                        child: Text(
                          'No products yet',
                          style: TextStyle(fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _products.length,
                        itemBuilder: (context, index) =>
                            _ProductCard(product: _products[index]),
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddProductSheet,
        icon: const Icon(Icons.qr_code_scanner_outlined),
        label: const Text('Add product'),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.accent,
  });

  final String title;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: accent.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: Colors.grey[700]),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final ProductItem product;

  @override
  Widget build(BuildContext context) {
    final days = product.daysUntilExpiry;
    final warning = days <= 7;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: warning
              ? Colors.orange.withValues(alpha: 0.14)
              : Colors.teal.withValues(alpha: 0.12),
          child: Icon(
            Icons.inventory_2_outlined,
            color: warning ? Colors.orange : Colors.teal,
          ),
        ),
        title: Text(
          product.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Barcode: ${product.barcode}'),
            Text(
              'Expiry: ${product.expiryDate.toLocal().toString().split(' ').first} • ${product.unitPrice.toStringAsFixed(2)} / unit',
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(warning ? '$days days left' : 'Safe'),
            if (warning)
              const Text(
                'Alert',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ProductForm extends StatefulWidget {
  const ProductForm({required this.onSave, super.key});

  final Future<void> Function(ProductItem) onSave;

  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  final barcodeController = TextEditingController();
  final nameController = TextEditingController();
  final priceController = TextEditingController();
  final quantityController = TextEditingController(text: '1');
  final MobileScannerController scannerController = MobileScannerController();
  DateTime manufacturingDate = DateTime.now().subtract(
    const Duration(days: 30),
  );
  DateTime expiryDate = DateTime.now().add(const Duration(days: 60));

  @override
  void dispose() {
    barcodeController.dispose();
    nameController.dispose();
    priceController.dispose();
    quantityController.dispose();
    scannerController.dispose();
    super.dispose();
  }

  Future<void> _openBarcodeScanner() async {
    final status = await Permission.camera.request();

    if (!mounted) {
      return;
    }

    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera permission is required to scan barcodes.'),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.72,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Scan barcode',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: MobileScanner(
                    controller: scannerController,
                    onDetect: (capture) {
                      final value = capture.barcodes.firstOrNull?.rawValue
                          ?.trim();
                      if (value == null || value.isEmpty) {
                        return;
                      }

                      barcodeController.text = value;
                      Navigator.of(sheetContext).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Barcode captured: $value')),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New product', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Capture product details quickly for the dashboard.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: barcodeController,
            decoration: InputDecoration(
              labelText: 'Barcode',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Scan barcode',
                onPressed: _openBarcodeScanner,
                icon: const Icon(Icons.qr_code_scanner_rounded),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Product name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: manufacturingDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() => manufacturingDate = picked);
                    }
                  },
                  child: Text(
                    'Mfg: ${manufacturingDate.toLocal().toString().split(' ').first}',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: expiryDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => expiryDate = picked);
                  },
                  child: Text(
                    'Exp: ${expiryDate.toLocal().toString().split(' ').first}',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Unit price',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: quantityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                final barcode = barcodeController.text.trim();
                final name = nameController.text.trim();
                if (barcode.isEmpty || name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter barcode and product name.'),
                    ),
                  );
                  return;
                }

                final price = double.tryParse(priceController.text) ?? 0.0;
                final quantity = int.tryParse(quantityController.text) ?? 1;

                await widget.onSave(
                  ProductItem(
                    barcode: barcode,
                    name: name,
                    manufacturingDate: manufacturingDate,
                    expiryDate: expiryDate,
                    unitPrice: price,
                    quantity: quantity,
                  ),
                );
              },
              icon: const Icon(Icons.save_alt),
              label: const Text('Save product'),
            ),
          ),
        ],
      ),
    );
  }
}

class ProductItem {
  ProductItem({
    required this.barcode,
    required this.name,
    required this.manufacturingDate,
    required this.expiryDate,
    required this.unitPrice,
    required this.quantity,
  });

  final String barcode;
  final String name;
  final DateTime manufacturingDate;
  final DateTime expiryDate;
  final double unitPrice;
  final int quantity;

  int get daysUntilExpiry => expiryDate.difference(DateTime.now()).inDays;

  Map<String, dynamic> toJson() => {
    'barcode': barcode,
    'name': name,
    'manufacturingDate': manufacturingDate.toIso8601String(),
    'expiryDate': expiryDate.toIso8601String(),
    'unitPrice': unitPrice,
    'quantity': quantity,
  };

  factory ProductItem.fromJson(Map<String, dynamic> json) => ProductItem(
    barcode: json['barcode'] as String,
    name: json['name'] as String,
    manufacturingDate: DateTime.parse(json['manufacturingDate'] as String),
    expiryDate: DateTime.parse(json['expiryDate'] as String),
    unitPrice: (json['unitPrice'] as num).toDouble(),
    quantity: json['quantity'] as int,
  );
}
