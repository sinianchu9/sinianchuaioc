import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
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
            icon: Icon(Icons.dashboard_outlined),
            label: Text('总览'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.extension_outlined),
            label: Text('系统工具'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.link_outlined),
            label: Text('外部连接'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            label: Text('状态中心'),
          ),
        ],
        onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
      ),
    );
  }

  Widget _buildHeader(
    ToolControlCenterState state,
    ToolControlCenterNotifier notifier,
  ) {
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
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
              DropdownMenuItem(
                value: 'DISABLED',
                child: Text('已禁用 (DISABLED)'),
              ),
              DropdownMenuItem(
                value: 'MISSING_CREDENTIALS',
                child: Text('缺少凭据 (MISSING_CREDENTIALS)'),
              ),
              DropdownMenuItem(
                value: 'MISCONFIGURED',
                child: Text('配置错误 (MISCONFIGURED)'),
              ),
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

  Widget _buildCurrentTab(
    ToolControlCenterState state,
    ToolControlCenterNotifier notifier,
  ) {
    if (_tabIndex == 0) {
      return _buildOverviewTab(state);
    }
    if (_tabIndex == 1) {
      return _buildToolsTab(state, notifier);
    }
    if (_tabIndex == 2) {
      return _buildIntegrationsTab(state, notifier);
    }
    return _buildStatusTab(state);
  }

  Widget _buildOverviewTab(ToolControlCenterState state) {
    final tools = state.tools;
    final integrations = state.integrations;
    final toolOk = tools.where((t) => (t['status'] ?? '') == 'OK').length;
    final toolEnabled = tools.where((t) => t['is_enabled'] == true).length;
    final integrationConfigured = integrations
        .where((i) => i['configured'] == true)
        .length;
    final toolErrors = tools
        .where(
          (t) =>
              (t['status'] ?? '') == 'ERROR' ||
              (t['status'] ?? '') == 'MISSING_CREDENTIALS' ||
              (t['status'] ?? '') == 'MISCONFIGURED',
        )
        .length;
    final integrationErrors = integrations
        .where(
          (i) =>
              (i['status'] ?? '') == 'ERROR' ||
              (i['status'] ?? '') == 'MISSING_CREDENTIALS' ||
              (i['status'] ?? '') == 'MISCONFIGURED',
        )
        .length;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _statusCard(
                '工具正常',
                '$toolOk/${tools.length}',
                AIOCTheme.success,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statusCard(
                '工具已启用',
                '$toolEnabled/${tools.length}',
                AIOCTheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statusCard(
                '外部连接已配置',
                '$integrationConfigured/${integrations.length}',
                integrationConfigured > 0
                    ? AIOCTheme.accent
                    : AIOCTheme.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _statusCard(
                '工具错误',
                '$toolErrors',
                toolErrors > 0 ? AIOCTheme.error : AIOCTheme.success,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statusCard(
                '外部连接错误',
                '$integrationErrors',
                integrationErrors > 0 ? AIOCTheme.error : AIOCTheme.success,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statusCard(
                '总错误',
                '${toolErrors + integrationErrors}',
                toolErrors + integrationErrors > 0
                    ? AIOCTheme.error
                    : AIOCTheme.success,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _buildPanel(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(
                  '口径说明：$toolEnabled/${tools.length} 是“启用”，不是“正常”。当前真正可执行能力请看“工具正常 $toolOk/${tools.length}”。',
                  style: const TextStyle(color: AIOCTheme.textSecondary),
                ),
                const SizedBox(height: 10),
                const Text(
                  '优先级规则：P0=核心运行链路，P1=系统能力受损，P2=外部依赖待补齐',
                  style: TextStyle(color: AIOCTheme.textSecondary),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _exportCapabilityMatrix(
                        context,
                        tools,
                        integrations,
                        format: 'markdown',
                      ),
                      icon: const Icon(Icons.file_copy_outlined, size: 16),
                      label: const Text('导出能力矩阵 Markdown'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _exportCapabilityMatrix(
                        context,
                        tools,
                        integrations,
                        format: 'csv',
                      ),
                      icon: const Icon(Icons.table_chart_outlined, size: 16),
                      label: const Text('导出能力矩阵 CSV'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '当前配置中心加载：tools=${state.tools.length}/${state.registeredToolCount}，integrations=${state.integrations.length}/${state.registeredIntegrationCount}\nmanifest=${state.manifestPath}',
                  style: const TextStyle(
                    color: AIOCTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'OpenClaw 注册能力清单',
                  style: TextStyle(
                    color: AIOCTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ..._buildToolCapabilityRows(tools),
                const SizedBox(height: 10),
                const Text(
                  '系统内部错误处理',
                  style: TextStyle(
                    color: AIOCTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '1. MISSING_BINARIES：安装缺失依赖（如 playwright）。\n'
                  '2. DISABLED：到“系统工具”页打开开关。\n'
                  '3. MISSING_INTEGRATIONS：补齐外部连接后再检查。\n'
                  '4. ERROR：根据 last_error_code / last_error_message 处理。',
                  style: TextStyle(color: AIOCTheme.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolsTab(
    ToolControlCenterState state,
    ToolControlCenterNotifier notifier,
  ) {
    final tools = state.filteredTools;
    return _buildPanel(
      child: ListView.separated(
        itemCount: tools.length,
        separatorBuilder: (_, _) =>
            Divider(color: AIOCTheme.surfaceLight.withOpacity(0.5)),
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
            if (missingIntegrations.isNotEmpty)
              '缺少集成: ${missingIntegrations.join(', ')}',
            if (missingBinaries.isNotEmpty)
              '缺少运行依赖: ${missingBinaries.join(', ')}',
          ].join('\n');

          return ListTile(
            title: Text(
              name,
              style: const TextStyle(
                color: AIOCTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              details,
              style: const TextStyle(color: AIOCTheme.textSecondary),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _priorityChip(_toolPriority(t)),
                const SizedBox(width: 6),
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

  Widget _buildIntegrationsTab(
    ToolControlCenterState state,
    ToolControlCenterNotifier notifier,
  ) {
    final integrations = state.filteredIntegrations;
    return _buildPanel(
      child: ListView.separated(
        itemCount: integrations.length,
        separatorBuilder: (_, _) =>
            Divider(color: AIOCTheme.surfaceLight.withOpacity(0.5)),
        itemBuilder: (context, index) {
          final it = integrations[index];
          final id = (it['id'] ?? '').toString();
          final displayName = (it['display_name'] ?? id).toString();
          final status = (it['status'] ?? '').toString();
          final requiredFields = _toStringList(it['required_fields']);
          final missingFields = _toStringList(it['missing_fields']);

          return ListTile(
            title: Text(
              displayName,
              style: const TextStyle(
                color: AIOCTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
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
                  onPressed: state.saving
                      ? null
                      : () => notifier.checkIntegration(id),
                  child: const Text('检查'),
                ),
                const SizedBox(width: 6),
                ElevatedButton(
                  onPressed: state.saving
                      ? null
                      : () => _showSecretDialog(
                          context,
                          notifier,
                          id,
                          requiredFields,
                        ),
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
    final toolErrors = issues
        .where(
          (i) =>
              (i['kind'] ?? '') == 'tool' &&
              ((i['status'] ?? '') == 'ERROR' ||
                  (i['status'] ?? '') == 'MISCONFIGURED' ||
                  (i['status'] ?? '') == 'MISSING_CREDENTIALS'),
        )
        .length;
    final integrationErrors = issues
        .where(
          (i) =>
              (i['kind'] ?? '') == 'integration' &&
              ((i['status'] ?? '') == 'ERROR' ||
                  (i['status'] ?? '') == 'MISCONFIGURED' ||
                  (i['status'] ?? '') == 'MISSING_CREDENTIALS'),
        )
        .length;
    final ok = (summary['ok'] ?? 0).toString();
    final warn = (summary['warn'] ?? 0).toString();
    final error =
        ((summary['error'] ?? 0) +
                (summary['missing_credentials'] ?? 0) +
                (summary['misconfigured'] ?? 0))
            .toString();

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
        Row(
          children: [
            Expanded(
              child: _statusCard(
                '工具错误',
                '$toolErrors',
                toolErrors > 0 ? AIOCTheme.error : AIOCTheme.success,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statusCard(
                '外部连接错误',
                '$integrationErrors',
                integrationErrors > 0 ? AIOCTheme.error : AIOCTheme.success,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statusCard(
                '错误合计',
                '${toolErrors + integrationErrors}',
                toolErrors + integrationErrors > 0
                    ? AIOCTheme.error
                    : AIOCTheme.success,
              ),
            ),
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
                final priority = kind == 'tool'
                    ? _toolPriority(issue)
                    : _integrationPriority(issue);
                return ListTile(
                  leading: Icon(
                    kind == 'tool' ? Icons.extension : Icons.link,
                    color: AIOCTheme.textSecondary,
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(color: AIOCTheme.textPrimary),
                  ),
                  subtitle: Text(
                    message,
                    style: const TextStyle(color: AIOCTheme.textSecondary),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _priorityChip(priority),
                      const SizedBox(width: 6),
                      _statusChip(status),
                    ],
                  ),
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
            child: Text(
              state.error!,
              style: const TextStyle(color: AIOCTheme.error),
            ),
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
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
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
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
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

  Future<void> _exportCapabilityMatrix(
    BuildContext context,
    List<Map<String, dynamic>> tools,
    List<Map<String, dynamic>> integrations, {
    required String format,
  }) async {
    final integrationMap = <String, Map<String, dynamic>>{};
    for (final i in integrations) {
      final id = (i['id'] ?? '').toString();
      if (id.isNotEmpty) {
        integrationMap[id] = i;
      }
    }

    final rows = tools.map((t) {
      final id = (t['id'] ?? '').toString();
      final name = (t['name'] ?? id).toString();
      final status = (t['status'] ?? '').toString();
      final dependencies = (t['dependencies'] is Map)
          ? Map<String, dynamic>.from(t['dependencies'] as Map)
          : <String, dynamic>{};
      final all = _toStringList(dependencies['all_of_integrations']);
      final any = _toStringList(dependencies['any_of_integrations']);
      final bins = _toStringList(dependencies['binaries']);
      final missingIntegrations = _toStringList(t['missing_integrations']);
      final missingBinaries = _toStringList(t['missing_binaries']);
      final lastErrorCode = (t['last_error_code'] ?? '').toString();
      final lastErrorMessage = (t['last_error_message'] ?? '').toString();

      final blockers = <String>[
        if (missingBinaries.isNotEmpty)
          'missing binaries: ${missingBinaries.join('; ')}',
        if (missingIntegrations.isNotEmpty)
          'missing integrations: ${missingIntegrations.map((iid) {
            final st = (integrationMap[iid]?['status'] ?? 'UNKNOWN').toString();
            return '$iid($st)';
          }).join('; ')}',
        if (status == 'DISABLED') 'disabled by admin',
        if (status == 'ERROR' && lastErrorCode.isNotEmpty)
          'error: $lastErrorCode ${lastErrorMessage.isEmpty ? '' : '($lastErrorMessage)'}',
      ];

      String fix;
      if (status == 'DISABLED') {
        fix = 'Enable in 系统工具 page';
      } else if (missingBinaries.isNotEmpty) {
        fix = 'Install binaries: ${missingBinaries.join(', ')}';
      } else if (missingIntegrations.isNotEmpty) {
        fix = 'Configure/check integrations: ${missingIntegrations.join(', ')}';
      } else if (status == 'ERROR') {
        fix = 'Inspect last_error_code/last_error_message';
      } else {
        fix = 'None';
      }

      return <String, String>{
        'tool_id': id,
        'tool_name': name,
        'boundary': _toolBoundaryLabel(id, all, any, bins),
        'status': status,
        'executable': status == 'OK' ? 'YES' : 'NO',
        'dependencies': [
          if (all.isNotEmpty) 'all_of=${all.join('|')}',
          if (any.isNotEmpty) 'any_of=${any.join('|')}',
          if (bins.isNotEmpty) 'binaries=${bins.join('|')}',
          if (all.isEmpty && any.isEmpty && bins.isEmpty) 'none',
        ].join('; '),
        'blockers': blockers.isEmpty ? 'none' : blockers.join(' | '),
        'fix': fix,
      };
    }).toList();

    final text = format == 'csv'
        ? _capabilityRowsToCsv(rows)
        : _capabilityRowsToMarkdown(rows);

    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('能力矩阵已复制到剪贴板（${format.toUpperCase()}）')),
    );
  }

  String _capabilityRowsToMarkdown(List<Map<String, String>> rows) {
    final header =
        '| tool_id | tool_name | boundary | status | executable | dependencies | blockers | fix |\n'
        '|---|---|---|---|---|---|---|---|';
    final body = rows
        .map((r) {
          String c(String k) =>
              (r[k] ?? '').replaceAll('|', '\\|').replaceAll('\n', ' ');
          return '| ${c('tool_id')} | ${c('tool_name')} | ${c('boundary')} | ${c('status')} | ${c('executable')} | ${c('dependencies')} | ${c('blockers')} | ${c('fix')} |';
        })
        .join('\n');
    return '$header\n$body';
  }

  String _capabilityRowsToCsv(List<Map<String, String>> rows) {
    const cols = [
      'tool_id',
      'tool_name',
      'boundary',
      'status',
      'executable',
      'dependencies',
      'blockers',
      'fix',
    ];
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    final lines = <String>[cols.join(',')];
    for (final r in rows) {
      lines.add(cols.map((c) => esc(r[c] ?? '')).join(','));
    }
    return lines.join('\n');
  }

  List<Widget> _buildToolCapabilityRows(List<Map<String, dynamic>> tools) {
    if (tools.isEmpty) {
      return const [
        Text('暂无已注册工具', style: TextStyle(color: AIOCTheme.textSecondary)),
      ];
    }

    return tools.map((t) {
      final id = (t['id'] ?? '').toString();
      final name = (t['name'] ?? id).toString();
      final status = (t['status'] ?? '').toString();
      final dependencies = (t['dependencies'] is Map)
          ? Map<String, dynamic>.from(t['dependencies'] as Map)
          : <String, dynamic>{};
      final all = _toStringList(dependencies['all_of_integrations']);
      final any = _toStringList(dependencies['any_of_integrations']);
      final bins = _toStringList(dependencies['binaries']);

      final depText = <String>[
        if (all.isNotEmpty) 'all_of: ${all.join(', ')}',
        if (any.isNotEmpty) 'any_of: ${any.join(', ')}',
        if (bins.isNotEmpty) 'binaries: ${bins.join(', ')}',
        if (all.isEmpty && any.isEmpty && bins.isEmpty)
          'no external dependency',
      ].join(' | ');

      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AIOCTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AIOCTheme.surfaceLight.withOpacity(0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: AIOCTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$id · ${_toolBoundaryLabel(id, all, any, bins)}',
                    style: const TextStyle(
                      color: AIOCTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    depText,
                    style: const TextStyle(
                      color: AIOCTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            _statusChip(status),
            const SizedBox(width: 6),
            _priorityChip(_toolPriority(t)),
          ],
        ),
      );
    }).toList();
  }

  String _toolPriority(Map<String, dynamic> tool) {
    final id = (tool['id'] ?? '').toString();
    final status = (tool['status'] ?? '').toString();
    final missingBins = _toStringList(tool['missing_binaries']);
    final missingInts = _toStringList(tool['missing_integrations']);

    final isCore = id == 'openclaw.runtime' || id == 'openclaw.fs';
    if (isCore && status != 'OK') return 'P0';
    if (status == 'ERROR' || status == 'MISCONFIGURED') return 'P1';
    if (missingBins.isNotEmpty) return 'P1';
    if (status == 'MISSING_CREDENTIALS' || missingInts.isNotEmpty) return 'P2';
    if (status == 'DISABLED') return isCore ? 'P0' : 'P1';
    return 'P3';
  }

  String _integrationPriority(Map<String, dynamic> integrationOrIssue) {
    final id = (integrationOrIssue['id'] ?? '').toString();
    final status = (integrationOrIssue['status'] ?? '').toString();
    if (id == 'llm.openai' && status != 'OK') return 'P0';
    if (status == 'ERROR' || status == 'MISCONFIGURED') return 'P1';
    if (status == 'MISSING_CREDENTIALS') return 'P2';
    return 'P3';
  }

  Widget _priorityChip(String p) {
    Color color;
    switch (p) {
      case 'P0':
        color = AIOCTheme.error;
        break;
      case 'P1':
        color = AIOCTheme.warning;
        break;
      case 'P2':
        color = AIOCTheme.accent;
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
        p,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _toolBoundaryLabel(
    String toolId,
    List<String> all,
    List<String> any,
    List<String> bins,
  ) {
    if ((toolId == 'openclaw.fs' || toolId == 'openclaw.runtime') &&
        all.isEmpty &&
        any.isEmpty &&
        bins.isEmpty) {
      return '系统内部核心';
    }
    if (all.isNotEmpty || any.isNotEmpty) {
      return '外部依赖能力';
    }
    if (bins.isNotEmpty) {
      return '系统内部（依赖本机组件）';
    }
    return '系统内部';
  }
}
