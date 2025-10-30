import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  bool _loading = false;

  List<Map<String, dynamic>> _goals = []; // 🔹 metas

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Future<void> _selectDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: DateTime(now.year + 1),
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
    final labelController = TextEditingController();
    final targetController = TextEditingController();
    String metric = 'km';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Nova Meta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                decoration: const InputDecoration(labelText: 'Descrição da meta'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: metric,
                decoration: const InputDecoration(labelText: 'Métrica'),
                items: const [
                  DropdownMenuItem(value: 'km', child: Text('Distância (km)')),
                  DropdownMenuItem(value: 'xp', child: Text('Experiência (XP)')),
                  DropdownMenuItem(value: 'runs', child: Text('Corridas')),
                  DropdownMenuItem(value: 'steps', child: Text('Passos')),
                ],
                onChanged: (v) => metric = v!,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: targetController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Valor alvo'),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6D00)),
              child: const Text('Adicionar'),
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

      final uid = _auth.currentUser?.uid ?? 'anon';
      final now = DateTime.now();

      final data = {
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'type': _type,
        'createdBy': uid,
        'startDate': Timestamp.fromDate(_startDate!),
        'endDate': Timestamp.fromDate(_endDate!),
        'createdAt': Timestamp.fromDate(now),
        'participants': [],
        'goals': _goals,
        if (_type == 'grupo')
          'teams': {
            'timeA': {'name': _teamAController.text.trim(), 'members': []},
            'timeB': {'name': _teamBController.text.trim(), 'members': []},
          },
      };

      await _firestore.collection('challenges').add(data);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Desafio criado com sucesso 🎯')),
      );

      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
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
    final df = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Criar Desafio', style: TextStyle(color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            const Text(
              '📅 Informações do Desafio',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _titleController,
              decoration: _inputDeco('Título do desafio'),
              validator: (v) => v!.trim().isEmpty ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _descController,
              decoration: _inputDeco('Descrição'),
              maxLines: 3,
              validator: (v) => v!.trim().isEmpty ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 16),

            const Text('Tipo:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _typeChip('Geral', 'geral'),
                _typeChip('Grupo x Grupo', 'grupo'),
                //_typeChip('Oficial', 'oficial'),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _selectDate(isStart: true),
                    child: AbsorbPointer(
                      child: TextFormField(
                        decoration: _inputDeco('Data inicial'),
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
                        decoration: _inputDeco('Data final'),
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
              const Text('Times:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _teamAController,
                decoration: _inputDeco('Nome do Time A'),
                validator: (v) => v!.trim().isEmpty ? 'Obrigatório' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _teamBController,
                decoration: _inputDeco('Nome do Time B'),
                validator: (v) => v!.trim().isEmpty ? 'Obrigatório' : null,
              ),
              const SizedBox(height: 16),
            ],

            const Text('🎯 Metas do desafio',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            if (_goals.isNotEmpty)
              Column(
                children: _goals
                    .asMap()
                    .entries
                    .map((e) => ListTile(
                  leading: const Icon(Icons.flag, color: Color(0xFFFF6D00)),
                  title: Text(e.value['label']),
                  subtitle: Text(
                      '${e.value['metric']} • Meta: ${e.value['target']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () => setState(() => _goals.removeAt(e.key)),
                  ),
                ))
                    .toList(),
              )
            else
              const Text('Nenhuma meta adicionada ainda.',
                  style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 10),

            OutlinedButton.icon(
              onPressed: _addGoalDialog,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar meta'),
            ),
            const SizedBox(height: 20),

            _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.black))
                : ElevatedButton.icon(
              onPressed: _saveChallenge,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Salvar desafio'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6D00),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.grey[100],
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );

  Widget _typeChip(String label, String value) {
    final selected = _type == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: const Color(0xFFFF6D00),
      backgroundColor: Colors.grey[200],
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.black87,
        fontWeight: FontWeight.w600,
      ),
      onSelected: (_) => setState(() => _type = value),
    );
  }
}
