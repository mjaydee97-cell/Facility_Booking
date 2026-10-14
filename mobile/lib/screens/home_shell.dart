import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/push_service.dart';
import '../state/auth_state.dart';
import 'admin/dashboard_screen.dart';
import 'admin/manage_facilities_screen.dart';
import 'admin/requests_screen.dart';
import 'bookings/my_bookings_screen.dart';
import 'checkin/scan_screen.dart';
import 'facilities/facility_list_screen.dart';
import 'notifications/inbox_screen.dart';

class _Tab {
  const _Tab(this.label, this.icon, this.page);
  final String label;
  final IconData icon;
  final Widget page;
}

/// Bottom-navigation home. Users and admins get different tabs.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.user});

  final User user;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  StreamSubscription? _pushSub;
  // Bumped each time a tab is opened so its page is rebuilt and reloads fresh data.
  final Map<int, int> _visits = {0: 0};

  late final List<_Tab> _tabs = widget.user.isAdmin
      ? const [
          _Tab('Dashboard', Icons.insights, DashboardScreen()),
          _Tab('Requests', Icons.pending_actions, RequestsScreen()),
          _Tab('Facilities', Icons.apartment, ManageFacilitiesScreen()),
          _Tab('Inbox', Icons.notifications_outlined, InboxScreen()),
        ]
      : const [
          _Tab('Facilities', Icons.meeting_room_outlined, FacilityListScreen()),
          _Tab('My Bookings', Icons.event_note, MyBookingsScreen()),
          _Tab('Check-in', Icons.qr_code_scanner, ScanScreen()),
          _Tab('Inbox', Icons.notifications_outlined, InboxScreen()),
        ];

  @override
  void initState() {
    super.initState();
    // Show pushes that arrive while the app is open.
    _pushSub = context.read<PushService>().foregroundMessages.stream.listen((m) {
      final n = m.notification;
      if (n == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${n.title}: ${n.body}')));
    });
  }

  @override
  void dispose() {
    _pushSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab = _tabs[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text(tab.label),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle),
            onSelected: (v) {
              if (v == 'logout') context.read<AuthState>().logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text('${widget.user.name}\n${widget.user.email}${widget.user.isAdmin ? '\nAdministrator' : ''}'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      // Tabs are built on first visit and refreshed whenever the user switches to them.
      body: IndexedStack(index: _index, children: [
        for (var i = 0; i < _tabs.length; i++)
          _visits.containsKey(i) ? KeyedSubtree(key: ValueKey(_visits[i]), child: _tabs[i].page) : const SizedBox(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          if (i != _index) _visits[i] = (_visits[i] ?? 0) + 1;
          _index = i;
        }),
        destinations: [for (final t in _tabs) NavigationDestination(icon: Icon(t.icon), label: t.label)],
      ),
    );
  }
}
