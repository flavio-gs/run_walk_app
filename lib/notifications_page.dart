import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timeago/timeago.dart' as timeago;

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _currentUserId = FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('pt_BR', timeago.PtBrMessages());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Notificações'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId)
            .collection('notifications')
            .orderBy('timestamp', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Ocorreu um erro.', style: TextStyle(color: Colors.white70)));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'Nenhuma notificação ainda.',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final notification = snapshot.data!.docs[index];
              final data = notification.data() as Map<String, dynamic>;

              final timestamp = (data['timestamp'] as Timestamp).toDate();
              final formattedTime = timeago.format(timestamp, locale: 'pt_BR');

              IconData icon;
              Color iconColor = Theme.of(context).colorScheme.secondary; // Verde padrão
              switch (data['type']) {
                case 'follow':
                  icon = Icons.person_add;
                  iconColor = Theme.of(context).colorScheme.primary; // Laranja
                  break;
                case 'like':
                  icon = Icons.favorite;
                  // CORREÇÃO: Usa a cor primária do tema (Laranja)
                  iconColor = Theme.of(context).colorScheme.primary;
                  break;
                case 'comment':
                  icon = Icons.comment;
                  iconColor = Theme.of(context).colorScheme.secondary; // Verde
                  break;
                default:
                  icon = Icons.notifications;
              }
              
              return Card(
                color: Colors.grey[900],
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: iconColor.withOpacity(0.15),
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                  title: Text(data['message'] ?? '', style: const TextStyle(color: Colors.white)),
                  subtitle: Text(formattedTime, style: const TextStyle(color: Colors.white70)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
