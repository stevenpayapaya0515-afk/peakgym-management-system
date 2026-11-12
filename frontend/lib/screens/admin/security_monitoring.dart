import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/api_service.dart';
import '../../core/storage/token_storage.dart';
import '../../core/theme/app_theme.dart';

/// Read-only, admin-only security activity viewer.
/// Access control is enforced by FastAPI, not by this widget.
class SecurityMonitoring extends StatefulWidget {
  const SecurityMonitoring({super.key});

  @override
  State<SecurityMonitoring> createState() => _SecurityMonitoringState();
}

class _SecurityMonitoringState extends State<SecurityMonitoring> {
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  String? _refreshedAt;
  DateTime _lastUserInteraction = DateTime.now();
  Timer? _refreshTimer;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _activities = [];
  List<Map<String, dynamic>> _flags = [];
  List<Map<String, dynamic>> _hours = [];
  List<Map<String, dynamic>> _topIps = [];
  List<String> _eventTypes = [];
  final _usernameController = TextEditingController();
  final _ipController = TextEditingController();
  String _usernameFilter = '';
  String _ipFilter = '';
  String? _eventFilter;
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    _loadSecurityData();
    // Poll without blanking the dashboard. Still checked by FastAPI for admin access.
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      // Background polling must not keep an otherwise idle session alive.
      // The enclosing IdleSessionGuard will log the user out on inactivity.
      if (mounted && !_loading && !_refreshing &&
          DateTime.now().difference(_lastUserInteraction) <
              const Duration(seconds: 30)) {
        _loadSecurityData(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _usernameController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  String _dateString(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _overviewEndpoint() {
    final params = <String, String>{'limit': '50'};
    if (_eventFilter != null) params['event_type'] = _eventFilter!;
    if (_usernameFilter.isNotEmpty) params['username'] = _usernameFilter;
    if (_ipFilter.isNotEmpty) params['ip_address'] = _ipFilter;
    if (_dateRange != null) {
      params['from_date'] = _dateString(_dateRange!.start);
      params['to_date'] = _dateString(_dateRange!.end);
    }
    return '/security-monitoring/overview?${Uri(queryParameters: params).query}';
  }

  Future<void> _loadSecurityData({bool silent = false}) async {
    if (!mounted || _refreshing) return;
    setState(() {
      if (silent) {
        _refreshing = true;
      } else {
        _loading = true;
      }
      _error = null;
    });

    try {
      final token = await TokenStorage.getToken();
      if (token == null || token.isEmpty) {
        throw Exception('Your session has expired. Please log in again.');
      }

      final response = await ApiService.get(
        _overviewEndpoint(),
        token: token,
      ).timeout(const Duration(seconds: 15));

      if (response['status_code'] != 200) {
        if (response['status_code'] == 401) {
          throw Exception('Session expired. Please log in again.');
        }
        if (response['status_code'] == 403) {
          throw Exception('Administrator access is required.');
        }
        throw Exception(
          response['detail']?.toString() ??
              'Unable to load security monitoring data.',
        );
      }

      final rawSummary = response['summary'];
      final rawActivities = response['recent_activities'];
      final rawFlags = response['security_flags'];
      final rawHours = response['hourly_failures'];
      final rawIps = response['top_ips'];
      final rawTypes = response['event_types'];

      if (rawSummary is! Map || rawActivities is! List) {
        throw Exception('Unexpected response from the security service.');
      }

      final parsedActivities = <Map<String, dynamic>>[];
      for (final item in rawActivities) {
        if (item is Map) {
          parsedActivities.add(Map<String, dynamic>.from(item));
        }
      }

      final parsedFlags = <Map<String, dynamic>>[];
      if (rawFlags is List) {
        for (final item in rawFlags) {
          if (item is Map) {
            parsedFlags.add(Map<String, dynamic>.from(item));
          }
        }
      }

      List<Map<String, dynamic>> asMapList(dynamic values) {
        if (values is! List) return [];
        return values.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }

      if (!mounted) return;
      setState(() {
        _flags = parsedFlags;
        _summary = Map<String, dynamic>.from(rawSummary);
        _activities = parsedActivities;
        _hours = asMapList(rawHours);
        _topIps = asMapList(rawIps);
        _eventTypes = rawTypes is List ? rawTypes.whereType<String>().toList() : [];
        _refreshedAt = response['refreshed_at']?.toString();
        _loading = false;
        _refreshing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
        _refreshing = false;
      });
    }
  }

  int? _count(String key) => (_summary[key] as num?)?.toInt();

  String _display(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '—' : text;
  }

  // Timestamps are shown as saved by the backend (server time).
  // Avoid silently interpreting MySQL's naive timestamps as device-local time.
  String _timestamp(dynamic value) {
    final text = _display(value);
    if (text == '—') return text;
    return text.replaceFirst('T', ' ').split('.').first;
  }

  Color _eventColor(String event) {
    switch (event) {
      case 'login_success':
        return AppTheme.primaryGreen;
      case 'account_locked':
      case 'login_otp_limit':
        return AppTheme.errorColor;
      case 'login_otp_failed':
      case 'login_otp_expired':
      case 'login_failed':
        return AppTheme.accentYellow;
      default:
        return AppTheme.secondaryText;
    }
  }

  String _eventLabel(String event) {
    switch (event) {
      case 'login_success': return 'Login success';
      case 'login_failed': return 'Failed login';
      case 'account_locked': return 'Account lockout';
      case 'login_otp_failed': return 'Incorrect OTP';
      case 'login_otp_expired': return 'Expired OTP';
      case 'login_otp_limit': return 'OTP limit reached';
      default: return event.replaceAll('_', ' ');
    }
  }

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
      color: AppTheme.cardBackground,
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: AppTheme.borderColor),
    );
  }

  Widget _metricCard({
    required String label,
    required int? count,
    required IconData icon,
    required Color accent,
    required String hint,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.primaryGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .6,
                  ),
                ),
              ),
              Icon(icon, size: 18, color: accent),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            count?.toString() ?? '—',
            style: TextStyle(
              color: accent,
              fontSize: 36,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            style: const TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetrics() {
    final metrics = <Widget>[
      _metricCard(
        label: 'Successful logins today', count: _count('successful_logins'),
        icon: Icons.verified_user_outlined, accent: AppTheme.primaryGreen,
        hint: 'Password and Gmail OTP verified',
      ),
      _metricCard(
        label: 'Failed logins today', count: _count('failed_logins'),
        icon: Icons.person_off_outlined, accent: AppTheme.errorColor,
        hint: 'Incorrect passwords recorded',
      ),
      _metricCard(
        label: 'Accounts locked now', count: _count('accounts_locked_now'),
        icon: Icons.lock_clock_outlined, accent: AppTheme.accentYellow,
        hint: 'Current account lockout state',
      ),
      _metricCard(
        label: 'IPs blocked now', count: _count('blocked_ips_now'),
        icon: Icons.block_outlined, accent: AppTheme.secondaryText,
        hint: 'Not tracked until IP blocking is implemented',
      ),
      _metricCard(
        label: 'OTPs sent today', count: _count('otp_sent'),
        icon: Icons.mark_email_read_outlined, accent: AppTheme.primaryGreen,
        hint: 'Sent-OTP event logging is not connected yet',
      ),
      _metricCard(
        label: 'Incorrect OTPs today', count: _count('otp_failures'),
        icon: Icons.password_outlined, accent: AppTheme.accentYellow,
        hint: 'Recorded OTP verification failures',
      ),
      _metricCard(
        label: 'Alert emails sent today', count: _count('alert_emails_sent'),
        icon: Icons.notifications_active_outlined, accent: AppTheme.secondaryText,
        hint: 'Alert-sent events are not tracked yet',
      ),
      _metricCard(
        label: 'OTP limits today', count: _count('otp_limits'),
        icon: Icons.gpp_bad_outlined, accent: AppTheme.errorColor,
        hint: 'Maximum incorrect code attempts',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cols = width >= 950 ? 4 : (width >= 560 ? 2 : 1);
        const gap = 14.0;
        final cardWidth = (width - (cols - 1) * gap) / cols;
        return Wrap(
          spacing: gap, runSpacing: gap,
          children: metrics.map((card) => SizedBox(width: cardWidth, child: card)).toList(),
        );
      },
    );
  }

  Widget _sectionHeading(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(
          color: AppTheme.primaryText, fontSize: 22, fontWeight: FontWeight.w700,
        )),
        const SizedBox(height: 8),
        Text(subtitle, style: const TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
      ],
    );
  }

  Widget _buildHourlyChart() {
    if (_hours.isEmpty) {
      return Container(
        width: double.infinity, padding: const EdgeInsets.all(24),
        decoration: _panelDecoration(),
        child: const Text('No hourly statistics available.',
          style: TextStyle(color: AppTheme.secondaryText)),
      );
    }
    final peak = _hours.map((e) => (e['failed_logins'] as num?)?.toInt() ?? 0)
        .fold<int>(1, (a, b) => a > b ? a : b);
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(20),
      decoration: _panelDecoration(),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final hour in _hours)
              SizedBox(
                width: 47,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${(hour['failed_logins'] as num?)?.toInt() ?? 0}',
                      style: const TextStyle(color: AppTheme.primaryText, fontSize: 11)),
                    const SizedBox(height: 5),
                    SizedBox(
                      height: 108,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: 24,
                          height: (((hour['failed_logins'] as num?)?.toDouble() ?? 0) / peak * 102)
                              .clamp(3.0, 102.0).toDouble(),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(hour['label']?.toString().substring(0, 2) ?? '--',
                      style: const TextStyle(color: AppTheme.secondaryText, fontSize: 10)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopIps() {
    if (_topIps.isEmpty) {
      return Container(
        width: double.infinity, padding: const EdgeInsets.all(24),
        decoration: _panelDecoration(),
        child: const Text('No failed-login IP addresses in the last 24 hours.',
          style: TextStyle(color: AppTheme.secondaryText)),
      );
    }
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Column(children: [
        for (final ip in _topIps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(children: [
              Expanded(flex: 3, child: Text(_display(ip['ip_address']),
                style: const TextStyle(color: AppTheme.primaryText, fontSize: 13))),
              Expanded(child: Text('${ip['failures'] ?? 0} failed',
                style: const TextStyle(color: AppTheme.errorColor, fontSize: 12))),
              Expanded(flex: 2, child: Text(_display(ip['block_status']),
                textAlign: TextAlign.end,
                style: const TextStyle(color: AppTheme.secondaryText, fontSize: 12))),
            ]),
          ),
      ]),
    );
  }

  Future<void> _selectDateRange() async {
    final now = DateTime.now();
    final selection = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020), lastDate: now,
      initialDateRange: _dateRange,
      helpText: 'Filter security activity dates',
    );
    if (!mounted || selection == null) return;
    setState(() => _dateRange = selection);
  }

  Widget _buildFilters() {
    final selectedType = _eventFilter != null && _eventTypes.contains(_eventFilter)
        ? _eventFilter! : '';
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: Wrap(
        spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              key: ValueKey(selectedType),
              initialValue: selectedType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Event type'),
              items: [
                const DropdownMenuItem(value: '', child: Text('All events')),
                for (final event in _eventTypes)
                  DropdownMenuItem(value: event, child: Text(
                    _eventLabel(event), overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (value) => setState(
                () => _eventFilter = value == null || value.isEmpty ? null : value),
            ),
          ),
          SizedBox(width: 185, child: TextField(
            controller: _usernameController,
            decoration: const InputDecoration(labelText: 'Username contains'),
            onChanged: (_) => _lastUserInteraction = DateTime.now(),
            onSubmitted: (_) => _applyFilters(),
          )),
          SizedBox(width: 170, child: TextField(
            controller: _ipController,
            decoration: const InputDecoration(labelText: 'IP address contains'),
            onChanged: (_) => _lastUserInteraction = DateTime.now(),
            onSubmitted: (_) => _applyFilters(),
          )),
          OutlinedButton.icon(
            onPressed: _selectDateRange,
            icon: const Icon(Icons.date_range_outlined, size: 17),
            label: Text(_dateRange == null ? 'Date range' :
              '${_dateString(_dateRange!.start)} to ${_dateString(_dateRange!.end)}'),
          ),
          OutlinedButton(
            onPressed: _loading ? null : _applyFilters,
            child: const Text('APPLY'),
          ),
          TextButton(
            onPressed: _loading ? null : _clearFilters,
            child: const Text('CLEAR'),
          ),
        ],
      ),
    );
  }

  void _applyFilters() {
    setState(() {
      _usernameFilter = _usernameController.text.trim();
      _ipFilter = _ipController.text.trim();
    });
    _loadSecurityData();
  }

  void _clearFilters() {
    _usernameController.clear();
    _ipController.clear();
    setState(() {
      _usernameFilter = '';
      _ipFilter = '';
      _eventFilter = null;
      _dateRange = null;
    });
    _loadSecurityData();
  }

  Widget _eventBadge(String event) {
    final color = _eventColor(event);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Text(
        _eventLabel(event),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  // Fixed, consistent column widths keep headings and values aligned.
  // On smaller windows the table scrolls horizontally rather than squeezing.
  Widget _tableHeaderCell(String label) {
    return Container(
      height: 52,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        label,
        maxLines: 1,
        style: const TextStyle(
          color: AppTheme.primaryText,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: .3,
        ),
      ),
    );
  }

  Widget _tableBodyCell(Widget child) {
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: child,
    );
  }

  Widget _tableText(String text, {bool bold = false}) {
    return Tooltip(
      message: text,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppTheme.primaryText,
          fontSize: 12,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildEventTable() {
    if (_activities.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(35),
        decoration: _panelDecoration(),
        child: const Text(
          'No security activities match the current filters.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.secondaryText),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Fill the entire desktop panel. Use horizontal scrolling on mobile.
        final tableWidth = constraints.maxWidth < 970
            ? 970.0
            : constraints.maxWidth;

        return Container(
          width: double.infinity,
          decoration: _panelDecoration(),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Table(
                columnWidths: const {
                  0: FixedColumnWidth(155),
                  1: FixedColumnWidth(185),
                  2: FixedColumnWidth(135),
                  3: FlexColumnWidth(),
                  4: FixedColumnWidth(190),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                border: const TableBorder(
                  horizontalInside: BorderSide(
                    color: AppTheme.borderColor,
                    width: .7,
                  ),
                ),
                children: [
                  TableRow(
                    decoration: const BoxDecoration(
                      color: AppTheme.inputBackground,
                    ),
                    children: [
                      _tableHeaderCell('EVENT'),
                      _tableHeaderCell('USERNAME'),
                      _tableHeaderCell('IP ADDRESS'),
                      _tableHeaderCell('DETAILS'),
                      _tableHeaderCell('SERVER TIME'),
                    ],
                  ),
                  for (var i = 0; i < _activities.length; i++)
                    TableRow(
                      decoration: BoxDecoration(
                        color: i.isEven
                            ? AppTheme.cardBackground
                            : const Color(0xFF171C1F),
                      ),
                      children: [
                        _tableBodyCell(
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _eventBadge(
                              _display(_activities[i]['event_type']),
                            ),
                          ),
                        ),
                        _tableBodyCell(_tableText(
                          _display(_activities[i]['username']),
                          bold: true,
                        )),
                        _tableBodyCell(_tableText(
                          _display(_activities[i]['ip_address']),
                        )),
                        _tableBodyCell(_tableText(
                          _display(_activities[i]['details']),
                        )),
                        _tableBodyCell(_tableText(
                          _timestamp(_activities[i]['created_at']),
                        )),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSecurityFlags() {
    if (_flags.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: _panelDecoration(),
        child: const Text(
          'No monitoring flags recorded yet. Run the backend monitor script to scan the last 24 hours.',
          style: TextStyle(color: AppTheme.secondaryText, fontSize: 12),
        ),
      );
    }

    return Column(
      children: [
        for (final flag in _flags)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: _panelDecoration(),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _display(flag['severity']).toUpperCase() == 'HIGH'
                          ? AppTheme.errorColor.withValues(alpha: .15)
                          : AppTheme.accentYellow.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      _display(flag['severity']),
                      style: TextStyle(
                        color: _display(flag['severity']).toUpperCase() == 'HIGH'
                            ? AppTheme.errorColor
                            : AppTheme.accentYellow,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    _display(flag['pattern']).replaceAll('_', ' '),
                    style: const TextStyle(
                      color: AppTheme.primaryText,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    _display(flag['target']),
                    style: const TextStyle(color: AppTheme.primaryGreen, fontSize: 12),
                  ),
                  Text(
                    _display(flag['description']),
                    style: const TextStyle(color: AppTheme.secondaryText, fontSize: 12),
                  ),
                  Text(
                    _display(flag['flag_date']),
                    style: const TextStyle(color: AppTheme.secondaryText, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRefreshButton() {
    return OutlinedButton.icon(
      onPressed: _loading || _refreshing ? null : _loadSecurityData,
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('REFRESH'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryGreen,
        minimumSize: const Size(120, 42),
        side: const BorderSide(color: AppTheme.borderColor),
      ),
    );
  }

  Widget _buildStatusAndRefreshRow() {
    final statusLabel = Row(
      children: const [
        Icon(Icons.shield_outlined, color: AppTheme.primaryGreen, size: 18),
        SizedBox(width: 8),
        Flexible(
          child: Text(
            'Read-only  •  Admin access  •  Today (PHT)',
            style: TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              statusLabel,
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: _buildRefreshButton(),
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: statusLabel),
            const SizedBox(width: 16),
            _buildRefreshButton(),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _lastUserInteraction = DateTime.now(),
      onPointerHover: (_) => _lastUserInteraction = DateTime.now(),
      onPointerMove: (_) => _lastUserInteraction = DateTime.now(),
      child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth <= 750;
        return SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 22 : 42),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Security Monitoring',
                style: TextStyle(
                  color: AppTheme.primaryText,
                  fontSize: compact ? 30 : 40,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Review recorded login activity and security events.',
                style: TextStyle(
                  color: AppTheme.secondaryText,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),
              const Divider(color: AppTheme.borderColor),
              const SizedBox(height: 18),
              _buildStatusAndRefreshRow(),
              if (_refreshedAt != null) ...[
                const SizedBox(height: 7),
                Text('Last updated: ${_timestamp(_refreshedAt)} PHT  •  Auto-refresh every 60 seconds while active',
                  style: const TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
              ],
              const SizedBox(height: 22),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(65),
                    child: CircularProgressIndicator(color: AppTheme.primaryGreen),
                  ),
                )
              else if (_error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: _panelDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_error!, style: const TextStyle(color: AppTheme.errorColor)),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: _loadSecurityData,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else ...[
                _buildMetrics(),
                const SizedBox(height: 32),
                _sectionHeading('Failed Logins per Hour',
                  'Last 24 hours, Philippine time. Scroll horizontally to inspect every hour.'),
                const SizedBox(height: 16),
                _buildHourlyChart(),
                const SizedBox(height: 32),
                _sectionHeading('Top 5 IP Addresses',
                  'Most failed login attempts in the past 24 hours. IP blocking is not yet enforced.'),
                const SizedBox(height: 16),
                _buildTopIps(),
                const SizedBox(height: 32),
                const Text(
                  'Detected Security Flags',
                  style: TextStyle(
                    color: AppTheme.primaryText,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Findings from the last manual monitoring scan. No editing or deleting.',
                  style: TextStyle(color: AppTheme.secondaryText, fontSize: 12),
                ),
                const SizedBox(height: 16),
                _buildSecurityFlags(),
                const SizedBox(height: 32),
                const Text(
                  'Recent Security Activity',
                  style: TextStyle(
                    color: AppTheme.primaryText,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Latest 50 recorded events. Scroll horizontally to see all columns.',
                  style: TextStyle(color: AppTheme.secondaryText, fontSize: 12),
                ),
                const SizedBox(height: 16),
                _buildFilters(),
                const SizedBox(height: 16),
                _buildEventTable(),
              ],
            ],
          ),
        );
      },
      ),
    );
  }
}
