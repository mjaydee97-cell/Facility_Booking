DateTime _dt(dynamic v) => DateTime.parse(v as String).toLocal();
DateTime? _dtOrNull(dynamic v) => v == null ? null : _dt(v);
double _num(dynamic v) => v == null ? 0 : (v as num).toDouble();

class User {
  User({required this.id, required this.name, required this.email, required this.role});

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as int,
        name: j['name'] as String,
        email: j['email'] as String,
        role: j['role'] as String,
      );

  final int id;
  final String name;
  final String email;
  final String role;

  bool get isAdmin => role == 'admin';
}

class Facility {
  Facility({
    required this.id,
    required this.name,
    required this.description,
    required this.location,
    required this.capacity,
    required this.openTime,
    required this.closeTime,
    required this.requiresApproval,
    required this.isActive,
  });

  factory Facility.fromJson(Map<String, dynamic> j) => Facility(
        id: j['id'] as int,
        name: j['name'] as String,
        description: j['description'] as String? ?? '',
        location: j['location'] as String? ?? '',
        capacity: j['capacity'] as int,
        openTime: j['open_time'] as String,
        closeTime: j['close_time'] as String,
        requiresApproval: j['requires_approval'] as bool,
        isActive: j['is_active'] as bool,
      );

  final int id;
  final String name;
  final String description;
  final String location;
  final int capacity;
  final String openTime; // "HH:MM"
  final String closeTime; // "HH:MM"
  final bool requiresApproval;
  final bool isActive;

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'location': location,
        'capacity': capacity,
        'open_time': openTime,
        'close_time': closeTime,
        'requires_approval': requiresApproval,
        'is_active': isActive,
      };
}

enum BookingStatus {
  pending('Pending'),
  approved('Approved'),
  rejected('Rejected'),
  cancelled('Cancelled'),
  checkedIn('In use'),
  completed('Completed'),
  noShow('No-show');

  const BookingStatus(this.label);
  final String label;

  static BookingStatus parse(String s) => switch (s) {
        'checked_in' => checkedIn,
        'no_show' => noShow,
        _ => values.byName(s),
      };
}

class Booking {
  Booking({
    required this.id,
    required this.facilityId,
    required this.facilityName,
    required this.facilityLocation,
    required this.userName,
    required this.userEmail,
    required this.startsAt,
    required this.endsAt,
    required this.purpose,
    required this.attendees,
    required this.status,
    this.adminRemarks,
    this.checkedInAt,
    this.checkedOutAt,
  });

  factory Booking.fromJson(Map<String, dynamic> j) => Booking(
        id: j['id'] as int,
        facilityId: j['facility_id'] as int,
        facilityName: j['facility_name'] as String,
        facilityLocation: j['facility_location'] as String? ?? '',
        userName: j['user_name'] as String,
        userEmail: j['user_email'] as String,
        startsAt: _dt(j['starts_at']),
        endsAt: _dt(j['ends_at']),
        purpose: j['purpose'] as String,
        attendees: j['attendees'] as int,
        status: BookingStatus.parse(j['status'] as String),
        adminRemarks: j['admin_remarks'] as String?,
        checkedInAt: _dtOrNull(j['checked_in_at']),
        checkedOutAt: _dtOrNull(j['checked_out_at']),
      );

  final int id;
  final int facilityId;
  final String facilityName;
  final String facilityLocation;
  final String userName;
  final String userEmail;
  final DateTime startsAt;
  final DateTime endsAt;
  final String purpose;
  final int attendees;
  final BookingStatus status;
  final String? adminRemarks;
  final DateTime? checkedInAt;
  final DateTime? checkedOutAt;

  bool get canCancel =>
      (status == BookingStatus.pending || status == BookingStatus.approved) &&
      startsAt.isAfter(DateTime.now());
}

class BusySlot {
  BusySlot({required this.startsAt, required this.endsAt, required this.status, required this.isMine});

  factory BusySlot.fromJson(Map<String, dynamic> j) => BusySlot(
        startsAt: _dt(j['starts_at']),
        endsAt: _dt(j['ends_at']),
        status: BookingStatus.parse(j['status'] as String),
        isMine: j['is_mine'] as bool? ?? false,
      );

  final DateTime startsAt;
  final DateTime endsAt;
  final BookingStatus status;
  final bool isMine;
}

class AppNotification {
  AppNotification({required this.id, required this.title, required this.body, required this.createdAt, this.readAt});

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as int,
        title: j['title'] as String,
        body: j['body'] as String,
        createdAt: _dt(j['created_at']),
        readAt: _dtOrNull(j['read_at']),
      );

  final int id;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;
}

class FacilityUtilization {
  FacilityUtilization.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        name = j['name'] as String,
        totalBookings = j['total_bookings'] as int,
        noShow = j['no_show'] as int,
        cancelled = j['cancelled'] as int,
        availableHours = _num(j['available_hours']),
        bookedHours = _num(j['booked_hours']),
        usedHours = _num(j['used_hours']),
        bookingRate = _num(j['booking_rate']),
        utilizationRate = _num(j['utilization_rate']),
        noShowRate = _num(j['no_show_rate']);

  final int id;
  final String name;
  final int totalBookings;
  final int noShow;
  final int cancelled;
  final double availableHours;
  final double bookedHours;
  final double usedHours;
  final double bookingRate;
  final double utilizationRate;
  final double noShowRate;
}

class AnalyticsSummary {
  AnalyticsSummary.fromJson(Map<String, dynamic> j)
      : from = j['from'] as String,
        to = j['to'] as String,
        totalBookings = j['totals']['total_bookings'] as int,
        byStatus = Map<String, int>.from(j['totals']['by_status'] as Map),
        availableHours = _num(j['totals']['available_hours']),
        bookedHours = _num(j['totals']['booked_hours']),
        usedHours = _num(j['totals']['used_hours']),
        bookingRate = _num(j['totals']['booking_rate']),
        utilizationRate = _num(j['totals']['utilization_rate']),
        noShowRate = _num(j['totals']['no_show_rate']),
        facilities = (j['facilities'] as List)
            .map((f) => FacilityUtilization.fromJson(f as Map<String, dynamic>))
            .toList(),
        daily = (j['daily'] as List)
            .map((d) => (date: DateTime.parse(d['date'] as String), booked: _num(d['booked_hours']), used: _num(d['used_hours'])))
            .toList(),
        peakHours = (j['peak_hours'] as List).map((h) => h['bookings'] as int).toList(),
        weekday = (j['weekday'] as List).map((w) => w['bookings'] as int).toList();

  final String from;
  final String to;
  final int totalBookings;
  final Map<String, int> byStatus;
  final double availableHours;
  final double bookedHours;
  final double usedHours;
  final double bookingRate;
  final double utilizationRate;
  final double noShowRate;
  final List<FacilityUtilization> facilities;
  final List<({DateTime date, double booked, double used})> daily;
  final List<int> peakHours; // index = hour of day 0..23
  final List<int> weekday; // index 0 = Monday
}
