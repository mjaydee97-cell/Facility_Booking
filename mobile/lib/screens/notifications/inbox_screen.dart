import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/backend.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final backend = context.read<Backend>();
    return AsyncView<List<AppNotification>>(
      load: backend.notifications,
      builder: (context, items, reload) {
        if (items.isEmpty) return const EmptyState(icon: Icons.notifications_none, message: 'No notifications yet');
        final unread = items.where((n) => n.readAt == null).length;
        return ListView(children: [
          if (unread > 0)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  await backend.markAllRead();
                  await reload();
                },
                child: Text('Mark $unread as read'),
              ),
            ),
          for (final n in items)
            ListTile(
              leading: Icon(
                n.readAt == null ? Icons.circle : Icons.circle_outlined,
                size: 12,
                color: n.readAt == null ? Theme.of(context).colorScheme.secondary : Colors.grey,
              ),
              title: Text(n.title, style: TextStyle(fontWeight: n.readAt == null ? FontWeight.bold : null)),
              subtitle: Text(n.body),
              trailing: Text(DateFormat('MMM d\nh:mm a').format(n.createdAt),
                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 11)),
              isThreeLine: n.body.length > 60,
            ),
        ]);
      },
    );
  }
}
