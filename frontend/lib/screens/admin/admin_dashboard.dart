import 'package:flutter/material.dart';

import '../../core/services/api_service.dart';
import '../../core/storage/token_storage.dart';
import '../../core/theme/app_theme.dart';
import '../auth/login_screen.dart';
import 'staff_management.dart';
import 'monthly_members.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  Map<String, dynamic>? _summary;

  String _selectedPage = 'Dashboard';
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = await TokenStorage.getToken();

      if (token == null || token.isEmpty) {
        throw Exception(
          'Your session has expired. Please log in again.',
        );
      }

      final response = await ApiService.get(
        '/dashboard/admin-summary',
        token: token,
      );

      if (response['status_code'] != 200) {
        throw Exception(
          response['detail']?.toString() ??
              'Unable to load dashboard information.',
        );
      }

      if (!mounted) return;

      setState(() {
        _summary = response;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.70),
      builder: (dialogContext) {
        bool loggingOut = false;
        String? errorMessage;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return PopScope(
              canPop: !loggingOut,
              child: AlertDialog(
                backgroundColor: AppTheme.cardBackground,
                surfaceTintColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                  side: const BorderSide(
                    color: AppTheme.borderColor,
                  ),
                ),
                titlePadding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
                contentPadding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
                actionsPadding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
                actionsOverflowButtonSpacing: 10,
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
                          fontSize: 13,
                          height: 1.7,
                        ),
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 14),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(
                              color: AppTheme.errorColor,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  OutlinedButton(
                    onPressed: loggingOut
                        ? null
                        : () => Navigator.pop(dialogContext, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryText,
                      minimumSize: const Size(80, 44),
                      side: const BorderSide(
                        color: AppTheme.borderColor,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: loggingOut
                        ? null
                        : () async {
                            setDialogState(() {
                              loggingOut = true;
                              errorMessage = null;
                            });

                            try {
                              await TokenStorage.deleteToken();

                              if (!dialogContext.mounted) return;

                              setDialogState(() {
                                loggingOut = false;
                              });

                              WidgetsBinding.instance
                                  .addPostFrameCallback((_) {
                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext, true);
                                }
                              });
                            } catch (_) {
                              if (!dialogContext.mounted) return;

                              setDialogState(() {
                                loggingOut = false;
                                errorMessage =
                                    'Unable to log out. Please try again.';
                              });
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.errorColor,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: AppTheme.errorColor,
                      disabledForegroundColor: Colors.black54,
                      minimumSize: const Size(112, 44),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    child: loggingOut
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Text(
                            errorMessage == null ? 'Log out' : 'Retry',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
      (route) => false,
    );
  }

  ButtonStyle _logoutButtonStyle() {
    return ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(80, 44)),
      foregroundColor: WidgetStateProperty.resolveWith<Color>(
        (states) {
          final highlighted = states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused) ||
              states.contains(WidgetState.pressed);

          return highlighted
              ? AppTheme.errorColor
              : AppTheme.secondaryText;
        },
      ),
      backgroundColor: WidgetStateProperty.resolveWith<Color>(
        (states) {
          final highlighted = states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused) ||
              states.contains(WidgetState.pressed);

          return highlighted
              ? AppTheme.errorColor.withValues(alpha: 0.10)
              : Colors.transparent;
        },
      ),
      side: WidgetStateProperty.resolveWith<BorderSide>(
        (states) {
          final highlighted = states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused) ||
              states.contains(WidgetState.pressed);

          return BorderSide(
            color: highlighted
                ? AppTheme.errorColor
                : AppTheme.borderColor,
          );
        },
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  void _selectPage(String page) {
    const availablePages = [
      'Dashboard',
      'Staff Management',
      'Monthly Members',
    ];

    if (!availablePages.contains(page) || page == _selectedPage) {
      return;
    }

    setState(() {
      _selectedPage = page;
    });
  }

  int _number(String key) {
    return (_summary?[key] as num?)?.toInt() ?? 0;
  }

  String _formattedAsOf() {
    final rawDate = _summary?['as_of']?.toString();

    if (rawDate == null || rawDate.isEmpty) return '';

    final date = DateTime.tryParse(rawDate);

    if (date == null) return '';

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return 'As of, ${months[date.month - 1]} ${date.day} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth <= 750;

            return Row(
              children: [
                if (!isMobile) _buildSidebar(),
                Expanded(
                  child: Column(
                    children: [
                      if (isMobile) _buildMobileHeader(),
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
                                      stops: const [0, 1],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: _buildMainContent(isMobile),
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

  Widget _buildSidebar() {
    return Container(
      width: 245,
      decoration: const BoxDecoration(
        color: AppTheme.cardBackground,
        border: Border(
          right: BorderSide(
            color: AppTheme.borderColor,
          ),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        _buildBrand(),
                        const SizedBox(height: 40),
                        _buildNavigationItem(
                          Icons.dashboard_outlined,
                          'Dashboard',
                        ),
                        _buildNavigationItem(
                          Icons.people_outline,
                          'Staff Management',
                        ),
                        _buildNavigationItem(
                          Icons.card_membership_outlined,
                          'Monthly Members',
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 30),
                      child: _buildAccountProfile(),
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

  Widget _buildBrand() {
    return Container(
      padding: const EdgeInsets.only(bottom: 20),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppTheme.borderColor,
          ),
        ),
      ),
      child: Row(
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
                    color: AppTheme.primaryText,
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
      ),
    );
  }

  Widget _buildNavigationItem(
    IconData icon,
    String label,
  ) {
    final isActive = _selectedPage == label;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isActive
            ? AppTheme.primaryGreen.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: isActive ? null : () => _selectPage(label),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isActive
                    ? AppTheme.primaryGreen.withValues(alpha: 0.25)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                if (isActive)
                  Container(
                    width: 3,
                    height: 24,
                    margin: const EdgeInsets.only(right: 11),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                Icon(
                  icon,
                  size: 18,
                  color: isActive
                      ? AppTheme.primaryText
                      : AppTheme.secondaryText,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isActive
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

  Widget _buildAccountProfile() {
    return Column(
      children: [
        const Divider(color: AppTheme.borderColor),
        const SizedBox(height: 15),
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.inputBackground,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.borderColor,
                ),
              ),
              child: const Icon(
                Icons.person_outline,
                size: 17,
                color: AppTheme.secondaryText,
              ),
            ),
            const SizedBox(width: 9),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Administrator',
                    style: TextStyle(
                      color: AppTheme.primaryText,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'PeakGym Administrator',
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
            style: _logoutButtonStyle(),
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

  Widget _buildMobileHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 15,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.cardBackground,
        border: Border(
          bottom: BorderSide(
            color: AppTheme.borderColor,
          ),
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
                color: AppTheme.primaryText,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Admin navigation',
            initialValue: _selectedPage,
            icon: const Icon(
              Icons.menu_rounded,
              color: AppTheme.primaryText,
            ),
            onSelected: _selectPage,
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'Dashboard',
                child: Text('Dashboard'),
              ),
              PopupMenuItem<String>(
                value: 'Staff Management',
                child: Text('Staff Management'),
              ),
              PopupMenuItem<String>(
                value: 'Monthly Members',
                child: Text('Monthly Members'),
              ),
            ],
          ),
          IconButton(
            onPressed: _logout,
            tooltip: 'Log out',
            style: _logoutButtonStyle(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(bool isMobile) {
    if (_selectedPage == 'Monthly Members') {
      return MonthlyMembers(
        onChanged: _loadDashboard,
      );
    }

    if (_selectedPage == 'Staff Management') {
      return StaffManagement(
        onChanged: _loadDashboard,
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 22 : 42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageHeader(),
          const SizedBox(height: 30),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(60),
                child: CircularProgressIndicator(
                  color: AppTheme.primaryGreen,
                ),
              ),
            )
          else if (_errorMessage != null)
            _buildErrorState()
          else ...[
            _buildStaffOverview(),
            const SizedBox(height: 35),
            _buildMembershipOverview(),
          ],
        ],
      ),
    );
  }

  Widget _buildPageHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 28),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0x15FFFFFF),
          ),
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dashboard',
            style: TextStyle(
              color: AppTheme.primaryText,
              fontSize: 42,
              fontWeight: FontWeight.bold,
              letterSpacing: -1.5,
              height: 1.1,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Your PeakGym staff and membership overview.',
            style: TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 13,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeading(
          'Staff overview',
          trailing: TextButton(
            onPressed: () => _selectPage('Staff Management'),
            style: TextButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: AppTheme.background,
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 13,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: const Text(
              'VIEW STAFF ACCOUNTS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _buildStatGrid(
          columns: 3,
          cards: [
            _buildStatCard(
              'TOTAL STAFF',
              _number('total_staff'),
              'All registered staff accounts',
            ),
            _buildStatCard(
              'ACTIVE STAFF',
              _number('active_staff'),
              'Staff accounts with active access',
              valueColor: AppTheme.primaryGreen,
            ),
            _buildStatCard(
              'INACTIVE STAFF',
              _number('inactive_staff'),
              'Deactivated staff accounts',
              valueColor: AppTheme.accentYellow,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMembershipOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeading(
          'Membership overview',
          trailing: Text(
            _formattedAsOf(),
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 18),
        _buildStatGrid(
          columns: 4,
          cards: [
            _buildStatCard(
              'TOTAL MEMBERS',
              _number('total_members'),
              'All registered members',
            ),
            _buildStatCard(
              'ACTIVE MEMBERSHIPS',
              _number('active_memberships'),
              'Valid for a workout today',
              valueColor: AppTheme.primaryGreen,
            ),
            _buildStatCard(
              'EXPIRING TODAY',
              _number('expiring_today'),
              'Current period ends today',
              valueColor: AppTheme.accentYellow,
            ),
            _buildStatCard(
              'EXPIRED MEMBERSHIPS',
              _number('expired_memberships'),
              'Ended with no upcoming renewal',
              valueColor: AppTheme.errorColor,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionHeading(
    String title, {
    required Widget trailing,
  }) {
    final heading = Text(
      title,
      style: const TextStyle(
        color: AppTheme.primaryText,
        fontSize: 18,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.4,
      ),
    );

    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 500) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: trailing,
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: heading),
              const SizedBox(width: 16),
              trailing,
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatGrid({
    required int columns,
    required List<Widget> cards,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 16.0;

        final int actualColumns;

        if (constraints.maxWidth < 500) {
          actualColumns = 1;
        } else if (constraints.maxWidth < 900) {
          actualColumns = 2;
        } else {
          actualColumns = columns;
        }

        final cardWidth =
            (constraints.maxWidth - spacing * (actualColumns - 1)) /
                actualColumns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards)
              SizedBox(
                width: cardWidth,
                child: card,
              ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(
    String label,
    int number,
    String note, {
    Color valueColor = AppTheme.primaryText,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 175),
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 26,
      ),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        border: Border.all(
          color: AppTheme.borderColor,
        ),
        borderRadius: BorderRadius.circular(7),
        boxShadow: const [
          BoxShadow(
            color: Color(0x20000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
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
            number.toString(),
            style: TextStyle(
              color: valueColor,
              fontSize: 40,
              fontWeight: FontWeight.bold,
              letterSpacing: -1,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            note,
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

  Widget _buildErrorState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        border: Border.all(
          color: AppTheme.borderColor,
        ),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            color: AppTheme.errorColor,
            size: 35,
          ),
          const SizedBox(height: 15),
          const Text(
            'Unable to load dashboard',
            style: TextStyle(
              color: AppTheme.primaryText,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'An unexpected error occurred.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _loadDashboard,
            icon: const Icon(
              Icons.refresh,
              size: 17,
            ),
            label: const Text('TRY AGAIN'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: AppTheme.background,
            ),
          ),
        ],
      ),
    );
  }
}