import 'package:atta/src/features/auth/passwordless_screen.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

Future<bool> promptGuestAuth(BuildContext context) async {
  final enter = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    showDragHandle: true,
    builder: (sheetContext) => const GuestAuthSheet(),
  );

  if (!context.mounted) return false;
  if (enter == true) {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        settings: const RouteSettings(name: 'web-auth-prompt'),
        builder: (_) => const PasswordlessScreen(
          returnToPreviousAfterAuth: true,
        ),
      ),
    );
  }

  if (!context.mounted) return false;
  return context.read<AuthService>().isAuthenticated;
}

@Deprecated('Use promptGuestAuth instead.')
Future<bool> promptWebGuestAuth(BuildContext context) =>
    promptGuestAuth(context);

class GuestAuthSheet extends StatelessWidget {
  const GuestAuthSheet({super.key});

  static final Uri _appStoreUrl =
      Uri.parse('https://apps.apple.com/us/app/atta/id6762604298');
  static final Uri _googlePlayUrl = Uri.parse(
    'https://play.google.com/store/apps/details?id=online.attomarket.atta',
  );

  void _openAuth(BuildContext context) {
    Navigator.of(context).pop(true);
  }

  Future<void> _openStore(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final sheetHeight = (screenHeight * 0.56).clamp(360.0, 520.0);

    return SafeArea(
      top: false,
      child: SizedBox(
        key: const ValueKey('guest_auth_sheet'),
        height: sheetHeight,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              tooltip: 'Закрыть',
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close),
                            ),
                          ),
                          const Spacer(),
                          SizedBox(
                            height: 56,
                            child: Image.asset(
                              'assets/branding/atta_logo.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Войдите, чтобы пользоваться всеми возможностями Атта',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 22),
                          FilledButton(
                            onPressed: () => _openAuth(context),
                            child: const Text('Войти'),
                          ),
                          if (kIsWeb) ...[
                            const SizedBox(height: 12),
                            Divider(color: theme.colorScheme.outlineVariant),
                            const SizedBox(height: 12),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                _StoreBadgeButton(
                                  icon: Icons.apple,
                                  label: 'App Store',
                                  onPressed: () => _openStore(_appStoreUrl),
                                ),
                                _StoreBadgeButton(
                                  icon: Icons.shop,
                                  label: 'Google Play',
                                  onPressed: () => _openStore(_googlePlayUrl),
                                ),
                              ],
                            ),
                          ],
                          const Spacer(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StoreBadgeButton extends StatelessWidget {
  const _StoreBadgeButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }
}
