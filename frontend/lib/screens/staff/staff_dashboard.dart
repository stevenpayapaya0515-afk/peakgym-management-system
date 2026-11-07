import 'package:flutter/material.dart';

import '../../core/services/api_service.dart';
import '../../core/storage/token_storage.dart';
import '../../core/theme/app_theme.dart';
import '../admin/monthly_members.dart';
import '../auth/login_screen.dart';
import 'staff_settings.dart';

class StaffDashboard extends StatefulWidget {
  const StaffDashboard({super.key});

  @override
  State<StaffDashboard> createState() => _StaffDashboardState();
}

class _StaffDashboardState extends State<StaffDashboard> {
  Map<String, dynamic>? _summary;

  String _selectedPage = 'Dashboard';
  bool _loading = true;
  bool _logoutOpen = false;
  String? _error;
  bool _accessDenied = false;

  String get _username {
    final user = _summary?['user'];

    if (user is Map) {
      return user['username']?.toString() ?? 'Staff';
    }

    return 'Staff';
  }

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = await TokenStorage.getToken();

      if (token == null || token.isEmpty) {
        if (!mounted) return;

        setState(() {
          _accessDenied = true;
          _error = 'Your session has expired. Please log in again.';
          _loading = false;
        });
        return;
      }

      final response = await ApiService.get(
        '/dashboard/staff-summary',
        token: token,
      );

      if (!mounted) return;

      final status = response['status_code'];

      if (status != 200) {
        setState(() {
          _accessDenied = status == 401 || status == 403;
          _error = response['detail']?.toString() ??
              'Unable to load your dashboard.';
          _loading = false;
        });
        return;
      }

      final user = response['user'];

      if (user is! Map || user['role'] != 'staff') {
        setState(() {
          _accessDenied = true;
          _error = 'This dashboard is for staff accounts.';
          _loading = false;
        });
        return;
      }

      setState(() {
        _summary = response;
        _accessDenied = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Unable to connect to the server. Please try again.';
        _loading = false;
      });
    }
  }

  int _number(String key) {
    return (_summary?[key] as num?)?.toInt() ?? 0;
  }

  String _asOf() {
    final date = DateTime.tryParse(
      _summary?['as_of']?.toString() ?? '',
    );

    if (date == null) return '';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    return 'As of, ${months[date.month - 1]} ${date.day} ${date.year}';
  }

  void _selectPage(String page) {
    const pages = [
      'Dashboard',
      'Monthly Members',
      'Settings',
    ];

    if (!pages.contains(page)) return;
    if (_accessDenied || _summary == null) return;
    if (_selectedPage == page) return;

    setState(() => _selectedPage = page);

    if (page == 'Dashboard') {
      _loadDashboard();
    }
  }

  Future<void> _logout() async {
    if (_logoutOpen) return;

    _logoutOpen = true;
    bool confirmed = false;

    try {
      confirmed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            barrierColor: Colors.black.withValues(alpha: 0.70),
            builder: (_) => const _StaffLogoutDialog(),
          ) ??
          false;
    } finally {
      _logoutOpen = false;
    }

    if (!confirmed || !mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  ButtonStyle _logoutStyle() {
    bool highlighted(Set<WidgetState> states) {
      return states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused) ||
          states.contains(WidgetState.pressed);
    }

    return ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith<Color>(
        (states) => highlighted(states)
            ? AppTheme.errorColor
            : AppTheme.secondaryText,
      ),
      backgroundColor: WidgetStateProperty.resolveWith<Color>(
        (states) => highlighted(states)
            ? AppTheme.errorColor.withValues(alpha: 0.10)
            : Colors.transparent,
      ),
      side: WidgetStateProperty.resolveWith<BorderSide>(
        (states) => BorderSide(
          color: highlighted(states)
              ? AppTheme.errorColor
              : AppTheme.borderColor,
        ),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  Widget _brand() {
    return Row(
      children: [
        Image.asset(
          'assets/logo_peak.png',
          width: 75,
          height: 75,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 5),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PEAKGYM',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              SizedBox(height: 7),
              Text(
                'MANAGEMENT SYSTEM',
                style: TextStyle(
                  color: AppTheme.secondaryText,
                  fontSize: 8,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _navigationItem(String title, IconData icon) {
    final active = _selectedPage == title;
    final enabled = !_accessDenied && _summary != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: active
            ? AppTheme.primaryGreen.withValues(alpha: 0.08)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(
            color: active
                ? AppTheme.primaryGreen.withValues(alpha: 0.25)
                : Colors.transparent,
          ),
        ),
        child: InkWell(
          onTap: enabled ? () => _selectPage(title) : null,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            child: Row(
              children: [
                if (active) ...[
                  Container(
                    width: 3,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 11),
                ],
                Icon(
                  icon,
                  size: 18,
                  color: active
                      ? AppTheme.primaryText
                      : AppTheme.secondaryText,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: active
                          ? AppTheme.primaryText
                          : AppTheme.secondaryText,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
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

  Widget _account() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: AppTheme.borderColor),
        const SizedBox(height: 16),
        Row(
          children: [
            const CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.inputBackground,
              child: Icon(
                Icons.person_outline,
                size: 18,
                color: AppTheme.secondaryText,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _username,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'PeakGym Staff',
                    style: TextStyle(
                      color: AppTheme.secondaryText,
                      fontSize: 10,
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
          height: 44,
          child: OutlinedButton.icon(
            onPressed: _logout,
            style: _logoutStyle(),
            icon: const Icon(Icons.logout, size: 16),
            label: const Text(
              'LOG OUT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sidebar() {
    return Container(
      width: 245,
      decoration: const BoxDecoration(
        color: AppTheme.cardBackground,
        border: Border(
          right: BorderSide(color: AppTheme.borderColor),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 30,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      children: [
                        _brand(),
                        const SizedBox(height: 20),
                        const Divider(color: AppTheme.borderColor),
                        const SizedBox(height: 30),
                        _navigationItem(
                          'Dashboard',
                          Icons.dashboard_outlined,
                        ),
                        _navigationItem(
                          'Monthly Members',
                          Icons.card_membership_outlined,
                        ),
                        _navigationItem(
                          'Settings',
                          Icons.settings_outlined,
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 30),
                      child: _account(),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _mobileHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.cardBackground,
        border: Border(
          bottom: BorderSide(color: AppTheme.borderColor),
        ),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/logo_peak.png',
            width: 45,
            height: 45,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'PEAKGYM',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Staff navigation',
            enabled: !_accessDenied && _summary != null,
            initialValue: _selectedPage,
            onSelected: _selectPage,
            icon: const Icon(Icons.menu_rounded),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'Dashboard',
                child: Text('Dashboard'),
              ),
              PopupMenuItem(
                value: 'Monthly Members',
                child: Text('Monthly Members'),
              ),
              PopupMenuItem(
                value: 'Settings',
                child: Text('Settings'),
              ),
            ],
          ),
          IconButton(
            onPressed: _logout,
            tooltip: 'Log out',
            style: _logoutStyle(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
    );
  }

  Widget _statCard(
    String title,
    String key,
    String description,
    Color valueColor,
  ) {
    return Container(
      constraints: const BoxConstraints(minHeight: 175),
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 26,
      ),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.primaryGreen,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.3,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _number(key).toString(),
            style: TextStyle(
              color: valueColor,
              fontSize: 40,
              fontWeight: FontWeight.bold,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            description,
            style: const TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 11,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _overview() {
    final cards = [
      _statCard(
        'TOTAL MEMBERS',
        'total_members',
        'All registered members',
        AppTheme.primaryText,
      ),
      _statCard(
        'ACTIVE MEMBERSHIPS',
        'active_memberships',
        'Valid for a workout today',
        AppTheme.primaryGreen,
      ),
      _statCard(
        'EXPIRING TODAY',
        'expiring_today',
        'Current period ends today',
        AppTheme.accentYellow,
      ),
      _statCard(
        'EXPIRED MEMBERSHIPS',
        'expired_memberships',
        'Ended with no upcoming renewal',
        AppTheme.errorColor,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 500
            ? 1
            : constraints.maxWidth < 900
                ? 2
                : 4;

        final width =
            (constraints.maxWidth - 16 * (columns - 1)) / columns;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (constraints.maxWidth < 500) ...[
              const Text(
                'Membership overview',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _asOf(),
                  style: const TextStyle(
                    color: AppTheme.secondaryText,
                    fontSize: 12,
                  ),
                ),
              ),
            ] else
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Membership overview',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    _asOf(),
                    style: const TextStyle(
                      color: AppTheme.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final card in cards)
                  SizedBox(width: width, child: card),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _errorState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            color: AppTheme.errorColor,
            size: 32,
          ),
          const SizedBox(height: 14),
          Text(
            _error ?? 'Unable to load your dashboard.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.secondaryText,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
          ),
          if (_accessDenied)
            TextButton(
              onPressed: _logout,
              child: const Text('Log out'),
            ),
        ],
      ),
    );
  }

  Widget _mainContent(bool mobile) {
    if (!_accessDenied &&
        _summary != null &&
        _selectedPage == 'Settings') {
      return const StaffSettings();
    }
    if (!_accessDenied &&
        _summary != null &&
        _selectedPage == 'Monthly Members') {
      return MonthlyMembers(
        onChanged: _loadDashboard,
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(mobile ? 22 : 42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dashboard',
            style: TextStyle(
              fontSize: mobile ? 32 : 42,
              fontWeight: FontWeight.bold,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your PeakGym staff workspace.',
            style: TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 13,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 28),
          const Divider(color: AppTheme.borderColor),
          const SizedBox(height: 30),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            _errorState()
          else ...[
            Text(
              'Welcome, $_username',
              style: TextStyle(
                fontSize: mobile ? 25 : 32,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'View your membership overview below.',
              style: TextStyle(
                color: AppTheme.secondaryText,
                fontSize: 13,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 40),
            _overview(),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mobile = constraints.maxWidth <= 750;

            return Row(
              children: [
                if (!mobile) _sidebar(),
                Expanded(
                  child: Column(
                    children: [
                      if (mobile) _mobileHeader(),
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned(
                              left: -150,
                              top: 100,
                              width: 480,
                              height: 480,
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      colors: [
                                        AppTheme.primaryGreen.withValues(
                                          alpha: 0.10,
                                        ),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: _mainContent(mobile),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StaffLogoutDialog extends StatefulWidget {
  const _StaffLogoutDialog();

  @override
  State<_StaffLogoutDialog> createState() => _StaffLogoutDialogState();
}

class _StaffLogoutDialogState extends State<_StaffLogoutDialog> {
  bool _saving = false;
  String? _error;

  Future<void> _confirm() async {
    if (_saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await TokenStorage.deleteToken();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _saving = false;
        _error = 'Unable to log out. Please try again.';
      });
      return;
    }

    if (!mounted) return;

    setState(() => _saving = false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: const BorderSide(color: AppTheme.borderColor),
        ),
        title: const Text(
          'Log out?',
          style: TextStyle(
            color: AppTheme.errorColor,
            fontSize: 23,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: SizedBox(
          width: 344,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Are you sure you want to log out of PeakGym?',
                style: TextStyle(
                  color: AppTheme.secondaryText,
                  height: 1.7,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: AppTheme.errorColor),
                ),
              ],
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        actions: [
          OutlinedButton(
            onPressed: _saving
                ? null
                : () => Navigator.pop(context, false),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryText,
              minimumSize: const Size(80, 44),
              side: const BorderSide(color: AppTheme.borderColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _saving ? null : _confirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.black,
              minimumSize: const Size(112, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_error == null ? 'Log out' : 'Retry'),
          ),
        ],
      ),
    );
  }
}