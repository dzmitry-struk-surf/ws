import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:ws/src/client/websocket_exception.dart';

/// {@nodoc}
@internal
final class WebSocketEventQueue {
  /// {@nodoc}
  WebSocketEventQueue();

  final DoubleLinkedQueue<WebSocketTask<Object?>> _queue =
      DoubleLinkedQueue<WebSocketTask<Object?>>();
  Future<void>? _processing;
  bool _isClosed = false;

  /// Push it at the end of the queue.
  /// {@nodoc}
  Future<T> push<T>(String id, FutureOr<T> Function() fn) {
    final task = WebSocketTask<T>(id, fn);
    _queue.add(task);
    _exec();
    return task.future;
  }

  /*
  /// Push it at the end of the queue if it doesn't exist.
  /// Otherwise, return the result from existing one.
  /// {@nodoc}
  Future<T> pushIfNotExists<T>(String id, FutureOr<T> Function() fn,
      [bool Function(WebSocketTask<T> task)? test]) {
    if (_queue.isEmpty) return push<T>(id, fn);
    final iter = _queue.iterator;
    WebSocketTask<Object?> current;
    test ??= (task) => task.id == id;
    while (iter.moveNext()) {
      current = iter.current;
      if (current is WebSocketTask<T> && test(current)) return current.future;
    }
    return push<T>(id, fn);
  }
  */

  /// Mark the queue as closed.
  /// The queue will be processed until it's empty.
  /// But all new and current events will be rejected with [WSClientClosed].
  /// {@nodoc}
  FutureOr<void> close() async {
    _isClosed = true;
    await _processing;
  }

  /// Execute the queue.
  /// {@nodoc}
  void _exec() => _processing ??= Future.doWhile(() async {
        final event = _queue.first;
        try {
          if (_isClosed) {
            event.reject(const WSClientClosedException(), StackTrace.current);
          } else {
            await event();
          }
        } on Object catch (error, stackTrace) {
          /* warning(
            error,
            stackTrace,
            'Error while processing event "${event.id}"',
          ); */
          Future<void>.sync(() => event.reject(error, stackTrace)).ignore();
        }
        _queue.removeFirst();
        final isEmpty = _queue.isEmpty;
        if (isEmpty) _processing = null;
        return !isEmpty;
      });
}

/// {@nodoc}
@internal
class WebSocketTask<T> {
  /// {@nodoc}
  WebSocketTask(this.id, FutureOr<T> Function() fn)
      : _fn = fn,
        _completer = Completer<T>();

  /// {@nodoc}
  final Completer<T> _completer;

  /// {@nodoc}
  final String id;

  /// {@nodoc}
  final FutureOr<T> Function() _fn;

  /// {@nodoc}
  Future<T> get future => _completer.future;

  /// {@nodoc}
  FutureOr<T> call() async {
    final result = await _fn();
    if (!_completer.isCompleted) {
      _completer.complete(result);
    }
    return result;
  }

  /// {@nodoc}
  void reject(Object error, [StackTrace? stackTrace]) {
    if (_completer.isCompleted) return;
    _completer.completeError(error, stackTrace);
  }
}
