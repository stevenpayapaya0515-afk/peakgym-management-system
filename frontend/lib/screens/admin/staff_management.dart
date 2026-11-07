import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/services/staff_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/action_feedback.dart';

BoxDecoration _staffPanelDecoration() {
  return BoxDecoration(
    color: AppTheme.cardBackground,
    borderRadius: BorderRadius.circular(7),
    border: Border.all(color: AppTheme.borderColor),
  );
}

InputDecoration _staffInputDecoration({String? hint}) {
  OutlineInputBorder border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(
      color: AppTheme.secondaryText,
      fontSize: 12,
    ),
    filled: true,
    fillColor: AppTheme.inputBackground,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 17,
    ),
    border: border(AppTheme.borderColor),
    enabledBorder: border(AppTheme.borderColor),
    disabledBorder: border(AppTheme.borderColor),
    focusedBorder: border(AppTheme.primaryGreen, 1.5),
    errorBorder: border(AppTheme.errorColor),
    focusedErrorBorder: border(AppTheme.errorColor, 1.5),
    errorMaxLines: 2,
  );
}

Widget _staffPrimaryButton({
  required String label,
  required VoidCallback? onPressed,
  bool loading = false,
  bool destructive = false,
  IconData? icon,
}) {
  return DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      color: destructive ? AppTheme.errorColor : null,
      gradient: destructive
          ? null
          : const LinearGradient(
              colors: [
                AppTheme.primaryGreen,
                AppTheme.accentYellow,
              ],
            ),
    ),
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.background,
        disabledForegroundColor: Colors.black54,
        minimumSize: const Size(80, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.background,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                ],
                Text(label),
              ],
            ),
    ),
  );
}

Widget _staffCancelButton(VoidCallback? onPressed) {
  return OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: AppTheme.primaryText,
      minimumSize: const Size(80, 44),
      side: const BorderSide(color: AppTheme.borderColor),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      textStyle: const TextStyle(fontSize: 12),
    ),
    child: const Text('Cancel'),
  );
}

Widget _staffPageHeader(bool compact) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Staff Management',
        style: TextStyle(
          color: AppTheme.primaryText,
          fontSize: compact ? 30 : 40,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Create staff accounts and manage their access.',
        style: TextStyle(
          color: AppTheme.secondaryText,
          fontSize: 13,
          height: 1.6,
        ),
      ),
      const SizedBox(height: 24),
      const Divider(color: AppTheme.borderColor),
      const SizedBox(height: 24),
    ],
  );
}

class StaffManagement extends StatefulWidget {
  const StaffManagement({
    super.key,
    required this.onChanged,
  });

  final Future<void> Function() onChanged;

  @override
  State<StaffManagement> createState() => _StaffManagementState();
}

class _StaffManagementState extends State<StaffManagement> {
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _staff = [];
  bool _loading = true;
  bool _creatingAccount = false;
  bool _dialogOpen = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStaff() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final staff = await StaffService.getStaff();

      if (!mounted) return;

      setState(() {
        _staff = staff;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _refreshAfterChange() async {
    await _loadStaff();

    if (!mounted) return;

    await widget.onChanged();
  }

  Future<void> _openDialog({
    required Map<String, dynamic> user,
    bool delete = false,
  }) async {
    if (_dialogOpen) return;

    setState(() => _dialogOpen = true);

    try {
      final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.70),
        builder: (_) => _StaffAccountDialog(
          user: user,
          delete: delete,
        ),
      );

      if (!mounted || changed != true) return;

      await _refreshAfterChange();
    } finally {
      if (mounted) {
        setState(() => _dialogOpen = false);
      }
    }
  }

  Future<void> _created() async {
    if (!mounted) return;

    setState(() => _creatingAccount = false);

    await _refreshAfterChange();
  }

  bool _isActive(Map<String, dynamic> user) {
    return user['is_active'] == true || user['is_active'] == 1;
  }

  Widget _status(Map<String, dynamic> user) {
    final active = _isActive(user);
    final color = active
        ? AppTheme.primaryGreen
        : AppTheme.accentYellow;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        active ? 'Active' : 'Inactive',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _actions(Map<String, dynamic> user) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      children: [
        TextButton.icon(
          onPressed: _dialogOpen
              ? null
              : () => _openDialog(user: user),
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: const Text('Edit'),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.primaryGreen,
          ),
        ),
        TextButton.icon(
          onPressed: _dialogOpen
              ? null
              : () => _openDialog(user: user, delete: true),
          icon: const Icon(Icons.delete_outline, size: 16),
          label: const Text('Delete'),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.errorColor,
          ),
        ),
      ],
    );
  }

  Widget _searchField() {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(
          color: AppTheme.primaryText,
          fontSize: 12,
        ),
        decoration: _staffInputDecoration(
          hint: 'Search username or email...',
        ).copyWith(
          prefixIcon: const Icon(
            Icons.search,
            size: 18,
            color: AppTheme.secondaryText,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _createButton() {
    return _staffPrimaryButton(
      label: 'Create staff account',
      icon: Icons.person_add_alt_1,
      onPressed: _loading || _dialogOpen
          ? null
          : () {
              setState(() => _creatingAccount = true);
            },
    );
  }

  Widget _toolbar(bool compact) {
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _searchField(),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: _createButton(),
          ),
        ],
      );
    }

    return Row(
      children: [
        SizedBox(width: 340, child: _searchField()),
        const Spacer(),
        _createButton(),
      ],
    );
  }

  Widget _table(List<Map<String, dynamic>> users) {
    return Container(
      width: double.infinity,
      decoration: _staffPanelDecoration(),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: constraints.maxWidth,
              ),
              child: DataTable(
                dividerThickness: 1,
                border: const TableBorder(
                  horizontalInside: BorderSide(
                    color: AppTheme.borderColor,
                  ),
                ),
                columnSpacing: 26,
                horizontalMargin: 22,
                headingRowHeight: 52,
                dataRowMinHeight: 64,
                dataRowMaxHeight: 76,
                headingTextStyle: const TextStyle(
                  color: AppTheme.secondaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                columns: const [
                  DataColumn(label: Text('Username')),
                  DataColumn(label: Text('Email')),
                  DataColumn(label: Text('Status')),
                  DataColumn(
                    label: Expanded(
                      child: Center(child: Text('Actions')),
                    ),
                  ),
                ],
                rows: users.map((user) {
                  return DataRow(
                    cells: [
                      DataCell(Text(user['username'].toString())),
                      DataCell(
                        Text((user['email'] ?? '').toString()),
                      ),
                      DataCell(_status(user)),
                      DataCell(Center(child: _actions(user))),
                    ],
                  );
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _mobileCards(List<Map<String, dynamic>> users) {
    return Column(
      children: users.map((user) {
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(18),
          decoration: _staffPanelDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user['username'].toString(),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                (user['email'] ?? '').toString(),
                style: const TextStyle(
                  color: AppTheme.secondaryText,
                ),
              ),
              const SizedBox(height: 12),
              _status(user),
              const SizedBox(height: 10),
              _actions(user),
            ],
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_creatingAccount) {
      return _CreateStaffPanel(
        onCancel: () {
          setState(() => _creatingAccount = false);
        },
        onCreated: _created,
      );
    }

    final query = _searchController.text.trim().toLowerCase();

    final filtered = _staff.where((user) {
      final username = user['username'].toString().toLowerCase();
      final email = (user['email'] ?? '').toString().toLowerCase();

      return username.contains(query) || email.contains(query);
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;

        return SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 22 : 42),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _staffPageHeader(compact),
              _toolbar(compact),
              const SizedBox(height: 24),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: _staffPanelDecoration(),
                  child: Column(
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.errorColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _loadStaff,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else if (filtered.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(30),
                  decoration: _staffPanelDecoration(),
                  child: Text(
                    query.isEmpty
                        ? 'No staff accounts yet. Create one to get started.'
                        : 'No staff accounts match your search.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.secondaryText,
                    ),
                  ),
                )
              else if (compact)
                _mobileCards(filtered)
              else
                _table(filtered),
            ],
          ),
        );
      },
    );
  }
}

class _StaffAccountDialog extends StatefulWidget {
  const _StaffAccountDialog({
    required this.user,
    this.delete = false,
  });

  final Map<String, dynamic> user;
  final bool delete;

  @override
  State<_StaffAccountDialog> createState() =>
      _StaffAccountDialogState();
}

class _StaffAccountDialogState extends State<_StaffAccountDialog> {
  late bool _active;
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    _active = widget.user['is_active'] == true ||
        widget.user['is_active'] == 1;
  }

  Future<void> _save() async {
    if (_saving) return;

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final success = await ActionFeedback.run(
      context: context,
      actionKey: widget.delete ? 'staff-delete' : 'staff-status',
      loadingMessage: widget.delete
          ? 'Deleting the staff account...'
          : 'Updating staff access...',
      successMessage: widget.delete
          ? 'Staff account deleted successfully.'
          : 'Staff status updated successfully.',
      action: () async {
        final id = (widget.user['id'] as num).toInt();

        if (widget.delete) {
          await StaffService.deleteStaff(id);
        } else {
          await StaffService.changeStatus(id, _active);
        }
      },
    );

    if (!mounted) return;

    setState(() => _saving = false);

    if (success) {
      // Let PopScope rebuild before closing this dialog.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: const BorderSide(color: AppTheme.borderColor),
        ),
        titlePadding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
        contentPadding: const EdgeInsets.fromLTRB(28, 14, 28, 0),
        actionsPadding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
        actionsAlignment: MainAxisAlignment.end,
        actionsOverflowButtonSpacing: 10,
        title: Text(
          widget.delete ? 'Delete staff account?' : 'Edit staff status',
          style: TextStyle(
            color: widget.delete
                ? AppTheme.errorColor
                : AppTheme.primaryText,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: SizedBox(
          width: widget.delete ? 384 : 304,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.user['username'].toString(),
                  style: const TextStyle(
                    color: AppTheme.secondaryText,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                if (widget.delete)
                  const Text(
                    'This permanently deletes the staff account. '
                    'The staff member will no longer be able to log in. '
                    'This action cannot be undone.',
                    style: TextStyle(
                      color: AppTheme.secondaryText,
                      fontSize: 13,
                      height: 1.7,
                    ),
                  )
                else ...[
                  const Text(
                    'Status',
                    style: TextStyle(
                      color: AppTheme.primaryText,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<bool>(
                    initialValue: _active,
                    isExpanded: true,
                    dropdownColor: AppTheme.inputBackground,
                    style: const TextStyle(
                      color: AppTheme.primaryText,
                      fontSize: 13,
                    ),
                    decoration: _staffInputDecoration(),
                    items: const [
                      DropdownMenuItem(
                        value: true,
                        child: Text('Active'),
                      ),
                      DropdownMenuItem(
                        value: false,
                        child: Text('Inactive'),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _active = value);
                          },
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          _staffCancelButton(
            _saving ? null : () => Navigator.pop(context, false),
          ),
          _staffPrimaryButton(
            label: widget.delete ? 'Delete account' : 'Save',
            onPressed: _saving ? null : _save,
            destructive: widget.delete,
            loading: _saving,
          ),
        ],
      ),
    );
  }
}

class _CreateStaffPanel extends StatefulWidget {
  const _CreateStaffPanel({
    required this.onCancel,
    required this.onCreated,
  });

  final VoidCallback onCancel;
  final Future<void> Function() onCreated;

  @override
  State<_CreateStaffPanel> createState() => _CreateStaffPanelState();
}

class _CreateStaffPanelState extends State<_CreateStaffPanel> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _showPasswords = false;
  bool _saving = false;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final success = await ActionFeedback.run(
      context: context,
      actionKey: 'staff-create',
      loadingMessage: 'Creating the staff account...',
      successMessage: 'Staff account created successfully.',
      action: () async {
        await StaffService.createStaff(
          username: _username.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
        );
      },
    );

    if (!mounted) return;

    setState(() => _saving = false);

    if (success) {
      await widget.onCreated();
    }
  }

  Widget _field(String label, Widget input) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.primaryText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        input,
      ],
    );
  }

  Widget _usernameField() {
    return _field(
      'Username',
      TextFormField(
        controller: _username,
        enabled: !_saving,
        autofocus: true,
        autocorrect: false,
        textInputAction: TextInputAction.next,
        style: const TextStyle(fontSize: 13),
        decoration: _staffInputDecoration(
          hint: 'juan.delacruz',
        ),
        validator: (value) {
          final username = value?.trim() ?? '';

          if (!RegExp(r'^[a-zA-Z0-9_.-]{3,50}$').hasMatch(username)) {
            return 'Use 3–50 letters, numbers, dots, '
                'underscores, or hyphens.';
          }

          return null;
        },
      ),
    );
  }

  Widget _emailField() {
    return _field(
      'Email',
      TextFormField(
        controller: _email,
        enabled: !_saving,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autocorrect: false,
        style: const TextStyle(fontSize: 13),
        decoration: _staffInputDecoration(
          hint: 'juan.delacruz@peakgym.com',
        ),
        validator: (value) {
          final email = value?.trim() ?? '';

          if (email.length > 100 ||
              !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
            return 'Enter a valid email, up to 100 characters.';
          }

          return null;
        },
      ),
    );
  }

  Widget _passwordField() {
    return _field(
      'Password',
      TextFormField(
        controller: _password,
        enabled: !_saving,
        obscureText: !_showPasswords,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const [AutofillHints.newPassword],
        textInputAction: TextInputAction.next,
        style: const TextStyle(fontSize: 13),
        decoration: _staffInputDecoration(),
        validator: (value) {
          final password = value ?? '';

          if (password.length < 12) {
            return 'Use at least 12 characters.';
          }

          if (utf8.encode(password).length > 72) {
            return 'Password exceeds 72 bytes.';
          }

          return null;
        },
      ),
    );
  }

  Widget _confirmPasswordField() {
    return _field(
      'Confirm password',
      TextFormField(
        controller: _confirmPassword,
        enabled: !_saving,
        obscureText: !_showPasswords,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _createAccount(),
        style: const TextStyle(fontSize: 13),
        decoration: _staffInputDecoration(),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Confirm your password.';
          }

          if (value != _password.text) {
            return 'Passwords do not match.';
          }

          return null;
        },
      ),
    );
  }

  Widget _formFields() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 600;

        final fieldWidth = twoColumns
            ? (constraints.maxWidth - 20) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: 20,
          runSpacing: 20,
          children: [
            SizedBox(
              width: fieldWidth,
              child: _usernameField(),
            ),
            SizedBox(
              width: fieldWidth,
              child: _emailField(),
            ),
            SizedBox(
              width: fieldWidth,
              child: _passwordField(),
            ),
            SizedBox(
              width: fieldWidth,
              child: _confirmPasswordField(),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;

        return SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 22 : 42),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _staffPageHeader(compact),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(compact ? 20 : 30),
                decoration: _staffPanelDecoration(),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Create staff account',
                          style: TextStyle(
                            color: AppTheme.primaryText,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "Enter the staff member's account details.",
                          style: TextStyle(
                            color: AppTheme.secondaryText,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 26),
                        _formFields(),
                        const SizedBox(height: 14),
                        const Text(
                          'Use a long, unique password with at least '
                          '12 characters.',
                          style: TextStyle(
                            color: AppTheme.secondaryText,
                            fontSize: 11,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                          activeColor: AppTheme.primaryGreen,
                          title: const Text(
                            'Show passwords',
                            style: TextStyle(
                              color: AppTheme.secondaryText,
                              fontSize: 12,
                            ),
                          ),
                          value: _showPasswords,
                          onChanged: _saving
                              ? null
                              : (value) {
                                  setState(() {
                                    _showPasswords = value ?? false;
                                  });
                                },
                        ),
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _staffCancelButton(
                                _saving ? null : widget.onCancel,
                              ),
                              _staffPrimaryButton(
                                label: 'Create account',
                                onPressed:
                                    _saving ? null : _createAccount,
                                loading: _saving,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}