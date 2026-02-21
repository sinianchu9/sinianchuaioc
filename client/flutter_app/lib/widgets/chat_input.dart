import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/app_localizations.dart';
import '../core/theme.dart';

class ChatInputSkill {
  final String id;
  final String name;

  const ChatInputSkill({required this.id, required this.name});
}

class ChatInput extends StatefulWidget {
  final Function(String) onSend;
  final VoidCallback? onStop;
  final bool isStreaming;
  final List<ChatInputSkill> skills;
  final List<String> selectedSkillIds;
  final ValueChanged<String>? onAddSkill;
  final ValueChanged<String>? onRemoveSkill;

  const ChatInput({
    super.key,
    required this.onSend,
    this.onStop,
    required this.isStreaming,
    this.skills = const [],
    this.selectedSkillIds = const [],
    this.onAddSkill,
    this.onRemoveSkill,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  static const int _maxFileBytes = 256 * 1024;
  static const int _maxEmbeddedChars = 12000;
  static const Set<String> _textExtensions = {
    'txt',
    'md',
    'markdown',
    'json',
    'yaml',
    'yml',
    'csv',
    'xml',
    'html',
    'htm',
    'js',
    'ts',
    'tsx',
    'jsx',
    'py',
    'go',
    'java',
    'c',
    'cc',
    'cpp',
    'h',
    'hpp',
    'cs',
    'rs',
    'php',
    'rb',
    'sh',
    'sql',
    'log',
    'ini',
    'conf',
    'toml',
  };

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _canSend = false;
  bool _isPickingFile = false;
  String? _attachedFileName;
  int? _attachedFileBytes;
  DateTime _lastSendTime = DateTime(2000);
  String _slashQuery = '';
  int _slashAnchor = -1;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isStreaming) return;

    final now = DateTime.now();
    if (now.difference(_lastSendTime).inMilliseconds < 500) return;
    _lastSendTime = now;

    widget.onSend(text);
    _controller.clear();
    _attachedFileName = null;
    _attachedFileBytes = null;
    setState(() {
      _canSend = false;
      _slashQuery = '';
      _slashAnchor = -1;
    });
    _focusNode.requestFocus();
  }

  void _updateSlashState(String text) {
    final cursor = _controller.selection.baseOffset;
    final upto = cursor >= 0 && cursor <= text.length ? text.substring(0, cursor) : text;
    final idx = upto.lastIndexOf('/');
    if (idx < 0) {
      if (_slashAnchor != -1 || _slashQuery.isNotEmpty) {
        setState(() {
          _slashAnchor = -1;
          _slashQuery = '';
        });
      }
      return;
    }

    if (idx > 0) {
      final prev = upto[idx - 1];
      if (prev.trim().isNotEmpty) {
        if (_slashAnchor != -1 || _slashQuery.isNotEmpty) {
          setState(() {
            _slashAnchor = -1;
            _slashQuery = '';
          });
        }
        return;
      }
    }

    final query = upto.substring(idx + 1);
    if (query.contains(RegExp(r'\s'))) {
      if (_slashAnchor != -1 || _slashQuery.isNotEmpty) {
        setState(() {
          _slashAnchor = -1;
          _slashQuery = '';
        });
      }
      return;
    }

    setState(() {
      _slashAnchor = idx;
      _slashQuery = query;
    });
  }

  List<ChatInputSkill> _slashSuggestions() {
    if (_slashAnchor < 0) return const [];
    final selected = widget.selectedSkillIds.toSet();
    final q = _slashQuery.trim().toLowerCase();
    final candidates = widget.skills.where((s) => !selected.contains(s.id));
    if (q.isEmpty) return candidates.take(8).toList();
    return candidates
        .where((s) => s.name.toLowerCase().contains(q) || s.id.toLowerCase().contains(q))
        .take(8)
        .toList();
  }

  void _chooseSkill(ChatInputSkill skill) {
    widget.onAddSkill?.call(skill.id);
    if (_slashAnchor >= 0 && _slashAnchor <= _controller.text.length) {
      final cursor = _controller.selection.baseOffset;
      final end = (cursor >= _slashAnchor && cursor <= _controller.text.length)
          ? cursor
          : _controller.text.length;
      final before = _controller.text.substring(0, _slashAnchor);
      final after = _controller.text.substring(end);
      final merged = (before + after).trimLeft();
      _controller.text = merged;
      _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
    }
    setState(() {
      _slashAnchor = -1;
      _slashQuery = '';
      _canSend = _controller.text.trim().isNotEmpty;
    });
    _focusNode.requestFocus();
  }

  Future<void> _pickFile() async {
    final l10n = context.l10n;
    if (widget.isStreaming || _isPickingFile) return;

    setState(() => _isPickingFile = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
      );
      if (!mounted || result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        _showError(l10n.t('fileReadError'));
        return;
      }
      if (bytes.length > _maxFileBytes) {
        _showError(l10n.tf('fileTooLarge', {'kb': '${_maxFileBytes ~/ 1024}'}));
        return;
      }

      final ext = (file.extension ?? '').toLowerCase();
      final isTextExt = _textExtensions.contains(ext);
      final likelyText = _isLikelyText(bytes);
      if (!isTextExt && !likelyText) {
        _showError(l10n.t('textFileOnly'));
        return;
      }

      String content = utf8.decode(bytes, allowMalformed: true).trim();
      if (content.isEmpty) {
        _showError(l10n.t('fileEmpty'));
        return;
      }

      bool truncated = false;
      if (content.length > _maxEmbeddedChars) {
        content = '${content.substring(0, _maxEmbeddedChars)}\n...[truncated]';
        truncated = true;
      }

      final payload = _buildFilePayload(
        fileName: file.name,
        bytes: bytes.length,
        content: content,
      );

      final current = _controller.text.trim();
      _controller.text = current.isEmpty ? payload : '$current\n\n$payload';
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );

      setState(() {
        _attachedFileName = file.name;
        _attachedFileBytes = bytes.length;
        _canSend = _controller.text.trim().isNotEmpty;
      });

      if (truncated) {
        _showInfo(l10n.tf('fileTruncated', {'chars': '$_maxEmbeddedChars'}));
      }
    } catch (e) {
      _showError(l10n.tf('filePickFailed', {'error': '$e'}));
    } finally {
      if (mounted) {
        setState(() => _isPickingFile = false);
      }
    }
  }

  bool _isLikelyText(Uint8List bytes) {
    int suspicious = 0;
    final sampleSize = bytes.length < 512 ? bytes.length : 512;
    for (int i = 0; i < sampleSize; i++) {
      final b = bytes[i];
      if (b == 0) return false;
      if (b < 9 || (b > 13 && b < 32)) suspicious++;
    }
    return suspicious < (sampleSize * 0.1);
  }

  String _buildFilePayload({
    required String fileName,
    required int bytes,
    required String content,
  }) {
    final l10n = context.l10n;
    return '[${l10n.t('fileAttachment')}]\n'
        'name: $fileName\n'
        'size: $bytes bytes\n'
        'content:\n'
        '```text\n'
        '$content\n'
        '```';
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AIOCTheme.error),
    );
  }

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selectedSkills = widget.skills
        .where((s) => widget.selectedSkillIds.contains(s.id))
        .toList();
    final suggestions = _slashSuggestions();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AIOCTheme.surface,
        border: Border(
          top: BorderSide(color: AIOCTheme.surfaceLight.withOpacity(0.5)),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selectedSkills.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: selectedSkills
                    .map(
                      (s) => InputChip(
                        label: Text(s.name, style: const TextStyle(fontSize: 12)),
                        onDeleted: widget.isStreaming ? null : () => widget.onRemoveSkill?.call(s.id),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        backgroundColor: AIOCTheme.surfaceCard,
                        side: BorderSide(color: AIOCTheme.surfaceLight.withOpacity(0.5)),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
            ],
            if (_attachedFileName != null) ...[
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AIOCTheme.surfaceCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AIOCTheme.surfaceLight.withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.insert_drive_file_outlined, size: 14, color: AIOCTheme.accent),
                        const SizedBox(width: 6),
                        Text(
                          '${_attachedFileName!} (${_attachedFileBytes ?? 0}B)',
                          style: const TextStyle(color: AIOCTheme.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () {
                            setState(() {
                              _attachedFileName = null;
                              _attachedFileBytes = null;
                            });
                          },
                          child: const Icon(Icons.close, size: 14, color: AIOCTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (suggestions.isNotEmpty) ...[
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 220),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AIOCTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AIOCTheme.surfaceLight.withOpacity(0.5)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: suggestions.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: AIOCTheme.surfaceLight.withOpacity(0.3)),
                  itemBuilder: (context, index) {
                    final s = suggestions[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.bolt_outlined, size: 16, color: AIOCTheme.accent),
                      title: Text(s.name, style: const TextStyle(fontSize: 13, color: AIOCTheme.textPrimary)),
                      subtitle: Text('/${s.id}', style: const TextStyle(fontSize: 11, color: AIOCTheme.textSecondary)),
                      onTap: widget.isStreaming ? null : () => _chooseSkill(s),
                    );
                  },
                ),
              ),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Material(
                    color: AIOCTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: (widget.isStreaming || _isPickingFile) ? null : _pickFile,
                      borderRadius: BorderRadius.circular(12),
                      child: Center(
                        child: _isPickingFile
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AIOCTheme.accent),
                              )
                            : const Icon(Icons.attach_file_rounded, size: 20, color: AIOCTheme.textSecondary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    decoration: BoxDecoration(
                      color: AIOCTheme.surfaceCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _focusNode.hasFocus
                            ? AIOCTheme.primary.withOpacity(0.5)
                            : Colors.transparent,
                      ),
                    ),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      maxLines: 6,
                      minLines: 1,
                      style: const TextStyle(color: AIOCTheme.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '${l10n.t('typeOrAttach')}  (输入 / 选择技能)',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      textInputAction: TextInputAction.newline,
                      onChanged: (text) {
                        final canSend = text.trim().isNotEmpty;
                        _updateSlashState(text);
                        if (canSend != _canSend) {
                          setState(() => _canSend = canSend);
                        }
                      },
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: _canSend && !widget.isStreaming
                        ? const LinearGradient(colors: [AIOCTheme.primary, AIOCTheme.accent])
                        : null,
                    color: _canSend && !widget.isStreaming ? null : AIOCTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.isStreaming ? widget.onStop : (_canSend ? _send : null),
                      borderRadius: BorderRadius.circular(12),
                      child: widget.isStreaming
                          ? const Center(
                              child: Icon(Icons.stop_rounded, size: 28, color: AIOCTheme.error),
                            )
                          : Icon(
                              Icons.send_rounded,
                              size: 20,
                              color: _canSend ? Colors.white : AIOCTheme.textSecondary,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
