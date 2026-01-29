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

  // ✅ Fonte de verdade (pós-entrada)
  Map<String, Map<String, dynamic>> _progressByUser = {};
  Map<int, String> _firstFinisherByGoal = {}; // goalIndex -> uid
  String? _championUid;

  List<Map<String, dynamic>> _goalRanking = [];

  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadAll();
  }

  bool get _isClosed {
    final data = _challenge?.data() as Map<String, dynamic>? ?? {};
    final status = (data['status'] ?? 'active').toString();
    // fallback: se não tiver status, fecha por data
    final now = DateTime.now();
    if (status == 'closed') return true;
    if (_end != null && _end!.isBefore(now)) return true;
    return false;
  }

  Future<void> _closeChallenge() async {
    if (!_isCreator) return;
    final ref = _firestore.collection('challenges').doc(widget.challengeId);
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      setState(() => _loading = true);

      await ref.set({
        'status': 'closed',
        'closedAt': FieldValue.serverTimestamp(),
        'closedBy': uid,
      }, SetOptions(merge: true));

      await _loadAll();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Desafio encerrado ✅')),
      );
    } catch (e) {
      debugPrint("Erro ao fechar desafio: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao encerrar: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAll() async {
    try {
      setState(() => _loading = true);

      final doc = await _firestore.collection('challenges').doc(widget.challengeId).get();
      if (!doc.exists) {
        if (mounted) setState(() {
          _challenge = null;
          _loading = false;
        });
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

      // ✅ fecha automaticamente se acabou (mas só se tiver status e não estiver fechado)
      final now = DateTime.now();
      if (end != null && end.isBefore(now) && (data['status'] ?? 'active') != 'closed') {
        await _firestore.collection('challenges').doc(widget.challengeId).set({
          'status': 'closed',
          'closedAt': Timestamp.fromDate(now),
        }, SetOptions(merge: true));
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
      await _loadProgressDocs(participants); // ✅ fonte de verdade
      _computeRanking(); // ✅ usa progress + champion

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
      final snap = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

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

  Future<void> _loadProgressDocs(List<String> uids) async {
    _progressByUser.clear();
    _firstFinisherByGoal.clear();
    _championUid = null;

    if (uids.isEmpty) return;

    // ✅ pega todos os progress do desafio
    final snap = await _firestore
        .collection('challenges')
        .doc(widget.challengeId)
        .collection('progress')
        .get();

    for (final d in snap.docs) {
      _progressByUser[d.id] = Map<String, dynamic>.from(d.data());
    }

    // ✅ primeiro a concluir cada goal (menor completedAt[i])
    for (int i = 0; i < _goals.length; i++) {
      Timestamp? bestTime;
      String? bestUid;

      for (final uid in uids) {
        final p = _progressByUser[uid];
        if (p == null) continue;

        final completedAtRaw = p['completedAt'];
        final Map<String, dynamic> completedAt = completedAtRaw is Map
            ? Map<String, dynamic>.from(completedAtRaw)
            : <String, dynamic>{};

        final t = completedAt['$i'];
        if (t is Timestamp) {
          if (bestTime == null || t.compareTo(bestTime) < 0) {
            bestTime = t;
            bestUid = uid;
          }
        }
      }

      if (bestUid != null) _firstFinisherByGoal[i] = bestUid;
    }

    // ✅ campeão: concluiu tudo mais cedo
    Timestamp? bestAll;
    String? bestChampion;

    for (final uid in uids) {
      final p = _progressByUser[uid];
      if (p == null) continue;

      final isCompleted = (p['isCompleted'] ?? false) == true;
      if (!isCompleted) continue;

      final t = p['completedAtAll'];
      if (t is Timestamp) {
        if (bestAll == null || t.compareTo(bestAll) < 0) {
          bestAll = t;
          bestChampion = uid;
        }
      } else {
        bestChampion ??= uid;
      }
    }

    _championUid = bestChampion;
  }

  void _computeRanking() {
    _goalRanking = [];

    for (final uid in _participants) {
      final p = _progressByUser[uid] ?? {};
      final completed = (p['completedGoalIndexes'] as List?) ?? [];
      final completedCount = completed.length;

      final isChampion = (_championUid != null && uid == _championUid);

      _goalRanking.add({
        'uid': uid,
        'completedCount': completedCount,
        'isChampion': isChampion,
        'completedAtAll': p['completedAtAll'], // desempate
      });
    }

    // ✅ campeão > mais metas > quem concluiu tudo mais cedo
    _goalRanking.sort((a, b) {
      final ac = (a['isChampion'] == true) ? 1 : 0;
      final bc = (b['isChampion'] == true) ? 1 : 0;
      if (ac != bc) return bc.compareTo(ac);

      final aCount = (a['completedCount'] as int);
      final bCount = (b['completedCount'] as int);
      if (aCount != bCount) return bCount.compareTo(aCount);

      final at = a['completedAtAll'];
      final bt = b['completedAtAll'];
      if (at is Timestamp && bt is Timestamp) return at.compareTo(bt);
      if (at is Timestamp) return -1;
      if (bt is Timestamp) return 1;

      return 0;
    });
  }

  Future<void> _toggleParticipation() async {
    if (_joining) return;
    _joining = true;

    final uid = _auth.currentUser?.uid;
    if (uid == null || _challenge == null) {
      _joining = false;
      return;
    }

    if (_isClosed && !_participating) {
      _joining = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este desafio já foi encerrado 🛑')),
      );
      return;
    }

    if (!_canJoin && !_participating) {
      _joining = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este desafio é restrito a seguidores 🔒')),
      );
      return;
    }

    final challengeRef = _firestore.collection('challenges').doc(widget.challengeId);
    final progressRef = challengeRef.collection('progress').doc(uid);
    final isJoining = !_participating;

    try {
      setState(() => _loading = true);

      if (isJoining) {
        await challengeRef.update({
          'participants': FieldValue.arrayUnion([uid]),
        });

        final pSnap = await progressRef.get();
        if (!pSnap.exists) {
          final now = DateTime.now();
          await progressRef.set({
            'joinedAt': FieldValue.serverTimestamp(),
            'joinedAtLocal': Timestamp.fromDate(now),
            'runs': 0,
            'km': 0.0,
            'xp': 0,
            'completedGoalIndexes': <int>[],
            'completedAt': <String, dynamic>{},
            'isCompleted': false,
            'completedAtAll': null,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } else {
        await challengeRef.update({
          'participants': FieldValue.arrayRemove([uid]),
        });
        // opcional:
        // await progressRef.delete();
      }

      await _loadAll();
    } catch (e) {
      debugPrint("Erro toggleParticipation: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      _joining = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFF6D00)),
        ),
      );
    }

    if (_challenge == null || !_challenge!.exists) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: Text('Não encontrado')),
      );
    }

    final data = _challenge!.data() as Map<String, dynamic>;
    final title = data['title'] ?? 'Desafio';
    final desc = data['description'] ?? '';
    final type = data['type'] ?? 'geral';
    final isPublic = data['isPublic'] ?? true;
    final df = DateFormat('dd/MM/yyyy');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          if (_isCreator)
            IconButton(
              tooltip: 'Encerrar desafio',
              onPressed: _isClosed ? null : _closeChallenge,
              icon: Icon(
                Icons.lock_clock,
                color: _isClosed ? Colors.black26 : Colors.black87,
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _participating ? Colors.redAccent : const Color(0xFFFF6D00),
        onPressed: (_loading || _joining || (_isClosed && !_participating))
            ? null
            : _toggleParticipation,
        label: Text(
          _isClosed && !_participating
              ? 'Encerrado'
              : (_participating ? 'Sair' : (_canJoin ? 'Participar' : 'Restrito 🔒')),
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        icon: Icon(
          _participating ? Icons.logout : (_isClosed ? Icons.lock : (_canJoin ? Icons.flag : Icons.lock)),
          color: Colors.white,
        ),
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
                    Chip(
                      label: Text(type.toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontSize: 12)),
                      backgroundColor: Colors.black87,
                    ),
                    const SizedBox(width: 8),
                    Chip(
                      label: Text(isPublic ? 'PÚBLICO' : 'RESTRITO',
                          style: const TextStyle(color: Colors.white, fontSize: 12)),
                      backgroundColor: isPublic ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Chip(
                      label: Text(_isClosed ? 'ENCERRADO' : 'ATIVO',
                          style: const TextStyle(color: Colors.white, fontSize: 12)),
                      backgroundColor: _isClosed ? Colors.redAccent : Colors.blueGrey,
                    ),
                    const Spacer(),
                    if (_start != null && _end != null)
                      Text(
                        '${df.format(_start!)} - ${df.format(_end!)}',
                        style: const TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                  ],
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            tabs: const [Tab(text: 'Visão geral'), Tab(text: 'Ranking')],
            labelColor: Colors.black,
            unselectedLabelColor: Colors.black54,
            indicatorColor: const Color(0xFFFF6D00),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildOverviewTab(), _buildRankingTab()],
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
        const Text(
          'Metas do Desafio',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black),
        ),
        const SizedBox(height: 12),

        ..._goals.asMap().entries.map((entry) {
          final idx = entry.key;
          final g = entry.value;

          final label = g['label'] ?? 'Meta';
          final metric = (g['metric'] ?? 'km').toString().toLowerCase();
          final target = (g['target'] ?? 0).toDouble();

          num totalValue = 0;
          for (final uid in _participants) {
            final p = _progressByUser[uid] ?? {};
            if (metric == 'km') totalValue += ((p['km'] ?? 0) as num);
            if (metric == 'xp') totalValue += ((p['xp'] ?? 0) as num);
            if (metric == 'runs') totalValue += ((p['runs'] ?? 0) as num);
            if (metric == 'steps') totalValue += ((p['steps'] ?? 0) as num);
          }

          final progress = target > 0
              ? (totalValue / target).clamp(0.0, 1.0).toDouble()
              : 0.0;

          final finisherUid = _firstFinisherByGoal[idx];
          final finisher = finisherUid != null ? _userMap[finisherUid] : null;
          final finisherName = finisher?['displayName'] ?? '';
          final finisherPhoto = finisher?['photoURL'];

          return Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                      ),
                      if (finisherUid != null)
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundImage: finisherPhoto != null ? NetworkImage(finisherPhoto) : null,
                              backgroundColor: Colors.grey[200],
                              child: finisherPhoto == null
                                  ? const Icon(Icons.person, size: 16, color: Colors.grey)
                                  : null,
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.emoji_events, size: 18, color: Colors.amber),
                          ],
                        ),
                    ],
                  ),
                  if (finisherUid != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Concluída primeiro por $finisherName',
                        style: const TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    'Total: ${totalValue.toStringAsFixed(1)} / $target $metric',
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: Colors.grey[200],
                      color: const Color(0xFFFF6D00),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),

        const SizedBox(height: 20),
        Text(
          'Participantes (${_participants.length})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black),
        ),
        const SizedBox(height: 12),

        ..._participants.map((uid) {
          final user = _userMap[uid] ?? {};
          final name = user['displayName'] ?? 'Runner';
          final photo = user['photoURL'];

          final p = _progressByUser[uid] ?? {};
          final km = ((p['km'] ?? 0) as num).toDouble();
          final xp = ((p['xp'] ?? 0) as num).toInt();
          final runs = ((p['runs'] ?? 0) as num).toInt();

          return ListTile(
            leading: CircleAvatar(
              backgroundImage: photo != null ? NetworkImage(photo) : null,
              backgroundColor: Colors.grey[200],
              child: photo == null ? const Icon(Icons.person, color: Colors.grey) : null,
            ),
            title: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black),
            ),
            subtitle: Text(
              '${km.toStringAsFixed(1)} km • $xp XP • $runs corridas',
              style: const TextStyle(color: Colors.black54),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildRankingTab() {
    if (_goalRanking.isEmpty) {
      return const Center(
        child: Text('Sem ranking disponível', style: TextStyle(color: Colors.black54)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _goalRanking.length,
      itemBuilder: (context, i) {
        final row = _goalRanking[i];
        final uid = row['uid'] as String;
        final user = _userMap[uid] ?? {};
        final name = user['displayName'] ?? 'Runner';
        final photo = user['photoURL'];

        final completedCount = (row['completedCount'] as int);
        final isChampion = row['isChampion'] == true;

        return Card(
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: photo != null ? NetworkImage(photo) : null,
              backgroundColor: Colors.grey[200],
              child: photo == null ? const Icon(Icons.person, color: Colors.grey) : null,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ),
                if (isChampion)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '🏆 CAMPEÃO',
                      style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black),
                    ),
                  ),
              ],
            ),
            subtitle: Text(
              'Metas concluídas: $completedCount / ${_goals.length}',
              style: const TextStyle(color: Colors.black54),
            ),
            trailing: Text(
              '$completedCount',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF6D00),
                fontSize: 18,
              ),
            ),
          ),
        );
      },
    );
  }
}
