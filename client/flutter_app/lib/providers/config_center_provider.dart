import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

class ConfigCenterState {
  final bool loading;
  final bool saving;
  final String? error;
  final Map<String, dynamic> panel;

  const ConfigCenterState({
    this.loading = false,
    this.saving = false,
    this.error,
    this.panel = const {},
  });

  ConfigCenterState copyWith({
    bool? loading,
    bool? saving,
    String? error,
    Map<String, dynamic>? panel,
  }) {
    return ConfigCenterState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      error: error,
      panel: panel ?? this.panel,
    );
  }
}

class ConfigCenterNotifier extends StateNotifier<ConfigCenterState> {
  ConfigCenterNotifier(this._ref) : super(const ConfigCenterState());

  final Ref _ref;

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final api = _ref.read(apiServiceProvider);
      final resp = await api.getConfigCenterStatus();
      if (!resp.isSuccess || resp.data is! Map<String, dynamic>) {
        state = state.copyWith(loading: false, error: resp.msg);
        return;
      }
      state = state.copyWith(
        loading: false,
        panel: Map<String, dynamic>.from(resp.data as Map),
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: 'Failed to load panel: $e');
    }
  }

  Future<void> validate() async {
    state = state.copyWith(saving: true, error: null);
    try {
      final api = _ref.read(apiServiceProvider);
      final resp = await api.validateConfigCenter();
      if (!resp.isSuccess || resp.data is! Map<String, dynamic>) {
        state = state.copyWith(saving: false, error: resp.msg);
        return;
      }
      state = state.copyWith(
        saving: false,
        panel: Map<String, dynamic>.from(resp.data as Map),
      );
    } catch (e) {
      state = state.copyWith(saving: false, error: 'Failed to validate: $e');
    }
  }

  Future<void> setIntegrationConfigured({
    required String integrationId,
    required bool configured,
  }) async {
    state = state.copyWith(saving: true, error: null);
    try {
      final api = _ref.read(apiServiceProvider);
      final resp = await api.updateConfigCenterIntegration(
        integrationId: integrationId,
        configured: configured,
        missingFields: configured ? const <String>[] : null,
      );
      if (!resp.isSuccess || resp.data is! Map<String, dynamic>) {
        state = state.copyWith(saving: false, error: resp.msg);
        return;
      }
      state = state.copyWith(
        saving: false,
        panel: Map<String, dynamic>.from(resp.data as Map),
      );
    } catch (e) {
      state = state.copyWith(
        saving: false,
        error: 'Failed to update integration: $e',
      );
    }
  }
}

final configCenterProvider =
    StateNotifierProvider<ConfigCenterNotifier, ConfigCenterState>((ref) {
      return ConfigCenterNotifier(ref);
    });

