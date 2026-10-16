import 'dart:typed_data';

import 'package:apexlytics/services/proxy_health.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

class _Unreachable implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw DioException.connectionError(
    requestOptions: options,
    reason: 'refused',
  );

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(HttpClientAdapter adapter) => Dio()..httpClientAdapter = adapter;

void main() {
  test('a healthy proxy is online, and no client token is sent', () async {
    final adapter = FakeHttpAdapter({
      'https://p.test/healthz': {'ok': true},
    });
    final health = await checkProxy(
      'https://p.test/',
      dio: _dioWith(adapter),
    );

    expect(health.state, ProxyState.online);
    expect(health.latency, isNotNull);
    expect(adapter.paths, ['https://p.test/healthz']);
    expect(adapter.requests.single.headers.containsKey('x-client-token'), false);
  });

  test('an error status counts as down', () async {
    final adapter = FakeHttpAdapter({
      'https://p.test/healthz': const FakeReply(503, {'error': 'busy'}),
    });
    final health = await checkProxy('https://p.test', dio: _dioWith(adapter));

    expect(health.state, ProxyState.down);
    expect(health.latency, isNull);
  });

  test('an unreachable host counts as down', () async {
    final health = await checkProxy(
      'https://p.test',
      dio: _dioWith(_Unreachable()),
    );

    expect(health.state, ProxyState.down);
  });

  test('no URL is not configured, and nothing is requested', () async {
    final adapter = FakeHttpAdapter();
    final health = await checkProxy('', dio: _dioWith(adapter));

    expect(health.state, ProxyState.notConfigured);
    expect(adapter.requests, isEmpty);
  });
}
