// create_group_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  // ✅ Controllers
  final TextEditingController _name = TextEditingController();
  final TextEditingController _desc = TextEditingController();

  // ✅ State
  bool _isPublic = true;
  bool _saving = false;

  // 🎨 Theme (igual ao resto do app)
  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kBg = Color(0xFF0B0B0F);
  static const Color kCard = Color(0xFF12121A);

  static const int kCreateClanCost = 25;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  String _normalizeUsername(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return '';
    return s.startsWith('@') ? s.substring(1) : s;
  }

  Future<void> _createGroup() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Você precisa estar logado para criar um clã.')),
      );
      return;
    }

    final name = _name.text.trim();
    final desc = _desc.text.trim();

    if (name.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O nome do clã precisa ter pelo menos 3 caracteres.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final userRef = _db.collection('users').doc(user.uid);
      final groupRef = _db.collection('groups').doc(); // autoId

      await _db.runTransaction((tx) async {
        // 1) Lê o usuário dentro da transação (fonte de verdade)
        final uSnap = await tx.get(userRef);
        final u = (uSnap.data() ?? <String, dynamic>{});

        final int totalPoints =
        (u['totalPoints'] is int) ? u['totalPoints'] as int : 0;

        if (totalPoints < kCreateClanCost) {
          throw Exception('PONTOS_INSUFICIENTES');
        }

        // 2) desconta 25
        tx.update(userRef, {
          'totalPoints': FieldValue.increment(-kCreateClanCost),
        });

        // 3) Pega dados pra espelhar no member
        final displayName = (u['displayName'] ?? u['name'] ?? 'Runner').toString();
        final photoUrl = (u['photoUrl'] ?? u['photoURL'] ?? '').toString();
        final username = _normalizeUsername((u['username'] ?? '').toString());

        // 4) Cria o grupo
        tx.set(groupRef, {
          'name': name,
          'description': desc,
          'isPublic': _isPublic,
          'ownerId': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
          'membersCount': 1,
          'searchName': name.toLowerCase(),
          'createCost': kCreateClanCost, // opcional (auditoria)
        });

        // 5) Adiciona owner como member
        tx.set(groupRef.collection('members').doc(user.uid), {
          'role': 'owner',
          'joinedAt': FieldValue.serverTimestamp(),
          'uid': user.uid,
          'displayName': displayName,
          'username': username,
          'photoUrl': photoUrl,
          // ranking interno (snapshot/mvp)
          'xp': 0,
          'km': 0,
        });
      });

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clã criado com sucesso 🧡 (-25 pontos)')),
      );
    } catch (e) {
      if (!mounted) return;

      final msg = e.toString().contains('PONTOS_INSUFICIENTES')
          ? 'Você precisa de $kCreateClanCost pontos para criar um clã.'
          : 'Erro ao criar clã: $e';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildPointsCostCard() {
    final user = _auth.currentUser;

    if (user == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: const Text(
          'Faça login para ver seus pontos.',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
        ),
      );
    }

    final userRef = _db.collection('users').doc(user.uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userRef.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? <String, dynamic>{};

        final int totalPoints =
        (data['totalPoints'] is int) ? data['totalPoints'] as int : 0;

        final int after = totalPoints - kCreateClanCost;
        final bool canCreate = totalPoints >= kCreateClanCost;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: canCreate ? kCard : const Color(0xFF2A1212),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: canCreate ? Colors.white12 : Colors.redAccent.withOpacity(0.35),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.bolt_rounded,
                color: canCreate ? kOrange : Colors.redAccent,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Criar um clã custa $kCreateClanCost pontos',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Seus pontos: $totalPoints  →  Após criar: ${after < 0 ? 0 : after}',
                      style: TextStyle(
                        color: canCreate ? Colors.white70 : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        height: 1.2,
                      ),
                    ),
                    if (!canCreate) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Pontos insuficientes para criar um clã.',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCreateButton() {
    final user = _auth.currentUser;

    if (user == null) {
      return ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor: kOrange,
          foregroundColor: Colors.black,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          disabledBackgroundColor: kOrange.withOpacity(0.35),
          disabledForegroundColor: Colors.black54,
        ),
        child: Text(
          'Criar Clã • $kCreateClanCost pts',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      );
    }

    final userRef = _db.collection('users').doc(user.uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userRef.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? <String, dynamic>{};
        final int totalPoints =
        (data['totalPoints'] is int) ? data['totalPoints'] as int : 0;

        final bool canCreate = totalPoints >= kCreateClanCost;

        return ElevatedButton(
          onPressed: (_saving || !canCreate) ? null : _createGroup,
          style: ElevatedButton.styleFrom(
            backgroundColor: kOrange,
            foregroundColor: Colors.black,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            disabledBackgroundColor: kOrange.withOpacity(0.35),
            disabledForegroundColor: Colors.black54,
          ),
          child: _saving
              ? const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
          )
              : Text(
            'Criar Clã • $kCreateClanCost pts',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: kBg,
        surfaceTintColor: kBg,
        centerTitle: true,
        title: const Text(
          'Criar Clã',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 20,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // 🧱 Card - Nome/Descrição
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Nome do Clã (ex: Clã dos Corredores)',
                      hintStyle: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 18),
                  TextField(
                    controller: _desc,
                    maxLines: 3,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Descrição (opcional)',
                      hintStyle: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 🔒 Card - Privacidade
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Privacidade do Clã',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _PrivacyOption(
                          selected: _isPublic,
                          icon: Icons.public_rounded,
                          title: 'Público',
                          subtitle: 'Qualquer um pode entrar',
                          onTap: () => setState(() => _isPublic = true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PrivacyOption(
                          selected: !_isPublic,
                          icon: Icons.lock_rounded,
                          title: 'Privado',
                          subtitle: 'Precisa aprovação do admin',
                          onTap: () => setState(() => _isPublic = false),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ✅ Card de pontos (saldo e após)
            _buildPointsCostCard(),

            const SizedBox(height: 18),

            // ✅ Botão Criar (com trava de pontos)
            _buildCreateButton(),

            const SizedBox(height: 10),

            // 📝 Nota
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kOrange.withOpacity(0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kOrange.withOpacity(0.25)),
              ),
              child: const Text(
                '⚔️ Dica: em grupos privados, os jogadores enviam um pedido e o admin decide quem entra.',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyOption extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  static const Color kOrange = Color(0xFFFF7A00);

  const _PrivacyOption({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? kOrange : const Color(0xFF0B0B0F);
    final fgTitle = selected ? Colors.black : Colors.white;
    final fgSub = selected ? Colors.black87 : Colors.white60;
    final border = selected ? kOrange.withOpacity(0.95) : Colors.white12;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: 1.2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: selected ? Colors.black : kOrange),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: fgTitle,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: fgSub,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
