// create_group_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:run_walk_app/theme/season_theme_scope.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  // Controllers
  final TextEditingController _name = TextEditingController();
  final TextEditingController _desc = TextEditingController();

  // State
  bool _isPublic = true;
  bool _saving = false;

  static const int kCreateClanCost = 25;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  SeasonTheme _S(BuildContext c) => SeasonThemeScope.of(c);

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
      final groupRef = _db.collection('groups').doc();

      await _db.runTransaction((tx) async {
        final uSnap = await tx.get(userRef);
        final u = (uSnap.data() ?? <String, dynamic>{});

        final int totalPoints = (u['totalPoints'] is int) ? u['totalPoints'] : 0;

        if (totalPoints < kCreateClanCost) {
          throw Exception('PONTOS_INSUFICIENTES');
        }

        tx.update(userRef, {
          'totalPoints': FieldValue.increment(-kCreateClanCost),
        });

        final displayName = (u['displayName'] ?? u['name'] ?? 'Runner').toString();
        final photoUrl = (u['photoUrl'] ?? u['photoURL'] ?? '').toString();
        final username = _normalizeUsername((u['username'] ?? '').toString());

        tx.set(groupRef, {
          'name': name,
          'description': desc,
          'isPublic': _isPublic,
          'ownerId': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
          'membersCount': 1,
          'searchName': name.toLowerCase(),
          'createCost': kCreateClanCost,
        });

        tx.set(groupRef.collection('members').doc(user.uid), {
          'role': 'owner',
          'joinedAt': FieldValue.serverTimestamp(),
          'uid': user.uid,
          'displayName': displayName,
          'username': username,
          'photoUrl': photoUrl,
          'xp': 0,
          'km': 0,
        });
      });

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Clã criado com sucesso 🧡 (-$kCreateClanCost pontos)')),
      );
    } catch (e) {
      if (!mounted) return;

      final msg = e.toString().contains('PONTOS_INSUFICIENTES')
          ? 'Você precisa de $kCreateClanCost pontos para criar um clã.'
          : 'Erro ao criar clã: $e';

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildPointsCostCard(SeasonTheme s) {
    final user = _auth.currentUser;

    if (user == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: s.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: s.border),
        ),
        child: Text(
          'Faça login para ver seus pontos.',
          style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w700),
        ),
      );
    }

    final userRef = _db.collection('users').doc(user.uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userRef.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? <String, dynamic>{};
        final int totalPoints = (data['totalPoints'] is int) ? data['totalPoints'] : 0;

        final int after = totalPoints - kCreateClanCost;
        final bool canCreate = totalPoints >= kCreateClanCost;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: canCreate ? s.card : s.destructive.withOpacity(0.25),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: canCreate ? s.border : s.destructive.withOpacity(0.6),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.bolt_rounded, color: canCreate ? s.primary : s.destructive),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    'Criar um clã custa $kCreateClanCost pontos',
                    style: TextStyle(
                      color: s.foreground,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Seus pontos: $totalPoints  →  Após criar: ${after < 0 ? 0 : after}',
                    style: TextStyle(
                      color: s.mutedForeground,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                  if (!canCreate) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Pontos insuficientes para criar um clã.',
                      style: TextStyle(
                        color: s.foreground,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCreateButton(SeasonTheme s) {
    final user = _auth.currentUser;
    if (user == null) {
      return ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor: s.primary,
          foregroundColor: s.primaryForeground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text('Criar Clã • $kCreateClanCost pts',
            style: const TextStyle(fontWeight: FontWeight.w900)),
      );
    }

    final userRef = _db.collection('users').doc(user.uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userRef.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? <String, dynamic>{};
        final int totalPoints = (data['totalPoints'] is int) ? data['totalPoints'] : 0;
        final bool canCreate = totalPoints >= kCreateClanCost;

        return ElevatedButton(
          onPressed: (_saving || !canCreate) ? null : _createGroup,
          style: ElevatedButton.styleFrom(
            backgroundColor: s.primary,
            foregroundColor: s.primaryForeground,
            disabledBackgroundColor: s.primary.withOpacity(0.35),
            disabledForegroundColor: s.primaryForeground.withOpacity(0.6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: _saving
              ? SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: s.primaryForeground),
          )
              : Text('Criar Clã • $kCreateClanCost pts',
              style: const TextStyle(fontWeight: FontWeight.w900)),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _S(context);

    return Scaffold(
      backgroundColor: s.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: s.background,
        surfaceTintColor: s.background,
        centerTitle: true,
        iconTheme: IconThemeData(color: s.foreground),
        title: Text(
          'Criar Clã',
          style: TextStyle(
            color: s.foreground,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _buildTextCard(s),
            const SizedBox(height: 12),
            _buildPrivacyCard(s),
            const SizedBox(height: 14),
            _buildPointsCostCard(s),
            const SizedBox(height: 18),
            _buildCreateButton(s),
          ],
        ),
      ),
    );
  }

  Widget _buildTextCard(SeasonTheme s) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: s.card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: s.border),
    ),
    child: Column(children: [
      TextField(
        controller: _name,
        style: TextStyle(color: s.foreground, fontWeight: FontWeight.w800),
        decoration: InputDecoration(
          hintText: 'Nome do Clã',
          hintStyle: TextStyle(color: s.mutedForeground),
          border: InputBorder.none,
        ),
      ),
      Divider(color: s.border),
      TextField(
        controller: _desc,
        maxLines: 3,
        style: TextStyle(color: s.foreground),
        decoration: InputDecoration(
          hintText: 'Descrição (opcional)',
          hintStyle: TextStyle(color: s.mutedForeground),
          border: InputBorder.none,
        ),
      ),
    ]),
  );

  Widget _buildPrivacyCard(SeasonTheme s) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: s.card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: s.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Privacidade do Clã',
          style: TextStyle(color: s.foreground, fontWeight: FontWeight.w900)),
      const SizedBox(height: 10),
      Row(children: [
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
      ]),
    ]),
  );
}

class _PrivacyOption extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PrivacyOption({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = SeasonThemeScope.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? s.primary : s.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? s.primary : s.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? s.primaryForeground : s.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: TextStyle(
                        color: selected ? s.primaryForeground : s.foreground,
                        fontWeight: FontWeight.w900,
                        fontSize: 13)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(
                        color: selected ? s.primaryForeground : s.mutedForeground,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
