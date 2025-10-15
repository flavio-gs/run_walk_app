import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:run_walk_app/widgets/main_scaffold.dart';

class CompleteProfilePage extends StatefulWidget {
  const CompleteProfilePage({super.key});

  @override
  State<CompleteProfilePage> createState() => _CompleteProfilePageState();
}

class _CompleteProfilePageState extends State<CompleteProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _weeklyGoalController = TextEditingController();
  final _cepController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  String? _selectedGender;
  bool _isLoading = false;
  bool _isSearchingCep = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    // Pré-preenche o nome e foto, se o login for via Google
    if (user?.displayName != null && user!.displayName!.isNotEmpty) {
      _displayNameController.text = user.displayName!;
    }
  }

  // 🔎 Busca cidade e estado via ViaCEP
  Future<void> _buscarCep() async {
    final cep = _cepController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cep.length != 8) return;

    setState(() => _isSearchingCep = true);
    try {
      final response = await http.get(Uri.parse('https://viacep.com.br/ws/$cep/json/'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data.containsKey('erro') && data['erro'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('CEP não encontrado.')),
          );
        } else {
          setState(() {
            _cityController.text = data['localidade'] ?? '';
            _stateController.text = data['uf'] ?? '';
          });
        }
      }
    } catch (e) {
      debugPrint("Erro ao buscar CEP: $e");
    } finally {
      setState(() => _isSearchingCep = false);
    }
  }

  // 💾 Salva o perfil completo no Firestore
  Future<void> _completeProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email ?? '',
        'displayName': _displayNameController.text.trim(),
        'photoURL': user.photoURL, // ✅ pega direto do Google se existir
        'birthDate': _birthDateController.text.trim(),
        'gender': _selectedGender,
        'weight': double.tryParse(_weightController.text.trim()) ?? 0,
        'height': double.tryParse(_heightController.text.trim()) ?? 0,
        'weeklyGoal': double.tryParse(_weeklyGoalController.text.trim()) ?? 0,
        'cep': _cepController.text.trim(),
        'city': _cityController.text.trim(),
        'state': _stateController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      await user.updateDisplayName(_displayNameController.text.trim());
      await user.reload();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScaffold()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar perfil: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final String? photoURL = user?.photoURL;

    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Complete seu Perfil'),
        backgroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // 📸 Exibe foto do Google (ou ícone padrão)
              CircleAvatar(
                radius: 55,
                backgroundColor: Colors.grey[800],
                backgroundImage:
                (photoURL != null && photoURL.isNotEmpty) ? NetworkImage(photoURL) : null,
                child: (photoURL == null || photoURL.isEmpty)
                    ? const Icon(Icons.person, color: Colors.white70, size: 50)
                    : null,
              ),
              const SizedBox(height: 20),

              _buildTextField(_displayNameController, "Nome completo", true),
              const SizedBox(height: 10),
              _buildDateField(),
              const SizedBox(height: 10),
              _buildDropdownGender(),
              const SizedBox(height: 10),
              _buildNumericField(_weightController, "Peso (kg)"),
              const SizedBox(height: 10),
              _buildNumericField(_heightController, "Altura (cm)"),
              const SizedBox(height: 10),
              _buildNumericField(_weeklyGoalController, "Meta semanal (km)"),
              const SizedBox(height: 10),
              _buildCepField(),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _buildReadOnlyField(_cityController, "Cidade")),
                  const SizedBox(width: 10),
                  Expanded(child: _buildReadOnlyField(_stateController, "Estado")),
                ],
              ),
              const SizedBox(height: 25),

              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                ),
                onPressed: _completeProfile,
                child: const Text('Salvar e Continuar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🧱 Campos reutilizáveis
  Widget _buildTextField(TextEditingController controller, String label, bool required) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: _decoration(label),
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty)) {
          return 'Campo obrigatório';
        }
        return null;
      },
    );
  }

  Widget _buildNumericField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      decoration: _decoration(label),
    );
  }

  Widget _buildCepField() {
    return TextFormField(
      controller: _cepController,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      maxLength: 9,
      decoration: _decoration("CEP (ex: 22713-350)").copyWith(
        counterText: "",
        suffixIcon: _isSearchingCep
            ? const Padding(
            padding: EdgeInsets.all(10),
            child: SizedBox(
                height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)))
            : IconButton(
          icon: const Icon(Icons.search, color: Colors.white70),
          onPressed: _buscarCep,
        ),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return "Informe o CEP";
        final cepRegex = RegExp(r'^\d{5}-?\d{3}$');
        if (!cepRegex.hasMatch(value)) return "CEP inválido";
        return null;
      },
      onChanged: (value) {
        if (value.length == 9) _buscarCep();
      },
    );
  }

  Widget _buildReadOnlyField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      style: const TextStyle(color: Colors.white70),
      decoration: _decoration(label),
    );
  }

  Widget _buildDateField() {
    return TextFormField(
      controller: _birthDateController,
      readOnly: true,
      style: const TextStyle(color: Colors.white),
      decoration: _decoration("Data de nascimento").copyWith(
        suffixIcon: const Icon(Icons.calendar_today, color: Colors.white70),
      ),
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: DateTime(2000),
          firstDate: DateTime(1950),
          lastDate: DateTime.now(),
        );
        if (date != null) {
          _birthDateController.text =
          "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
        }
      },
    );
  }

  Widget _buildDropdownGender() {
    return DropdownButtonFormField<String>(
      value: _selectedGender,
      dropdownColor: Colors.grey[850],
      decoration: _decoration("Gênero"),
      items: const [
        DropdownMenuItem(value: "Feminino", child: Text("Feminino")),
        DropdownMenuItem(value: "Masculino", child: Text("Masculino")),
        DropdownMenuItem(value: "Outro", child: Text("Outro")),
      ],
      onChanged: (value) => setState(() => _selectedGender = value),
      style: const TextStyle(color: Colors.white),
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white54)),
      focusedBorder:
      const OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
    );
  }
}
