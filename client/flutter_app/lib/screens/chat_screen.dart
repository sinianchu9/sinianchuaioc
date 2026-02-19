import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_localizations.dart';
import '../core/theme.dart';
import '../providers/chat_provider.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatProvider);
    final session = chatState.activeSession;
    final l10n = context.l10n;

    return Container(
      color: AIOCTheme.background,
      child: Column(
        children: [
          // Top bar
          _buildTopBar(context, chatState, l10n),

          // Messages
          Expanded(
            child: session == null || session.messages.isEmpty
                ? _buildEmptyState(ref, l10n)
                : _buildMessageList(session.messages),
          ),

          // Error banner
          if (chatState.error != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AIOCTheme.error.withOpacity(0.1),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber,
                    color: AIOCTheme.error,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      chatState.error!,
                      style: const TextStyle(
                        color: AIOCTheme.error,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Input
          ChatInput(
            onSend: (text) => ref.read(chatProvider.notifier).sendMessage(text),
            onStop: () => ref.read(chatProvider.notifier).stopGeneration(),
            isStreaming: chatState.isStreaming,
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    ChatState state,
    AppLocalizations l10n,
  ) {
    final skillNames = state.skills
        .where((s) => state.selectedSkillIds.contains(s.id))
        .map((s) => s.name)
        .toList();
    final skillLabel = skillNames.isEmpty
        ? l10n.t('generalAssistant')
        : skillNames.join(' · ');
    final scenarioLabel = state.selectedRoleId.isEmpty
        ? '未选择场景'
        : '${state.selectedRoleId}/${state.selectedTaskId}';
    final projectName = state.projects
        .where((p) => p.id == state.selectedProjectId)
        .map((p) => p.name)
        .toList();
    final projectLabel = state.selectedProjectId.isEmpty
        ? '未选择项目'
        : (projectName.isNotEmpty
              ? projectName.first
              : state.selectedProjectId);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AIOCTheme.surface,
        border: Border(
          bottom: BorderSide(color: AIOCTheme.surfaceLight.withOpacity(0.5)),
        ),
      ),
      child: Row(
        children: [
          Text(
            state.activeSession?.title ?? l10n.t('chat'),
            style: const TextStyle(
              color: AIOCTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // Skill indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AIOCTheme.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AIOCTheme.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  skillLabel,
                  style: TextStyle(
                    color: AIOCTheme.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AIOCTheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$scenarioLabel | $projectLabel',
              style: const TextStyle(
                color: AIOCTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(WidgetRef ref, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AIOCTheme.primary.withOpacity(0.3),
                  AIOCTheme.accent.withOpacity(0.3),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 32,
              color: AIOCTheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.t('startConversation'),
            style: TextStyle(
              color: AIOCTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.t('typeToStart'),
            style: TextStyle(color: AIOCTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 18),
          Text(
            l10n.t('quickTasks'),
            style: TextStyle(
              color: AIOCTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _quickTaskChip(
                ref,
                label: l10n.t('systemInspect'),
                prompt:
                    'Use OpenClaw tools to run pwd and ls, then summarize the environment.',
              ),
              _quickTaskChip(
                ref,
                label: l10n.t('processSnapshot'),
                prompt:
                    'Use OpenClaw tools to run whoami and ps, then provide a concise status report.',
              ),
              _quickTaskChip(
                ref,
                label: l10n.t('chartDemo'),
                prompt:
                    'Generate a data chart component with a weekly CPU usage example and explain the trend.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickTaskChip(
    WidgetRef ref, {
    required String label,
    required String prompt,
  }) {
    return OutlinedButton(
      onPressed: () => ref.read(chatProvider.notifier).sendMessage(prompt),
      style: OutlinedButton.styleFrom(
        foregroundColor: AIOCTheme.textPrimary,
        side: BorderSide(color: AIOCTheme.surfaceLight.withOpacity(0.6)),
      ),
      child: Text(label),
    );
  }

  Widget _buildMessageList(List<ChatMessage> messages) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: messages.length,
      reverse: false,
      itemBuilder: (ctx, i) => MessageBubble(message: messages[i]),
    );
  }
}
