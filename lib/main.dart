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
    const _slate900 = Color(0xFF0F172A);
    const _slate700 = Color(0xFF334155);
    const _slate100 = Color(0xFFF1F5F9);
    const _indigo500 = Color(0xFF6366F1);

    return MaterialApp(
      title: 'Expired',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _indigo500,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: _slate100,
        appBarTheme: const AppBarTheme(
          backgroundColor: _slate100,
          foregroundColor: _slate900,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: _slate900,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _slate100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _indigo500, width: 1.5),
          ),
          labelStyle: TextStyle(color: _slate700, fontSize: 14),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _slate900,
            letterSpacing: -0.3,
          ),
          bodyMedium: TextStyle(color: _slate700, fontSize: 14),
          bodySmall: TextStyle(color: _slate700, fontSize: 12),
        ),
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

    const indigo = Color(0xFF6366F1);
    const amber = Color(0xFFF59E0B);
    const slate900 = Color(0xFF0F172A);
    const slate500 = Color(0xFF64748B);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expired'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: IconButton(
              onPressed: () => _openProductSheet(),
              icon: const Icon(Icons.add, size: 22),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: slate900,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header greeting
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Text(
                'Track products before they expire.',
                style: TextStyle(
                  color: slate500,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
            // stat cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      title: 'Total',
                      value: '${_products.length}',
                      accent: indigo,
                      icon: Icons.inventory_2_rounded,
                      isActive: _filter == _DashboardFilter.all,
                      onTap: () => setState(() => _filter = _DashboardFilter.all),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SummaryCard(
                      title: 'Expiring soon',
                      value: '$expiringSoon',
                      accent: amber,
                      icon: Icons.warning_amber_rounded,
                      isActive: _filter == _DashboardFilter.expiringSoon,
                      onTap: () => setState(() => _filter = _DashboardFilter.expiringSoon),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // section header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    _filter == _DashboardFilter.expiringSoon
                        ? 'Expiring Soon'
                        : 'All Products',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: slate900,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const Spacer(),
                  if (_filter == _DashboardFilter.expiringSoon)
                    GestureDetector(
                      onTap: () => setState(() => _filter = _DashboardFilter.all),
                      child: Text(
                        'Show all',
                        style: TextStyle(
                          color: indigo,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // list
            Expanded(
              child: displayedProducts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _filter == _DashboardFilter.expiringSoon
                                ? Icons.check_circle_outline_rounded
                                : Icons.inventory_2_outlined,
                            size: 52,
                            color: slate500.withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _filter == _DashboardFilter.expiringSoon
                                ? 'Nothing expiring soon'
                                : 'No products yet',
                            style: TextStyle(
                              fontSize: 15,
                              color: slate500,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openProductSheet(),
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
        elevation: 0,
        icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
        label: const Text(
          'Scan / Add',
          style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.2),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.accent,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String title;
  final String value;
  final Color accent;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isActive ? accent : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.white.withValues(alpha: 0.25)
                    : accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 18,
                color: isActive ? Colors.white : accent,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: isActive ? Colors.white : const Color(0xFF0F172A),
                height: 1,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isActive
                    ? Colors.white.withValues(alpha: 0.8)
                    : const Color(0xFF64748B),
              ),
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
    final critical = days <= 3;
    final warning = days <= 7;
    final accentColor = critical
        ? const Color(0xFFEF4444)
        : warning
            ? const Color(0xFFF59E0B)
            : const Color(0xFF10B981);
    final expiryLabel = days < 0
        ? 'Expired'
        : days == 0
            ? 'Today'
            : '$days d left';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // left accent bar
              Container(width: 4, color: accentColor),
              // content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // icon
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.inventory_2_rounded,
                          size: 20,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              product.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (product.volume.isNotEmpty)
                              Text(
                                product.volume,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                _Tag(
                                  label: expiryLabel,
                                  color: accentColor,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Qty ${product.quantity}  ·  ৳${product.unitPrice.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // actions
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ActionBtn(
                            icon: Icons.edit_rounded,
                            color: const Color(0xFF6366F1),
                            onPressed: onEdit,
                            tooltip: 'Edit',
                          ),
                          const SizedBox(height: 4),
                          _ActionBtn(
                            icon: Icons.delete_rounded,
                            color: const Color(0xFFEF4444),
                            onPressed: onDelete,
                            tooltip: 'Delete',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.color,
    required this.onPressed,
    required this.tooltip,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
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
    const indigo = Color(0xFF6366F1);
    const slate900 = Color(0xFF0F172A);
    const slate500 = Color(0xFF64748B);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 28,
                decoration: BoxDecoration(
                  color: indigo,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                widget.product == null ? 'New Product' : 'Edit Product',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: slate900,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(
              widget.product == null
                  ? 'Fill in the details below to add a product.'
                  : 'Update the saved product details.',
              style: const TextStyle(color: slate500, fontSize: 13),
            ),
          ),
          const SizedBox(height: 20),
          if (_loadError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _loadError!,
                style: const TextStyle(color: Color(0xFFF59E0B)),
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
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: 0.2,
                ),
              ),
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

