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

enum _DashboardFilter { all, expiringSoon }

class _ProductDashboardPageState extends State<ProductDashboardPage> {
  final List<ProductItem> _products = <ProductItem>[];
  _DashboardFilter _filter = _DashboardFilter.all;

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
                purchaseDate: DateTime.now().subtract(
                  const Duration(days: 30),
                ),
                expiryDate: DateTime.now().add(const Duration(days: 60)),
                unitPrice: record.price,
                quantity: 1,
                volume: record.volume,
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
          volume: product.volume,
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

    final displayedProducts = _filter == _DashboardFilter.expiringSoon
        ? _products.where((p) => p.daysUntilExpiry <= 7).toList()
        : List<ProductItem>.from(_products);

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
                      isActive: _filter == _DashboardFilter.all,
                      onTap: () => setState(
                        () => _filter = _DashboardFilter.all,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SummaryCard(
                      title: 'Expiring in 7 days',
                      value: '$expiringSoon',
                      accent: Colors.orange,
                      isActive: _filter == _DashboardFilter.expiringSoon,
                      onTap: () => setState(
                        () => _filter = _DashboardFilter.expiringSoon,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text('Dashboard', style: Theme.of(context).textTheme.titleLarge),
                  if (_filter == _DashboardFilter.expiringSoon) ...
                    [
                      const SizedBox(width: 8),
                      Chip(
                        label: const Text('Expiring soon'),
                        backgroundColor: Colors.orange.withOpacity(0.15),
                        side: const BorderSide(color: Colors.orange),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () => setState(
                          () => _filter = _DashboardFilter.all,
                        ),
                      ),
                    ],
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: displayedProducts.isEmpty
                    ? Center(
                        child: Text(
                          _filter == _DashboardFilter.expiringSoon
                              ? 'No products expiring soon'
                              : 'No products yet',
                          style: const TextStyle(fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        itemCount: displayedProducts.length,
                        itemBuilder: (context, index) {
                          final product = displayedProducts[index];
                          final originalIndex = _products.indexOf(product);
                          return _ProductCard(
                            product: product,
                            onEdit: () => _openProductSheet(
                              product: product,
                              index: originalIndex,
                            ),
                            onDelete: () => _deleteProduct(originalIndex),
                          );
                        },
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
    required this.isActive,
    required this.onTap,
  });

  final String title;
  final String value;
  final Color accent;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: isActive
            ? Border.all(color: accent, width: 2)
            : Border.all(color: Colors.transparent, width: 2),
      ),
      child: Card(
        elevation: isActive ? 2 : 0,
        margin: EdgeInsets.zero,
        color: isActive ? accent.withValues(alpha: 0.14) : accent.withValues(alpha: 0.07),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: isActive ? accent : Colors.grey[700],
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (isActive)
                      Icon(Icons.filter_list_rounded, size: 14, color: accent),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isActive ? accent : null,
                  ),
                ),
              ],
            ),
          ),
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
                  ? Colors.orange.withOpacity(0.14)
                  : Colors.teal.withOpacity(0.12),
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
                    '${product.name}${product.volume.isNotEmpty ? ' (${product.volume})' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text('Barcode: ${product.barcode}'),
                  const SizedBox(height: 2),
                  Text(
                    'Expiry: ${product.expiryDate.toLocal().toString().split(' ').first} • Qty: ${product.quantity} • ${product.unitPrice.toStringAsFixed(2)} / unit',
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
  late final TextEditingController volumeValueController;
  String volumeUnit = 'ml';
  TextEditingController? categoryController;
  final MobileScannerController scannerController = MobileScannerController();
  List<CategoryRecord> _categories = const [];
  bool _isLoadingCategories = true;
  String? _loadError;
  late DateTime purchaseDate;
  late DateTime expiryDate;

  // FocusNodes to control next field and skip category autoexpand
  late final FocusNode barcodeFocusNode;
  late final FocusNode nameFocusNode;
  late final FocusNode volumeValueFocusNode;
  late final FocusNode categoryFocusNode;
  late final FocusNode priceFocusNode;
  late final FocusNode quantityFocusNode;

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

    final productVolume = product?.volume ?? '';
    String volValue = '';
    String volUnit = 'ml';
    if (productVolume.isNotEmpty) {
      final parts = productVolume.trim().split(' ');
      if (parts.length == 2) {
        volValue = parts[0];
        volUnit = parts[1];
      } else {
        volValue = productVolume;
      }
    }
    volumeValueController = TextEditingController(text: volValue);
    volumeUnit = ['ml', 'kg', 'gm'].contains(volUnit) ? volUnit : 'ml';

    purchaseDate =
        product?.purchaseDate ??
        DateTime.now().subtract(const Duration(days: 30));
    expiryDate =
        product?.expiryDate ?? DateTime.now().add(const Duration(days: 60));

    barcodeFocusNode = FocusNode();
    nameFocusNode = FocusNode();
    volumeValueFocusNode = FocusNode();
    categoryFocusNode = FocusNode();
    priceFocusNode = FocusNode();
    quantityFocusNode = FocusNode();
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
    volumeValueController.dispose();
    barcodeFocusNode.dispose();
    nameFocusNode.dispose();
    volumeValueFocusNode.dispose();
    categoryFocusNode.dispose();
    priceFocusNode.dispose();
    quantityFocusNode.dispose();
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
                              if (!mounted) return;
                              if (record != null) {
                                nameController.text = record.name;
                                priceController.text = record.price.toString();
                                final parts = record.volume.trim().split(' ');
                                if (parts.length == 2) {
                                  volumeValueController.text = parts[0];
                                  setState(() => volumeUnit = parts[1]);
                                } else {
                                  volumeValueController.text = record.volume;
                                }
                              }
                              nameFocusNode.requestFocus();
                            })
                            .catchError((_) {
                              nameFocusNode.requestFocus();
                            });
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
            focusNode: barcodeFocusNode,
            onSubmitted: (_) => nameFocusNode.requestFocus(),
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
            focusNode: nameFocusNode,
            onSubmitted: (_) => volumeValueFocusNode.requestFocus(),
            decoration: const InputDecoration(
              labelText: 'Product name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: volumeValueController,
                  focusNode: volumeValueFocusNode,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => priceFocusNode.requestFocus(),
                  decoration: const InputDecoration(
                    labelText: 'Volume',
                    border: OutlineInputBorder(),
                    hintText: 'e.g. 500, 1',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<String>(
                  value: volumeUnit,
                  decoration: const InputDecoration(
                    labelText: 'Unit',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'ml', child: Text('ml')),
                    DropdownMenuItem(value: 'kg', child: Text('kg')),
                    DropdownMenuItem(value: 'gm', child: Text('gm')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => volumeUnit = value);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Autocomplete<String>(
            optionsBuilder: (textEditingValue) {
              if (textEditingValue.text.trim().isEmpty) {
                return const Iterable<String>.empty();
              }
              return _categories
                  .map((category) => category.name)
                  .where(
                    (name) => name.toLowerCase().contains(
                      textEditingValue.text.toLowerCase(),
                    ),
                  )
                  .take(5);
            },
            onSelected: (value) => categoryController?.text = value,
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
                  categoryController = controller;
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                      hintText: 'Type to search categories',
                    ),
                  );
                },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: expiryDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => expiryDate = picked);
              },
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(
                'Expiry date: ${expiryDate.toLocal().toString().split(' ').first}',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: priceController,
                  focusNode: priceFocusNode,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => quantityFocusNode.requestFocus(),
                  decoration: const InputDecoration(
                    labelText: 'Unit price',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quantity / Units',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove),
                            onPressed: () {
                              final current = int.tryParse(quantityController.text) ?? 1;
                              if (current > 1) {
                                setState(() {
                                  quantityController.text = (current - 1).toString();
                                });
                              }
                            },
                          ),
                          Expanded(
                            child: TextField(
                              controller: quantityController,
                              focusNode: quantityFocusNode,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: () {
                              final current = int.tryParse(quantityController.text) ?? 1;
                              setState(() {
                                quantityController.text = (current + 1).toString();
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
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
                      final categoryName = categoryController?.text.trim() ?? '';

                      final volumeVal = volumeValueController.text.trim();
                      final volumeStr = volumeVal.isEmpty ? '' : '$volumeVal $volumeUnit';

                      final existingProduct = await AppDatabase.instance
                          .findProductByBarcode(barcode);
                      final productId = await AppDatabase.instance
                          .upsertProduct(
                            ProductRecord(
                              id: existingProduct?.id,
                              barcode: barcode,
                              name: name,
                              price: price,
                              volume: volumeStr,
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
                      final now = DateTime.now();
                      await AppDatabase.instance.insertItem(
                        InventoryItemRecord(
                          productId: productId,
                          categoryId: category?.id,
                          purchaseDate: now.toIso8601String(),
                          entryDate: now.toIso8601String(),
                          finished: 0,
                          createdAt: now.toIso8601String(),
                        ),
                      );

                      await widget.onSave(
                        ProductItem(
                          barcode: barcode,
                          name: name,
                          purchaseDate: now,
                          expiryDate: expiryDate,
                          unitPrice: price,
                          quantity: quantity,
                          volume: volumeStr,
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
    required this.purchaseDate,
    required this.expiryDate,
    required this.unitPrice,
    required this.quantity,
    required this.volume,
  });

  final String barcode;
  final String name;
  final DateTime purchaseDate;
  final DateTime expiryDate;
  final double unitPrice;
  final int quantity;
  final String volume;

  int get daysUntilExpiry => expiryDate.difference(DateTime.now()).inDays;

  Map<String, dynamic> toJson() => {
    'barcode': barcode,
    'name': name,
    'purchaseDate': purchaseDate.toIso8601String(),
    'expiryDate': expiryDate.toIso8601String(),
    'unitPrice': unitPrice,
    'quantity': quantity,
    'volume': volume,
  };

  factory ProductItem.fromJson(Map<String, dynamic> json) => ProductItem(
    barcode: json['barcode'] as String,
    name: json['name'] as String,
    purchaseDate: DateTime.parse(json['purchaseDate'] as String),
    expiryDate: DateTime.parse(json['expiryDate'] as String),
    unitPrice: (json['unitPrice'] as num).toDouble(),
    quantity: json['quantity'] as int,
    volume: json['volume'] as String? ?? '',
  );
}

