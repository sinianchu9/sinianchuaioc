import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_localizations.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';

class AutomationsScreen extends ConsumerStatefulWidget {
  const AutomationsScreen({super.key});

  @override
  ConsumerState<AutomationsScreen> createState() => _AutomationsScreenState();
}

class _AutomationsScreenState extends ConsumerState<AutomationsScreen> {
  List<Map<String, dynamic>> _automations = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ref.read(apiServiceProvider);
    final resp = await api.getAutomations();
    if (!mounted) return;
    if (resp.isSuccess && resp.data is List) {
      setState(() {
        _automations = (resp.data as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } else {
      setState(() {
        _error = resp.msg;
        _loading = false;
      });
    }
  }

  Future<void> _createAutomation() async {
    final l10n = context.l10n;
    final skills = ref.read(chatProvider).skills;
    final selected = <String>{};
    final nameCtrl = TextEditingController();
    final promptCtrl = TextEditingController();
    final intervalCtrl = TextEditingController(text: '24');
    bool runImmediately = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              backgroundColor: AIOCTheme.surface,
              title: Text(l10n.t('createAutomation')),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.t('name'),
                          hintText: 'e.g. Daily Ops Summary',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: promptCtrl,
                        maxLines: 5,
                        decoration: InputDecoration(
                          labelText: l10n.t('prompt'),
                          hintText: 'What should this automation execute?',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: intervalCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: l10n.t('runEveryHours'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.t('skills'),
                        style: const TextStyle(
                          color: AIOCTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: skills.map((s) {
                          final checked = selected.contains(s.id);
                          return FilterChip(
                            label: Text(s.name),
                            selected: checked,
                            onSelected: (_) {
                              setLocal(() {
                                if (checked) {
                                  selected.remove(s.id);
                                } else {
                                  selected.add(s.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: runImmediately,
                        onChanged: (v) => setLocal(() => runImmediately = v),
                        title: Text(l10n.t('runImmediately')),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(l10n.t('cancel')),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(l10n.t('create')),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;
    final api = ref.read(apiServiceProvider);
    final resp = await api.createAutomation(
      name: nameCtrl.text.trim(),
      prompt: promptCtrl.text.trim(),
      skills: selected.toList(),
      intervalHours: int.tryParse(intervalCtrl.text.trim()) ?? 24,
      runImmediately: runImmediately,
    );

    if (!mounted) return;
    if (!resp.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tf('createFailed', {'error': resp.msg})),
          backgroundColor: AIOCTheme.error,
        ),
      );
      return;
    }
    await _load();
  }

  Future<void> _toggleStatus(Map<String, dynamic> item) async {
    final api = ref.read(apiServiceProvider);
    final current = '${item['status'] ?? 'active'}';
    final target = current == 'active' ? 'paused' : 'active';
    final resp = await api.updateAutomationStatus(
      automationId: '${item['automation_id']}',
      status: target,
    );
    if (resp.isSuccess) {
      await _load();
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final api = ref.read(apiServiceProvider);
    final resp = await api.deleteAutomation('${item['automation_id']}');
    if (resp.isSuccess) {
      await _load();
    }
  }

  Future<void> _runNow(Map<String, dynamic> item) async {
    final l10n = context.l10n;
    final api = ref.read(apiServiceProvider);
    final resp = await api.runAutomationNow('${item['automation_id']}');
    if (!mounted) return;
    if (!resp.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tf('runFailed', {'error': resp.msg})),
          backgroundColor: AIOCTheme.error,
        ),
      );
      return;
    }
    final data = Map<String, dynamic>.from(resp.data ?? const {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.tf('runCompleted', {
            'cost': '${data['cost'] ?? '0'}',
            'request': '${data['request_id'] ?? '-'}',
          }),
        ),
      ),
    );
    await _load();
  }

  Future<void> _showRuns(Map<String, dynamic> item) async {
    final l10n = context.l10n;
    final api = ref.read(apiServiceProvider);
    final resp = await api.getAutomationRuns('${item['automation_id']}');
    if (!mounted) return;
    if (!resp.isSuccess || resp.data is! List) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tf('loadRunsFailed', {'error': resp.msg})),
          backgroundColor: AIOCTheme.error,
        ),
      );
      return;
    }
    final runs = (resp.data as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AIOCTheme.surface,
      builder: (ctx) {
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  l10n.t('automationRuns'),
                  style: const TextStyle(
                    color: AIOCTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: runs.isEmpty
                    ? Center(
                        child: Text(
                          l10n.t('noRunsYet'),
                          style: const TextStyle(
                            color: AIOCTheme.textSecondary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: runs.length,
                        itemBuilder: (context, i) {
                          final run = runs[i];
                          final status = '${run['status'] ?? 'unknown'}';
                          return Card(
                            color: AIOCTheme.surfaceCard,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${l10n.t('status')}: $status',
                                    style: const TextStyle(
                                      color: AIOCTheme.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${l10n.t('started')}: ${run['started_at'] ?? '-'}',
                                    style: const TextStyle(
                                      color: AIOCTheme.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    '${l10n.t('cost')}: ${run['cost'] ?? '0'} | ${l10n.t('inOut')}: ${run['tokens_in'] ?? 0}/${run['tokens_out'] ?? 0}',
                                    style: const TextStyle(
                                      color: AIOCTheme.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    '${l10n.t('request')}: ${run['request_id'] ?? '-'}',
                                    style: const TextStyle(
                                      color: AIOCTheme.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if ((run['response_preview'] ?? '')
                                      .toString()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      '${run['response_preview']}',
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AIOCTheme.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      color: AIOCTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AIOCTheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: AIOCTheme.surfaceLight.withOpacity(0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.t('automations'),
                      style: const TextStyle(
                        color: AIOCTheme.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.t('createScheduled'),
                      style: const TextStyle(
                        color: AIOCTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _createAutomation,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.t('newAutomation')),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AIOCTheme.error),
                    ),
                  )
                : _automations.isEmpty
                ? Center(
                    child: Text(
                      l10n.t('noAutomationsYet'),
                      style: const TextStyle(color: AIOCTheme.textSecondary),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _automations.length,
                    itemBuilder: (context, i) {
                      final item = _automations[i];
                      final skills = List<String>.from(
                        item['skills'] ?? const [],
                      );
                      final status = '${item['status'] ?? 'active'}';
                      return Card(
                        color: AIOCTheme.surfaceCard,
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${item['name'] ?? l10n.t('automations')}',
                                      style: const TextStyle(
                                        color: AIOCTheme.textPrimary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Chip(
                                    label: Text(status),
                                    backgroundColor: status == 'active'
                                        ? AIOCTheme.success.withOpacity(0.2)
                                        : AIOCTheme.warning.withOpacity(0.2),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${item['prompt'] ?? ''}',
                                style: const TextStyle(
                                  color: AIOCTheme.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  ...skills.map((s) => _skillChip(s)),
                                  _skillChip(
                                    l10n.tf('everyHours', {
                                      'hours':
                                          '${item['interval_hours'] ?? 24}',
                                    }),
                                  ),
                                  _skillChip('${item['timezone'] ?? 'UTC'}'),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: () => _runNow(item),
                                    child: Text(l10n.t('runNow')),
                                  ),
                                  TextButton(
                                    onPressed: () => _showRuns(item),
                                    child: Text(l10n.t('runs')),
                                  ),
                                  TextButton(
                                    onPressed: () => _toggleStatus(item),
                                    child: Text(
                                      status == 'active'
                                          ? l10n.t('pause')
                                          : l10n.t('resume'),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => _delete(item),
                                    child: Text(
                                      l10n.t('delete'),
                                      style: const TextStyle(
                                        color: AIOCTheme.error,
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
                  ),
          ),
        ],
      ),
    );
  }

  Widget _skillChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AIOCTheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(color: AIOCTheme.textSecondary, fontSize: 11),
      ),
    );
  }
}
