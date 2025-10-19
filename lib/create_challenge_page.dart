import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CreateChallengePage extends StatefulWidget {
  const CreateChallengePage({super.key});

  @override
  State<CreateChallengePage> createState() => _CreateChallengePageState();
}

class _CreateChallengePageState extends State<CreateChallengePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _distanceCtrl = TextEditingController();
  DateTime? _deadline;
  bool _loading = false;

  Future<void> _createChallenge() async {
    if (!_formKey.currentState!.validate() || _deadline == null) return;

    setState(() => _loading = true);

    final user = FirebaseAuth.instance.currentUser!;
    await FirebaseFirestore.instance.collection('posts').add({
      'type': 'challenge',
      'authorId': user.uid,
      'authorName': user.displayName ?? 'Jogador',
      'title': _titleCtrl.text,
      'distance': double.tryParse(_distanceCtrl.text),
      'deadline': _deadline,
      'participants': [],
      'timestamp': FieldValue.serverTimestamp(),
    });

    setState(() => _loading = false);
    if (mounted) Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🏁 Desafio criado com sucesso!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Criar Desafio'),
        backgroundColor: Colors.green,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Título do Desafio',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Digite um título' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _distanceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Distância (km)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Informe a distância' : null,
              ),
              const SizedBox(height: 16),
              ListTile(
                title: Text(
                  _deadline == null
                      ? 'Selecionar prazo'
                      : 'Prazo: ${_deadline!.day}/${_deadline!.month}/${_deadline!.year}',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _deadline = picked);
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loading ? null : _createChallenge,
                icon: const Icon(Icons.flag),
                label: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Criar Desafio'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Colors.green,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
