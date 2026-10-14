import 'package:facility_booking/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a booking from the API and converts times to local', () {
    final b = Booking.fromJson({
      'id': 7,
      'facility_id': 2,
      'facility_name': 'Conference Room A',
      'facility_location': 'Admin Bldg, 3F',
      'user_id': 3,
      'user_name': 'Juan Dela Cruz',
      'user_email': 'user@example.com',
      'starts_at': '2030-01-02T01:00:00.000Z',
      'ends_at': '2030-01-02T03:00:00.000Z',
      'purpose': 'Meeting',
      'attendees': 5,
      'status': 'checked_in',
      'admin_remarks': null,
      'checked_in_at': '2030-01-02T01:05:00.000Z',
      'checked_out_at': null,
    });
    expect(b.status, BookingStatus.checkedIn);
    expect(b.startsAt.isUtc, isFalse);
    expect(b.endsAt.difference(b.startsAt), const Duration(hours: 2));
    expect(b.checkedOutAt, isNull);
    expect(b.canCancel, isFalse);
  });

  test('maps every backend status', () {
    for (final s in ['pending', 'approved', 'rejected', 'cancelled', 'checked_in', 'completed', 'no_show']) {
      expect(() => BookingStatus.parse(s), returnsNormally);
    }
  });

  test('parses analytics summary', () {
    final s = AnalyticsSummary.fromJson({
      'from': '2030-01-01',
      'to': '2030-01-02',
      'totals': {
        'total_bookings': 3,
        'by_status': {'completed': 2, 'no_show': 1},
        'available_hours': 18,
        'booked_hours': 6,
        'used_hours': 3.5,
        'booking_rate': 0.3333,
        'utilization_rate': 0.1944,
        'no_show_rate': 0.3333,
      },
      'facilities': [
        {
          'id': 1, 'name': 'Gym', 'total_bookings': 3, 'no_show': 1, 'cancelled': 0,
          'available_hours': 18, 'booked_hours': 6, 'used_hours': 3.5,
          'booking_rate': 0.3333, 'utilization_rate': 0.1944, 'no_show_rate': 0.3333,
        },
      ],
      'daily': [
        {'date': '2030-01-01', 'bookings': 2, 'booked_hours': 4, 'used_hours': 3.5},
        {'date': '2030-01-02', 'bookings': 1, 'booked_hours': 2, 'used_hours': 0},
      ],
      'peak_hours': [for (var h = 0; h < 24; h++) {'hour': h, 'bookings': h == 9 ? 2 : 0}],
      'weekday': [for (var d = 1; d <= 7; d++) {'dow': d, 'bookings': 0}],
    });
    expect(s.utilizationRate, closeTo(0.1944, 1e-9));
    expect(s.facilities.single.usedHours, 3.5);
    expect(s.daily.first.used, 3.5);
    expect(s.peakHours[9], 2);
    expect(s.byStatus['no_show'], 1);
  });
}
