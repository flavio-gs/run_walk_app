import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:run_walk_app/theme/season_theme_scope.dart';


class CreateChallengePage extends StatefulWidget {
  const CreateChallengePage({super.key});

  @override
  State<CreateChallengePage> createState() => _CreateChallengePageState();
}

class _CreateChallengePageState extends State<CreateChallengePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _teamAController = TextEditingController();
  final _teamBController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  String _type = 'geral'; // geral | grupo | oficial
  bool _isPublic = true; // privacidade
  bool _loading = false;

  List<Map<String, dynamic>> _goals = []; // metas

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _teamAController.dispose();
    _teamBController.dispose();
    super.dispose();
  }

  Future<void> _selectDate({required bool isStart}) async {
    final theme = SeasonThemeScope.of(context);
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: DateTime(now.year + 1),
      builder: (context, child) {
        final base = ThemeData.dark().copyWith(
          colorScheme: ColorScheme.dark(
            primary: theme.accent,
            surface: theme.card,
            onSurface: Colors.white,
          ),
          dialogBackgroundColor: theme.card,
        );
        return Theme(data: base, child: child!);
      },
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate != null && _endDate!.isBefore(_startDate!)) {
            _endDate = null;
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  void _addGoalDialog() {
    final theme = SeasonThemeScope.of(context);
    final labelController = TextEditingController();
    final targetController = TextEditingController();
    String metric = 'km';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: theme.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Nova Meta',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDeco(theme, 'Descrição da meta'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: metric,
                dropdownColor: theme.card,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                decoration: _inputDeco(theme, 'Métrica'),
                items: const [
                  DropdownMenuItem(value: 'km', child: Text('Distância (km)')),
                  DropdownMenuItem(value: 'xp', child: Text('Experiência (XP)')),
                  DropdownMenuItem(value: 'runs', child: Text('Corridas')),
                  DropdownMenuItem(value: 'steps', child: Text('Passos')),
                ],
                onChanged: (v) => metric = v ?? 'km',
              ),
              const SizedBox(height: 10),
              TextField(
                controller: targetController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDeco(theme, 'Valor alvo'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w900),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.accent,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Adicionar', style: TextStyle(fontWeight: FontWeight.w900)),
              onPressed: () {
                if (labelController.text.isNotEmpty && targetController.text.isNotEmpty) {
                  setState(() {
                    _goals.add({
                      'label': labelController.text.trim(),
                      'metric': metric,
                      'target': double.tryParse(targetController.text) ?? 0,
                    });
                  });
                  Navigator.pop(context);
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveChallenge() async {
    if (!_formKey.currentState!.validate()) return;

    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Defina as datas do desafio.')),
      );
      return;
    }

    if (_goals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adicione pelo menos uma meta.')),
      );
      return;
    }

    try {
      setState(() => _loading = true);

      final uid = _auth.currentUser?.uid;
      if (uid == null) throw Exception('Usuário não autenticado');

      final now = DateTime.now();

      final challengeData = {
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'type': _type, // geral | grupo
        'isPublic': _isPublic,
        'status': 'active',
        'createdBy': uid,
        'createdAt': Timestamp.fromDate(now),
        'startDate': Timestamp.fromDate(_startDate!),
        'endDate': Timestamp.fromDate(_endDate!),

        'participants': [uid],
        'goals': _goals,

        if (_type == 'grupo')
          'teams': {
            'timeA': {
              'name': _teamAController.text.trim(),
              'members': [uid],
            },
            'timeB': {
              'name': _teamBController.text.trim(),
              'members': [],
            },
          },
      };

      final challengeRef = await _firestore.collection('challenges').add(challengeData);

      await challengeRef.collection('progress').doc(uid).set({
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
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Desafio criado com sucesso 🎯')),
      );

      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Erro ao salvar desafio: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = SeasonThemeScope.of(context);
    final df = DateFormat('dd/MM/yyyy');

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.background,
        surfaceTintColor: theme.background,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        title: const Text(
          'Criar Desafio',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
          children: [
            const Text(
              '📅 Informações do Desafio',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
              decoration: _inputDeco(theme, 'Título do desafio'),
              validator: (v) => v!.trim().isEmpty ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _descController,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
              decoration: _inputDeco(theme, 'Descrição'),
              maxLines: 3,
              validator: (v) => v!.trim().isEmpty ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 16),

            const Text(
              'Tipo:',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _typeChip(theme, 'Geral', 'geral'),
                _typeChip(theme, 'Grupo x Grupo', 'grupo'),
              ],
            ),
            const SizedBox(height: 20),

            const Text(
              'Privacidade:',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _isPublic ? 'Público' : 'Apenas Seguidores',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                _isPublic
                    ? 'Qualquer usuário poderá ver e participar.'
                    : 'Apenas seus seguidores aprovados poderão participar.',
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
              ),
              value: _isPublic,
              onChanged: (v) => setState(() => _isPublic = v),
              activeColor: theme.accent,
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _selectDate(isStart: true),
                    child: AbsorbPointer(
                      child: TextFormField(
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                        decoration: _inputDeco(theme, 'Data inicial'),
                        controller: TextEditingController(
                          text: _startDate != null ? df.format(_startDate!) : '',
                        ),
                        validator: (_) => _startDate == null ? 'Obrigatório' : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _selectDate(isStart: false),
                    child: AbsorbPointer(
                      child: TextFormField(
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                        decoration: _inputDeco(theme, 'Data final'),
                        controller: TextEditingController(
                          text: _endDate != null ? df.format(_endDate!) : '',
                        ),
                        validator: (_) => _endDate == null ? 'Obrigatório' : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_type == 'grupo') ...[
              const Text(
                'Times:',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _teamAController,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                decoration: _inputDeco(theme, 'Nome do Time A'),
                validator: (v) => v!.trim().isEmpty ? 'Obrigatório' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _teamBController,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                decoration: _inputDeco(theme, 'Nome do Time B'),
                validator: (v) => v!.trim().isEmpty ? 'Obrigatório' : null,
              ),
              const SizedBox(height: 16),
            ],

            const Text(
              '🎯 Metas do desafio',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),

            if (_goals.isNotEmpty)
              Column(
                children: _goals.asMap().entries.map((e) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: theme.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: ListTile(
                      leading: Icon(Icons.flag, color: theme.accent),
                      title: Text(
                        e.value['label'],
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        '${e.value['metric']} • Meta: ${e.value['target']}',
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: () => setState(() => _goals.removeAt(e.key)),
                      ),
                    ),
                  );
                }).toList(),
              )
            else
              const Text(
                'Nenhuma meta adicionada ainda.',
                style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w700),
              ),

            const SizedBox(height: 10),

            OutlinedButton.icon(
              onPressed: _addGoalDialog,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar meta'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withOpacity(0.18)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),

            const SizedBox(height: 20),

            _loading
                ? Center(child: CircularProgressIndicator(color: theme.accent))
                : ElevatedButton.icon(
              onPressed: _saveChallenge,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text(
                'Salvar desafio',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: theme.accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(SeasonTheme theme, String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800),
    filled: true,
    fillColor: theme.card,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: theme.accent.withOpacity(0.75), width: 1.2),
    ),
  );

  Widget _typeChip(SeasonTheme theme, String label, String value) {
    final selected = _type == value;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: theme.accent,
      backgroundColor: theme.card,
      side: BorderSide(color: Colors.white.withOpacity(0.14)),
      labelStyle: TextStyle(
        color: selected ? Colors.black : Colors.white,
        fontWeight: FontWeight.w900,
      ),
      onSelected: (_) => setState(() => _type = value),
    );
  }
}
