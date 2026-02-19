import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/tool_control_center_provider.dart';

class ConfigCenterScreen extends ConsumerStatefulWidget {
  const ConfigCenterScreen({super.key});

  @override
  ConsumerState<ConfigCenterScreen> createState() => _ConfigCenterScreenState();
}

class _ConfigCenterScreenState extends ConsumerState<ConfigCenterScreen> {
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(toolControlCenterProvider.notifier).loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(toolControlCenterProvider);
    final notifier = ref.read(toolControlCenterProvider.notifier);

    return Container(
      color: AIOCTheme.background,
      child: Row(
        children: [
          _buildRail(),
          Expanded(
            child: Column(
              children: [
                _buildHeader(state, notifier),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  color: AIOCTheme.warning.withOpacity(0.12),
                  child: const Text(
                    '提示：配置中心反映“配置与健康检查”状态，不等同于业务执行链路已接入。OCR/ASR/TTS 如显示未接入执行，请按文档继续接入运行时工具。',
                    style: TextStyle(color: AIOCTheme.warning, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: state.loading
                      ? const Center(child: CircularProgressIndicator())
                      : Padding(
                          padding: const EdgeInsets.all(16),
                          child: _buildCurrentTab(state, notifier),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRail() {
    return Container(
      width: 140,
      color: AIOCTheme.surface,
      child: NavigationRail(
        selectedIndex: _tabIndex,
        backgroundColor: AIOCTheme.surface,
        labelType: NavigationRailLabelType.all,
        destinations: const [
          NavigationRailDestination(
            icon: Icon(Icons.extension_outlined),
            label: Text('工具'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.link_outlined),
            label: Text('集成'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            label: Text('状态'),
          ),
        ],
        onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
      ),
    );
  }

  Widget _buildHeader(ToolControlCenterState state, ToolControlCenterNotifier notifier) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AIOCTheme.surface,
        border: Border(
          bottom: BorderSide(color: AIOCTheme.surfaceLight.withOpacity(0.5)),
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '工具配置中心与状态中心',
              style: TextStyle(
                color: AIOCTheme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: 220,
            child: TextField(
              onChanged: notifier.setSearch,
              decoration: InputDecoration(
                hintText: '搜索工具/集成/状态',
                isDense: true,
                filled: true,
                fillColor: AIOCTheme.surfaceCard,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: state.statusFilter,
            dropdownColor: AIOCTheme.surfaceCard,
            items: const [
              DropdownMenuItem(value: 'ALL', child: Text('全部')),
              DropdownMenuItem(value: 'OK', child: Text('正常 (OK)')),
              DropdownMenuItem(value: 'WARN', child: Text('警告 (WARN)')),
              DropdownMenuItem(value: 'ERROR', child: Text('错误 (ERROR)')),
              DropdownMenuItem(value: 'DISABLED', child: Text('已禁用 (DISABLED)')),
              DropdownMenuItem(value: 'MISSING_CREDENTIALS', child: Text('缺少凭据 (MISSING_CREDENTIALS)')),
              DropdownMenuItem(value: 'MISCONFIGURED', child: Text('配置错误 (MISCONFIGURED)')),
            ],
            onChanged: (v) {
              if (v != null) {
                notifier.setStatusFilter(v);
              }
            },
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: state.loading ? null : notifier.loadAll,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('刷新'),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentTab(ToolControlCenterState state, ToolControlCenterNotifier notifier) {
    if (_tabIndex == 0) {
      return _buildToolsTab(state, notifier);
    }
    if (_tabIndex == 1) {
      return _buildIntegrationsTab(state, notifier);
    }
    return _buildStatusTab(state);
  }

  Widget _buildToolsTab(ToolControlCenterState state, ToolControlCenterNotifier notifier) {
    final tools = state.filteredTools;
    return _buildPanel(
      child: ListView.separated(
        itemCount: tools.length,
        separatorBuilder: (_, _) => Divider(color: AIOCTheme.surfaceLight.withOpacity(0.5)),
        itemBuilder: (context, index) {
          final t = tools[index];
          final id = (t['id'] ?? '').toString();
          final name = (t['name'] ?? '').toString();
          final category = (t['category'] ?? '').toString();
          final status = (t['status'] ?? '').toString();
          final enabled = t['is_enabled'] == true;
          final missingIntegrations = _toStringList(t['missing_integrations']);
          final missingBinaries = _toStringList(t['missing_binaries']);
          final details = <String>[
            '$id  ·  $category',
            if (missingIntegrations.isNotEmpty) '缺少集成: ${missingIntegrations.join(', ')}',
            if (missingBinaries.isNotEmpty) '缺少运行依赖: ${missingBinaries.join(', ')}',
          ].join('\n');

          return ListTile(
            title: Text(name, style: const TextStyle(color: AIOCTheme.textPrimary, fontWeight: FontWeight.w600)),
            subtitle: Text(details, style: const TextStyle(color: AIOCTheme.textSecondary)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _statusChip(status),
                const SizedBox(width: 8),
                Switch(
                  value: enabled,
                  onChanged: state.saving
                      ? null
                      : (v) => notifier.toggleTool(toolId: id, enabled: v),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildIntegrationsTab(ToolControlCenterState state, ToolControlCenterNotifier notifier) {
    final integrations = state.filteredIntegrations;
    return _buildPanel(
      child: ListView.separated(
        itemCount: integrations.length,
        separatorBuilder: (_, _) => Divider(color: AIOCTheme.surfaceLight.withOpacity(0.5)),
        itemBuilder: (context, index) {
          final it = integrations[index];
          final id = (it['id'] ?? '').toString();
          final displayName = (it['display_name'] ?? id).toString();
          final status = (it['status'] ?? '').toString();
          final requiredFields = _toStringList(it['required_fields']);
          final missingFields = _toStringList(it['missing_fields']);

          return ListTile(
            title: Text(displayName, style: const TextStyle(color: AIOCTheme.textPrimary, fontWeight: FontWeight.w600)),
            subtitle: Text(
              '$id\n必填字段: ${requiredFields.join(', ')}${missingFields.isEmpty ? '' : '\n缺失字段: ${missingFields.join(', ')}'}',
              style: const TextStyle(color: AIOCTheme.textSecondary),
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _statusChip(status),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: state.saving ? null : () => notifier.checkIntegration(id),
                  child: const Text('检查'),
                ),
                const SizedBox(width: 6),
                ElevatedButton(
                  onPressed: state.saving
                      ? null
                      : () => _showSecretDialog(context, notifier, id, requiredFields),
                  child: const Text('配置'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusTab(ToolControlCenterState state) {
    final summary = state.summary;
    final issues = state.issues;
    final ok = (summary['ok'] ?? 0).toString();
    final warn = (summary['warn'] ?? 0).toString();
    final error = (summary['error'] ?? 0).toString();

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _statusCard('正常', ok, AIOCTheme.success)),
            const SizedBox(width: 8),
            Expanded(child: _statusCard('警告', warn, AIOCTheme.warning)),
            const SizedBox(width: 8),
            Expanded(child: _statusCard('错误', error, AIOCTheme.error)),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _buildPanel(
            child: ListView.builder(
              itemCount: issues.length,
              itemBuilder: (context, i) {
                final issue = issues[i];
                final kind = (issue['kind'] ?? '').toString();
                final name = (issue['name'] ?? issue['id'] ?? '').toString();
                final status = (issue['status'] ?? '').toString();
                final message = (issue['last_error_message'] ?? '').toString();
                return ListTile(
                  leading: Icon(
                    kind == 'tool' ? Icons.extension : Icons.link,
                    color: AIOCTheme.textSecondary,
                  ),
                  title: Text(name, style: const TextStyle(color: AIOCTheme.textPrimary)),
                  subtitle: Text(message, style: const TextStyle(color: AIOCTheme.textSecondary)),
                  trailing: _statusChip(status),
                );
              },
            ),
          ),
        ),
        if (state.error != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(8),
            color: AIOCTheme.error.withOpacity(0.1),
            child: Text(state.error!, style: const TextStyle(color: AIOCTheme.error)),
          ),
      ],
    );
  }

  Widget _buildPanel({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AIOCTheme.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AIOCTheme.surfaceLight.withOpacity(0.5)),
      ),
      child: child,
    );
  }

  Widget _statusCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AIOCTheme.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AIOCTheme.surfaceLight.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AIOCTheme.textSecondary)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    Color color;
    switch (status) {
      case 'OK':
        color = AIOCTheme.success;
        break;
      case 'WARN':
        color = AIOCTheme.warning;
        break;
      case 'ERROR':
      case 'MISSING_CREDENTIALS':
      case 'MISCONFIGURED':
        color = AIOCTheme.error;
        break;
      default:
        color = AIOCTheme.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'OK':
        return '正常';
      case 'WARN':
        return '警告';
      case 'ERROR':
        return '错误';
      case 'DISABLED':
        return '已禁用';
      case 'MISSING_CREDENTIALS':
        return '缺少凭据';
      case 'MISCONFIGURED':
        return '配置错误';
      default:
        return status;
    }
  }

  Future<void> _showSecretDialog(
    BuildContext context,
    ToolControlCenterNotifier notifier,
    String integrationId,
    List<String> requiredFields,
  ) async {
    final keyController = TextEditingController(
      text: requiredFields.isNotEmpty ? requiredFields.first : '',
    );
    final valueController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('配置集成：$integrationId'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: keyController,
                  decoration: const InputDecoration(labelText: '密钥字段名'),
                ),
                TextField(
                  controller: valueController,
                  decoration: const InputDecoration(labelText: '密钥值'),
                  obscureText: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final keyName = keyController.text.trim();
                final secretValue = valueController.text.trim();
                if (keyName.isEmpty || secretValue.isEmpty) {
                  return;
                }
                await notifier.saveSecret(
                  integrationId: integrationId,
                  secretKeyName: keyName,
                  secretValue: secretValue,
                );
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  List<String> _toStringList(dynamic v) {
    if (v is! List) return const <String>[];
    return v.map((e) => e.toString()).toList();
  }
}
