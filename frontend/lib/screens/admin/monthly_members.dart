import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/services/member_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/action_feedback.dart';

String _message(Object error) {
  return error.toString().replaceFirst('Exception: ', '');
}

String _iso(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

String _dateText(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');

  if (date == null) return '—';

  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

DateTime _nextMonth(DateTime start) {
  final lastDay = DateTime(start.year, start.month + 2, 0).day;
  final day = start.day > lastDay ? lastDay : start.day;

  return DateTime(start.year, start.month + 1, day);
}

BoxDecoration _panelDecoration() {
  return BoxDecoration(
    color: AppTheme.cardBackground,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: AppTheme.borderColor),
  );
}

Widget _primaryButton(
  String label,
  VoidCallback? onPressed, {
  bool loading = false,
}) {
  return DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(5),
      gradient: const LinearGradient(
        colors: [
          AppTheme.primaryGreen,
          AppTheme.accentYellow,
        ],
      ),
    ),
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.black,
        disabledForegroundColor: Colors.black54,
        minimumSize: const Size(112, 44),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
        ),
      ),
      child: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.black,
              ),
            )
          : Text(label),
    ),
  );
}

Widget _statusBadge(String status) {
  final color = switch (status) {
    'Active' => AppTheme.primaryGreen,
    'Expired' => AppTheme.errorColor,
    'Upcoming' => AppTheme.accentYellow,
    _ => AppTheme.secondaryText,
  };

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.30)),
    ),
    child: Text(
      status,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class MonthlyMembers extends StatefulWidget {
  const MonthlyMembers({
    super.key,
    required this.onChanged,
  });

  final Future<void> Function() onChanged;

  @override
  State<MonthlyMembers> createState() => _MonthlyMembersState();
}

class _MonthlyMembersState extends State<MonthlyMembers> {
  final _search = TextEditingController();

  List<Map<String, dynamic>> _members = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  String? _formMode;
  Map<String, dynamic>? _selected;
  int _photoVersion = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final members = await MemberService.getMembers();

      if (!mounted) return;

      setState(() {
        _members = members;
        _loading = false;
        _photoVersion++;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = _message(error);
        _loading = false;
      });
    }
  }

  Future<void> _refreshAfterChange() async {
    await _load();

    if (!mounted) return;

    await widget.onChanged();
  }

  void _openForm(String mode, [Map<String, dynamic>? member]) {
    if (_busy) return;

    setState(() {
      _formMode = mode;
      _selected = member;
    });
  }

  Future<void> _closeForm() async {
    if (!mounted) return;

    setState(() {
      _formMode = null;
      _selected = null;
    });

    await _refreshAfterChange();
  }

  Future<void> _saved() async {
    if (!mounted) return;

    setState(() {
      _formMode = null;
      _selected = null;
    });

    await _refreshAfterChange();
  }

  Future<void> _delete(Map<String, dynamic> member) async {
    if (_busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.70),
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppTheme.cardBackground,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7),
            side: const BorderSide(color: AppTheme.borderColor),
          ),
          titlePadding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
          contentPadding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
          actionsPadding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
          actionsAlignment: MainAxisAlignment.end,
          actionsOverflowButtonSpacing: 10,
          title: const Text(
            'Delete member?',
            style: TextStyle(
              color: AppTheme.errorColor,
              fontSize: 23,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: SizedBox(
            width: 384,
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Permanently delete '),
                  TextSpan(
                    text: member['full_name'].toString(),
                    style: const TextStyle(
                      color: AppTheme.primaryText,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const TextSpan(
                    text: ', including their membership history '
                        'and photo? This cannot be undone.',
                  ),
                ],
              ),
              style: const TextStyle(
                color: AppTheme.secondaryText,
                fontSize: 13,
                height: 1.9,
              ),
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryText,
                minimumSize: const Size(80, 44),
                side: const BorderSide(color: AppTheme.borderColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorColor,
                foregroundColor: Colors.black,
                minimumSize: const Size(128, 44),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              child: const Text(
                'Delete member',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    // Cancel, back, or dismiss must NEVER delete the member.
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);

    try {
      final success = await ActionFeedback.run(
        context: context,
        actionKey: 'member-delete',
        loadingMessage: 'Deleting the member and membership history...',
        successMessage: 'Member deleted successfully.',
        action: () => MemberService.deleteMember(
          (member['id'] as num).toInt(),
        ),
      );

      if (!mounted) return;

      if (success) {
        await _refreshAfterChange();
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _history(Map<String, dynamic> member) {
    showDialog<void>(
      context: context,
      builder: (_) => _HistoryDialog(member: member),
    );
  }

  Widget _actions(Map<String, dynamic> member) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 2,
      children: [
        TextButton.icon(
          onPressed: _busy ? null : () => _openForm('edit', member),
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: const Text('Edit'),
        ),
        TextButton.icon(
          onPressed: _busy || member['membership_id'] == null
              ? null
              : () => _openForm('renew', member),
          icon: const Icon(Icons.autorenew, size: 16),
          label: const Text('Renew'),
        ),
        TextButton.icon(
          onPressed: _busy ? null : () => _history(member),
          icon: const Icon(Icons.history, size: 16),
          label: const Text('History'),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.primaryText,
          ),
        ),
        TextButton.icon(
          onPressed: _busy ? null : () => _delete(member),
          icon: const Icon(Icons.delete_outline, size: 16),
          label: const Text('Delete'),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.errorColor,
          ),
        ),
      ],
    );
  }

  Widget _memberIdentity(Map<String, dynamic> member) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MemberPhoto(
          key: ValueKey('${member['id']}-$_photoVersion'),
          memberId: (member['id'] as num).toInt(),
          hasPhoto: member['photo'] != null,
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            member['full_name'].toString(),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _table(List<Map<String, dynamic>> members) {
    return Container(
      decoration: _panelDecoration(),
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
                horizontalMargin: 22,
                columnSpacing: 24,
                headingRowHeight: 52,
                dataRowMinHeight: 76,
                dataRowMaxHeight: 88,
                dividerThickness: 1,
                border: const TableBorder(
                  horizontalInside: BorderSide(
                    color: AppTheme.borderColor,
                  ),
                ),
                headingTextStyle: const TextStyle(
                  color: AppTheme.secondaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                columns: const [
                  DataColumn(label: Text('Member')),
                  DataColumn(label: Text('Start date')),
                  DataColumn(label: Text('Due date')),
                  DataColumn(label: Text('Status')),
                  DataColumn(
                    label: Expanded(
                      child: Center(child: Text('Actions')),
                    ),
                  ),
                ],
                rows: members.map((member) {
                  return DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 180,
                          child: _memberIdentity(member),
                        ),
                      ),
                      DataCell(Text(_dateText(member['start_date']))),
                      DataCell(Text(_dateText(member['due_date']))),
                      DataCell(
                        _statusBadge(
                          member['status']?.toString() ?? 'Unknown',
                        ),
                      ),
                      DataCell(Center(child: _actions(member))),
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

  Widget _mobileCards(List<Map<String, dynamic>> members) {
    return Column(
      children: members.map((member) {
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: _panelDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _memberIdentity(member),
              const SizedBox(height: 14),
              _statusBadge(member['status']?.toString() ?? 'Unknown'),
              const SizedBox(height: 14),
              Text('Start date: ${_dateText(member['start_date'])}'),
              const SizedBox(height: 6),
              Text('Due date: ${_dateText(member['due_date'])}'),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(color: AppTheme.borderColor),
              ),
              _actions(member),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _toolbar(bool compact) {
    final searchField = SizedBox(
      height: 44,
      child: TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 12),
        decoration: const InputDecoration(
          hintText: 'Search member name...',
          isDense: true,
          prefixIcon: Icon(
            Icons.search,
            size: 18,
            color: AppTheme.secondaryText,
          ),
        ),
      ),
    );

    final addButton = _primaryButton(
      'Add member',
      _busy || _loading ? null : () => _openForm('add'),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          searchField,
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: addButton,
          ),
        ],
      );
    }

    return Row(
      children: [
        SizedBox(width: 340, child: searchField),
        const Spacer(),
        addButton,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();

    final filtered = _members.where((member) {
      return member['full_name']
          .toString()
          .toLowerCase()
          .contains(query);
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;

        return SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 22 : 42),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Monthly Members',
                style: TextStyle(
                  fontSize: compact ? 30 : 40,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Manage members, monthly renewals, and due dates.',
                style: TextStyle(
                  color: AppTheme.secondaryText,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 30),
              const Divider(color: AppTheme.borderColor),
              const SizedBox(height: 24),
              if (_formMode != null)
                _MemberForm(
                  key: ValueKey('$_formMode-${_selected?['id']}'),
                  mode: _formMode!,
                  member: _selected,
                  onCancel: _closeForm,
                  onSaved: _saved,
                )
              else ...[
                _toolbar(compact),
                const SizedBox(height: 24),
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: _panelDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: AppTheme.errorColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh, size: 17),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                else if (filtered.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(30),
                    decoration: _panelDecoration(),
                    child: Text(
                      query.isEmpty
                          ? 'No members yet. Add your first member.'
                          : 'No members match your search.',
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
            ],
          ),
        );
      },
    );
  }
}

class _MemberPhoto extends StatefulWidget {
  const _MemberPhoto({
    super.key,
    required this.memberId,
    required this.hasPhoto,
    this.size = 40,
  });

  final int memberId;
  final bool hasPhoto;
  final double size;

  @override
  State<_MemberPhoto> createState() => _MemberPhotoState();
}

class _MemberPhotoState extends State<_MemberPhoto> {
  late final Future<Uint8List?> _photo;

  @override
  void initState() {
    super.initState();

    _photo = widget.hasPhoto
        ? MemberService.photo(widget.memberId)
        : Future<Uint8List?>.value(null);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _photo,
      builder: (context, snapshot) {
        return ClipOval(
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: snapshot.data != null
                ? Image.memory(
                    snapshot.data!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, error, stack) =>
                        const ColoredBox(
                      color: AppTheme.inputBackground,
                      child: Icon(Icons.person_outline),
                    ),
                  )
                : const ColoredBox(
                    color: AppTheme.inputBackground,
                    child: Icon(
                      Icons.person_outline,
                      color: AppTheme.secondaryText,
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _MemberForm extends StatefulWidget {
  const _MemberForm({
    super.key,
    required this.mode,
    required this.member,
    required this.onCancel,
    required this.onSaved,
  });

  final String mode;
  final Map<String, dynamic>? member;
  final Future<void> Function() onCancel;
  final Future<void> Function() onSaved;

  @override
  State<_MemberForm> createState() => _MemberFormState();
}

class _MemberFormState extends State<_MemberForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;

  late DateTime _start;
  late DateTime _due;

  Uint8List? _photoBytes;
  String? _photoName;
  bool _removePhoto = false;
  bool _saving = false;
  bool _preparing = false;
  bool _renewalReady = false;
  String? _error;

  int? _savedMemberId;
  bool _renewalSaved = false;

  bool get _renewing => widget.mode == 'renew';
  bool get _editing => widget.mode == 'edit';

  @override
  void initState() {
    super.initState();

    _name = TextEditingController(
      text: widget.member?['full_name']?.toString() ?? '',
    );

    final today = DateUtils.dateOnly(DateTime.now());

    _start = _editing
        ? DateTime.tryParse(
              widget.member?['start_date']?.toString() ?? '',
            ) ??
            today
        : today;

    _due = _editing
        ? DateTime.tryParse(
              widget.member?['due_date']?.toString() ?? '',
            ) ??
            _nextMonth(_start)
        : _nextMonth(_start);

    if (_renewing) {
      _prepareRenewal();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _prepareRenewal() async {
    if (!mounted) return;

    setState(() {
      _preparing = true;
      _renewalReady = false;
      _error = null;
    });

    try {
      final history = await MemberService.history(
        (widget.member!['id'] as num).toInt(),
      );

      if (history.isEmpty) {
        throw Exception('This member has no membership to renew.');
      }

      final dates = history
          .map((entry) => DateTime.parse(entry['due_date'].toString()))
          .toList()
        ..sort();

      final today = DateUtils.dateOnly(DateTime.now());
      final next = dates.last.add(const Duration(days: 1));
      final suggested = next.isAfter(today) ? next : today;

      if (suggested.isAfter(DateTime(2099, 12, 31))) {
        throw Exception(
          'The next renewal exceeds the supported date range.',
        );
      }

      if (!mounted) return;

      setState(() {
        _start = suggested;
        _due = _nextMonth(_start);
        _preparing = false;
        _renewalReady = true;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = _message(error);
        _preparing = false;
      });
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
      );

      if (file == null) return;

      final bytes = await file.readAsBytes();

      if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
        throw Exception(
          'Choose a non-empty JPEG or PNG up to 2 MB.',
        );
      }

      if (!mounted) return;

      setState(() {
        _photoBytes = bytes;
        _photoName = file.name;
        _removePhoto = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() => _error = _message(error));
    }
  }

  Future<void> _pickDate({bool dueDate = false}) async {
    final initial = dueDate ? _due : _start;
    final first = DateTime(1900);
    final last = DateTime(dueDate ? 2100 : 2099, 12, 31);

    final safeInitial = initial.isBefore(first)
        ? first
        : initial.isAfter(last)
            ? last
            : initial;

    final picked = await showDatePicker(
      context: context,
      initialDate: safeInitial,
      firstDate: first,
      lastDate: last,
    );

    if (picked == null || !mounted) return;

    setState(() {
      if (dueDate) {
        _due = picked;
      } else {
        _start = picked;
        _due = _nextMonth(picked);
      }
    });
  }

  Future<void> _save() async {
    if (_saving || _preparing) return;
    if (_renewing && !_renewalReady) return;
    if (!_formKey.currentState!.validate()) return;

    if (_due.isBefore(_start)) {
      setState(() {
        _error = 'Due date cannot be before the start date.';
      });
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _saving = true;
      _error = null;
    });

    final success = await ActionFeedback.run(
      context: context,
      actionKey: 'member-${widget.mode}',
      loadingMessage: _renewing
          ? 'Saving the new membership period...'
          : _editing
              ? 'Updating member information...'
              : 'Registering the member...',
      successMessage: _renewing
          ? 'Membership renewed successfully.'
          : _editing
              ? 'Member details updated successfully.'
              : 'Member registered successfully.',
      action: () async {
        var completedStep = '';

        try {
          if (_renewing) {
            if (!_renewalSaved) {
              await MemberService.renew(
                memberId: (widget.member!['id'] as num).toInt(),
                startDate: _iso(_start),
              );

              _renewalSaved = true;
            }
          } else {
            if (_editing) {
              _savedMemberId =
                  (widget.member!['id'] as num).toInt();

              await MemberService.updateMember(
                memberId: _savedMemberId!,
                fullName: _name.text.trim(),
              );

              completedStep = 'The member name was saved. ';

              final membershipId =
                  widget.member!['membership_id'];

              if (membershipId != null) {
                await MemberService.updateMembership(
                  membershipId: (membershipId as num).toInt(),
                  memberId: _savedMemberId!,
                  startDate: _iso(_start),
                  dueDate: _iso(_due),
                );
              }
            } else {
              // Preserve the returned ID if a later photo upload fails.
              _savedMemberId ??=
                  await MemberService.createMember(
                fullName: _name.text.trim(),
                startDate: _iso(_start),
              );
            }

            completedStep = 'The member details were saved. ';

            if (_photoBytes != null) {
              await MemberService.uploadPhoto(
                memberId: _savedMemberId!,
                bytes: _photoBytes!,
                filename: _photoName!,
              );
            } else if (_removePhoto &&
                widget.member?['photo'] != null) {
              await MemberService.removePhoto(_savedMemberId!);
            }
          }
        } catch (error) {
          throw Exception('$completedStep${_message(error)}');
        }
      },
    );

    if (!mounted) return;

    setState(() => _saving = false);

    if (success) {
      await widget.onSaved();
    }
  }

  Widget _label(String title, Widget field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.secondaryText,
          ),
        ),
        const SizedBox(height: 9),
        field,
      ],
    );
  }

  Widget _dateField(
    String label,
    DateTime value, {
    bool editable = false,
    bool dueDate = false,
  }) {
    final canEdit = editable && !_saving && !_preparing;

    return _label(
      label,
      Semantics(
        button: canEdit,
        label: '$label: ${_dateText(_iso(value))}',
        child: Material(
          color: AppTheme.inputBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: const BorderSide(color: AppTheme.borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: canEdit
                ? () => _pickDate(dueDate: dueDate)
                : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _dateText(_iso(value)),
                      style: TextStyle(
                        fontSize: 13,
                        color: editable
                            ? AppTheme.primaryText
                            : AppTheme.secondaryText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    editable
                        ? Icons.calendar_today_outlined
                        : Icons.lock_outline,
                    size: 17,
                    color: AppTheme.secondaryText,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _photoPicker() {
    Widget preview;

    if (_photoBytes != null) {
      preview = Image.memory(
        _photoBytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, error, stack) => const Center(
          child: Text('Invalid image'),
        ),
      );
    } else if (!_removePhoto && widget.member?['photo'] != null) {
      preview = Center(
        child: _MemberPhoto(
          memberId: (widget.member!['id'] as num).toInt(),
          hasPhoto: true,
          size: 120,
        ),
      );
    } else {
      preview = const Center(
        child: Text(
          'No photo',
          style: TextStyle(
            color: AppTheme.secondaryText,
            fontSize: 12,
          ),
        ),
      );
    }

    return SizedBox(
      width: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(
            'Member photo',
            Container(
              height: 145,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppTheme.inputBackground,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: preview,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _saving ? null : _pickPhoto,
            child: const Text('Choose photo'),
          ),
          if (_photoBytes != null ||
              (!_removePhoto && widget.member?['photo'] != null))
            TextButton(
              onPressed: _saving
                  ? null
                  : () {
                      setState(() {
                        _photoBytes = null;
                        _photoName = null;
                        _removePhoto = true;
                      });
                    },
              child: const Text('Remove photo'),
            ),
          const SizedBox(height: 8),
          Text(
            _photoName ?? 'Optional · PNG or JPEG · Up to 2 MB',
            style: const TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fields() {
    final lockCreatedFields = !_editing && _savedMemberId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(
          'Member name',
          TextFormField(
            controller: _name,
            readOnly: _renewing || lockCreatedFields,
            enabled: !_saving,
            maxLength: 100,
            decoration: const InputDecoration(
              hintText: 'Enter full name',
              counterText: '',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter the member name.';
              }
              return null;
            },
          ),
        ),
        if (!_editing || widget.member?['membership_id'] != null) ...[
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final start = _dateField(
                'Start date',
                _start,
                editable: !lockCreatedFields,
              );

              final due = _dateField(
                'Due date',
                _due,
                editable: _editing,
                dueDate: true,
              );

              if (constraints.maxWidth < 480) {
                return Column(
                  children: [
                    start,
                    const SizedBox(height: 16),
                    due,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: start),
                  const SizedBox(width: 18),
                  Expanded(child: due),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            _editing
                ? 'You are editing the membership period shown in the table.'
                : 'Due date is calculated one calendar month after '
                    'the start date and is the last valid workout day.',
            style: const TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _renewing
        ? 'Renew membership'
        : _editing
            ? 'Edit member'
            : 'Add member';

    final renewalUnavailable =
        _renewing && !_preparing && !_renewalReady;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: _panelDecoration(),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _renewing
                  ? 'Add a new membership period for this member.'
                  : 'Enter the member’s information and membership dates.',
              style: const TextStyle(
                color: AppTheme.secondaryText,
                fontSize: 13,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Divider(color: AppTheme.borderColor),
            ),
            if (_preparing)
              const Center(child: CircularProgressIndicator())
            else if (!renewalUnavailable)
              LayoutBuilder(
                builder: (context, constraints) {
                  if (_renewing) return _fields();

                  if (constraints.maxWidth < 650) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _photoPicker(),
                        const SizedBox(height: 24),
                        _fields(),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _photoPicker(),
                      const SizedBox(width: 30),
                      Expanded(child: _fields()),
                    ],
                  );
                },
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: AppTheme.errorColor,
                    ),
                  ),
                ),
              ),
            if (renewalUnavailable)
              TextButton.icon(
                onPressed: _prepareRenewal,
                icon: const Icon(Icons.refresh, size: 17),
                label: const Text('Retry'),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Divider(color: AppTheme.borderColor),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: _saving ? null : widget.onCancel,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(80, 44),
                      foregroundColor: AppTheme.primaryText,
                      side: const BorderSide(
                        color: AppTheme.borderColor,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                  _primaryButton(
                    _renewing ? 'Renew membership' : 'Save member',
                    _saving || _preparing || renewalUnavailable
                        ? null
                        : _save,
                    loading: _saving,
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

class _HistoryDialog extends StatefulWidget {
  const _HistoryDialog({required this.member});

  final Map<String, dynamic> member;

  @override
  State<_HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<_HistoryDialog> {
  late Future<List<Map<String, dynamic>>> _history;

  @override
  void initState() {
    super.initState();
    _history = _loadHistory();
  }

  Future<List<Map<String, dynamic>>> _loadHistory() {
    return MemberService.history(
      (widget.member['id'] as num).toInt(),
    );
  }

  Widget _historyTable(List<Map<String, dynamic>> entries) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth =
            constraints.maxWidth < 400 ? 400.0 : constraints.maxWidth;

        const headerStyle = TextStyle(
          color: AppTheme.secondaryText,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        );

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(),
                1: FlexColumnWidth(),
                2: FixedColumnWidth(108),
              },
              defaultVerticalAlignment:
                  TableCellVerticalAlignment.middle,
              border: const TableBorder(
                horizontalInside: BorderSide(
                  color: AppTheme.borderColor,
                ),
              ),
              children: [
                const TableRow(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(0, 0, 12, 14),
                      child: Text(
                        'Start date',
                        style: headerStyle,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(0, 0, 12, 14),
                      child: Text(
                        'Due date',
                        style: headerStyle,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: Text(
                        'Status',
                        textAlign: TextAlign.center,
                        style: headerStyle,
                      ),
                    ),
                  ],
                ),
                for (final entry in entries)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          0, 16, 12, 16,
                        ),
                        child: Text(
                          _dateText(entry['start_date']),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          0, 16, 12, 16,
                        ),
                        child: Text(
                          _dateText(entry['due_date']),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                        child: Center(
                          child: _statusBadge(
                            entry['status']?.toString() ?? 'Unknown',
                          ),
                        ),
                      ),
                    ],
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
    return AlertDialog(
      backgroundColor: AppTheme.cardBackground,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(7),
        side: const BorderSide(color: AppTheme.borderColor),
      ),
      titlePadding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
      contentPadding: const EdgeInsets.fromLTRB(28, 14, 28, 0),
      actionsPadding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
      title: const Text(
        'Membership history',
        style: TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.member['full_name'].toString(),
                style: const TextStyle(
                  color: AppTheme.secondaryText,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 26),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _history,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _message(snapshot.error!),
                          style: const TextStyle(
                            color: AppTheme.errorColor,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _history = _loadHistory();
                            });
                          },
                          icon: const Icon(Icons.refresh, size: 17),
                          label: const Text('Retry'),
                        ),
                      ],
                    );
                  }

                  final entries =
                      snapshot.data ?? <Map<String, dynamic>>[];

                  if (entries.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'No records available. This member has '
                        'no membership history yet.',
                        style: TextStyle(
                          color: AppTheme.secondaryText,
                        ),
                      ),
                    );
                  }

                  return _historyTable(entries);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryText,
            minimumSize: const Size(80, 44),
            side: const BorderSide(color: AppTheme.borderColor),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          child: const Text(
            'Close',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}