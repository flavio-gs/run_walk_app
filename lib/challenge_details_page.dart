import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  late final TabController _tabController;

  // Dados auxiliares
  Map<String, Map<String, dynamic>> _userMap = {}; // uid -> {displayName, photoURL, level}
  List<String> _participants = [];
  List<Map<String, dynamic>> _goals = [];
  DateTime? _start, _end;

  // Estatísticas agregadas por usuário
  // uid -> { km, xp, runs, steps }
  Map<String, Map<String, dynamic>> _stats = {};

  // Ranking por meta: metric -> lista ordenada [{uid, value, progress(0..1)}]
  Map<String, List<Map<String, dynamic>>> _ranking = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // 👇 Adiciona o listener para atualizar a tela ao trocar de aba
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
        if (mounted) {
          setState(() {
            _challenge = null;
            _loading = false;
          });
        }
        return;
      }

      final data = doc.data()!;
      final uid = _auth.currentUser?.uid;
      final participants = List<String>.from(data['participants'] ?? []);
      final goals = List<Map<String, dynamic>>.from(data['goals'] ?? []);
      final start = (data['startDate'] as Timestamp?)?.toDate();
      final end = (data['endDate'] as Timestamp?)?.toDate();
      final createdBy = data['createdBy'] as String?;

      // 🔹 Encerramento automático caso o prazo tenha expirado
      final now = DateTime.now();
      if (end != null && end.isBefore(now) && (data['status'] ?? 'active') != 'closed') {
        try {
          await _firestore.collection('challenges').doc(widget.challengeId).update({
            'status': 'closed',
            'closedAt': Timestamp.fromDate(now),
          });
          debugPrint('Desafio ${widget.challengeId} encerrado automaticamente.');
          data['status'] = 'closed'; // Atualiza o cache local também
        } catch (e) {
          debugPrint('Erro ao encerrar desafio automaticamente: $e');
        }
      }


      // Estado básico
      _challenge = doc;
      _participants = participants;
      _goals = goals;
      _start = start;
      _end = end;
      _participating = uid != null && participants.contains(uid);
      _isCreator = uid != null && createdBy == uid;

      // Carrega perfis dos participantes (foto/nome/nível)
      await _loadParticipantProfiles(participants);

      // Agrega progresso real (km, xp, runs, steps) por participante
      await _aggregateProgress(participants, start, end, data);

      // Calcula ranking por meta
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

    // Batch query em grupos de até 10 (limite do whereIn)
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

      // Se algum não retornou (usuário antigo), cria placeholder
      for (final id in chunk) {
        _userMap.putIfAbsent(id, () => {
          'displayName': 'Runner ${id.substring(0, 6)}',
          'photoURL': null,
          'level': 0,
        });
      }
    }
  }

  Future<void> _aggregateProgress(
      List<String> uids,
      DateTime? start,
      DateTime? end,
      Map<String, dynamic>? challengeData, // 👈 dados do desafio com metas
      ) async {
    _stats.clear();
    if (uids.isEmpty || start == null || end == null) return;

    const chunkSize = 10;
    final startTs = Timestamp.fromDate(start);
    final endTs = Timestamp.fromDate(end);

    for (int i = 0; i < uids.length; i += chunkSize) {
      final chunk = uids.sublist(i, min(i + chunkSize, uids.length));

      // 🔹 1. Busca corridas no período
      final snap = await _firestore
          .collection('corridas')
          .where('userId', whereIn: chunk)
          .where('createdAt', isGreaterThanOrEqualTo: startTs)
          .where('createdAt', isLessThanOrEqualTo: endTs)
          .get();

      for (final uid in chunk) {
        _stats.putIfAbsent(uid, () => {'km': 0.0, 'xp': 0.0, 'runs': 0, 'steps': 0});
      }

      // 🔹 2. Processa corridas
      for (final d in snap.docs) {
        final m = d.data() as Map<String, dynamic>;
        final uid = m['userId'] as String?;
        if (uid == null) continue;

        final km = (m['distance'] ?? m['distanceKm'] ?? 0).toDouble();
        final duration = (m['duration'] ?? 0).toDouble(); // segundos
        final calories = (m['calories'] ?? 0).toDouble();

        // 🔹 3. XP dinâmico balanceado
// Baseado em distância e intensidade, com limites realistas
        double xp = (km * 10) + (calories * 0.2) + (duration / 60); // duração em minutos
        if (xp > 1000) xp = 1000; // limite de segurança

// 🔹 Atualiza acumulado do usuário
        final bucket = _stats[uid]!;
        bucket['km'] = (bucket['km'] as num) + km;

// XP arredondado e controlado
        bucket['xp'] = ((bucket['xp'] as num) + xp).clamp(0, 999999);

// número de corridas
        bucket['runs'] = (bucket['runs'] as num) + 1;

// estimativa de passos (aprox. 1300 passos/km)
        bucket['steps'] = (bucket['steps'] as num) + (km * 1300);
      }

      // 🔹 4. Fallback com XP do perfil
      final usersSnap = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final user in usersSnap.docs) {
        final uid = user.id;
        final data = user.data();
        final userXp = (data['xp'] ?? 0).toDouble();
        final bucket = _stats[uid]!;

        if ((bucket['xp'] ?? 0) == 0) {
          bucket['xp'] = userXp * 0.1;
        }
      }
    }

    // 🔹 5. Calcula progresso de cada meta
    if (challengeData != null && challengeData['goals'] is List) {
      final goals = (challengeData['goals'] as List).cast<Map<String, dynamic>>();

      for (final uid in _stats.keys) {
        final userStats = _stats[uid]!;

        final metas = <Map<String, dynamic>>[];

        for (final goal in goals) {
          final metric = (goal['metric'] ?? '').toLowerCase();
          final target = (goal['target'] ?? 0).toDouble();
          final label = goal['label'] ?? metric.toUpperCase();

          double current = 0.0;
          if (metric == 'km') current = userStats['km'] as double;
          else if (metric == 'xp') current = userStats['xp'] as double;
          else if (metric == 'steps') current = userStats['steps'] as double;

          final progress = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
          metas.add({
            'label': label,
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

        rows.add({
          'uid': uid,
          'value': value,
          'progress': progress,
        });
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
    if (uid == null) return;
    if (_challenge == null) return;

    final ref = _firestore.collection('challenges').doc(widget.challengeId);
    final data = _challenge!.data() as Map<String, dynamic>;
    final isJoining = !_participating;
    final type = data['type'] ?? 'geral';

    try {
      setState(() => _loading = true);

      // 🔹 Se for desafio em grupo, mostra seleção de time
      if (isJoining && type == 'grupo') {
        final teams = data['teams'] as Map<String, dynamic>? ?? {};
        final teamA = teams['timeA']?['name'] ?? 'Time A';
        final teamB = teams['timeB']?['name'] ?? 'Time B';

        String? chosenTeam = await showDialog<String>(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Escolha seu time'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.local_fire_department, color: Colors.white),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    minimumSize: const Size(double.infinity, 45),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(context, 'timeA'),
                  label: Text(teamA, style: const TextStyle(color: Colors.white)),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.ac_unit, color: Colors.white),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    minimumSize: const Size(double.infinity, 45),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(context, 'timeB'),
                  label: Text(teamB, style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        );

        if (chosenTeam == null) {
          setState(() => _loading = false);
          return; // cancelou
        }

        // 🔸 Adiciona o jogador no time escolhido
        await ref.update({
          'participants': FieldValue.arrayUnion([uid]),
          'teams.$chosenTeam.members': FieldValue.arrayUnion([uid]),
        });
      }

      // 🔹 Se for desafio normal
      else if (isJoining) {
        await ref.update({
          'participants': FieldValue.arrayUnion([uid]),
        });
      }

      // 🔹 Caso o jogador saia do desafio
      else {
        await ref.update({
          'participants': FieldValue.arrayRemove([uid]),
          'teams.timeA.members': FieldValue.arrayRemove([uid]),
          'teams.timeB.members': FieldValue.arrayRemove([uid]),
        });
      }

      _participating = isJoining;
      await _loadAll();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isJoining
              ? (type == 'grupo'
              ? 'Você entrou no time escolhido 🎯'
              : 'Você entrou no desafio 🎯')
              : 'Você saiu do desafio 😕'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }



  Future<void> _editChallengeDialog() async {
    if (_challenge == null) return;

    final m = _challenge!.data() as Map<String, dynamic>;
    final titleC = TextEditingController(text: m['title'] ?? '');
    final descC = TextEditingController(text: m['description'] ?? '');
    DateTime? start = (m['startDate'] as Timestamp?)?.toDate();
    DateTime? end = (m['endDate'] as Timestamp?)?.toDate();

    Future<void> pickDate({required bool isStart}) async {
      final picked = await showDatePicker(
        context: context,
        initialDate: (isStart ? start : end) ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        builder: (context, child) {
          return Theme(
            data: ThemeData.light().copyWith(
              colorScheme: const ColorScheme.light(primary: Color(0xFFFF6D00)),
            ),
            child: child!,
          );
        },
      );
      if (picked != null) {
        setState(() {
          if (isStart) {
            start = picked;
            if (end != null && end!.isBefore(start!)) end = null;
          } else {
            end = picked;
          }
        });
      }
    }

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: Row(
          children: const [
            Icon(Icons.edit, color: Color(0xFFFF6D00)),
            SizedBox(width: 8),
            Text('Editar desafio', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleC,
                decoration: const InputDecoration(
                  labelText: 'Título',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descC,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Descrição',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today),
                      label: Text(start != null
                          ? 'Início: ${DateFormat('dd/MM/yyyy').format(start!)}'
                          : 'Definir início'),
                      onPressed: () async => await pickDate(isStart: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.flag),
                      label: Text(end != null
                          ? 'Fim: ${DateFormat('dd/MM/yyyy').format(end!)}'
                          : 'Definir fim'),
                      onPressed: () async => await pickDate(isStart: false),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.black54),
            label: const Text('Cancelar', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6D00),
              shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              try {
                await _firestore.collection('challenges').doc(widget.challengeId).update({
                  'title': titleC.text.trim(),
                  'description': descC.text.trim(),
                  if (start != null) 'startDate': Timestamp.fromDate(start!),
                  if (end != null) 'endDate': Timestamp.fromDate(end!),
                });
                if (mounted) {
                  Navigator.pop(context);
                  await _loadAll();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Desafio atualizado ✅')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erro: $e')),
                  );
                }
              }
            },
            icon: const Icon(Icons.save),
            label: const Text('Salvar'),
          ),
        ],
      ),
    );
  }




  Future<void> _closeChallenge() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.flag_circle, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Encerrar desafio', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Tem certeza que deseja encerrar este desafio?\n'
              'Ele será finalizado e não poderá mais receber novas participações.',
          style: TextStyle(color: Colors.black87),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(Icons.close, color: Colors.black54),
            label: const Text('Cancelar', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.flag),
            label: const Text('Encerrar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _firestore.collection('challenges').doc(widget.challengeId).update({
          'status': 'closed',
          'closedAt': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          await _loadAll();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Desafio encerrado 🏁')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e')),
          );
        }
      }
    }
  }


  // =============== UI ===============

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: Colors.black)),
      );
    }


    if (_challenge == null || !_challenge!.exists) {
      return const Scaffold(
        body: Center(child: Text('Desafio não encontrado 😕')),
      );
    }

    final data = _challenge!.data() as Map<String, dynamic>;
    final title = data['title'] ?? 'Desafio';
    final desc = data['description'] ?? '';
    final type = data['type'] ?? 'geral';
    final df = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isCreator) ...[
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit, color: Colors.black87),
              onPressed: _editChallengeDialog,
            ),
            IconButton(
              tooltip: 'Encerrar',
              icon: const Icon(Icons.flag_circle, color: Colors.black87),
              onPressed: _closeChallenge,
            ),
          ],
        ],
      ),
      backgroundColor: Colors.white,
      // 🔹 BOTÃO DE PARTICIPAÇÃO / SAÍDA
      floatingActionButton: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _tabController.index == 2
            ? null
            : FloatingActionButton.extended(
          key: const ValueKey('fab_main'),
          backgroundColor:
          _participating ? Colors.redAccent : const Color(0xFFFF6D00),
          foregroundColor: Colors.white,
          icon: Icon(_participating ? Icons.logout : Icons.flag),
          label: Text(
            _participating ? 'Sair do desafio' : 'Participar',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          onPressed: _toggleParticipation,
        ),
      ),

      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(desc, style: const TextStyle(fontSize: 16, color: Colors.black87)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Chip(
                      label: Text(
                        type.toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: type == 'grupo'
                          ? Colors.blueGrey
                          : type == 'oficial'
                          ? Colors.orange
                          : Colors.black87,
                    ),
                    const SizedBox(width: 8),
                    if (_start != null && _end != null)
                      Text(
                        '${df.format(_start!)} → ${df.format(_end!)}',
                        style: const TextStyle(color: Colors.black54),
                      )
                    else
                      const Text(
                        'Período não definido',
                        style: TextStyle(color: Colors.black54),
                      ),
                  ],
                ),
                if ((data['status'] ?? 'active') == 'closed') ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.flag_circle, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Desafio encerrado em '
                            '${DateFormat('dd/MM/yyyy – HH:mm').format((data['closedAt'] as Timestamp?)?.toDate() ?? _end!)} 🏁',
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],

              ],
            ),
          ),

          // Abas
          TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFFFF6D00),
            labelColor: Colors.black,
            unselectedLabelColor: Colors.black54,
            tabs: const [
              Tab(text: 'Visão geral'),
              Tab(text: 'Ranking'),
              Tab(text: 'Chat'),
            ],
          ),
          const Divider(height: 1),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const BouncingScrollPhysics(),
              children: [
                _buildOverviewTab(),
                _buildRankingTab(),
                _buildChatTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- VISÃO GERAL ----------
  Widget _buildOverviewTab() {
    final data = _challenge?.data() as Map<String, dynamic>? ?? {};
    final type = (data['type'] ?? 'geral').toString().toLowerCase();
    final goals = _goals;
    final participants = _participants;
    final stats = _stats;

    // 🔹 Mensagem se não há nada ainda
    if (goals.isEmpty && participants.isEmpty) {
      return const Center(
        child: Text(
          'Ainda não há dados de progresso para este desafio 😕',
          style: TextStyle(color: Colors.black54, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      );
    }

    // ==========================================================
    // 🔹 Layout principal
    // ==========================================================
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        const Text(
          'Metas',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 8),

        // Caso sem metas
        if (goals.isEmpty)
          const Text(
            'Nenhuma meta definida para este desafio.',
            style: TextStyle(color: Colors.black54),
          )
        else
          Column(
            children: goals.map((g) {
              final label = (g['label'] ?? 'Meta').toString();
              final metric = (g['metric'] ?? 'km').toString();
              final target = (g['target'] ?? 0).toDouble();

              // 🔹 Soma geral ou média (dependendo do tipo)
              num totalValue = 0;
              for (final uid in participants) {
                if (stats[uid] != null && stats[uid]![metric] != null) {
                  totalValue += (stats[uid]![metric] as num);
                }
              }

              // 🔹 Se for desafio geral, média dos participantes
              if (type == 'geral' && participants.isNotEmpty) {
                totalValue = totalValue / participants.length;
              }

              // 🔹 Ajusta unidades e escala
              String unit = metric;
              double displayValue = totalValue.toDouble();
              if (metric == 'km' && displayValue > 1000) {
                displayValue = displayValue / 1000;
                unit = 'km';
              } else if (metric == 'xp' && displayValue > 10000) {
                displayValue = displayValue / 1000;
                unit = 'mil XP';
              }

              final progress =
              target > 0 ? (displayValue / target).clamp(0.0, 1.0) : 0.0;

              return Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 1,
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.black)),
                      const SizedBox(height: 4),
                      Text(
                        'Meta: $target $unit • ${type == 'geral' ? 'Média atual' : 'Total'}: ${displayValue.toStringAsFixed(2)} $unit',
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          backgroundColor: Colors.grey[300],
                          color: const Color(0xFFFF6D00),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

        const SizedBox(height: 20),
        Text(
          'Participantes (${participants.length})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 8),

        // ==========================================================
        // 🔸 Exibição de participantes
        // ==========================================================
        if (participants.isEmpty)
          const Text('Nenhum participante ainda.', style: TextStyle(color: Colors.black54))
        else if (type == 'grupo')
          DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const TabBar(
                  labelColor: Colors.black,
                  unselectedLabelColor: Colors.black54,
                  indicatorColor: Color(0xFFFF6D00),
                  tabs: [
                    Tab(text: 'Time A ⚡'),
                    Tab(text: 'Time B 🔥'),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 320,
                  child: TabBarView(
                    children: [
                      _buildTeamList('A'),
                      _buildTeamList('B'),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
        // 🔸 Lista individual para desafios gerais
          Column(
            children: participants.map((uid) {
              final user = _userMap[uid] ?? {};
              final name = (user['displayName'] ?? 'Runner') as String;
              final photo = user['photoURL'] as String?;
              final level = (user['level'] ?? 0).toString();

              final s = stats[uid] ?? {'km': 0.0, 'xp': 0.0, 'runs': 0};
              final km = (s['km'] ?? 0).toStringAsFixed(2);
              final xp = (s['xp'] ?? 0).toStringAsFixed(0);

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundImage: photo != null ? NetworkImage(photo) : null,
                    backgroundColor: Colors.grey[200],
                    child: photo == null
                        ? const Icon(Icons.person, color: Colors.black54)
                        : null,
                  ),
                  title: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Nível $level • $km km • $xp XP',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }



  Widget _buildTeamList(String? team) {
    // Filtra participantes do time (ou todos, se null)
    final teamMembers = team == null
        ? _participants
        : _participants.where((uid) => _getUserTeam(uid) == team).toList();

    if (teamMembers.isEmpty) {
      return Center(
        child: Text(
          team == null
              ? 'Nenhum participante.'
              : 'Nenhum participante no Time $team ainda.',
          style: const TextStyle(color: Colors.black54),
        ),
      );
    }

    return ListView.builder(
      itemCount: teamMembers.length,
      itemBuilder: (_, i) {
        final uid = teamMembers[i];
        final u = _userMap[uid] ?? {};
        final photo = u['photoURL'] as String?;
        final name = (u['displayName'] ?? 'Runner') as String;
        final level = (u['level'] ?? 0).toString();

        final s = _stats[uid] ?? {'km': 0.0, 'xp': 0.0, 'runs': 0};
        final km = (s['km'] ?? 0).toStringAsFixed(2);
        final xp = (s['xp'] ?? 0).toStringAsFixed(0);

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 0),
          leading: CircleAvatar(
            radius: 24,
            backgroundColor:
            team == 'A' ? Colors.blue[100] : team == 'B' ? Colors.red[100] : Colors.grey[300],
            backgroundImage: photo != null ? NetworkImage(photo) : null,
            child: photo == null
                ? Icon(Icons.person,
                color: team == 'A'
                    ? Colors.blueAccent
                    : team == 'B'
                    ? Colors.redAccent
                    : Colors.black87)
                : null,
          ),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('Nível $level • ${double.parse(km).toStringAsFixed(2)} km • ${int.parse(xp).toString()} XP',
            style: const TextStyle(color: Colors.black54),
          ),
        );
      },
    );
  }


  // ---------- RANKING ----------
  Widget _buildRankingTab() {
    final isGroup = ((_challenge?.data() as Map<String, dynamic>?)?['type'] ?? '') == 'grupo';

    if (_goals.isEmpty || _participants.isEmpty) {
      return const Center(
        child: Text(
          'Sem metas ou participantes para ranquear.',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    // =========================================================
    // 🔹 RANKING COLETIVO (Desafio de Grupo)
    // =========================================================
    if (isGroup) {
      final teamStats = {
        'A': {'km': 0.0, 'xp': 0.0, 'runs': 0, 'steps': 0},
        'B': {'km': 0.0, 'xp': 0.0, 'runs': 0, 'steps': 0},
      };

      // Soma as métricas de cada jogador dentro do seu time
      for (final uid in _participants) {
        final team = _getUserTeam(uid);
        if (team == null) continue;

        final stats = _stats[uid] ?? {};
        for (final key in teamStats[team]!.keys) {
          final value = (stats[key] ?? 0).toDouble();
          teamStats[team]![key] = (teamStats[team]![key]! + value);
        }
      }

      final firstGoal = _goals.first['metric'] ?? 'km';
      final aValue = teamStats['A']![firstGoal] ?? 0;
      final bValue = teamStats['B']![firstGoal] ?? 0;
      final total = (aValue + bValue).clamp(0, double.infinity);
      final aPercent = total > 0 ? aValue / total : 0.5;
      final bPercent = total > 0 ? bValue / total : 0.5;

      final winner = aValue == bValue
          ? '⚖️ Empate técnico!'
          : aValue > bValue
          ? '🏆 Time A está dominando o desafio!'
          : '🔥 Time B está liderando a competição!';

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          const Text(
            '🏁 Ranking de Times',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 12),

          if (_goals.length > 1)
            ..._goals.map((g) {
              final metric = g['metric'];
              final label = g['label'] ?? metric.toUpperCase();
              final aValue = teamStats['A']![metric] ?? 0;
              final bValue = teamStats['B']![metric] ?? 0;
              final total = (aValue + bValue).clamp(0, double.infinity);
              final aPercent = total > 0 ? aValue / total : 0.5;
              final bPercent = total > 0 ? bValue / total : 0.5;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Stack(
                      children: [
                        Container(
                          height: 20,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey[300],
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              height: 20,
                              width: aPercent * MediaQuery.of(context).size.width * 0.4,
                              decoration: const BoxDecoration(
                                color: Colors.blueAccent,
                                borderRadius: BorderRadius.horizontal(left: Radius.circular(12)),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 20,
                                decoration: const BoxDecoration(
                                  color: Colors.redAccent,
                                  borderRadius: BorderRadius.horizontal(right: Radius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),


          // Time A
          Card(
            color: Colors.blue[50],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.blueAccent,
                child: Text('A', style: TextStyle(color: Colors.white)),
              ),
              title: const Text(
                'Time A',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Total: ${aValue.toStringAsFixed(2)} $firstGoal',
                style: const TextStyle(color: Colors.black54),
              ),
              trailing: const Text('⚡', style: TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(height: 8),

          // Time B
          Card(
            color: Colors.red[50],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.redAccent,
                child: Text('B', style: TextStyle(color: Colors.white)),
              ),
              title: const Text(
                'Time B',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Total: ${bValue.toStringAsFixed(2)} $firstGoal',
                style: const TextStyle(color: Colors.black54),
              ),
              trailing: const Text('🔥', style: TextStyle(fontSize: 20)),
            ),
          ),

          const SizedBox(height: 24),

          // =========================================================
          // 🔥 Barra comparativa (Time A vs Time B)
          // =========================================================
          Container(
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.grey[300],
            ),
            child: Row(
              children: [
                // Barra azul (Time A)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  width: aPercent * MediaQuery.of(context).size.width * 0.8,
                  decoration: const BoxDecoration(
                    color: Colors.blueAccent,
                    borderRadius: BorderRadius.horizontal(left: Radius.circular(20)),
                  ),
                ),
                // Barra vermelha (Time B)
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          Center(
            child: Text(
              winner,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      );
    }

    // =========================================================
    // 🔸 Ranking individual (para desafios normais)
    // =========================================================
    final firstMetric = _goals.first['metric'] as String;
    final current = _ranking[firstMetric] ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Row(
          children: [
            const Text('Ranking por meta:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: firstMetric,
              items: _goals
                  .map((g) => DropdownMenuItem<String>(
                value: g['metric'],
                child: Text(g['metric']),
              ))
                  .toList(),
              onChanged: (v) async {
                setState(() {});
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (current.isEmpty)
          const Text('Sem dados para essa meta ainda.',
              style: TextStyle(color: Colors.black54))
        else
          Column(
            children: current.asMap().entries.map((e) {
              final pos = e.key + 1;
              final row = e.value;
              final uid = row['uid'] as String;
              final value = (row['value'] as num);
              final progress = (row['progress'] as double);
              final goalsList = (_stats[uid]?['goals'] as List?) ?? [];

              final u = _userMap[uid] ?? {};
              final name = (u['displayName'] ?? 'Runner') as String;
              final photo = u['photoURL'] as String?;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.grey[300],
                          backgroundImage: photo != null ? NetworkImage(photo) : null,
                          child: photo == null
                              ? Text('$pos', style: const TextStyle(color: Colors.black))
                              : Text('$pos',
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: Text(
                          value is double ? value.toStringAsFixed(2) : '$value',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),

                      // 🔸 Barras de progresso para cada meta
                      if (goalsList.isNotEmpty)
                        ...goalsList.map((g) {
                          final goal = g as Map<String, dynamic>;
                          final percent = (goal['progress'] ?? 0.0) as double;
                          final color = goal['goalReached'] ? Colors.green : const Color(0xFFFF6D00);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6, left: 16, right: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${goal['label']} (${(percent * 100).toStringAsFixed(1)}%)',
                                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: percent,
                                    minHeight: 8,
                                    backgroundColor: Colors.grey[200],
                                    color: color,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              );

            }).toList(),
          ),
      ],
    );
  }



  void _updateMentionSuggestions(String text, ValueNotifier<List<Map<String, String>>> suggestions) {
    final match = RegExp(r'@(\w+)$').firstMatch(text);
    if (match == null) {
      suggestions.value = [];
      return;
    }

    final query = match.group(1)!.toLowerCase();
    if (query.isEmpty) {
      suggestions.value = [];
      return;
    }

    final filtered = _userMap.entries
        .where((e) =>
        (e.value['displayName'] as String)
            .toLowerCase()
            .contains(query))
        .map((e) => {
      'uid': e.key,
      'name': e.value['displayName'] ?? 'Runner',
    })
        .toList();

    suggestions.value = filtered.take(5).map((e) => Map<String, String>.from(e)).toList();

  }


  // ---------- CHAT ----------
  Widget _buildChatTab() {
    final messagesRef = _firestore
        .collection('challenges')
        .doc(widget.challengeId)
        .collection('messages')
        .orderBy('createdAt', descending: true);

    final textCtrl = TextEditingController();
    final FocusNode inputFocus = FocusNode();
    final ValueNotifier<List<Map<String, String>>> mentionSuggestions = ValueNotifier([]);
    final uid = _auth.currentUser?.uid;

    Future<void> sendMessage() async {
      if (uid == null || textCtrl.text.trim().isEmpty) return;

      // ✅ bloqueia envio se não estiver participando
      if (!_participating) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Apenas participantes podem enviar mensagens 🚫')),
        );
        return;
      }

      final user = _userMap[uid] ?? {};
      await _firestore
          .collection('challenges')
          .doc(widget.challengeId)
          .collection('messages')
          .add({
        'text': textCtrl.text.trim(),
        'senderId': uid,
        'senderName': user['displayName'] ?? 'Runner',
        'senderPhoto': user['photoURL'],
        'createdAt': FieldValue.serverTimestamp(),
      });
      textCtrl.clear();
    }

    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: messagesRef.snapshots(),
            builder: (_, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator(color: Colors.black));
              }
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Center(
                  child: Text('Nenhuma mensagem ainda. Comece o papo! 💬',
                      style: TextStyle(color: Colors.black54)),
                );
              }

              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final m = docs[i].data() as Map<String, dynamic>;
                  final me = _auth.currentUser?.uid;
                  final isMe = m['senderId'] == me;
                  final senderId = m['senderId'] as String;
                  final senderTeam = _getUserTeam(senderId);

                  // 🔹 Define cor de fundo conforme time
                  Color bubbleColor;
                  if (senderTeam == 'A') {
                    bubbleColor = Colors.blue[100]!;
                  } else if (senderTeam == 'B') {
                    bubbleColor = Colors.red[100]!;
                  } else {
                    bubbleColor = Colors.grey[200]!;
                  }

                  // 🔹 Borda da bolha
                  final border = Border.all(
                    color: senderTeam == 'A'
                        ? Colors.blueAccent
                        : senderTeam == 'B'
                        ? Colors.redAccent
                        : Colors.grey[400]!,
                    width: 1,
                  );

                  return Align(
                    alignment:
                    isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(10),
                      constraints: const BoxConstraints(maxWidth: 280),
                      decoration: BoxDecoration(
                        color: bubbleColor,
                        borderRadius: BorderRadius.circular(12),
                        border: border,
                      ),
                      child: Column(
                        crossAxisAlignment: isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isMe && m['senderPhoto'] != null)
                                CircleAvatar(
                                  radius: 10,
                                  backgroundImage:
                                  NetworkImage(m['senderPhoto']),
                                ),
                              if (!isMe) const SizedBox(width: 6),
                              Text(
                                isMe
                                    ? 'Você'
                                    : (m['senderName'] ?? 'Runner'),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: senderTeam == 'A'
                                      ? Colors.blueAccent
                                      : senderTeam == 'B'
                                      ? Colors.redAccent
                                      : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          RichText(
                            text: TextSpan(
                              children: (m['text'] ?? '')
                                  .split(' ')
                                  .map<TextSpan>((word) {
                                if (word.startsWith('@')) {
                                  return TextSpan(
                                    text: '$word ',
                                    style: const TextStyle(
                                      color: Color(0xFFFF6D00),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  );
                                }
                                return TextSpan(
                                  text: '$word ',
                                  style: const TextStyle(color: Colors.black87),
                                );
                              })
                                  .toList(),
                            ),
                          ),

                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),

        // 🔹 Campo de envio (apenas participantes)
        if (_participating)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Stack(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 🔸 Campo de texto
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: textCtrl,
                              focusNode: inputFocus,
                              onChanged: (v) =>
                                  _updateMentionSuggestions(v, mentionSuggestions),
                              decoration: InputDecoration(
                                hintText: 'Escreva uma mensagem...',
                                filled: true,
                                fillColor: Colors.grey[100],
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: sendMessage,
                            icon: const Icon(Icons.send),
                            color: const Color(0xFFFF6D00),
                          ),
                        ],
                      ),

                      // 🔸 Sugestões de menções
                      ValueListenableBuilder<List<Map<String, String>>>(
                        valueListenable: mentionSuggestions,
                        builder: (_, list, __) {
                          if (list.isEmpty) return const SizedBox.shrink();
                          return Container(
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: list.length,
                              itemBuilder: (_, i) {
                                final item = list[i];
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    item['name']!,
                                    style: const TextStyle(color: Colors.black),
                                  ),
                                  onTap: () {
                                    final text = textCtrl.text;
                                    final atMatch = RegExp(r'@\w*$')
                                        .firstMatch(textCtrl.text);
                                    if (atMatch != null) {
                                      final start = atMatch.start;
                                      final newText =
                                          text.substring(0, start) + '@${item['name']} ';
                                      textCtrl.text = newText;
                                      textCtrl.selection = TextSelection.fromPosition(
                                        TextPosition(offset: newText.length),
                                      );
                                    } else {
                                      textCtrl.text += '@${item['name']} ';
                                    }
                                    mentionSuggestions.value = [];
                                    FocusScope.of(context).requestFocus(inputFocus);
                                  },
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )

        else
          Container(
            color: Colors.grey[100],
            padding: const EdgeInsets.all(16),
            child: const Text(
              'Entre em um time para participar do chat 💬',
              style: TextStyle(color: Colors.black54),
            ),
          ),
      ],
    );
  }

}
