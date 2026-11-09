import 'package:expired/ad_banner_widget.dart';
import 'package:expired/backup_helper.dart';
import 'package:expired/barcode_service.dart';
import 'package:expired/database_helper.dart';
import 'package:expired/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  try {
    await MobileAds.instance.initialize();
  } catch (_) {
    // Best-effort ad initialization
  }
  runApp(const ExpiredApp());
}

class ExpiredApp extends StatelessWidget {
  const ExpiredApp({super.key});

  @override
  Widget build(BuildContext context) {
    const slate900 = Color(0xFF1E2233);
    const slate700 = Color(0xFF475569);
    const slate100 = Color(0xFFF6F7FB);
    const indigo500 = Color(0xFFFF5A3C);

    return MaterialApp(
      title: 'Expired',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: indigo500,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: slate100,
        appBarTheme: const AppBarTheme(
          backgroundColor: slate100,
          foregroundColor: slate900,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: slate900,
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
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          modalBackgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: slate100,
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
            borderSide: const BorderSide(color: indigo500, width: 1.5),
          ),
          labelStyle: const TextStyle(color: slate700, fontSize: 14),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: slate900,
            letterSpacing: -0.3,
          ),
          bodyMedium: TextStyle(color: slate700, fontSize: 14),
          bodySmall: TextStyle(color: slate700, fontSize: 12),
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

enum _DashboardFilter { all, thisWeek, expired }

class _ProductDashboardPageState extends State<ProductDashboardPage> {
  final List<ProductItem> _products = <ProductItem>[];
  _DashboardFilter _filter = _DashboardFilter.all;
  String? _storageFilter; // null = All, 'fridge', 'freezer', 'pantry'
  ({double used, double wasted, int usedCount, int wastedCount}) _monthStats = (
    used: 0,
    wasted: 0,
    usedCount: 0,
    wastedCount: 0,
  );

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    await NotificationService.instance.requestPermission();
    await NotificationService.instance.rescheduleAll();
  }

  /// Reloads the dashboard from the DB, refreshes reminders, and updates JSON mirror.
  Future<void> _loadProducts() async {
    try {
      final items = await AppDatabase.instance.getDashboardItems();
      final stats = await AppDatabase.instance.getMonthlyStats(DateTime.now());
      if (!mounted) return;
      setState(() {
        _monthStats = stats;
        _products
          ..clear()
          ..addAll(
            items.map(
              (item) => ProductItem(
                productId: item['productId'] as int,
                barcode: item['barcode'] as String,
                name: item['name'] as String,
                category: item['category'] as String?,
                purchaseDate:
                    DateTime.tryParse(item['purchaseDate'] as String? ?? '') ??
                    DateTime.now(),
                cookedDate:
                    DateTime.tryParse(item['cookedDate'] as String? ?? ''),
                expiryKey: item['expiryDate'] as String? ?? '',
                expiryDate:
                    DateTime.tryParse(item['expiryDate'] as String? ?? '') ??
                    DateTime.now().add(const Duration(days: 60)),
                unitPrice: (item['price'] as num).toDouble(),
                quantity: item['quantity'] as int,
                storageLocation:
                    item['storageLocation'] as String? ??
                    StorageLocation.fridge,
                portionCount: (item['totalPortions'] as num?)?.toInt() ?? 1,
                isHomemade: (item['isHomemade'] as num?)?.toInt() != 0,
                notes: item['notes'] as String?,
              ),
            ),
          );
      });
      // Maintain offline mirror backup in background
      LocalBackupHelper.instance.updateMirrorBackup();
    } catch (_) {
      if (!mounted) return;
      setState(() => _products.clear());
    }
    NotificationService.instance.rescheduleAll();
  }

  Future<void> _openProductSheet({
    ProductItem? product,
    String? initialBarcode,
    String? initialLocation,
  }) async {
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
            initialBarcode: initialBarcode,
            initialLocation: initialLocation ?? _storageFilter,
            onSave: () async {
              await _loadProducts();
              if (mounted) {
                navigator.pop();
              }
            },
            onDelete: product == null
                ? null
                : () async {
                    await _deleteProduct(product);
                    if (mounted) {
                      navigator.pop();
                    }
                  },
          ),
        );
      },
    );
  }

  /// Flow to add without camera scan directly (ideal for homemade food).
  Future<void> _quickAddFood() async {
    await _openProductSheet(initialBarcode: '');
  }

  /// FAB flow: open the camera first, then the form with the barcode filled.
  Future<void> _scanAndAdd() async {
    final code = await showBarcodeScanner(context, allowManual: true);
    if (code == null || !mounted) return;
    await _openProductSheet(initialBarcode: code);
  }

  Future<void> _deleteProduct(ProductItem product) async {
    setState(() => _products.remove(product));
    await AppDatabase.instance.deleteItemsByProductAndExpiry(
      product.productId,
      product.expiryKey,
      storageLocation: product.storageLocation,
    );
    await _loadProducts();
  }

  /// Marks one unit of [product] as used or wasted, with an Undo snackbar.
  Future<void> _finishOne(ProductItem product, String reason) async {
    final ids = await AppDatabase.instance.markItemsFinished(
      product.productId,
      product.expiryKey,
      1,
      reason,
      storageLocation: product.storageLocation,
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          reason == 'used'
              ? '${product.name} marked as used'
              : '${product.name} marked as wasted',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await AppDatabase.instance.unfinishItems(ids);
            await _loadProducts();
          },
        ),
      ),
    );
  }

  /// Thaws frozen food to fridge with a fresh 3-day expiry.
  Future<void> _thawToFridge(ProductItem product) async {
    final newExpiry = dateOnlyString(
      DateTime.now().add(const Duration(days: 3)),
    );
    await AppDatabase.instance.moveItemToStorage(
      productId: product.productId,
      expiryDate: product.expiryKey,
      fromLocation: StorageLocation.freezer,
      toLocation: StorageLocation.fridge,
      newExpiryDate: newExpiry,
    );
    await _loadProducts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Moved ${product.name} to Fridge 🧊 (expires in 3 days)',
        ),
      ),
    );
  }

  /// Freezes food from fridge/pantry with a 3-month expiry.
  Future<void> _freezeItem(ProductItem product) async {
    final newExpiry = dateOnlyString(
      DateTime.now().add(const Duration(days: 90)),
    );
    await AppDatabase.instance.moveItemToStorage(
      productId: product.productId,
      expiryDate: product.expiryKey,
      fromLocation: product.storageLocation,
      toLocation: StorageLocation.freezer,
      newExpiryDate: newExpiry,
    );
    await _loadProducts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Moved ${product.name} to Freezer ❄️ (expires in 3 months)',
        ),
      ),
    );
  }

  void _showAboutMeDialog() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        const slate900 = Color(0xFF1E2233);
        const slate500 = Color(0xFF6B7280);
        const indigo = Color(0xFFFF5A3C);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: indigo.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.inventory_2_rounded,
                        color: indigo,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Expired',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: slate900,
                            letterSpacing: -0.3,
                          ),
                        ),
                        _VersionText(),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Expired helps you keep track of your home-made food, '
                  'meal prep, and groceries. Keep your food organized across '
                  'Fridge, Freezer, and Pantry with zero waste.',
                  style: TextStyle(fontSize: 14, color: slate500, height: 1.5),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F7FB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined,
                          size: 20, color: Color(0xFF10B981)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Zero Data Loss: Your data is safely persisted '
                          'locally with automatic snapshot redundancy.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 4),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.language, color: slate900),
                  title: const Text('App Website'),
                  trailing: const Icon(
                    Icons.open_in_new,
                    size: 18,
                    color: slate500,
                  ),
                  onTap: () =>
                      launchUrl(Uri.parse('https://expiredapp.tiiny.site/')),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.privacy_tip_outlined,
                    color: slate900,
                  ),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(
                    Icons.open_in_new,
                    size: 18,
                    color: slate500,
                  ),
                  onTap: () => launchUrl(
                    Uri.parse(
                      'https://expiredapp.tiiny.site/privacy-policy.html',
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.description_outlined,
                    color: slate900,
                  ),
                  title: const Text('Terms of Service'),
                  trailing: const Icon(
                    Icons.open_in_new,
                    size: 18,
                    color: slate500,
                  ),
                  onTap: () => launchUrl(
                    Uri.parse(
                      'https://expiredapp.tiiny.site/terms-and-conditions.html',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    '© ${DateTime.now().year} Expired. All rights reserved.',
                    style: const TextStyle(fontSize: 11, color: slate500),
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
    final thisWeek = _products
        .where((p) => p.daysUntilExpiry >= 0 && p.daysUntilExpiry <= 7)
        .toList();
    final expired = _products.where((p) => p.daysUntilExpiry < 0).toList();

    final displayedProducts = _products.where((p) {
      final matchesExpiry = switch (_filter) {
        _DashboardFilter.thisWeek =>
          p.daysUntilExpiry >= 0 && p.daysUntilExpiry <= 7,
        _DashboardFilter.expired => p.daysUntilExpiry < 0,
        _DashboardFilter.all => true,
      };
      final matchesStorage =
          _storageFilter == null || p.storageLocation == _storageFilter;
      return matchesExpiry && matchesStorage;
    }).toList();

    const indigo = Color(0xFFFF5A3C);
    const amber = Color(0xFFF59E0B);
    const red = Color(0xFFEF4444);
    const slate900 = Color(0xFF1E2233);
    const slate500 = Color(0xFF6B7280);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expired'),
        actions: [
          // Quick add without opening camera
          IconButton(
            tooltip: 'Add food directly',
            onPressed: _quickAddFood,
            icon: const Icon(Icons.add_circle_outline_rounded, size: 24),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: indigo,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: _showAboutMeDialog,
            icon: const Icon(Icons.info_outline, size: 22),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: slate900,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Subtitle
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
              child: Text(
                'Track home-cooked meals & groceries before they expire.',
                style: TextStyle(color: slate500, fontSize: 13, height: 1.4),
              ),
            ),

            // Stat cards
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
                      onTap: () =>
                          setState(() => _filter = _DashboardFilter.all),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SummaryCard(
                      title: 'This week',
                      value: '${thisWeek.length}',
                      accent: amber,
                      icon: Icons.warning_amber_rounded,
                      isActive: _filter == _DashboardFilter.thisWeek,
                      onTap: () =>
                          setState(() => _filter = _DashboardFilter.thisWeek),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SummaryCard(
                      title: 'Expired',
                      value: '${expired.length}',
                      accent: red,
                      icon: Icons.event_busy_rounded,
                      isActive: _filter == _DashboardFilter.expired,
                      onTap: () =>
                          setState(() => _filter = _DashboardFilter.expired),
                    ),
                  ),
                ],
              ),
            ),

            // Monthly stats bar
            if (_monthStats.used > 0 || _monthStats.wasted > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: _MonthStatsBar(
                  used: _monthStats.used,
                  wasted: _monthStats.wasted,
                ),
              ),

            const SizedBox(height: 12),

            // Storage Location Segmented Bar (All | Fridge | Freezer | Pantry)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _StorageFilterChip(
                      label: 'All Storage',
                      isSelected: _storageFilter == null,
                      onSelected: () => setState(() => _storageFilter = null),
                    ),
                    const SizedBox(width: 8),
                    _StorageFilterChip(
                      label: '🧊 Fridge',
                      isSelected: _storageFilter == StorageLocation.fridge,
                      onSelected: () => setState(
                        () => _storageFilter = StorageLocation.fridge,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StorageFilterChip(
                      label: '❄️ Freezer',
                      isSelected: _storageFilter == StorageLocation.freezer,
                      onSelected: () => setState(
                        () => _storageFilter = StorageLocation.freezer,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StorageFilterChip(
                      label: '🧺 Pantry',
                      isSelected: _storageFilter == StorageLocation.pantry,
                      onSelected: () => setState(
                        () => _storageFilter = StorageLocation.pantry,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Section header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    switch (_filter) {
                      _DashboardFilter.thisWeek => 'Expiring This Week',
                      _DashboardFilter.expired => 'Expired',
                      _DashboardFilter.all => _storageFilter == null
                          ? 'All Food Items'
                          : '${StorageLocation.displayName(_storageFilter!)} Items',
                    },
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: slate900,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const Spacer(),
                  if (_filter != _DashboardFilter.all || _storageFilter != null)
                    GestureDetector(
                      onTap: () => setState(() {
                        _filter = _DashboardFilter.all;
                        _storageFilter = null;
                      }),
                      child: const Text(
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

            if (displayedProducts.isNotEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(
                  'Tap to edit · Swipe right when used · Swipe left if wasted',
                  style: TextStyle(fontSize: 11, color: slate500),
                ),
              ),

            const SizedBox(height: 10),

            // Product List
            Expanded(
              child: displayedProducts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _filter == _DashboardFilter.all
                                ? Icons.inventory_2_outlined
                                : Icons.check_circle_outline_rounded,
                            size: 52,
                            color: slate500.withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            switch (_filter) {
                              _DashboardFilter.thisWeek =>
                                'Nothing expiring this week',
                              _DashboardFilter.expired => 'Nothing expired',
                              _DashboardFilter.all => _storageFilter == null
                                  ? 'No products yet'
                                  : 'No products in ${StorageLocation.displayName(_storageFilter!)}',
                            },
                            style: const TextStyle(
                              fontSize: 15,
                              color: slate500,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (_filter == _DashboardFilter.all &&
                              _storageFilter == null) ...[
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: _scanAndAdd,
                              icon: const Icon(Icons.qr_code_scanner_rounded),
                              label: const Text('Scan your first product'),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      itemCount: displayedProducts.length,
                      itemBuilder: (context, index) {
                        final product = displayedProducts[index];
                        return Dismissible(
                          key: ValueKey(
                            '${product.productId}-${product.expiryKey}-'
                            '${product.storageLocation}-${product.quantity}',
                          ),
                          background: const _SwipeBackground(
                            color: Color(0xFF10B981),
                            icon: Icons.check_circle_rounded,
                            label: 'Used',
                            alignStart: true,
                          ),
                          secondaryBackground: const _SwipeBackground(
                            color: red,
                            icon: Icons.delete_sweep_rounded,
                            label: 'Wasted',
                            alignStart: false,
                          ),
                          confirmDismiss: (direction) async {
                            await _finishOne(
                              product,
                              direction == DismissDirection.startToEnd
                                  ? 'used'
                                  : 'wasted',
                            );
                            if (product.quantity > 1) {
                              _loadProducts();
                              return false;
                            }
                            return true;
                          },
                          onDismissed: (_) {
                            setState(() => _products.remove(product));
                            _loadProducts();
                          },
                          child: _ProductCard(
                            product: product,
                            onTap: () => _openProductSheet(product: product),
                            onThawToFridge:
                                product.storageLocation ==
                                        StorageLocation.freezer
                                    ? () => _thawToFridge(product)
                                    : null,
                            onFreeze:
                                product.storageLocation !=
                                        StorageLocation.freezer
                                    ? () => _freezeItem(product)
                                    : null,
                          ),
                        );
                      },
                    ),
            ),

            // Adaptive Bottom AdMob Banner Container
            const BottomAdBanner(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanAndAdd,
        backgroundColor: const Color(0xFFFF5A3C),
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

class _StorageFilterChip extends StatelessWidget {
  const _StorageFilterChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    const indigo = Color(0xFFFF5A3C);
    return GestureDetector(
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? indigo : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? indigo : Colors.grey.shade300,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: indigo.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF1E2233),
          ),
        ),
      ),
    );
  }
}

class _VersionText extends StatelessWidget {
  const _VersionText();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version;
        return Text(
          version == null ? '' : 'Version $version',
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        );
      },
    );
  }
}

class _MonthStatsBar extends StatelessWidget {
  const _MonthStatsBar({required this.used, required this.wasted});

  final double used;
  final double wasted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Text(
            'This month',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E2233),
            ),
          ),
          const Spacer(),
          const Icon(
            Icons.check_circle_rounded,
            size: 14,
            color: Color(0xFF10B981),
          ),
          const SizedBox(width: 4),
          Text(
            'Used ৳${used.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF10B981)),
          ),
          const SizedBox(width: 12),
          const Icon(
            Icons.delete_sweep_rounded,
            size: 14,
            color: Color(0xFFEF4444),
          ),
          const SizedBox(width: 4),
          Text(
            'Wasted ৳${wasted.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444)),
          ),
        ],
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.color,
    required this.icon,
    required this.label,
    required this.alignStart,
  });

  final Color color;
  final IconData icon;
  final String label;
  final bool alignStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: alignStart ? Alignment.centerLeft : Alignment.centerRight,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
                color: isActive ? Colors.white : const Color(0xFF1E2233),
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
                    : const Color(0xFF6B7280),
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
    required this.onTap,
    this.onThawToFridge,
    this.onFreeze,
  });

  final ProductItem product;
  final VoidCallback onTap;
  final VoidCallback? onThawToFridge;
  final VoidCallback? onFreeze;

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
            : days == 1
                ? 'Tomorrow'
                : '$days d left';

    final locEmoji = StorageLocation.emoji(product.storageLocation);
    final details = [
      '$locEmoji ${StorageLocation.displayName(product.storageLocation)}',
      'Qty ${product.quantity}',
      if (product.unitPrice > 0) '৳${product.unitPrice.toStringAsFixed(0)}',
      if (product.category != null && product.category!.isNotEmpty)
        product.category!,
    ].join('  ·  ');

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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
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
                            product.storageLocation == StorageLocation.freezer
                                ? Icons.ac_unit_rounded
                                : product.isHomemade
                                    ? Icons.soup_kitchen_rounded
                                    : Icons.inventory_2_rounded,
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
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      product.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: Color(0xFF1E2233),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (onThawToFridge != null) ...[
                                    InkWell(
                                      onTap: onThawToFridge,
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE0F2FE),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          '🧊 Thaw',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0284C7),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  _Tag(label: expiryLabel, color: accentColor),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      details,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFFCBD5E1),
                        ),
                      ],
                    ),
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

/// Opens the camera scanner. Returns the scanned code, `''` when the user
/// chose to enter details manually (only if [allowManual]), or `null` when
/// the scanner was closed.
Future<String?> showBarcodeScanner(
  BuildContext context, {
  bool allowManual = false,
}) async {
  try {
    final status = await Permission.camera.request();
    if (!context.mounted) return null;

    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera permission is required to scan barcodes.'),
        ),
      );
      return allowManual ? '' : null;
    }

    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ScannerSheet(allowManual: allowManual),
    );
  } catch (_) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unable to open the scanner right now.')),
    );
    return allowManual ? '' : null;
  }
}

class _ScannerSheet extends StatefulWidget {
  const _ScannerSheet({required this.allowManual});

  final bool allowManual;

  @override
  State<_ScannerSheet> createState() => _ScannerSheetState();
}

class _ScannerSheetState extends State<_ScannerSheet> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final value = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (value == null || value.isEmpty) return;
    _handled = true;
    _controller.stop();
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
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
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
              ),
            ),
            if (widget.allowManual)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(''),
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('No barcode? Enter manually'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Quick expiry options tailored for fridge vs freezer
const _fridgeExpiryOptions = <({String label, int days})>[
  (label: '2 days', days: 2),
  (label: '3 days', days: 3),
  (label: '5 days', days: 5),
  (label: '1 week', days: 7),
  (label: '2 weeks', days: 14),
  (label: '1 month', days: 30),
];

const _freezerExpiryOptions = <({String label, int days})>[
  (label: '1 month', days: 30),
  (label: '2 months', days: 60),
  (label: '3 months', days: 90),
  (label: '6 months', days: 180),
  (label: '1 year', days: 365),
];

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String _formatPrice(double price) {
  if (price == 0) return '';
  return price == price.roundToDouble()
      ? price.toStringAsFixed(0)
      : price.toString();
}

class ProductForm extends StatefulWidget {
  const ProductForm({
    required this.onSave,
    this.product,
    this.initialBarcode,
    this.initialLocation,
    this.onDelete,
    super.key,
  });

  final Future<void> Function() onSave;
  final ProductItem? product;
  final String? initialBarcode;
  final String? initialLocation;
  final Future<void> Function()? onDelete;

  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  late final TextEditingController barcodeController;
  late final TextEditingController nameController;
  late final TextEditingController priceController;
  late final TextEditingController quantityController;
  TextEditingController? categoryController;
  List<CategoryRecord> _categories = const [];
  bool _isLoadingCategories = true;
  bool _isSaving = false;
  bool _isLookingUpOnline = false;
  String? _loadError;
  late DateTime expiryDate;
  late String storageLocation;
  bool isHomemade = true;

  late final FocusNode barcodeFocusNode;
  late final FocusNode nameFocusNode;
  FocusNode? categoryFocusNode;
  late final FocusNode priceFocusNode;
  late final FocusNode quantityFocusNode;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    final product = widget.product;
    final barcode = product?.barcode ?? widget.initialBarcode ?? '';
    barcodeController = TextEditingController(
      text: barcode.startsWith(_localBarcodePrefix) ? '' : barcode,
    );
    nameController = TextEditingController(text: product?.name ?? '');
    priceController = TextEditingController(
      text: product == null ? '' : _formatPrice(product.unitPrice),
    );
    quantityController = TextEditingController(
      text: product?.quantity.toString() ?? '1',
    );

    storageLocation = product?.storageLocation ??
        widget.initialLocation ??
        StorageLocation.fridge;
    isHomemade = product?.isHomemade ?? true;

    final expiry = product?.expiryDate;
    expiryDate = expiry != null
        ? DateTime(expiry.year, expiry.month, expiry.day)
        : _today().add(
            Duration(days: storageLocation == StorageLocation.freezer ? 90 : 7),
          );

    barcodeFocusNode = FocusNode();
    nameFocusNode = FocusNode();
    priceFocusNode = FocusNode();
    quantityFocusNode = FocusNode();

    if (product == null && barcode.isNotEmpty) {
      _applyBarcodeInfo(barcode);
    }
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _categories = const [];
        _isLoadingCategories = false;
        _loadError = 'Unable to load categories right now.';
      });
    }
  }

  /// Checks local DB first; if not found, automatically queries Open Food Facts API!
  Future<void> _applyBarcodeInfo(String barcode) async {
    try {
      // 1. Local database lookup
      final record = await AppDatabase.instance.findProductByBarcode(barcode);
      if (!mounted) return;
      if (record != null) {
        final categoryId = record.categoryId;
        final category = categoryId == null
            ? null
            : await AppDatabase.instance.getCategoryById(categoryId);
        if (!mounted) return;
        setState(() {
          nameController.text = record.name;
          priceController.text = _formatPrice(record.price);
          storageLocation = record.defaultLocation;
          isHomemade = record.isHomemade == 1;
          if (category != null) categoryController?.text = category.name;
          final shelfDays = record.defaultShelfDays;
          if (shelfDays != null && shelfDays > 0) {
            expiryDate = _today().add(Duration(days: shelfDays));
          }
        });
        return;
      }

      // 2. Open Food Facts Online Lookup for new products
      setState(() => _isLookingUpOnline = true);
      final onlineResult = await BarcodeService.instance.lookupOnline(barcode);
      if (!mounted) return;
      setState(() => _isLookingUpOnline = false);

      if (onlineResult != null) {
        setState(() {
          nameController.text = onlineResult.name;
          isHomemade = false; // scanned grocery product
          if (onlineResult.category != null) {
            categoryController?.text = onlineResult.category!;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Found: ${onlineResult.name} ✨'),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        nameFocusNode.requestFocus();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLookingUpOnline = false);
        nameFocusNode.requestFocus();
      }
    }
  }

  @override
  void dispose() {
    barcodeController.dispose();
    nameController.dispose();
    priceController.dispose();
    quantityController.dispose();
    barcodeFocusNode.dispose();
    nameFocusNode.dispose();
    priceFocusNode.dispose();
    quantityFocusNode.dispose();
    super.dispose();
  }

  Future<void> _openBarcodeScanner() async {
    final code = await showBarcodeScanner(context);
    if (code == null || code.isEmpty || !mounted) return;
    barcodeController.text = code;
    await _applyBarcodeInfo(code);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text(
          'This removes all ${widget.product!.quantity} unit(s) of '
          '${widget.product!.name} from ${StorageLocation.displayName(widget.product!.storageLocation)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.onDelete?.call();
    }
  }

  Future<void> _save() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a product name.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final enteredBarcode = barcodeController.text.trim();
      final barcode = enteredBarcode.isNotEmpty
          ? enteredBarcode
          : widget.product?.barcode ??
              '$_localBarcodePrefix${DateTime.now().microsecondsSinceEpoch}';
      final price = double.tryParse(priceController.text) ?? 0.0;
      final quantity = int.tryParse(quantityController.text) ?? 1;
      final categoryName = categoryController?.text.trim() ?? '';
      final category = _categories
          .where(
            (item) => item.name.toLowerCase() == categoryName.toLowerCase(),
          )
          .firstOrNull;
      final shelfDays = expiryDate.difference(_today()).inDays;

      final existingProduct = await AppDatabase.instance.findProductByBarcode(
        barcode,
      );
      final productId = await AppDatabase.instance.upsertProduct(
        ProductRecord(
          id: existingProduct?.id,
          barcode: barcode,
          name: name,
          price: price,
          categoryId: category?.id,
          defaultLocation: storageLocation,
          isHomemade: isHomemade ? 1 : 0,
          defaultShelfDays: shelfDays > 0
              ? shelfDays
              : existingProduct?.defaultShelfDays,
          createdAt:
              existingProduct?.createdAt ?? DateTime.now().toIso8601String(),
        ),
      );

      final original = widget.product;
      if (original != null) {
        await AppDatabase.instance.deleteItemsByProductAndExpiry(
          original.productId,
          original.expiryKey,
          storageLocation: original.storageLocation,
        );
      }

      final now = DateTime.now();
      final purchaseDate = original?.purchaseDate ?? now;
      for (int i = 0; i < quantity; i++) {
        await AppDatabase.instance.insertItem(
          InventoryItemRecord(
            productId: productId,
            categoryId: category?.id,
            purchaseDate: purchaseDate.toIso8601String(),
            entryDate: now.toIso8601String(),
            expiryDate: dateOnlyString(expiryDate),
            storageLocation: storageLocation,
            cookedDate: isHomemade ? now.toIso8601String() : null,
            portionCount: 1,
            isHomemade: isHomemade ? 1 : 0,
            finished: 0,
            createdAt: now.toIso8601String(),
          ),
        );
      }

      await widget.onSave();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const indigo = Color(0xFFFF5A3C);
    const slate900 = Color(0xFF1E2233);
    const slate500 = Color(0xFF6B7280);
    final today = _today();
    final pickerFirstDate = expiryDate.isBefore(today) ? expiryDate : today;
    final quickOptions = storageLocation == StorageLocation.freezer
        ? _freezerExpiryOptions
        : _fridgeExpiryOptions;

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
              const Spacer(),
              if (_isLookingUpOnline)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(
              widget.product == null
                  ? 'Record home-cooked meals, meal prep, or scanned foods.'
                  : 'Update saved food details.',
              style: const TextStyle(color: slate500, fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),

          // Storage Location Selector (Fridge | Freezer | Pantry)
          const Text(
            'Storage Location',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: slate900,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final loc in StorageLocation.all) ...[
                Expanded(
                  child: ChoiceChip(
                    label: Center(
                      child: Text(
                        '${StorageLocation.emoji(loc)} ${StorageLocation.displayName(loc)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: storageLocation == loc
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    selected: storageLocation == loc,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          storageLocation = loc;
                          // Default expiry adjustment
                          if (loc == StorageLocation.freezer) {
                            expiryDate = today.add(const Duration(days: 90));
                          } else if (loc == StorageLocation.pantry) {
                            expiryDate = today.add(const Duration(days: 14));
                          } else {
                            expiryDate = today.add(const Duration(days: 4));
                          }
                        });
                      }
                    },
                  ),
                ),
                if (loc != StorageLocation.all.last) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 14),

          // Product Name
          TextField(
            controller: nameController,
            focusNode: nameFocusNode,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => priceFocusNode.requestFocus(),
            decoration: InputDecoration(
              labelText: 'Food / Product name',
              hintText: 'e.g. Lentil Soup, Cooked Chicken, Lasagna',
              border: const OutlineInputBorder(),
              suffixIcon: _isLookingUpOnline
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 12),

          // Expiry options
          Row(
            children: [
              Text(
                'Expires in (${StorageLocation.displayName(storageLocation)})',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: slate900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in quickOptions)
                ChoiceChip(
                  label: Text(option.label),
                  selected:
                      expiryDate == today.add(Duration(days: option.days)),
                  onSelected: (_) => setState(
                    () => expiryDate = today.add(Duration(days: option.days)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: expiryDate,
                  firstDate: pickerFirstDate,
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(
                    () => expiryDate = DateTime(
                      picked.year,
                      picked.month,
                      picked.day,
                    ),
                  );
                  categoryFocusNode?.requestFocus();
                }
              },
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text('Custom Expiry: ${dateOnlyString(expiryDate)}'),
            ),
          ),
          const SizedBox(height: 12),

          // Barcode (Optional)
          TextField(
            controller: barcodeController,
            focusNode: barcodeFocusNode,
            onSubmitted: (val) {
              if (val.isNotEmpty) _applyBarcodeInfo(val);
              nameFocusNode.requestFocus();
            },
            decoration: InputDecoration(
              labelText: 'Barcode (optional for store-bought)',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Scan barcode to auto-fill name',
                onPressed: _openBarcodeScanner,
                icon: const Icon(Icons.qr_code_scanner_rounded),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Category
          Autocomplete<String>(
            initialValue: TextEditingValue(
              text: widget.product?.category ?? '',
            ),
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
              categoryFocusNode = focusNode;
              return TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Leftovers, Meal Prep, Soups',
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // Price & Quantity / Portions
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: priceController,
                  focusNode: priceFocusNode,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onSubmitted: (_) => quantityFocusNode.requestFocus(),
                  decoration: const InputDecoration(
                    labelText: 'Cost / Price (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                              final current =
                                  int.tryParse(quantityController.text) ?? 1;
                              if (current > 1) {
                                setState(() {
                                  quantityController.text =
                                      (current - 1).toString();
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
                              final current =
                                  int.tryParse(quantityController.text) ?? 1;
                              setState(() {
                                quantityController.text =
                                    (current + 1).toString();
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

          // Save button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF5A3C),
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
              onPressed: _isLoadingCategories || _isSaving ? null : _save,
              icon: const Icon(Icons.save_alt),
              label: Text(
                widget.product == null ? 'Save product' : 'Update product',
              ),
            ),
          ),
          if (widget.onDelete != null) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _isSaving ? null : _confirmDelete,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                ),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete product'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Prefix for ids generated for products saved without a barcode.
const _localBarcodePrefix = 'local-';

class ProductItem {
  ProductItem({
    required this.productId,
    required this.barcode,
    required this.name,
    required this.purchaseDate,
    required this.expiryKey,
    required this.expiryDate,
    required this.unitPrice,
    required this.quantity,
    this.category,
    this.storageLocation = StorageLocation.fridge,
    this.cookedDate,
    this.portionCount = 1,
    this.isHomemade = true,
    this.notes,
  });

  final int productId;
  final String barcode;
  final String name;
  final String? category;
  final DateTime purchaseDate;
  final String expiryKey;
  final DateTime expiryDate;
  final double unitPrice;
  final int quantity;
  final String storageLocation;
  final DateTime? cookedDate;
  final int portionCount;
  final bool isHomemade;
  final String? notes;

  int get daysUntilExpiry {
    final now = DateTime.now();
    return DateTime.utc(
      expiryDate.year,
      expiryDate.month,
      expiryDate.day,
    ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
  }
}
