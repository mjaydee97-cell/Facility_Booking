import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api/api_client.dart';
import 'api/backend.dart';
import 'config.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home_shell.dart';
import 'services/push_service.dart';
import 'state/auth_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final push = PushService()..init();
  final backend = Backend(ApiClient(baseUrl: apiBaseUrl));
  final auth = AuthState(backend, push)..restore();

  runApp(MultiProvider(
    providers: [
      Provider.value(value: backend),
      Provider.value(value: push),
      ChangeNotifierProvider.value(value: auth),
    ],
    child: const FacilityBookingApp(),
  ));
}

class FacilityBookingApp extends StatelessWidget {
  const FacilityBookingApp({super.key});

  static const navy = Color(0xFF13235B);
  static const red = Color(0xFFC00000);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: navy, primary: navy, secondary: red);
    return MaterialApp(
      title: 'Facility Booking',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        appBarTheme: const AppBarTheme(backgroundColor: navy, foregroundColor: Colors.white),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: Consumer<AuthState>(
        builder: (context, auth, _) => switch (auth.status) {
          AuthStatus.unknown => const Scaffold(body: Center(child: CircularProgressIndicator())),
          AuthStatus.signedOut => const LoginScreen(),
          AuthStatus.signedIn => HomeShell(key: ValueKey(auth.user!.id), user: auth.user!),
        },
      ),
    );
  }
}
