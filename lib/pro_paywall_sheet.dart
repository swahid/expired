import 'package:expired/subscription_service.dart';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shows the Expired Pro paywall sheet.
Future<void> showProPaywall(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _ProPaywallSheet(),
  );
}

class _ProPaywallSheet extends StatefulWidget {
  const _ProPaywallSheet();

  @override
  State<_ProPaywallSheet> createState() => _ProPaywallSheetState();
}

class _ProPaywallSheetState extends State<_ProPaywallSheet> {
  bool _isLoading = true;
  bool _isPurchasing = false;
  Offerings? _offerings;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    final offerings = await SubscriptionService.instance.getOfferings();
    if (!mounted) return;
    setState(() {
      _offerings = offerings;
      _isLoading = false;
    });
  }

  Future<void> _buy(Package package) async {
    setState(() => _isPurchasing = true);
    final success = await SubscriptionService.instance.purchasePackage(package);
    if (!mounted) return;
    setState(() => _isPurchasing = false);

    if (success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Welcome to Expired Pro! 🎉 Unlimited entries & ad-free.'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }
  }

  Future<void> _restore() async {
    setState(() => _isPurchasing = true);
    final success = await SubscriptionService.instance.restorePurchases();
    if (!mounted) return;
    setState(() => _isPurchasing = false);

    if (success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Purchases restored successfully! 🎉'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active subscription found to restore.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const indigo = Color(0xFFFF5A3C);
    const slate900 = Color(0xFF1E2233);
    const slate500 = Color(0xFF6B7280);

    final currentOffering = _offerings?.current;
    final packages = currentOffering?.availablePackages ?? const [];
    final monthlyPackage = packages.where(
      (p) => p.packageType == PackageType.monthly,
    ).firstOrNull ?? packages.firstOrNull;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Crown Badge
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF7A59), Color(0xFFFF5A3C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: indigo.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.stars_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: 14),

              const Text(
                'Expired Pro Monthly',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: slate900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Ad-free experience & unlimited food tracking.',
                textAlign: TextAlign.center,
                style: TextStyle(color: slate500, fontSize: 13),
              ),
              const SizedBox(height: 18),

              // Monthly Subscription Hero Card ($9.99/mo)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: indigo, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: indigo.withValues(alpha: 0.1),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pro Membership',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: slate900,
                              ),
                            ),
                            Text(
                              'Auto-renewing subscription',
                              style: TextStyle(fontSize: 12, color: slate500),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: indigo.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            monthlyPackage?.storeProduct.priceString ?? '\$9.99 / mo',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: indigo,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                    const _CheckBenefitRow(text: '100% Ad-Free (no bottom banners or popups)'),
                    const SizedBox(height: 8),
                    const _CheckBenefitRow(text: 'Unlimited Food & Meal Prep entries'),
                    const SizedBox(height: 8),
                    const _CheckBenefitRow(text: 'Zero Data Loss Redundancy Backup'),
                    const SizedBox(height: 8),
                    const _CheckBenefitRow(text: 'Unlimited Fridge, Freezer & Pantry storage'),
                    const SizedBox(height: 18),

                    // Primary Action Button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _isPurchasing
                            ? null
                            : () {
                                if (monthlyPackage != null) {
                                  _buy(monthlyPackage);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please configure your RevenueCat API key and Google Play product to complete live purchase.',
                                      ),
                                    ),
                                  );
                                }
                              },
                        icon: _isPurchasing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.flash_on_rounded),
                        label: Text(
                          _isPurchasing
                              ? 'Processing...'
                              : 'Subscribe Now · ${monthlyPackage?.storeProduct.priceString ?? '\$9.99/mo'}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Additional packages if configured (e.g. Annual or Lifetime)
              if (packages.length > 1) ...[
                for (final pkg in packages.where((p) => p != monthlyPackage)) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _isPurchasing ? null : () => _buy(pkg),
                      child: Text(
                        '${pkg.storeProduct.title} (${pkg.storeProduct.priceString})',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
              ],

              // Restore Purchases
              TextButton(
                onPressed: _isPurchasing ? null : _restore,
                child: const Text(
                  'Restore Purchases',
                  style: TextStyle(
                    color: slate500,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // Terms & Privacy
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => launchUrl(
                      Uri.parse('https://expiredapp.tiiny.site/terms-and-conditions.html'),
                    ),
                    child: const Text(
                      'Terms of Service',
                      style: TextStyle(fontSize: 11, color: slate500),
                    ),
                  ),
                  const Text('  ·  ', style: TextStyle(color: slate500)),
                  GestureDetector(
                    onTap: () => launchUrl(
                      Uri.parse('https://expiredapp.tiiny.site/privacy-policy.html'),
                    ),
                    child: const Text(
                      'Privacy Policy',
                      style: TextStyle(fontSize: 11, color: slate500),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Cancel anytime in Google Play Store subscriptions.',
                style: TextStyle(fontSize: 10, color: slate500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckBenefitRow extends StatelessWidget {
  const _CheckBenefitRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            color: Color(0xFFE0F2FE),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            color: Color(0xFF0284C7),
            size: 14,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E2233),
            ),
          ),
        ),
      ],
    );
  }
}
