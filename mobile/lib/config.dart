/// Base URL of the REST API.
///
/// Override at build time, e.g.
///   flutter run --dart-define=API_BASE_URL=https://api.example.edu/api
///
/// The default `10.0.2.2` is how the Android emulator reaches the host machine's
/// localhost. Use `http://localhost:3000/api` for the iOS simulator.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:3000/api',
);

/// Prefix the backend puts in facility check-in QR codes.
const String qrPrefix = 'FBUM:';
