import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:run_walk_app/service/service/firestore_service.dart';

class ChallengeDetailsPage extends StatefulWidget {
  final String challengeId;
  const ChallengeDetailsPage({super.key, required this.challengeId});

  @override
  State<ChallengeDetailsPage> createState() => _ChallengeDetailsPageState();
}

class _ChallengeDetailsPageState extends State<ChallengeDetailsPage>
    with SingleTickerProviderStateMixin {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  DocumentSnapshot? _challenge;
  bool _loading = true;
  bool _participating = false;
  bool _isCreator = false;
  bool _canJoin = true; 

  late final TabController _tabController;

  Map<String, Map<String, dynamic>> _userMap = {}; 
  List<String> _participants = [];
  List<Map<String, dynamic>> _goals = [];
  DateTime? _start, _end;

  Map<String, Map<String, dynamic>> _stats = {};
  Map<String, List<Map<String, dynamic>>> _ranking = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      setState(() => _loading = true);

      final doc = await _firestore.collection('challenges').doc(widget.challengeId).get();
      if (!doc.exists) {
        if (mounted) setState(() { _challenge = null; _loading = false; });
        return;
      }

      final data = doc.data()!;
      final uid = _auth.currentUser?.uid;
      final participants = List<String>.from(data['participants'] ?? []);
      final goals = List<Map<String, dynamic>>.from(data['goals'] ?? []);
      final start = (data['startDate'] as Timestamp?)?.toDate();
      final end = (data['endDate'] as Timestamp?)?.toDate();
      final createdBy = data['createdBy'] as String?;
      final isPublic = data['isPublic'] ?? true;

      final now = DateTime.now();
      if (end != null && end.isBefore(now) && (data['status'] ?? 'active') != 'closed') {
        await _firestore.collection('challenges').doc(widget.challengeId).update({
          'status': 'closed',
          'closedAt': Timestamp.fromDate(now),
        });
        data['status'] = 'closed';
      }

      _challenge = doc;
      _participants = participants;
      _goals = goals;
      _start = start;
      _end = end;
      _participating = uid != null && participants.contains(uid);
      _isCreator = uid != null && createdBy == uid;

      if (uid != null && !_isCreator && !isPublic) {
        _canJoin = await FirestoreService().isFollowing(createdBy!);
      } else {
        _canJoin = true;
      }

      await _loadParticipantProfiles(participants);
      await _aggregateProgress(participants, start, end, data);
      _computeRanking();

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint('Erro _loadAll: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadParticipantProfiles(List<String> uids) async {
    _userMap.clear();
    if (uids.isEmpty) return;
    const chunkSize = 10;
    for (int i = 0; i < uids.length; i += chunkSize) {
      final chunk = uids.sublist(i, min(i + chunkSize, uids.length));
      final snap = await _firestore.collection('users').where(FieldPath.documentId, whereIn: chunk).get();
      for (final d in snap.docs) {
        final m = d.data();
        _userMap[d.id] = {
          'displayName': m['displayName'] ?? 'Runner',
          'photoURL': m['photoURL'] ?? m['photoUrl'] ?? null,
          'level': m['level'] ?? 0,
        };
      }
    }
  }

  Future<void> _aggregateProgress(List<String> uids, DateTime? start, DateTime? end, Map<String, dynamic>? challengeData) async {
    _stats.clear();
    if (uids.isEmpty || start == null || end == null) return;
    const chunkSize = 10;
    final startTs = Timestamp.fromDate(start);
    final endTs = Timestamp.fromDate(end);
    for (int i = 0; i < uids.length; i += chunkSize) {
      final chunk = uids.sublist(i, min(i + chunkSize, uids.length));
      final snap = await _firestore.collection('corridas').where('userId', whereIn: chunk).where('createdAt', isGreaterThanOrEqualTo: startTs).where('createdAt', isLessThanOrEqualTo: endTs).get();
      for (final uid in chunk) { _stats.putIfAbsent(uid, () => {'km': 0.0, 'xp': 0.0, 'runs': 0, 'steps': 0}); }
      for (final d in snap.docs) {
        final m = d.data() as Map<String, dynamic>;
        final uid = m['userId'] as String?;
        if (uid == null) continue;
        final km = (m['distance'] ?? m['distanceKm'] ?? 0).toDouble() / 1000.0;
        final duration = (m['duration'] ?? 0).toDouble();
        final calories = (m['calories'] ?? 0).toDouble();
        double xp = (km * 10) + (calories * 0.2) + (duration / 60);
        final bucket = _stats[uid]!;
        bucket['km'] = (bucket['km'] as num) + km;
        bucket['xp'] = (bucket['xp'] as num) + xp;
        bucket['runs'] = (bucket['runs'] as num) + 1;
        bucket['steps'] = (bucket['steps'] as num) + (km * 1300);
      }
    }
    if (challengeData != null && challengeData['goals'] is List) {
      final goals = (challengeData['goals'] as List).cast<Map<String, dynamic>>();
      for (final uid in _stats.keys) {
        final userStats = _stats[uid]!;
        final metas = <Map<String, dynamic>>[];
        for (final goal in goals) {
          final metric = (goal['metric'] ?? '').toLowerCase();
          final target = (goal['target'] ?? 0).toDouble();
          double current = 0.0;
          if (metric == 'km') current = userStats['km'] as double;
          else if (metric == 'xp') current = userStats['xp'] as double;
          else if (metric == 'steps') current = userStats['steps'] as double;
          final progress = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
          metas.add({
            'label': goal['label'],
            'metric': metric,
            'target': target,
            'current': current,
            'progress': progress,
            'goalReached': progress >= 1.0,
          });
        }
        userStats['goals'] = metas;
      }
    }
  }

  void _computeRanking() {
    _ranking.clear();
    if (_goals.isEmpty || _participants.isEmpty) return;
    for (final goal in _goals) {
      final metric = (goal['metric'] ?? 'km') as String;
      final target = (goal['target'] ?? 0).toDouble();
      final rows = <Map<String, dynamic>>[];
      for (final uid in _participants) {
        final s = _stats[uid] ?? {'km': 0.0, 'xp': 0.0, 'runs': 0, 'steps': 0};
        final value = (s[metric] ?? 0) as num;
        final progress = target > 0 ? (value / target).clamp(0, 1).toDouble() : 0.0;
        rows.add({'uid': uid, 'value': value, 'progress': progress});
      }
      rows.sort((a, b) => (b['value'] as num).compareTo(a['value'] as num));
      _ranking[metric] = rows;
    }
  }

  String? _getUserTeam(String uid) {
    final data = _challenge?.data() as Map<String, dynamic>? ?? {};
    final teams = data['teams'] as Map<String, dynamic>?;
    if (teams == null) return null;
    final aMembers = List<String>.from(teams['timeA']?['members'] ?? []);
    final bMembers = List<String>.from(teams['timeB']?['members'] ?? []);
    if (aMembers.contains(uid)) return 'A';
    if (bMembers.contains(uid)) return 'B';
    return null;
  }

  Future<void> _toggleParticipation() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || _challenge == null) return;
    if (!_canJoin && !_participating) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este desafio é restrito a seguidores 🔒')));
      return;
    }
    final ref = _firestore.collection('challenges').doc(widget.challengeId);
    final isJoining = !_participating;
    try {
      setState(() => _loading = true);
      if (isJoining) {
        await ref.update({'participants': FieldValue.arrayUnion([uid])});
      } else {
        await ref.update({'participants': FieldValue.arrayRemove([uid])});
      }
      await _loadAll();
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'))); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: Colors.white, body: Center(child: CircularProgressIndicator(color: Color(0xFFFF6D00))));
    if (_challenge == null || !_challenge!.exists) return const Scaffold(backgroundColor: Colors.white, body: Center(child: Text('Não encontrado')));

    final data = _challenge!.data() as Map<String, dynamic>;
    final title = data['title'] ?? 'Desafio';
    final desc = data['description'] ?? '';
    final type = data['type'] ?? 'geral';
    final isPublic = data['isPublic'] ?? true;
    final df = DateFormat('dd/MM/yyyy');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      floatingActionButton: _tabController.index == 2 ? null : FloatingActionButton.extended(
        backgroundColor: _participating ? Colors.redAccent : const Color(0xFFFF6D00),
        onPressed: _toggleParticipation,
        label: Text(_participating ? 'Sair' : (_canJoin ? 'Participar' : 'Restrito 🔒'), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        icon: Icon(_participating ? Icons.logout : (_canJoin ? Icons.flag : Icons.lock), color: Colors.white),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(desc, style: const TextStyle(fontSize: 16, color: Colors.black87)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Chip(label: Text(type.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12)), backgroundColor: Colors.black87),
                    const SizedBox(width: 8),
                    Chip(
                      label: Text(isPublic ? 'PÚBLICO' : 'RESTRITO', style: const TextStyle(color: Colors.white, fontSize: 12)),
                      backgroundColor: isPublic ? Colors.green : Colors.orange,
                    ),
                    const Spacer(),
                    if (_start != null && _end != null)
                      Text('${df.format(_start!)} - ${df.format(_end!)}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            tabs: const [Tab(text: 'Visão geral'), Tab(text: 'Ranking'), Tab(text: 'Chat')],
            labelColor: Colors.black,
            unselectedLabelColor: Colors.black54,
            indicatorColor: const Color(0xFFFF6D00),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildOverviewTab(), _buildRankingTab(), _buildChatTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Metas do Desafio', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black)),
        const SizedBox(height: 12),
        ..._goals.map((g) {
          final label = g['label'] ?? 'Meta';
          final metric = g['metric'] ?? 'km';
          final target = (g['target'] ?? 0).toDouble();
          
          num totalValue = 0;
          for (final uid in _participants) {
            if (_stats[uid] != null && _stats[uid]![metric] != null) totalValue += (_stats[uid]![metric] as num);
          }
          final progress = target > 0 ? (totalValue / target).clamp(0.0, 1.0).toDouble() : 0.0;

          return Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                  const SizedBox(height: 4),
                  Text('Total: ${totalValue.toStringAsFixed(1)} / $target $metric', style: const TextStyle(color: Colors.black54, fontSize: 13)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: Colors.grey[200], color: const Color(0xFFFF6D00)),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 20),
        Text('Participantes (${_participants.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black)),
        const SizedBox(height: 12),
        ..._participants.map((uid) {
          final user = _userMap[uid] ?? {};
          final name = user['displayName'] ?? 'Runner';
          final photo = user['photoURL'];
          final s = _stats[uid] ?? {'km': 0.0, 'xp': 0.0};
          return ListTile(
            leading: CircleAvatar(backgroundImage: photo != null ? NetworkImage(photo) : null, backgroundColor: Colors.grey[200], child: photo == null ? const Icon(Icons.person, color: Colors.grey) : null),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black)),
            subtitle: Text('${(s['km'] as double).toStringAsFixed(1)} km • ${(s['xp'] as double).toInt()} XP', style: const TextStyle(color: Colors.black54)),
          );
        }),
      ],
    );
  }

  Widget _buildRankingTab() {
    if (_ranking.isEmpty) return const Center(child: Text('Sem ranking disponível', style: TextStyle(color: Colors.black54)));
    final firstMetric = _goals.isNotEmpty ? _goals.first['metric'] : 'km';
    final current = _ranking[firstMetric] ?? [];
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: current.length,
      itemBuilder: (context, i) {
        final row = current[i];
        final uid = row['uid'] as String;
        final user = _userMap[uid] ?? {};
        final name = user['displayName'] ?? 'Runner';
        final photo = user['photoURL'];
        final value = row['value'] as num;

        return Card(
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: i < 3 ? Colors.amber : Colors.grey[200], child: Text('${i + 1}', style: TextStyle(color: i < 3 ? Colors.white : Colors.black, fontWeight: FontWeight.bold))),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
            trailing: Text(value is double ? '${value.toStringAsFixed(1)}' : '$value', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF6D00), fontSize: 16)),
          ),
        );
      },
    );
  }

  Widget _buildChatTab() {
    return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.chat_bubble_outline, size: 50, color: Colors.grey), SizedBox(height: 10), Text('Chat disponível apenas para participantes', style: TextStyle(color: Colors.black54))]));
  }
}
