import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class ChatScreen extends StatefulWidget {
  final String patientUsername;
  final bool asDoctor;
  final String? doctorName;
  final String? patientDisplayName;
  final bool readOnly;
  final String? bannerText;

  const ChatScreen({
    super.key,
    required this.patientUsername,
    this.asDoctor = false,
    this.doctorName,
    this.patientDisplayName,
    this.readOnly = false,
    this.bannerText,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;
  bool _loading = true;
  bool _showSlowHint = false;
  List<dynamic> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _showSlowHint = false;
      });
    }

    // If server is cold-starting or network is slow, show a hint rather than feeling "stuck".
    unawaited(
      Future<void>.delayed(const Duration(seconds: 8)).then((_) {
        if (!mounted) return;
        if (_loading) setState(() => _showSlowHint = true);
      }),
    );

    try {
      final res = widget.asDoctor
          ? await ApiService.getDoctorChatThread(widget.patientUsername)
          : await ApiService.getChatThread();
      if (!mounted) return;
      setState(() {
        _messages = res ?? [];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages = [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
        _scrollToEnd();
      }
    }
  }

  Future<void> _sendMessage() async {
    if (widget.readOnly) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _sending = true;
    });
    final ok = widget.asDoctor
        ? await ApiService.sendDoctorChatMessage(widget.patientUsername, text)
        : await ApiService.sendChatMessage(text);
    if (ok) {
      _controller.clear();
      await _loadMessages();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to send message'), backgroundColor: Colors.redAccent));
      }
    }
    if (mounted) {
      setState(() {
        _sending = false;
      });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doctorLabel = (widget.doctorName != null && widget.doctorName!.trim().isNotEmpty)
        ? widget.doctorName!.trim()
        : 'Doctor';
    final patientLabel = (widget.patientDisplayName != null && widget.patientDisplayName!.trim().isNotEmpty)
        ? widget.patientDisplayName!.trim()
        : widget.patientUsername;
    final title = widget.asDoctor ? 'Chat • $patientLabel' : 'Chat with $doctorLabel';

    final showTreatmentCompleteSeparator = widget.readOnly;
    final treatmentCompleteText = (widget.bannerText != null && widget.bannerText!.trim().isNotEmpty)
        ? widget.bannerText!.trim()
        : 'Treatment completed';

    final items = _buildChatItems(
      _messages,
      showTreatmentCompleteSeparator: showTreatmentCompleteSeparator,
      treatmentCompleteText: treatmentCompleteText,
    );

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        // Safety net: some devices/gestures can fail to pop and appear "stuck".
        if (!didPop) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _loadMessages,
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: _loading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          if (_showSlowHint) ...[
                            const SizedBox(height: 12),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                'Taking longer than usual. You can tap refresh to retry.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  : (_messages.isEmpty && !showTreatmentCompleteSeparator)
                      ? const Center(child: Text('No messages yet. Start the conversation!'))
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];

                            if (item.kind == _ChatItemKind.separator) {
                              return _Separator(text: item.text ?? '', accent: item.accent);
                            }

                            final msg = item.message!;
                            final role = (msg['sender_role'] ?? '').toString();
                            final isMe = widget.asDoctor ? role == 'doctor' : role == 'patient';
                            final text = (msg['message'] ?? '').toString();

                            final senderUsername = (msg['sender_username'] ?? '').toString().trim();
                            final String senderLabel;
                            if (widget.asDoctor) {
                              senderLabel = role == 'doctor'
                                  ? 'Doctor'
                                  : (patientLabel.isNotEmpty
                                      ? patientLabel
                                      : (senderUsername.isNotEmpty ? senderUsername : widget.patientUsername));
                            } else {
                              senderLabel = role == 'doctor'
                                  ? (widget.doctorName != null && widget.doctorName!.trim().isNotEmpty
                                      ? widget.doctorName!.trim()
                                      : (senderUsername.isNotEmpty ? senderUsername : 'Doctor'))
                                  : (senderUsername.isNotEmpty ? senderUsername : widget.patientUsername);
                            }

                            final createdAt = _formatTimestamp(msg['created_at']);

                            return Align(
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                constraints: const BoxConstraints(maxWidth: 320),
                                decoration: BoxDecoration(
                                  color: isMe ? const Color(0xFF0F9D58) : const Color(0xFF4285F4),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(12),
                                    topRight: const Radius.circular(12),
                                    bottomLeft: Radius.circular(isMe ? 12 : 2),
                                    bottomRight: Radius.circular(isMe ? 2 : 12),
                                  ),
                                  boxShadow: const [
                                    BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      senderLabel,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(text, style: const TextStyle(color: Colors.white, fontSize: 15)),
                                    const SizedBox(height: 4),
                                    Text(createdAt, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            const Divider(height: 1),
            if (!widget.readOnly)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: SafeArea(
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            hintText: 'Type your message...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _sending ? null : _sendMessage,
                        icon: _sending
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send, size: 18),
                        label: const Text('Send'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  List<_ChatItem> _buildChatItems(
    List<dynamic> messages, {
    required bool showTreatmentCompleteSeparator,
    required String treatmentCompleteText,
  }) {
    final List<_ChatItem> items = [];

    DateTime? lastDay;
    for (final rawMessage in messages) {
      if (rawMessage is! Map) continue;
      final msg = rawMessage.cast<String, dynamic>();

      final createdAtRaw = msg['created_at']?.toString();
      final createdAt = createdAtRaw == null ? null : _parseBackendTimestampToLocal(createdAtRaw);
      final day = createdAt == null ? null : DateTime(createdAt.year, createdAt.month, createdAt.day);

      if (day != null && (lastDay == null || !_sameDay(lastDay, day))) {
        items.add(_ChatItem.separator(_dayLabel(day)));
        lastDay = day;
      }

      items.add(_ChatItem.message(msg));
    }

    if (showTreatmentCompleteSeparator) {
      items.add(_ChatItem.separator(treatmentCompleteText, accent: true));
    }

    return items;
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (_sameDay(day, today)) return 'Today';
    if (_sameDay(day, yesterday)) return 'Yesterday';
    return DateFormat('MMM d, yyyy').format(day);
  }

  String _formatTimestamp(dynamic value) {
    if (value == null) return '';
    final raw = value.toString().trim();
    if (raw.isEmpty) return '';

    final parsedLocal = _parseBackendTimestampToLocal(raw);
    if (parsedLocal == null) return raw;
    return DateFormat('yyyy-MM-dd • h:mm a').format(parsedLocal);
  }

  DateTime? _parseBackendTimestampToLocal(String raw) {
    // Backend sometimes returns:
    // - UTC with Z: 2025-12-05T14:08:26.038580Z
    // - With offset: 2025-12-05T14:08:26+00:00
    // - Naive (no timezone): 2025-12-05T14:08:26.038580
    // For naive timestamps we assume UTC (server time) and convert to local.
    var s = raw;
    if (s.contains(' ') && !s.contains('T')) {
      s = s.replaceFirst(' ', 'T');
    }

    final dt = DateTime.tryParse(s);
    if (dt == null) return null;

    final hasExplicitTz = RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(s);
    if (hasExplicitTz) {
      return dt.toLocal();
    }

    final assumedUtc = DateTime.utc(
      dt.year,
      dt.month,
      dt.day,
      dt.hour,
      dt.minute,
      dt.second,
      dt.millisecond,
      dt.microsecond,
    );
    return assumedUtc.toLocal();
  }
}

enum _ChatItemKind { message, separator }

class _ChatItem {
  final _ChatItemKind kind;
  final Map<String, dynamic>? message;
  final String? text;
  final bool accent;

  const _ChatItem._(this.kind, {this.message, this.text, this.accent = false});

  factory _ChatItem.message(Map<String, dynamic> msg) => _ChatItem._(_ChatItemKind.message, message: msg);

  factory _ChatItem.separator(String text, {bool accent = false}) =>
      _ChatItem._(_ChatItemKind.separator, text: text, accent: accent);
}

class _Separator extends StatelessWidget {
  final String text;
  final bool accent;

  const _Separator({required this.text, required this.accent});

  @override
  Widget build(BuildContext context) {
    final color = accent ? Theme.of(context).colorScheme.primary : Colors.black45;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Text(
          text,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
