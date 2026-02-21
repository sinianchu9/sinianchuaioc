import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

class ToolControlCenterState {
  final bool loading;
  final bool saving;
  final String? error;
  final List<Map<String, dynamic>> tools;
  final List<Map<String, dynamic>> integrations;
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> issues;
  final String manifestPath;
  final int registeredToolCount;
  final int registeredIntegrationCount;
  final String search;
  final String statusFilter;

  const ToolControlCenterState({
    this.loading = false,
    this.saving = false,
    this.error,
    this.tools = const <Map<String, dynamic>>[],
    this.integrations = const <Map<String, dynamic>>[],
    this.summary = const <String, dynamic>{},
    this.issues = const <Map<String, dynamic>>[],
    this.manifestPath = '',
    this.registeredToolCount = 0,
    this.registeredIntegrationCount = 0,
    this.search = '',
    this.statusFilter = 'ALL',
  });

  ToolControlCenterState copyWith({
    bool? loading,
    bool? saving,
    String? error,
    List<Map<String, dynamic>>? tools,
    List<Map<String, dynamic>>? integrations,
    Map<String, dynamic>? summary,
    List<Map<String, dynamic>>? issues,
    String? manifestPath,
    int? registeredToolCount,
    int? registeredIntegrationCount,
    String? search,
    String? statusFilter,
  }) {
    return ToolControlCenterState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      error: error,
      tools: tools ?? this.tools,
      integrations: integrations ?? this.integrations,
      summary: summary ?? this.summary,
      issues: issues ?? this.issues,
      manifestPath: manifestPath ?? this.manifestPath,
      registeredToolCount: registeredToolCount ?? this.registeredToolCount,
      registeredIntegrationCount:
          registeredIntegrationCount ?? this.registeredIntegrationCount,
      search: search ?? this.search,
      statusFilter: statusFilter ?? this.statusFilter,
    );
  }

  List<Map<String, dynamic>> get filteredTools {
    return _filterList(tools);
  }

  List<Map<String, dynamic>> get filteredIntegrations {
    return _filterList(integrations);
  }

  List<Map<String, dynamic>> _filterList(List<Map<String, dynamic>> source) {
    final q = search.trim().toLowerCase();
    return source.where((item) {
      final status = (item['status'] ?? '').toString();
      final name = (item['name'] ?? item['display_name'] ?? '').toString();
      final category = (item['category'] ?? '').toString();

      if (statusFilter != 'ALL' && status != statusFilter) {
        return false;
      }
      if (q.isEmpty) return true;
      return name.toLowerCase().contains(q) ||
          category.toLowerCase().contains(q) ||
          status.toLowerCase().contains(q);
    }).toList();
  }
}

class ToolControlCenterNotifier extends StateNotifier<ToolControlCenterState> {
  ToolControlCenterNotifier(this._ref) : super(const ToolControlCenterState());

  final Ref _ref;

  Future<void> loadAll() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final api = _ref.read(apiServiceProvider);
      final toolsResp = await api.getAdminTools();
      final integrationsResp = await api.getAdminIntegrations();
      final statusResp = await api.getAdminStatusSummary();

      if (!toolsResp.isSuccess ||
          !integrationsResp.isSuccess ||
          !statusResp.isSuccess) {
        state = state.copyWith(
          loading: false,
          error: toolsResp.msg.isNotEmpty
              ? toolsResp.msg
              : integrationsResp.msg.isNotEmpty
              ? integrationsResp.msg
              : statusResp.msg,
        );
        return;
      }

      final toolsData = _toMap(toolsResp.data);
      final integrationsData = _toMap(integrationsResp.data);
      final statusData = _toMap(statusResp.data);

      state = state.copyWith(
        loading: false,
        tools: _toMapList(toolsData['tools']),
        integrations: _toMapList(integrationsData['integrations']),
        summary: _toMap(statusData['summary']),
        issues: _toMapList(statusData['issues']),
        manifestPath: (toolsData['manifest_path'] ?? '').toString(),
        registeredToolCount: _toInt(toolsData['registered_tool_count']),
        registeredIntegrationCount: _toInt(
          toolsData['registered_integration_count'],
        ),
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: '加载失败: $e');
    }
  }

  Future<void> toggleTool({
    required String toolId,
    required bool enabled,
  }) async {
    state = state.copyWith(saving: true, error: null);
    try {
      final api = _ref.read(apiServiceProvider);
      final resp = await api.toggleAdminTool(toolId: toolId, enabled: enabled);
      if (!resp.isSuccess) {
        state = state.copyWith(saving: false, error: resp.msg);
        return;
      }
      state = state.copyWith(saving: false);
      await loadAll();
    } catch (e) {
      state = state.copyWith(saving: false, error: '工具开关操作失败: $e');
    }
  }

  Future<void> checkIntegration(String integrationId) async {
    state = state.copyWith(saving: true, error: null);
    try {
      final api = _ref.read(apiServiceProvider);
      final resp = await api.checkAdminIntegration(integrationId);
      if (!resp.isSuccess) {
        state = state.copyWith(saving: false, error: resp.msg);
        return;
      }
      state = state.copyWith(saving: false);
      await loadAll();
    } catch (e) {
      state = state.copyWith(saving: false, error: '集成检查失败: $e');
    }
  }

  Future<void> saveSecret({
    required String integrationId,
    required String secretKeyName,
    required String secretValue,
  }) async {
    state = state.copyWith(saving: true, error: null);
    try {
      final api = _ref.read(apiServiceProvider);
      final resp = await api.updateAdminIntegrationSecret(
        integrationId: integrationId,
        secretKeyName: secretKeyName,
        secretValue: secretValue,
      );
      if (!resp.isSuccess) {
        state = state.copyWith(saving: false, error: resp.msg);
        return;
      }
      state = state.copyWith(saving: false);
      await loadAll();
    } catch (e) {
      state = state.copyWith(saving: false, error: '保存密钥失败: $e');
    }
  }

  void setSearch(String value) {
    state = state.copyWith(search: value, error: null);
  }

  void setStatusFilter(String value) {
    state = state.copyWith(statusFilter: value, error: null);
  }

  static Map<String, dynamic> _toMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _toMapList(dynamic v) {
    if (v is! List) return const <Map<String, dynamic>>[];
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

final toolControlCenterProvider =
    StateNotifierProvider<ToolControlCenterNotifier, ToolControlCenterState>((
      ref,
    ) {
      return ToolControlCenterNotifier(ref);
    });
