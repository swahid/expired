import 'package:expired/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

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
      debugShowCheckedModeBanner: false,
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
    try {
      final records = await AppDatabase.instance.getProducts();
      if (!mounted) return;
      setState(() {
        _products
          ..clear()
          ..addAll(
            records.map(
              (record) => ProductItem(
                barcode: record.barcode,
                name: record.name,
                manufacturingDate: DateTime.now().subtract(
                  const Duration(days: 30),
                ),
                expiryDate: DateTime.now().add(const Duration(days: 60)),
                unitPrice: record.price,
                quantity: 1,
              ),
            ),
          );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _products.clear());
    }
  }

  Future<void> _saveProducts() async {
    for (final product in _products) {
      await AppDatabase.instance.upsertProduct(
        ProductRecord(
          barcode: product.barcode,
          name: product.name,
          price: product.unitPrice,
          volume: product.quantity.toString(),
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
    }
  }

  Future<void> _openProductSheet({ProductItem? product, int? index}) async {
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
            product: product,
            onSave: (updatedProduct) async {
              setState(() {
                if (index == null) {
                  _products.add(updatedProduct);
                } else {
                  _products[index] = updatedProduct;
                }
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

  Future<void> _deleteProduct(int index) async {
    final product = _products[index];
    setState(() {
      _products.removeAt(index);
    });
    await AppDatabase.instance.deleteProduct(
      await AppDatabase.instance
          .findProductByBarcode(product.barcode)
          .then((value) => value?.id ?? -1),
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
            onPressed: () => _openProductSheet(),
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
                        itemBuilder: (context, index) => _ProductCard(
                          product: _products[index],
                          onEdit: () => _openProductSheet(
                            product: _products[index],
                            index: index,
                          ),
                          onDelete: () => _deleteProduct(index),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openProductSheet(),
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
  const _ProductCard({
    required this.product,
    required this.onEdit,
    required this.onDelete,
  });

  final ProductItem product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final days = product.daysUntilExpiry;
    final warning = days <= 7;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: warning
                  ? Colors.orange.withValues(alpha: 0.14)
                  : Colors.teal.withValues(alpha: 0.12),
              child: Icon(
                Icons.inventory_2_outlined,
                color: warning ? Colors.orange : Colors.teal,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text('Barcode: ${product.barcode}'),
                  const SizedBox(height: 2),
                  Text(
                    'Expiry: ${product.expiryDate.toLocal().toString().split(' ').first} • ${product.unitPrice.toStringAsFixed(2)} / unit',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 88,
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints.tight(const Size(32, 32)),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: onDelete,
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: Colors.red,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints.tight(const Size(32, 32)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductForm extends StatefulWidget {
  const ProductForm({required this.onSave, this.product, super.key});

  final Future<void> Function(ProductItem) onSave;
  final ProductItem? product;

  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  late final TextEditingController barcodeController;
  late final TextEditingController nameController;
  late final TextEditingController priceController;
  late final TextEditingController quantityController;
  late final TextEditingController categoryController;
  final MobileScannerController scannerController = MobileScannerController();
  List<CategoryRecord> _categories = const [];
  bool _isLoadingCategories = true;
  String? _loadError;
  late DateTime manufacturingDate;
  late DateTime expiryDate;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    final product = widget.product;
    barcodeController = TextEditingController(text: product?.barcode ?? '');
    nameController = TextEditingController(text: product?.name ?? '');
    priceController = TextEditingController(
      text: product?.unitPrice.toString() ?? '',
    );
    quantityController = TextEditingController(
      text: product?.quantity.toString() ?? '1',
    );
    categoryController = TextEditingController();
    manufacturingDate =
        product?.manufacturingDate ??
        DateTime.now().subtract(const Duration(days: 30));
    expiryDate =
        product?.expiryDate ?? DateTime.now().add(const Duration(days: 60));
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await AppDatabase.instance.getCategories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _isLoadingCategories = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _categories = const [];
        _isLoadingCategories = false;
        _loadError = 'Unable to load categories right now.';
      });
    }
  }

  @override
  void dispose() {
    barcodeController.dispose();
    nameController.dispose();
    priceController.dispose();
    quantityController.dispose();
    categoryController.dispose();
    scannerController.dispose();
    super.dispose();
  }

  Future<void> _openBarcodeScanner() async {
    try {
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
                        AppDatabase.instance
                            .findProductByBarcode(value)
                            .then((record) {
                              if (!mounted || record == null) return;
                              nameController.text = record.name;
                              priceController.text = record.price.toString();
                              quantityController.text = record.volume;
                            })
                            .catchError((_) {});
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
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the scanner right now.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.product == null ? 'New product' : 'Edit product',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            widget.product == null
                ? 'Capture product details quickly for the dashboard.'
                : 'Update the saved product details below.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (_loadError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _loadError!,
                style: const TextStyle(color: Colors.orange),
              ),
            ),
          if (_isLoadingCategories)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator()),
            ),
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
          Autocomplete<String>(
            optionsBuilder: (textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return _categories.map((category) => category.name);
              }
              return _categories
                  .map((category) => category.name)
                  .where(
                    (name) => name.toLowerCase().contains(
                      textEditingValue.text.toLowerCase(),
                    ),
                  );
            },
            onSelected: (value) => categoryController.text = value,
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
                  categoryController = controller;
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                      hintText: 'Choose or type a category',
                    ),
                  );
                },
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
              onPressed: _isLoadingCategories
                  ? null
                  : () async {
                      final barcode = barcodeController.text.trim();
                      final name = nameController.text.trim();
                      if (barcode.isEmpty || name.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Please enter barcode and product name.',
                            ),
                          ),
                        );
                        return;
                      }

                      final price =
                          double.tryParse(priceController.text) ?? 0.0;
                      final quantity =
                          int.tryParse(quantityController.text) ?? 1;
                      final categoryName = categoryController.text.trim();

                      final existingProduct = await AppDatabase.instance
                          .findProductByBarcode(barcode);
                      final productId = await AppDatabase.instance
                          .upsertProduct(
                            ProductRecord(
                              id: existingProduct?.id,
                              barcode: barcode,
                              name: name,
                              price: price,
                              volume: quantity.toString(),
                              createdAt:
                                  existingProduct?.createdAt ??
                                  DateTime.now().toIso8601String(),
                            ),
                          );

                      final category = _categories
                          .where(
                            (item) =>
                                item.name.toLowerCase() ==
                                categoryName.toLowerCase(),
                          )
                          .firstOrNull;
                      await AppDatabase.instance.insertItem(
                        InventoryItemRecord(
                          productId: productId,
                          categoryId: category?.id,
                          purchaseDate: manufacturingDate.toIso8601String(),
                          entryDate: DateTime.now().toIso8601String(),
                          finished: 0,
                          createdAt: DateTime.now().toIso8601String(),
                        ),
                      );

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
              label: Text(
                widget.product == null ? 'Save product' : 'Update product',
              ),
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
