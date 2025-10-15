// lib/complete_profile_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Importe o MainScaffold para o redirecionamento
import 'package:run_walk_app/widgets/main_scaffold.dart';

class CompleteProfilePage extends StatefulWidget {
  const CompleteProfilePage({super.key});

  @override
  State<CompleteProfilePage> createState() => _CompleteProfilePageState();
}

class _CompleteProfilePageState extends State<CompleteProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    // Pré-popula o nome se o Google/outro provedor já o fornecer
    if (user?.displayName != null && user!.displayName!.isNotEmpty) {
      _displayNameController.text = user.displayName!;
    }
  }

  Future<void> _completeProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() { _isLoading = true; });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Lógica de segurança
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro: Usuário não encontrado.')),
      );
      setState(() { _isLoading = false; });
      return;
    }

    try {
      // 1. Cria o documento do usuário na coleção 'users'
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email ?? '',
        'displayName': _displayNameController.text,
        // ====================================================================
        // AQUI ESTÁ A MÁGICA:
        // Pegamos a photoURL diretamente do objeto 'user' do FirebaseAuth.
        // Se o login foi com Google, ela estará aqui.
        // Se foi com email/senha e o usuário não tem foto, será null.
        'photoURL': user.photoURL,
        // ====================================================================
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2. Atualiza o displayName no próprio FirebaseAuth também
      // Isso garante consistência se você chamar user.displayName em outros lugares
      if (user.displayName != _displayNameController.text) {
        await user.updateDisplayName(_displayNameController.text);
      }

      // Atualiza os dados do usuário localmente para refletir as mudanças imediatamente
      await user.reload();

      if (mounted) {
        // Redireciona o usuário para a tela principal (MainScaffold)
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainScaffold()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar perfil: $e')),
      );
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pega a URL da foto do usuário atual para exibir no avatar
    final String? photoURL = FirebaseAuth.instance.currentUser?.photoURL;

    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Complete seu Cadastro'),
        backgroundColor: Colors.black,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView( // Adicionado para evitar overflow em telas pequenas
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // --- NOVO: Avatar para mostrar a foto do Google ---
                  if (photoURL != null)
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: NetworkImage(photoURL),
                      backgroundColor: Colors.grey[800],
                    )
                  else
                    CircleAvatar( // Um ícone padrão se não houver foto
                      radius: 50,
                      backgroundColor: Colors.grey[800],
                      child: Icon(Icons.person, size: 50, color: Colors.white70),
                    ),
                  const SizedBox(height: 20),
                  // -----------------------------------------------
                  const Text(
                    'Falta pouco! Escolha seu nome de usuário.',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _displayNameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome de Usuário',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                      errorBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.red)),
                      focusedErrorBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.redAccent)),
                    ),
                    style: const TextStyle(color: Colors.white),
                    validator: (value) {
                      if (value == null || value.trim().length < 3) {
                        return 'O nome deve ter pelo menos 3 caracteres.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 30),
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
        ),
      ),
    );
  }
}
