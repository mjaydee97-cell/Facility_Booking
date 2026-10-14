import '../models/models.dart';
import 'api_client.dart';

/// Typed wrapper around every REST endpoint the app uses.
class Backend {
  Backend(this.client);

  final ApiClient client;

  List<T> _list<T>(dynamic json, T Function(Map<String, dynamic>) f) =>
      (json as List).map((e) => f(e as Map<String, dynamic>)).toList();

  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ---- Auth ----
  Future<({String token, User user})> login(String email, String password) async {
    final j = await client.post('/auth/login', {'email': email, 'password': password});
    return (token: j['token'] as String, user: User.fromJson(j['user'] as Map<String, dynamic>));
  }

  Future<({String token, User user})> register(String name, String email, String password) async {
    final j = await client.post('/auth/register', {'name': name, 'email': email, 'password': password});
    return (token: j['token'] as String, user: User.fromJson(j['user'] as Map<String, dynamic>));
  }

  Future<User> me() async => User.fromJson(await client.get('/auth/me') as Map<String, dynamic>);

  Future<void> registerDeviceToken(String token, String platform) =>
      client.post('/auth/device-token', {'token': token, 'platform': platform});

  Future<void> removeDeviceToken(String token) => client.delete('/auth/device-token', {'token': token});

  // ---- Facilities ----
  Future<List<Facility>> facilities({bool includeInactive = false}) async => _list(
      await client.get('/facilities', query: includeInactive ? {'all': 'true'} : null), Facility.fromJson);

  Future<List<BusySlot>> availability(int facilityId, DateTime day) async {
    final j = await client.get('/facilities/$facilityId/availability', query: {'date': _date(day)});
    return _list(j['busy'], BusySlot.fromJson);
  }

  Future<Facility> saveFacility(Facility f, {int? id}) async => Facility.fromJson(
      (id == null ? await client.post('/facilities', f.toJson()) : await client.put('/facilities/$id', f.toJson()))
          as Map<String, dynamic>);

  Future<String> facilityQr(int id, {bool rotate = false}) async {
    final j = rotate ? await client.post('/facilities/$id/checkin-qr/rotate') : await client.get('/facilities/$id/checkin-qr');
    return j['qr_payload'] as String;
  }

  // ---- Bookings ----
  Future<Booking> createBooking({
    required int facilityId,
    required DateTime startsAt,
    required DateTime endsAt,
    required String purpose,
    required int attendees,
  }) async =>
      Booking.fromJson(await client.post('/bookings', {
        'facility_id': facilityId,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt.toUtc().toIso8601String(),
        'purpose': purpose,
        'attendees': attendees,
      }) as Map<String, dynamic>);

  Future<List<Booking>> myBookings({bool past = false}) async =>
      _list(await client.get('/bookings/mine', query: {'scope': past ? 'past' : 'upcoming'}), Booking.fromJson);

  Future<List<Booking>> allBookings({String? status}) async =>
      _list(await client.get('/bookings', query: status == null ? null : {'status': status}), Booking.fromJson);

  Future<Booking> _action(int id, String action, [Object? body]) async =>
      Booking.fromJson(await client.post('/bookings/$id/$action', body) as Map<String, dynamic>);

  Future<Booking> cancel(int id) => _action(id, 'cancel');
  Future<Booking> approve(int id, {String? remarks}) => _action(id, 'approve', {'remarks': ?remarks});
  Future<Booking> reject(int id, {String? remarks}) => _action(id, 'reject', {'remarks': ?remarks});
  Future<Booking> checkOut(int id) => _action(id, 'check-out');

  Future<Booking> checkIn(String qrPayload) async =>
      Booking.fromJson(await client.post('/bookings/check-in', {'qr_payload': qrPayload}) as Map<String, dynamic>);

  // ---- Notifications ----
  Future<List<AppNotification>> notifications() async =>
      _list(await client.get('/notifications'), AppNotification.fromJson);

  Future<void> markAllRead() => client.post('/notifications/read-all');

  // ---- Analytics ----
  Future<AnalyticsSummary> analytics({required DateTime from, required DateTime to, int? facilityId}) async =>
      AnalyticsSummary.fromJson(await client.get('/analytics/summary', query: {
        'from': _date(from),
        'to': _date(to),
        if (facilityId != null) 'facility_id': '$facilityId',
      }) as Map<String, dynamic>);
}
