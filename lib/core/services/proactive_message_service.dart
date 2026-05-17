import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/chat/chat_service.dart';
import 'notification_service.dart';

class ProactiveMessageService {
  static final ProactiveMessageService _instance =
      ProactiveMessageService._();
  static ProactiveMessageService get instance => _instance;
  ProactiveMessageService._();

  String? _serverUrl;
  bool _enabled = false;
  String? _assistantName;
  ChatService? _chatService;
  String? Function(String name)? _resolveAssistantId;

  StreamSubscription<String>? _sub;
  Timer? _reconnectTimer;
  bool _running = false;

  // Emits conversationId whenever a proactive message is inserted into the DB.
  final _insertedController = StreamController<String>.broadcast();
  Stream<String> get insertedStream => _insertedController.stream;

  // Optional in-app callback.
  void Function(String content, String time)? onMessage;

  // Dedup: track recent content to avoid inserting duplicates from multiple SSE connections.
  final Map<String, DateTime> _recentContents = {};
  static const _dedupWindow = Duration(seconds: 10);

  void configure({
    required String serverUrl,
    required bool enabled,
    String? assistantName,
    ChatService? chatService,
    String? Function(String name)? resolveAssistantId,
  }) {
    _serverUrl = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    _enabled = enabled;
    if (assistantName != null) _assistantName = assistantName.trim();
    if (chatService != null) _chatService = chatService;
    if (resolveAssistantId != null) _resolveAssistantId = resolveAssistantId;
  }

  Future<void> start() async {
    if (_running) return;
    if (!_enabled || _serverUrl == null || _serverUrl!.isEmpty) return;
    _running = true;
    await NotificationService.ensureInitializedForPlatform();
    _connect();
  }

  void stop() {
    _running = false;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _sub = null;
  }

  void _connect() {
    if (!_running) return;
    final url = '$_serverUrl/push-api/events';
    _sub?.cancel();

    final client = http.Client();
    final request = http.Request('GET', Uri.parse(url));
    request.headers['Accept'] = 'text/event-stream';
    request.headers['Cache-Control'] = 'no-cache';

    client.send(request).then((response) {
      if (response.statusCode != 200) {
        client.close();
        _scheduleReconnect();
        return;
      }
      _sub = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _onLine,
            onError: (_) {
              client.close();
              _scheduleReconnect();
            },
            onDone: () {
              client.close();
              _scheduleReconnect();
            },
          );
    }).catchError((_) {
      _scheduleReconnect();
    });
  }

  void _onLine(String line) {
    if (line.startsWith('data:')) {
      final data = line.substring(5).trim();
      _handleData(data);
    }
  }

  void _handleData(String data) {
    if (data.isEmpty || data == ':') return;
    try {
      final map = jsonDecode(data) as Map<String, dynamic>;
      if (map['type'] == 'proactive') {
        final content = (map['content'] as String?) ?? '';
        final time = (map['time'] as String?) ?? '';
        if (content.isNotEmpty) {
          _insertAndNotify(content, time);
        }
      }
    } catch (_) {}
  }

  bool _isDuplicate(String content) {
    final now = DateTime.now();
    _recentContents.removeWhere((_, t) => now.difference(t) > _dedupWindow);
    if (_recentContents.containsKey(content)) return true;
    _recentContents[content] = now;
    return false;
  }

  Future<void> _insertAndNotify(String content, String time) async {
    if (_isDuplicate(content)) return;
    final svc = _chatService;
    final name = _assistantName;
    final resolve = _resolveAssistantId;

    String? conversationId;

    if (svc != null && name != null && name.isNotEmpty && resolve != null) {
      final assistantId = resolve(name);
      if (assistantId != null) {
        // Find most recent conversation for this assistant, or create one.
        final convos = svc.getAllConversations()
            .where((c) => c.assistantId == assistantId)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        final convo = convos.isNotEmpty
            ? convos.first
            : await svc.createConversation(assistantId: assistantId);

        await svc.addMessage(
          conversationId: convo.id,
          role: 'assistant',
          content: content,
        );

        conversationId = convo.id;
        _insertedController.add(conversationId);
      }
    }

    NotificationService.showProactive(content: content);
    onMessage?.call(content, time);
  }

  void _scheduleReconnect() {
    if (!_running) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 8), _connect);
  }
}
