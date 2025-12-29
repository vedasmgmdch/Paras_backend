import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ChatScreen extends StatefulWidget {
  final String patientUsername;
  final bool asDoctor;
  final String? doctorName;

  const ChatScreen({super.key, required this.patientUsername, this.asDoctor = false, this.doctorName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;
  bool _loading = true;
  List<dynamic> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    setState(() { _loading = true; });
    final res = widget.asDoctor
        ? await ApiService.getDoctorChatThread(widget.patientUsername)
        : await ApiService.getChatThread();
    if (!mounted) return;
    setState(() {
      _messages = res ?? [];
      _loading = false;
    });
    _scrollToEnd();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() { _sending = true; });
    final ok = widget.asDoctor
        ? await ApiService.sendDoctorChatMessage(widget.patientUsername, text)
        : await ApiService.sendChatMessage(text);
    if (ok) {
      _controller.clear();
      await _loadMessages();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send message'), backgroundColor: Colors.redAccent),
        );
      }
    }
    if (mounted) {
      setState(() { _sending = false; });
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
    final title = widget.asDoctor
        ? 'Chat • ${widget.patientUsername}'
        : 'Chat with Doctor';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
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
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(child: Text('No messages yet. Start the conversation!'))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index] as Map<String, dynamic>;
                          final role = (msg['sender_role'] ?? '').toString();
                          final isMe = widget.asDoctor ? role == 'doctor' : role == 'patient';
                          final text = (msg['message'] ?? '').toString();
                          final time = (msg['created_at'] ?? '').toString();
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
                                    text,
                                    style: const TextStyle(color: Colors.white, fontSize: 15),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    time,
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          const Divider(height: 1),
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
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send, size: 18),
                    label: const Text('Send'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
