import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_localizations.dart';
import '../core/theme.dart';

import '../providers/auth_provider.dart';

class UsageScreen extends ConsumerStatefulWidget {
  const UsageScreen({super.key});

  @override
  ConsumerState<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends ConsumerState<UsageScreen> {
  Map<String, dynamic>? _billingData;
  Map<String, dynamic>? _capabilities;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final api = ref.read(apiServiceProvider);
    try {
      final billingResp = await api.getBillingSummary();
      final capsResp = await api.getCapabilities();

      setState(() {
        if (billingResp.isSuccess) _billingData = billingResp.data;
        if (capsResp.isSuccess) _capabilities = capsResp.data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final l10n = context.l10n;
      setState(() {
        _error = l10n.tf('failedLoadData', {'error': '$e'});
        _isLoading = false;
      });
    }
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
                Text(
                  l10n.t('usageBilling'),
                  style: const TextStyle(
                    color: AIOCTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    Icons.refresh,
                    color: AIOCTheme.textSecondary,
                  ),
                  onPressed: _loadData,
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AIOCTheme.primary),
                  )
                : _error != null
                ? Center(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AIOCTheme.error),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPlanCard(l10n),
                        const SizedBox(height: 16),
                        _buildUsageCards(l10n),
                        const SizedBox(height: 16),
                        _buildCapabilitiesCard(l10n),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(AppLocalizations l10n) {
    final plan = _billingData?['plan_level'] ?? 'free';
    final balance = _billingData?['balance'] ?? '0.000000';

    final planColors = {
      'free': AIOCTheme.textSecondary,
      'pro': AIOCTheme.primary,
      'team': AIOCTheme.accent,
      'enterprise': AIOCTheme.warning,
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            (planColors[plan] ?? AIOCTheme.primary).withOpacity(0.15),
            AIOCTheme.surfaceCard,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (planColors[plan] ?? AIOCTheme.primary).withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: (planColors[plan] ?? AIOCTheme.primary).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.diamond_outlined,
              color: planColors[plan] ?? AIOCTheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${plan.toUpperCase()} ${l10n.t('plan')}',
                  style: TextStyle(
                    color: planColors[plan] ?? AIOCTheme.primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${l10n.t('balance')}: \$$balance',
                  style: const TextStyle(
                    color: AIOCTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageCards(AppLocalizations l10n) {
    final tokensIn = _billingData?['total_tokens_in'] ?? 0;
    final tokensOut = _billingData?['total_tokens_out'] ?? 0;
    final cost = _billingData?['total_cost'] ?? '0.000000';
    final requests = _billingData?['request_count'] ?? 0;
    final period = _billingData?['period'] ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.tf('usageFor', {'period': '$period'}),
          style: const TextStyle(
            color: AIOCTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _metricCard(
                l10n.t('requests'),
                '$requests',
                Icons.call_made,
                AIOCTheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _metricCard(
                l10n.t('cost'),
                '\$$cost',
                Icons.attach_money,
                AIOCTheme.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _metricCard(
                l10n.t('tokensIn'),
                _formatNumber(tokensIn),
                Icons.input,
                AIOCTheme.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _metricCard(
                l10n.t('tokensOut'),
                _formatNumber(tokensOut),
                Icons.output,
                AIOCTheme.economyColor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _metricCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AIOCTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AIOCTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: AIOCTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapabilitiesCard(AppLocalizations l10n) {
    if (_capabilities == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.t('features'),
          style: const TextStyle(
            color: AIOCTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AIOCTheme.surfaceCard,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _featureRow(l10n.t('chat'), _capabilities?['chat'] ?? false),
              _featureRow(
                l10n.t('streaming'),
                _capabilities?['stream'] ?? false,
              ),
              _featureRow(l10n.t('tools'), _capabilities?['tools'] ?? false),
              _featureRow('RAG', _capabilities?['rag'] ?? false),
              const Divider(color: AIOCTheme.surfaceLight),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.model_training,
                      size: 16,
                      color: AIOCTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.t('models'),
                      style: const TextStyle(
                        color: AIOCTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      (_capabilities?['models'] as List?)?.join(', ') ??
                          'economy',
                      style: const TextStyle(
                        color: AIOCTheme.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.layers,
                      size: 16,
                      color: AIOCTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.t('maxSessions'),
                      style: const TextStyle(
                        color: AIOCTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_capabilities?['max_sessions'] ?? 5}',
                      style: const TextStyle(
                        color: AIOCTheme.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _featureRow(String label, bool enabled) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: enabled ? AIOCTheme.success : AIOCTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: enabled ? AIOCTheme.textPrimary : AIOCTheme.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(dynamic n) {
    final num = int.tryParse('$n') ?? 0;
    if (num >= 1000000) return '${(num / 1000000).toStringAsFixed(1)}M';
    if (num >= 1000) return '${(num / 1000).toStringAsFixed(1)}K';
    return '$num';
  }
}
