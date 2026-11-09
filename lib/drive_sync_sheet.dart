import 'package:expired/drive_sync_service.dart';
import 'package:flutter/material.dart';

/// Shows the Google Drive Cloud Sync bottom sheet.
Future<void> showDriveSyncSheet(BuildContext context, {VoidCallback? onDataRestored}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _DriveSyncSheet(onDataRestored: onDataRestored),
  );
}

class _DriveSyncSheet extends StatefulWidget {
  const _DriveSyncSheet({this.onDataRestored});

  final VoidCallback? onDataRestored;

  @override
  State<_DriveSyncSheet> createState() => _DriveSyncSheetState();
}

class _DriveSyncSheetState extends State<_DriveSyncSheet> {
  bool _isProcessing = false;
  String? _statusMessage;

  Future<void> _backup() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Connecting to Google Drive...';
    });

    final res = await DriveSyncService.instance.backupToDrive();
    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      _statusMessage = res.message;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.message),
        backgroundColor: res.success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
      ),
    );
  }

  Future<void> _restore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from Google Drive?'),
        content: const Text(
          'This will import your saved food data from Google Drive and merge it with your local records.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF5A3C)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restore Data'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Downloading backup from Google Drive...';
    });

    final res = await DriveSyncService.instance.restoreFromDrive();
    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      _statusMessage = res.message;
    });

    if (res.success) {
      widget.onDataRestored?.call();
      Navigator.of(context).pop();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.message),
        backgroundColor: res.success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const indigo = Color(0xFFFF5A3C);
    const slate900 = Color(0xFF1E2233);
    const slate500 = Color(0xFF6B7280);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: ValueListenableBuilder(
            valueListenable: DriveSyncService.instance.currentUser,
            builder: (context, user, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Handle
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Drive Icon
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.cloud_sync_rounded,
                      color: Color(0xFF0284C7),
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 12),

                  const Text(
                    'Google Drive Sync',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: slate900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Zero Data Loss · 100% Private to your Google account',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: slate500, fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  // Privacy Guarantee Box
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F7FB),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.security_rounded,
                          color: Color(0xFF10B981),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your data is stored exclusively in your personal Google Drive AppData folder. '
                            'The app developer has zero access to your food records or files.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade800,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  if (user == null) ...[
                    // Not signed in
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _isProcessing
                            ? null
                            : () => DriveSyncService.instance.signIn(),
                        icon: const Icon(Icons.account_circle_outlined),
                        label: const Text(
                          'Sign in with Google',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Signed in user card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: indigo.withValues(alpha: 0.1),
                            child: Text(
                              user.displayName?.isNotEmpty == true
                                  ? user.displayName![0].toUpperCase()
                                  : 'G',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: indigo,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.displayName ?? 'Google Account',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: slate900,
                                  ),
                                ),
                                Text(
                                  user.email,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: slate500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Sign out',
                            icon: const Icon(Icons.logout_rounded, size: 20),
                            onPressed: _isProcessing
                                ? null
                                : () => DriveSyncService.instance.signOut(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Backup Button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _isProcessing ? null : _backup,
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.cloud_upload_outlined),
                        label: const Text(
                          'Back Up to Google Drive Now',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Restore Button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _isProcessing ? null : _restore,
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const Text(
                          'Restore Data from Drive',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],

                  if (_statusMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _statusMessage!,
                      style: const TextStyle(fontSize: 12, color: slate500),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

