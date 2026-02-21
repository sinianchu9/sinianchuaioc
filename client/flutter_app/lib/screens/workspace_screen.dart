import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import 'chat_screen.dart';
import 'projects_screen.dart';
import 'project_detail_screen.dart';

class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  // Whether we are explicitly viewing the project details
  bool _showProjectDetails = false;

  // Whether we are explicitly entering the chat workspace
  bool _showChatWorkspace = false;

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final hasActiveProject = chatState.selectedProjectId.isNotEmpty;

    Widget currentView;

    if (hasActiveProject && _showChatWorkspace) {
      currentView = ChatScreen(
        onBack: () {
          // Return to project details
          setState(() {
            _showChatWorkspace = false;
            _showProjectDetails = true;
          });
        },
      );
    } else if (hasActiveProject && _showProjectDetails) {
      currentView = ProjectDetailScreen(
        onBack: () {
          // Return to project grid
          ref.read(chatProvider.notifier).selectProject('');
          setState(() {
            _showProjectDetails = false;
            _showChatWorkspace = false;
          });
        },
        onOpenChat: () {
          setState(() {
            _showChatWorkspace = true;
            _showProjectDetails = false;
          });
        },
      );
    } else {
      // Default dashboard view
      currentView = ProjectsScreen(
        onSelectProject: () {
          setState(() {
            _showProjectDetails = true;
          });
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Expanded(child: currentView)],
    );
  }
}
