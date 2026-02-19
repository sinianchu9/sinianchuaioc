/// AIOC API Service
/// Handles all HTTP communication with the AIOC Gateway

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String _configuredBaseUrl = String.fromEnvironment(
    'AIOC_API_BASE_URL',
  );
  static String baseUrl = _normalizeBaseUrl(
    _configuredBaseUrl.isNotEmpty
        ? _configuredBaseUrl
        : 'http://127.0.0.1:8080/api/v1',
  );
  String? _accessToken;
  String? _refreshToken;

  static String _normalizeBaseUrl(String raw) {
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  String? get _fallbackBaseUrl {
    const suffix = '/api/v1';
    if (baseUrl.endsWith(suffix)) {
      return baseUrl.substring(0, baseUrl.length - suffix.length);
    }
    return null;
  }

  Future<http.Response> _requestWithFallback(
    Future<http.Response> Function(String base) requestBuilder,
  ) async {
    var resp = await requestBuilder(baseUrl);
    if (resp.statusCode != 404) return resp;

    final fallback = _fallbackBaseUrl;
    if (fallback == null || fallback == baseUrl) return resp;

    resp = await requestBuilder(fallback);
    return resp;
  }

  void setTokens(String access, String refresh) {
    _accessToken = access;
    _refreshToken = refresh;
  }

  void clearTokens() {
    _accessToken = null;
    _refreshToken = null;
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
    'X-Client-Id':
        '00000000-0000-0000-0000-000000000102', // Default Windows Client ID
    'X-Client-Version': '1.0.0',
  };

  // ==================== Auth ====================

  Future<ApiResponse> login(String email, String password) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> refreshToken() async {
    if (_refreshToken == null) throw Exception('No refresh token');
    try {
      final resp = await http
          .post(
            Uri.parse('$baseUrl/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': _refreshToken}),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  // ==================== Chat ====================

  Stream<ChatStreamEvent> chatStream({
    required List<Map<String, dynamic>> messages,
    required String mode,
    List<String>? skills,
    String? sessionId,
    String? roleId,
    String? taskId,
    String? projectId,
  }) {
    final controller = StreamController<ChatStreamEvent>();
    final client = http.Client();

    Future<void> run() async {
      try {
        final request = http.Request('POST', Uri.parse('$baseUrl/chat/stream'));
        request.headers.addAll(_headers);
        final payload = <String, dynamic>{'messages': messages, 'mode': mode};
        if (skills?.isNotEmpty ?? false) payload['skills'] = skills;
        if (sessionId != null) payload['session_id'] = sessionId;
        if (roleId != null && roleId.isNotEmpty) payload['role_id'] = roleId;
        if (taskId != null && taskId.isNotEmpty) payload['task_id'] = taskId;
        if (projectId != null && projectId.isNotEmpty) {
          payload['project_id'] = projectId;
        }
        request.body = jsonEncode(payload);

        final response = await client.send(request);
        if (response.statusCode != 200) {
          final body = await response.stream.bytesToString();
          try {
            final err = jsonDecode(body);
            controller.add(
              ChatStreamEvent(
                type: 'error',
                data: err['msg'] ?? 'Unknown error',
              ),
            );
          } catch (_) {
            controller.add(
              ChatStreamEvent(
                type: 'error',
                data: 'Server error: ${response.statusCode}',
              ),
            );
          }
          await controller.close();
          return;
        }

        final stream = response.stream.transform(utf8.decoder);
        String buffer = '';

        await for (final chunk in stream) {
          buffer += chunk;
          final lines = buffer.split('\n');
          buffer = lines.removeLast();

          String? currentEvent;
          for (final line in lines) {
            if (line.startsWith('event: ')) {
              currentEvent = line.substring(7).trim();
            } else if (line.startsWith('data: ')) {
              final data = line.substring(6);
              if (currentEvent != null) {
                controller.add(ChatStreamEvent(type: currentEvent, data: data));
              }
            }
          }
        }
      } catch (e) {
        if (!controller.isClosed) {
          controller.add(ChatStreamEvent(type: 'error', data: e.toString()));
        }
      } finally {
        client.close();
        if (!controller.isClosed) await controller.close();
      }
    }

    controller.onCancel = () {
      client.close();
    };

    run();
    return controller.stream;
  }

  // ==================== Sessions ====================

  Future<ApiResponse> getSessions() async {
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl/sessions'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> getSession(String id) async {
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl/sessions/$id'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> createSession({
    String title = 'New Chat',
    String mode = 'economy',
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$baseUrl/sessions'),
            headers: _headers,
            body: jsonEncode({'title': title, 'model_mode': mode}),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> deleteSession(String sessionId) async {
    try {
      final resp = await http
          .delete(Uri.parse('$baseUrl/sessions/$sessionId'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  // ==================== Billing ====================

  Future<ApiResponse> getBillingSummary({String? period}) async {
    try {
      final query = period != null ? '?period=$period' : '';
      final resp = await http
          .get(Uri.parse('$baseUrl/billing/summary$query'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  // ==================== Client Capabilities ====================

  Future<ApiResponse> getCapabilities() async {
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl/client/capabilities'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> getSkills() async {
    try {
      final resp = await _requestWithFallback(
        (base) => http
            .get(Uri.parse('$base/client/skills'), headers: _headers)
            .timeout(const Duration(seconds: 10)),
      );
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> getUseCases() async {
    try {
      final resp = await _requestWithFallback(
        (base) => http
            .get(Uri.parse('$base/client/use-cases'), headers: _headers)
            .timeout(const Duration(seconds: 10)),
      );
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> getProjects() async {
    try {
      final resp = await _requestWithFallback(
        (base) => http
            .get(Uri.parse('$base/projects'), headers: _headers)
            .timeout(const Duration(seconds: 10)),
      );
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> createProject({
    required String name,
    String description = '',
  }) async {
    try {
      final resp = await _requestWithFallback(
        (base) => http
            .post(
              Uri.parse('$base/projects'),
              headers: _headers,
              body: jsonEncode({'name': name, 'description': description}),
            )
            .timeout(const Duration(seconds: 10)),
      );
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> getProjectSources(String projectId) async {
    try {
      final resp = await _requestWithFallback(
        (base) => http
            .get(
              Uri.parse('$base/projects/$projectId/sources'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 10)),
      );
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> createProjectSource({
    required String projectId,
    required String sourceType,
    required String name,
    String sourceId = '',
    String contentText = '',
    String filePath = '',
    String linkUrl = '',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final resp = await _requestWithFallback(
        (base) => http
            .post(
              Uri.parse('$base/projects/$projectId/sources'),
              headers: _headers,
              body: jsonEncode({
                if (sourceId.isNotEmpty) 'source_id': sourceId,
                'source_type': sourceType,
                'name': name,
                'content_text': contentText,
                'file_path': filePath,
                'link_url': linkUrl,
                'metadata': metadata ?? <String, dynamic>{},
              }),
            )
            .timeout(const Duration(seconds: 15)),
      );
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> getSources() async {
    try {
      final resp = await _requestWithFallback(
        (base) => http
            .get(Uri.parse('$base/sources'), headers: _headers)
            .timeout(const Duration(seconds: 10)),
      );
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> createSource({
    required String sourceType,
    required String name,
    String contentText = '',
    String filePath = '',
    String linkUrl = '',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final resp = await _requestWithFallback(
        (base) => http
            .post(
              Uri.parse('$base/sources'),
              headers: _headers,
              body: jsonEncode({
                'source_type': sourceType,
                'name': name,
                'content_text': contentText,
                'file_path': filePath,
                'link_url': linkUrl,
                'metadata': metadata ?? <String, dynamic>{},
              }),
            )
            .timeout(const Duration(seconds: 15)),
      );
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> updateSource({
    required String sourceId,
    required String sourceType,
    required String name,
    String contentText = '',
    String filePath = '',
    String linkUrl = '',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final resp = await http
          .put(
            Uri.parse('$baseUrl/sources/$sourceId'),
            headers: _headers,
            body: jsonEncode({
              'source_type': sourceType,
              'name': name,
              'content_text': contentText,
              'file_path': filePath,
              'link_url': linkUrl,
              'metadata': metadata ?? <String, dynamic>{},
            }),
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> deleteSource(String sourceId) async {
    try {
      final resp = await http
          .delete(Uri.parse('$baseUrl/sources/$sourceId'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> deleteProjectSource({
    required String projectId,
    required String sourceId,
  }) async {
    try {
      final resp = await http
          .delete(
            Uri.parse('$baseUrl/projects/$projectId/sources/$sourceId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  // ==================== Automations ====================

  Future<ApiResponse> getAutomations() async {
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl/automations'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> createAutomation({
    required String name,
    required String prompt,
    required List<String> skills,
    String scheduleKind = 'interval',
    int intervalHours = 24,
    String timezone = 'UTC',
    bool runImmediately = false,
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$baseUrl/automations'),
            headers: _headers,
            body: jsonEncode({
              'name': name,
              'prompt': prompt,
              'skills': skills,
              'schedule_kind': scheduleKind,
              'interval_hours': intervalHours,
              'timezone': timezone,
              'run_immediately': runImmediately,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> updateAutomationStatus({
    required String automationId,
    required String status,
  }) async {
    try {
      final resp = await http
          .patch(
            Uri.parse('$baseUrl/automations/$automationId/status'),
            headers: _headers,
            body: jsonEncode({'status': status}),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> deleteAutomation(String automationId) async {
    try {
      final resp = await http
          .delete(
            Uri.parse('$baseUrl/automations/$automationId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> runAutomationNow(String automationId) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$baseUrl/automations/$automationId/run'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 120));
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> getAutomationRuns(String automationId) async {
    try {
      final resp = await http
          .get(
            Uri.parse('$baseUrl/automations/$automationId/runs'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  // ==================== Config Center (Admin) ====================

  Future<ApiResponse> getConfigCenterStatus() async {
    try {
      final resp = await _requestWithFallback(
        (base) => http
            .get(Uri.parse('$base/admin/config-center/status'), headers: _headers)
            .timeout(const Duration(seconds: 15)),
      );
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> validateConfigCenter() async {
    try {
      final resp = await _requestWithFallback(
        (base) => http
            .post(Uri.parse('$base/admin/config-center/validate'), headers: _headers)
            .timeout(const Duration(seconds: 20)),
      );
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> updateConfigCenterIntegration({
    required String integrationId,
    required bool configured,
    List<String>? missingFields,
    String notes = '',
  }) async {
    try {
      final resp = await _requestWithFallback(
        (base) => http
            .patch(
              Uri.parse('$base/admin/config-center/integrations/$integrationId'),
              headers: _headers,
              body: jsonEncode({
                'configured': configured,
                'missing_fields': missingFields ?? <String>[],
                'notes': notes,
              }),
            )
            .timeout(const Duration(seconds: 20)),
      );
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  // ==================== Tool Control Center (Admin) ====================

  Future<ApiResponse> getAdminTools() async {
    try {
      final resp = await _requestWithFallback(
        (base) => http
            .get(Uri.parse('$base/admin/tools'), headers: _headers)
            .timeout(const Duration(seconds: 15)),
      );
      final parsed = _handleResponse(resp);
      if (parsed.isSuccess) return parsed;

      final legacy = await _getLegacyConfigCenterStatus();
      if (!legacy.isSuccess || legacy.data is! Map) {
        return parsed;
      }
      final data = Map<String, dynamic>.from(legacy.data as Map);
      final legacyTools = _asMapList(data['tool_status']);
      final mapped = legacyTools
          .map(
            (t) => <String, dynamic>{
              'id': (t['tool_id'] ?? '').toString(),
              'name': (t['tool_id'] ?? '').toString(),
              'category': (t['category'] ?? '').toString(),
              'description': (t['notes'] ?? '').toString(),
              'risk_level': '',
              'is_enabled': t['enabled'] == true,
              'status': _mapLegacyToolStatus(t),
              'missing_integrations': _toStringList(t['missing_integrations']),
              'missing_binaries': _toStringList(t['missing_dependencies']),
              'last_check_at': '',
              'last_error_code': '',
              'last_error_message': (t['notes'] ?? '').toString(),
            },
          )
          .toList();
      return ApiResponse(code: 1, msg: 'ok (legacy fallback)', data: {'tools': mapped});
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> getAdminToolDetail(String toolId) async {
    try {
      final resp = await _requestWithFallback(
        (base) => http
            .get(Uri.parse('$base/admin/tools/$toolId'), headers: _headers)
            .timeout(const Duration(seconds: 15)),
      );
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> toggleAdminTool({
    required String toolId,
    required bool enabled,
  }) async {
    try {
      final resp = await _requestWithFallback(
        (base) => http
            .post(
              Uri.parse('$base/admin/tools/$toolId/toggle'),
              headers: _headers,
              body: jsonEncode({'enabled': enabled}),
            )
            .timeout(const Duration(seconds: 15)),
      );
      return _handleResponse(resp);
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> getAdminIntegrations() async {
    try {
      final resp = await _requestWithFallback(
        (base) => http
            .get(Uri.parse('$base/admin/integrations'), headers: _headers)
            .timeout(const Duration(seconds: 15)),
      );
      final parsed = _handleResponse(resp);
      if (parsed.isSuccess) return parsed;

      final legacy = await _getLegacyConfigCenterStatus();
      if (!legacy.isSuccess || legacy.data is! Map) {
        return parsed;
      }
      final data = Map<String, dynamic>.from(legacy.data as Map);
      final legacyIntegrations = _asMapList(data['integration_status']);
      final mapped = legacyIntegrations
          .map(
            (i) => <String, dynamic>{
              'id': (i['integration_id'] ?? '').toString(),
              'type': '',
              'display_name': (i['integration_id'] ?? '').toString(),
              'category': (i['category'] ?? '').toString(),
              'description': (i['notes'] ?? '').toString(),
              'required_fields': _toStringList(i['required_fields']),
              'optional_fields': const <String>[],
              'missing_fields': _toStringList(i['missing_fields']),
              'is_enabled': true,
              'status': _mapLegacyStatus((i['status'] ?? '').toString()),
              'last_check_at': (i['last_validated_at'] ?? '').toString(),
              'last_error_code': '',
              'last_error_message': (i['notes'] ?? '').toString(),
              'mandatory': i['mandatory'] == true,
              'check_type': '',
              'configured': i['configured'] == true,
            },
          )
          .toList();
      return ApiResponse(
        code: 1,
        msg: 'ok (legacy fallback)',
        data: {'integrations': mapped},
      );
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> getAdminStatusSummary() async {
    try {
      final resp = await _requestWithFallback(
        (base) => http
            .get(Uri.parse('$base/admin/status/summary'), headers: _headers)
            .timeout(const Duration(seconds: 15)),
      );
      final parsed = _handleResponse(resp);
      if (parsed.isSuccess) return parsed;

      final legacy = await _getLegacyConfigCenterStatus();
      if (!legacy.isSuccess || legacy.data is! Map) {
        return parsed;
      }
      final data = Map<String, dynamic>.from(legacy.data as Map);
      final summary = _toMap(data['summary']);
      final counts = _toMap(summary['counts']);
      final legacyTools = _asMapList(data['tool_status']);
      final legacyIntegrations = _asMapList(data['integration_status']);

      final issues = <Map<String, dynamic>>[];
      for (final t in legacyTools) {
        final s = _mapLegacyStatus((t['status'] ?? '').toString());
        if (s == 'OK') continue;
        issues.add({
          'kind': 'tool',
          'id': (t['tool_id'] ?? '').toString(),
          'name': (t['tool_id'] ?? '').toString(),
          'category': (t['category'] ?? '').toString(),
          'status': s,
          'last_error_code': '',
          'last_error_message': (t['notes'] ?? '').toString(),
        });
      }
      for (final i in legacyIntegrations) {
        final s = _mapLegacyStatus((i['status'] ?? '').toString());
        if (s == 'OK') continue;
        issues.add({
          'kind': 'integration',
          'id': (i['integration_id'] ?? '').toString(),
          'name': (i['integration_id'] ?? '').toString(),
          'category': (i['category'] ?? '').toString(),
          'status': s,
          'last_error_code': '',
          'last_error_message': (i['notes'] ?? '').toString(),
          'missing_fields': _toStringList(i['missing_fields']),
        });
      }

      return ApiResponse(
        code: 1,
        msg: 'ok (legacy fallback)',
        data: {
          'summary': {
            'ok': (counts['tools_ready'] ?? 0) + (counts['integrations_ready'] ?? 0),
            'warn': counts['tools_blocked'] ?? 0,
            'error': counts['mandatory_missing'] ?? 0,
            'disabled': 0,
            'missing_credentials': counts['integrations_missing'] ?? 0,
            'misconfigured': 0,
          },
          'issues': issues,
        },
      );
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> updateAdminIntegrationSecret({
    required String integrationId,
    required String secretKeyName,
    required String secretValue,
    String displayName = '',
    bool? isEnabled,
  }) async {
    try {
      final body = <String, dynamic>{
        'secret_key_name': secretKeyName,
        'secret_value': secretValue,
        if (displayName.isNotEmpty) 'display_name': displayName,
        ...?isEnabled != null ? {'is_enabled': isEnabled} : null,
      };
      final resp = await _requestWithFallback(
        (base) => http
            .post(
              Uri.parse('$base/admin/integrations/$integrationId/secret'),
              headers: _headers,
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 20)),
      );
      final parsed = _handleResponse(resp);
      if (parsed.isSuccess) return parsed;

      // Legacy fallback: mark integration configured and clear missing fields.
      final legacyResp = await _requestWithFallback(
        (base) => http
            .patch(
              Uri.parse('$base/admin/config-center/integrations/$integrationId'),
              headers: _headers,
              body: jsonEncode({
                'configured': true,
                'missing_fields': <String>[],
                'notes':
                    'configured via legacy fallback; secret stored externally or pending migration',
              }),
            )
            .timeout(const Duration(seconds: 20)),
      );
      final legacyParsed = _handleResponse(legacyResp);
      if (!legacyParsed.isSuccess) return parsed;

      // Trigger legacy revalidation so status panel can refresh blockers.
      await validateConfigCenter();
      return ApiResponse(
        code: 1,
        msg: 'ok (legacy fallback)',
        data: legacyParsed.data,
      );
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> checkAdminIntegration(String integrationId) async {
    try {
      final resp = await _requestWithFallback(
        (base) => http
            .post(
              Uri.parse('$base/admin/integrations/$integrationId/check'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 20)),
      );
      final parsed = _handleResponse(resp);
      if (parsed.isSuccess) return parsed;

      // Legacy fallback only supports full validate.
      final legacy = await validateConfigCenter();
      if (!legacy.isSuccess) return parsed;
      return ApiResponse(
        code: 1,
        msg: 'checked via legacy validate',
        data: {'integration_id': integrationId, 'status': 'WARN', 'cached': false},
      );
    } catch (e) {
      return ApiResponse(code: 0, msg: e.toString());
    }
  }

  Future<ApiResponse> _getLegacyConfigCenterStatus() async {
    final resp = await _requestWithFallback(
      (base) => http
          .get(Uri.parse('$base/admin/config-center/status'), headers: _headers)
          .timeout(const Duration(seconds: 15)),
    );
    return _handleResponse(resp);
  }

  static Map<String, dynamic> _toMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _asMapList(dynamic v) {
    if (v is! List) return const <Map<String, dynamic>>[];
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static List<String> _toStringList(dynamic v) {
    if (v is! List) return const <String>[];
    return v.map((e) => e.toString()).toList();
  }

  static String _mapLegacyStatus(String status) {
    switch (status.toLowerCase()) {
      case 'ok':
        return 'OK';
      case 'blocked':
        return 'MISSING_CREDENTIALS';
      case 'warn':
        return 'WARN';
      case 'unknown':
        return 'WARN';
      default:
        return 'WARN';
    }
  }

  static String _mapLegacyToolStatus(Map<String, dynamic> row) {
    final deps = _toStringList(row['missing_dependencies']);
    if (deps.isNotEmpty) return 'MISCONFIGURED';
    return _mapLegacyStatus((row['status'] ?? '').toString());
  }

  // ==================== Health ====================

  Future<bool> healthCheck() async {
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  ApiResponse _handleResponse(http.Response resp) {
    if (resp.body.isEmpty) {
      return ApiResponse(
        code: 0,
        msg: 'Server returned empty response (Status: ${resp.statusCode})',
      );
    }
    try {
      final data = jsonDecode(resp.body);
      return ApiResponse.fromJson(data);
    } catch (e) {
      final ct = resp.headers['content-type'] ?? '';
      final preview = resp.body.length > 120
          ? '${resp.body.substring(0, 120)}...'
          : resp.body;
      if (resp.statusCode == 404 && ct.contains('text/html')) {
        return ApiResponse(
          code: 0,
          msg:
              'HTTP 404 (HTML). API base 可能不正确，当前为 $baseUrl。'
              '请检查是否连到了 Flutter 开发端口而不是 Gateway。'
              '可用 --dart-define=AIOC_API_BASE_URL=http://127.0.0.1:8080/api/v1',
        );
      }
      return ApiResponse(
        code: 0,
        msg: 'Invalid JSON response (Status: ${resp.statusCode}): $preview',
      );
    }
  }
}

class ApiResponse {
  final int code;
  final String msg;
  final dynamic data;
  final String traceId;

  ApiResponse({
    required this.code,
    required this.msg,
    this.data,
    this.traceId = '',
  });

  bool get isSuccess => code == 1;

  factory ApiResponse.fromJson(Map<String, dynamic> json) {
    return ApiResponse(
      code: json['code'] ?? 0,
      msg: json['msg'] ?? '',
      data: json['data'],
      traceId: json['trace_id'] ?? '',
    );
  }
}

class ChatStreamEvent {
  final String type;
  final String data;

  ChatStreamEvent({required this.type, required this.data});
}
