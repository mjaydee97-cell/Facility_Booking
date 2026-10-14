import 'dart:convert';

import 'package:facility_booking/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('sends the bearer token and decodes JSON', () async {
    late http.Request seen;
    final api = ApiClient(
      baseUrl: 'https://api.test/api',
      httpClient: MockClient((req) async {
        seen = req;
        return http.Response(jsonEncode({'ok': true}), 200);
      }),
    )..token = 'abc';
    final res = await api.post('/bookings', {'x': 1});
    expect(res, {'ok': true});
    expect(seen.url.toString(), 'https://api.test/api/bookings');
    expect(seen.headers['Authorization'], 'Bearer abc');
    expect(jsonDecode(seen.body), {'x': 1});
  });

  test('turns server errors into ApiException with the server message', () async {
    final api = ApiClient(
      baseUrl: 'https://api.test/api',
      httpClient: MockClient((_) async => http.Response(jsonEncode({'error': 'This time slot overlaps'}), 409)),
    );
    expect(
      () => api.post('/bookings', {}),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'status', 409)
          .having((e) => e.message, 'message', 'This time slot overlaps')),
    );
  });

  test('a 401 with a token triggers onUnauthorized', () async {
    var called = false;
    final api = ApiClient(
      baseUrl: 'https://api.test/api',
      httpClient: MockClient((_) async => http.Response(jsonEncode({'error': 'Invalid or expired token'}), 401)),
    )
      ..token = 'old'
      ..onUnauthorized = () => called = true;
    await expectLater(api.get('/auth/me'), throwsA(isA<ApiException>()));
    expect(called, isTrue);
  });
}
