import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:ws/src/client/web_socket_ready_state.dart';
import 'package:ws/src/client/websocket_exception.dart';
import 'package:ws/src/client/ws_client_base.dart';
import 'package:ws/src/client/ws_client_interface.dart';
import 'package:ws/src/client/ws_options.dart';
import 'package:ws/src/client/ws_options_vm.dart';
import 'package:ws/src/util/logger.dart';

/// {@nodoc}
@internal
IWebSocketClient $platformWebSocketClient(WebSocketOptions? options) =>
    switch (options) {
      $WebSocketOptions$VM options => WebSocketClient$VM(
          protocols: options.protocols,
          options: options,
        ),
      _ => WebSocketClient$VM(
          protocols: options?.protocols,
        ),
    };

/// {@nodoc}
@internal
final class WebSocketClient$VM extends WebSocketClientBase {
  /// {@nodoc}
  WebSocketClient$VM({super.protocols, $WebSocketOptions$VM? options})
      : _options = options;

  /// {@nodoc}
  final $WebSocketOptions$VM? _options;

  /// Native WebSocket client.
  /// {@nodoc}
  // Close it at a [disconnect] or [close] method.
  // ignore: close_sinks
  io.WebSocket? _client;

  /// Binding to data from native WebSocket client.
  /// The subscription of [_communication] to [_controller].
  /// {@nodoc}
  StreamSubscription<Object?>? _dataBindSubscription;

  @override
  WebSocketReadyState get readyState {
    final code = _client?.readyState;
    assert(code == null || code >= 0 && code <= 3, 'Invalid readyState code.');
    return code == null
        ? WebSocketReadyState.closed
        : WebSocketReadyState.fromCode(code);
  }

  @override
  FutureOr<void> add(Object data) {
    super.add(data);
    final client = _client;
    if (client == null) {
      throw const WSClientClosedException(
          message: 'WebSocket client is not connected.');
    }
    try {
      switch (data) {
        case String text:
          client.addUtf8Text(utf8.encode(text));
        case Uint8List bytes:
          client.add(bytes);
        case ByteBuffer bb:
          client.add(bb.asUint8List());
        case List<int> bytes:
          client.add(Uint8List.fromList(bytes));
        default:
          throw ArgumentError.value(data, 'data', 'Invalid data type.');
      }
    } on Object catch (error, stackTrace) {
      warning(error, stackTrace, 'WebSocketClient\$IO.add: $error');
      onError(error, stackTrace);
      rethrow;
    }
  }

  @override
  FutureOr<void> connect(String url) async {
    try {
      if (_client != null) await disconnect(1001, 'RECONNECTING');
      super.connect(url);
      if (_options?.userAgent case String userAgent) {
        io.WebSocket.userAgent = userAgent;
      }
      // Close it at a [disconnect] or [close] method.
      // ignore: close_sinks
      final client = _client = await io.WebSocket.connect(
        url,
        protocols: protocols,
        headers: _options?.headers,
        compression:
            _options?.compression ?? io.CompressionOptions.compressionDefault,
        customClient: _options?.customClient,
      );
      _dataBindSubscription = client
          .asyncMap<Object?>((data) => switch (data) {
                String text => text,
                Uint8List bytes => bytes,
                ByteBuffer bb => bb.asUint8List(),
                List<int> bytes => bytes,
                _ => data,
              })
          .listen(
            onReceivedData,
            onError: onError,
            onDone: () => disconnect(1000, 'SUBSCRIPTION_CLOSED'),
            cancelOnError: false,
          );
      if (!readyState.isOpen) {
        disconnect(1001, 'IS_NOT_OPEN_AFTER_CONNECT');
        assert(
          false,
          'Invalid readyState code after connect: $readyState',
        );
      }
      super.onConnected(url);
    } on Object catch (error, stackTrace) {
      onError(error, stackTrace);
      Future<void>.sync(() => disconnect(1006, 'CONNECTION_FAILED')).ignore();
      rethrow;
    }
  }

  @override
  FutureOr<void> disconnect(
      [int? code = 1000, String? reason = 'NORMAL_CLOSURE']) async {
    final client = _client;
    await super.disconnect(code, reason);
    _dataBindSubscription?.cancel().ignore();
    _dataBindSubscription = null;
    if (client != null) {
      try {
        await client.close(code, reason);
      } on Object {/* ignore */}
      _client = null;
    }
    super.onDisconnected(code, reason);
  }

  @override
  FutureOr<void> close(
      [int? code = 1000, String? reason = 'NORMAL_CLOSURE']) async {
    await super.close(code, reason);
    _client = null;
  }
}
