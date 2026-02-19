import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../core/app_localizations.dart';
import '../core/theme.dart';
import '../providers/chat_provider.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) _buildAvatar(isUser),
          if (!isUser) const SizedBox(width: 10),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.65,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser
                    ? AIOCTheme.primary.withOpacity(0.2)
                    : AIOCTheme.surfaceCard,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: Border.all(
                  color: isUser
                      ? AIOCTheme.primary.withOpacity(0.3)
                      : AIOCTheme.surfaceLight.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isUser && message.toolEvents.isNotEmpty)
                    _buildToolTimeline(context, message.toolEvents),
                  if (!isUser && message.toolEvents.isNotEmpty)
                    const SizedBox(height: 10),
                  if (!isUser && message.executionSummary != null)
                    _buildExecutionSummary(context, message.executionSummary!),
                  if (!isUser && message.executionSummary != null)
                    const SizedBox(height: 10),
                  if (message.content.isEmpty && message.isStreaming)
                    _buildStreamingIndicator(context)
                  else
                    _buildContent(context, isUser),
                  if (!isUser && message.content.isNotEmpty)
                    _buildActions(context),
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 10),
          if (isUser) _buildAvatar(isUser),
        ],
      ),
    );
  }

  Widget _buildAvatar(bool isUser) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isUser
              ? [AIOCTheme.primary, AIOCTheme.primaryDark]
              : [AIOCTheme.accent, const Color(0xFF0099CC)],
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        isUser ? Icons.person : Icons.auto_awesome,
        size: 18,
        color: Colors.white,
      ),
    );
  }

  Widget _buildStreamingIndicator(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AIOCTheme.accent,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          context.l10n.t('thinking'),
          style: const TextStyle(color: AIOCTheme.textSecondary, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, bool isUser) {
    if (message.component != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildUIComponent(context),
          if (message.content.isNotEmpty) const SizedBox(height: 12),
          if (message.content.isNotEmpty) _buildMarkdown(context),
        ],
      );
    }

    if (isUser) {
      return SelectableText(
        message.content,
        style: const TextStyle(
          color: AIOCTheme.textPrimary,
          fontSize: 14,
          height: 1.5,
        ),
      );
    }
    return _buildMarkdown(context);
  }

  Widget _buildMarkdown(BuildContext context) {
    return MarkdownBody(
      data: message.content,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(
          color: AIOCTheme.textPrimary,
          fontSize: 14,
          height: 1.6,
        ),
      ),
    );
  }

  Widget _buildUIComponent(BuildContext context) {
    final l10n = context.l10n;
    final component = message.component;
    final args = message.componentArgs ?? {};

    if (component == 'calendar') {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AIOCTheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AIOCTheme.primary.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_month, color: AIOCTheme.accent),
                const SizedBox(width: 8),
                Text(
                  args['title'] ?? l10n.t('selectDate'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            CalendarDatePicker(
              initialDate: DateTime.now(),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              onDateChanged: (_) {},
            ),
          ],
        ),
      );
    }

    if (component == 'data_chart') {
      return _buildDataChart(context, args);
    }
    if (component == 'artifact_file') {
      return _buildArtifactCard(context, args, bundled: false);
    }
    if (component == 'artifact_bundle') {
      return _buildArtifactCard(context, args, bundled: true);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(l10n.tf('unknownComponent', {'component': '$component'})),
    );
  }

  Widget _buildArtifactCard(
    BuildContext context,
    Map<String, dynamic> args, {
    required bool bundled,
  }) {
    final path = '${args[bundled ? 'bundle_path' : 'file_path'] ?? ''}';
    final filename = '${args['filename'] ?? ''}';
    final outputType = '${args['actual_type'] ?? args['requested_type'] ?? ''}';
    final size = '${args['size_bytes'] ?? 0}';
    final warning = '${args['warning'] ?? ''}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AIOCTheme.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AIOCTheme.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                bundled ? Icons.archive_outlined : Icons.description_outlined,
                color: AIOCTheme.accent,
              ),
              const SizedBox(width: 8),
              Text(
                bundled ? '文件包已生成' : '产物文件已生成',
                style: const TextStyle(
                  color: AIOCTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (filename.isNotEmpty)
            Text(
              '文件名: $filename',
              style: const TextStyle(
                color: AIOCTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          if (outputType.isNotEmpty)
            Text(
              '类型: $outputType',
              style: const TextStyle(
                color: AIOCTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          Text(
            '大小: $size bytes',
            style: const TextStyle(
              color: AIOCTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          if (warning.isNotEmpty)
            Text(
              '提示: $warning',
              style: const TextStyle(color: AIOCTheme.warning, fontSize: 12),
            ),
          if (path.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              path,
              style: const TextStyle(color: AIOCTheme.accent, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDataChart(BuildContext context, Map<String, dynamic> args) {
    final l10n = context.l10n;
    final String type = args['type'] ?? 'bar';
    final List<dynamic> labels = args['labels'] ?? [];
    final List<dynamic> values = args['values'] ?? [];
    final String title = args['title'] ?? l10n.t('dataVisualization');

    if (labels.isEmpty || values.isEmpty) {
      return Text(l10n.t('invalidChartData'));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AIOCTheme.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AIOCTheme.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AIOCTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: type == 'pie'
                ? _buildPieChart(values, labels)
                : _buildBarChart(values, labels),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(List<dynamic> values, List<dynamic> labels) {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY:
            values
                .map((e) => (e as num).toDouble())
                .reduce((a, b) => a > b ? a : b) *
            1.2,
        barGroups: List.generate(values.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: (values[i] as num).toDouble(),
                color: AIOCTheme.accent,
                width: 16,
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildPieChart(List<dynamic> values, List<dynamic> labels) {
    final colors = [
      AIOCTheme.primary,
      AIOCTheme.accent,
      Colors.purple,
      Colors.orange,
      Colors.teal,
    ];
    return PieChart(
      PieChartData(
        sections: List.generate(values.length, (i) {
          return PieChartSectionData(
            color: colors[i % colors.length],
            value: (values[i] as num).toDouble(),
            title: labels[i].toString(),
            radius: 50,
          );
        }),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _actionButton(Icons.copy, l10n.t('copy'), () {
            Clipboard.setData(ClipboardData(text: message.content));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.t('copied')),
                duration: const Duration(seconds: 1),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildToolTimeline(BuildContext context, List<ToolTraceEvent> events) {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AIOCTheme.background.withOpacity(0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AIOCTheme.surfaceLight.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.t('executionTimeline'),
            style: const TextStyle(
              color: AIOCTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          ...events.map((e) {
            final isStart = e.phase == 'start';
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isStart ? Icons.play_circle_outline : Icons.check_circle,
                    size: 14,
                    color: isStart ? AIOCTheme.warning : AIOCTheme.success,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${e.tool} · ${isStart ? 'start' : 'result'}\n${e.details}',
                      style: const TextStyle(
                        color: AIOCTheme.textSecondary,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AIOCTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: AIOCTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutionSummary(
    BuildContext context,
    Map<String, dynamic> summary,
  ) {
    final l10n = context.l10n;
    final model = '${summary['model'] ?? 'unknown'}';
    final tokensIn = '${summary['tokens_in'] ?? 0}';
    final tokensOut = '${summary['tokens_out'] ?? 0}';
    final cost = '${summary['cost'] ?? '0.000000'}';
    final fallback = '${summary['fallback_used'] ?? false}';
    final requestID = '${summary['request_id'] ?? ''}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AIOCTheme.background.withOpacity(0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AIOCTheme.surfaceLight.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.t('executionSummary'),
            style: const TextStyle(
              color: AIOCTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'model: $model  in:$tokensIn  out:$tokensOut  cost:\$$cost  fallback:$fallback',
            style: const TextStyle(
              color: AIOCTheme.textSecondary,
              fontSize: 11,
            ),
          ),
          if (requestID.isNotEmpty) ...[
            const SizedBox(height: 4),
            SelectableText(
              'request_id: $requestID',
              style: const TextStyle(
                color: AIOCTheme.textSecondary,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
