import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'notification_service.dart';

/// SSE-based proactive message service.
/// Connects to /push-api/events on the configured server and shows
/// local notifications when API澄 decides to send a proactive message.
class ProactiveMessageService {
  static final ProactiveMessageService _instance =
      ProactiveMessageService._();
  static ProactiveMessageService get instance => _instance;
  ProactiveMessageService._();

  String? _serverUrl;
  bool _enabled = false;
  StreamSubscription<String>? _sub;
  Timer? _reconnectTimer;
  bool _running = false;

  // Callback for in-app display (optional)
  void Function(String content, String time)? onMessage;

  void configure({required String serverUrl, required bool enabled}) {
    _serverUrl = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    _enabled = enabled;
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

  String _buf = '';

  void _onLine(String line) {
    if (line.startsWith('data:')) {
      _buf = line.substring(5).trim();
      _handleData(_buf);
      _buf = '';
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
          NotificationService.showProactive(content: content);
          onMessage?.call(content, time);
        }
      }
    } catch (_) {}
  }

  void _scheduleReconnect() {
    if (!_running) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 8), _connect);
  }
}
