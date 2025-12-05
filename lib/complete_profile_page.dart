import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:run_walk_app/widgets/main_scaffold.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class CompleteProfilePage extends StatefulWidget {
  const CompleteProfilePage({super.key});

  @override
  State<CompleteProfilePage> createState() => _CompleteProfilePageState();
}

class _CompleteProfilePageState extends State<CompleteProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
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
  String? _usernameError;
  String? _cepResumo;

  bool _isFormattingCep = false;
  bool _isUploadingPhoto = false;
  String? _overridePhotoUrl;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user?.displayName != null && user!.displayName!.isNotEmpty) {
      _displayNameController.text = user.displayName!;
    }
  }

  Future<bool> _usernameExists(String username) async {
    final result = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: username.toLowerCase())
        .limit(1)
        .get();
    return result.docs.isNotEmpty;
  }

  Future<void> _buscarCep() async {
    final cepDigits = _cepController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cepDigits.length != 8) return;

    setState(() {
      _isSearchingCep = true;
      _cepResumo = null;
      _cityController.clear();
      _stateController.clear();
    });

    try {
      final response =
      await http.get(Uri.parse('https://viacep.com.br/ws/$cepDigits/json/'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data.containsKey('erro') && data['erro'] == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('CEP não encontrado.')),
            );
          }
          setState(() {
            _cepResumo = 'CEP não encontrado';
          });
        } else {
          final cidade = data['localidade'] ?? '';
          final uf = data['uf'] ?? '';
          final rua = data['logradouro'] ?? '';

          setState(() {
            _cityController.text = cidade;
            _stateController.text = uf;

            if (rua.isNotEmpty) {
              _cepResumo = 'Local encontrado: $rua, $cidade - $uf';
            } else {
              _cepResumo = 'Local encontrado: $cidade - $uf';
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Erro ao buscar CEP: $e");
      setState(() {
        _cepResumo = 'Erro ao buscar CEP. Tente novamente.';
      });
    } finally {
      setState(() => _isSearchingCep = false);
    }
  }

  Future<void> _completeProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final username = _usernameController.text.trim().toLowerCase();
    if (username.isEmpty) {
      setState(() => _usernameError = 'Escolha um nome de usuário');
      return;
    }
    if (await _usernameExists(username)) {
      setState(() => _usernameError = 'Este nome de usuário já está em uso');
      return;
    }

    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email ?? '',
        'displayName': _displayNameController.text.trim(),
        'username': username,
        'photoURL': user.photoURL,
        'birthDate': _birthDateController.text.trim(),
        'gender': _selectedGender,
        'weight': double.tryParse(_weightController.text.trim()) ?? 0,
        'height': double.tryParse(_heightController.text.trim()) ?? 0,
        'weeklyGoal': double.tryParse(_weeklyGoalController.text.trim()) ?? 0,
        'cep': _cepController.text.trim(),
        'city': _cityController.text.trim(),
        'state': _stateController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await user.updateDisplayName(_displayNameController.text.trim());
      await user.reload();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScaffold()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar perfil: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ---------- FOTO DE PERFIL ----------

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.black87),
                title: const Text(
                  "Tirar foto",
                  style: TextStyle(color: Colors.black87),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndEditPhoto(ImageSource.camera);
                },
              ),
              ListTile(
                leading:
                const Icon(Icons.photo_library, color: Colors.black87),
                title: const Text(
                  "Escolher da galeria",
                  style: TextStyle(color: Colors.black87),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndEditPhoto(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndEditPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 90,
      );

      if (picked == null) return;

      final file = File(picked.path);

      final confirmed = await _showPreviewDialog(file);
      if (!confirmed) return;

      await _uploadPhotoWithThumbnail(file);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao selecionar foto: $e')),
      );
    }
  }

  Future<bool> _showPreviewDialog(File imageFile) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          contentPadding: const EdgeInsets.all(16),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Pré-visualização',
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              CircleAvatar(
                radius: 60,
                backgroundImage: FileImage(imageFile),
              ),
              const SizedBox(height: 16),
              const Text(
                'Usar esta foto de perfil?',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6D00),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  Future<void> _uploadPhotoWithThumbnail(File imageFile) async {
    try {
      setState(() => _isUploadingPhoto = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw 'Usuário não autenticado';
      }

      final mainBytes = await FlutterImageCompress.compressWithFile(
        imageFile.path,
        quality: 80,
        minWidth: 600,
        minHeight: 600,
      );

      if (mainBytes == null) throw 'Falha ao comprimir imagem principal';

      final thumbBytes = await FlutterImageCompress.compressWithFile(
        imageFile.path,
        quality: 60,
        minWidth: 200,
        minHeight: 200,
      );

      if (thumbBytes == null) throw 'Falha ao comprimir thumbnail';

      final storage = FirebaseStorage.instance;

      final mainRef =
      storage.ref().child('users').child(user.uid).child('photo.jpg');
      final thumbRef =
      storage.ref().child('users').child(user.uid).child('photo_thumb.jpg');

      await mainRef.putData(mainBytes,
          SettableMetadata(contentType: 'image/jpeg'));
      final downloadURL = await mainRef.getDownloadURL();

      await thumbRef.putData(thumbBytes,
          SettableMetadata(contentType: 'image/jpeg'));

      await user.updatePhotoURL(downloadURL);
      await user.reload();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'photoURL': downloadURL,
        'photoThumbURL': await thumbRef.getDownloadURL(),
      }, SetOptions(merge: true));

      setState(() {
        _overridePhotoUrl = downloadURL;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto atualizada com sucesso!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar foto: $e')),
      );
    } finally {
      setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _removePhoto() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      setState(() => _isUploadingPhoto = true);

      final storage = FirebaseStorage.instance;
      final mainRef =
      storage.ref().child('users').child(user.uid).child('photo.jpg');
      final thumbRef =
      storage.ref().child('users').child(user.uid).child('photo_thumb.jpg');

      await mainRef.delete().catchError((_) {});
      await thumbRef.delete().catchError((_) {});

      await user.updatePhotoURL(null);
      await user.reload();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'photoURL': null,
        'photoThumbURL': null,
      }, SetOptions(merge: true));

      setState(() {
        _overridePhotoUrl = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto de perfil removida.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao remover foto: $e')),
      );
    } finally {
      setState(() => _isUploadingPhoto = false);
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF5F5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.black87),
          title: ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFFFF9800), Color(0xFFFF6D00)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds),
            child: const Text(
              "Complete seu Perfil",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: Colors.white, // fica branco por causa do ShaderMask
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20).copyWith(bottom: 24),
            child: Column(
              children: [
                const SizedBox(height: 4),
                const Text(
                  "Só mais alguns detalhes para deixar seu Império da Corrida com a sua cara.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                _GlassContainer(
                  padding: const EdgeInsets.all(20),
                  borderRadius: 22,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: _showPhotoOptions,
                                child: Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 55,
                                      backgroundColor: Colors.grey[300],
                                      backgroundImage: (() {
                                        final currentUser =
                                            FirebaseAuth.instance.currentUser;
                                        final String? photoURL =
                                            _overridePhotoUrl ??
                                                currentUser?.photoURL;
                                        if (photoURL != null &&
                                            photoURL.isNotEmpty) {
                                          return NetworkImage(photoURL);
                                        }
                                        return null;
                                      })(),
                                      child: (() {
                                        final currentUser =
                                            FirebaseAuth.instance.currentUser;
                                        final String? photoURL =
                                            _overridePhotoUrl ??
                                                currentUser?.photoURL;
                                        if (photoURL == null ||
                                            photoURL.isEmpty) {
                                          return const Icon(Icons.person,
                                              color: Colors.black45,
                                              size: 50);
                                        }
                                        return null;
                                      })(),
                                    ),
                                    if (_isUploadingPhoto)
                                      Positioned.fill(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color:
                                            Colors.black.withOpacity(0.3),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Center(
                                            child: SizedBox(
                                              height: 24,
                                              width: 24,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  TextButton.icon(
                                    onPressed: _isUploadingPhoto
                                        ? null
                                        : _showPhotoOptions,
                                    icon: const Icon(
                                      Icons.camera_alt_outlined,
                                      color: Colors.black54,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      "Alterar foto",
                                      style:
                                      TextStyle(color: Colors.black54),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    onPressed: _isUploadingPhoto
                                        ? null
                                        : _removePhoto,
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      "Remover",
                                      style: TextStyle(
                                          color: Colors.redAccent),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 22),
                        const _SectionTitle("Informações básicas"),

                        _buildTextField(
                          _displayNameController,
                          "Nome completo",
                          true,
                        ),
                        const SizedBox(height: 10),
                        _buildTextField(
                          _usernameController,
                          "Nome de usuário (sem @)",
                          true,
                          helper:
                          "Escolha um nome único — é como outros jogadores vão te encontrar e seguir.",
                          errorText: _usernameError,
                          onChanged: (value) {
                            if (_usernameError != null) {
                              setState(() => _usernameError = null);
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        _buildDateField(),
                        const SizedBox(height: 10),
                        _buildDropdownGender(),

                        const SizedBox(height: 22),
                        const _SectionTitle("Dados físicos"),

                        Row(
                          children: [
                            Expanded(
                              child: _buildNumericField(
                                _weightController,
                                "Peso (kg)",
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildNumericField(
                                _heightController,
                                "Altura (cm)",
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildNumericField(
                          _weeklyGoalController,
                          "Meta semanal (km)",
                          helperText:
                          "Quantos km você quer correr por semana?",
                        ),

                        const SizedBox(height: 22),
                        const _SectionTitle("Localização"),

                        _buildCepField(),
                        if (_cepResumo != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                _cepResumo!.startsWith('Local encontrado')
                                    ? Icons.location_on_outlined
                                    : Icons.info_outline,
                                size: 16,
                                color: _cepResumo!.startsWith('Local encontrado')
                                    ? Colors.green
                                    : Colors.orangeAccent,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _cepResumo!,
                                  style: TextStyle(
                                    color: _cepResumo!
                                        .startsWith('Local encontrado')
                                        ? Colors.green[800]
                                        : Colors.orange[800],
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),

                        _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: _primaryBtn,
                            onPressed: _completeProfile,
                            icon: const Icon(
                                Icons.check_circle_outline),
                            label:
                            const Text('Salvar e continuar'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController controller,
      String label,
      bool required, {
        String? helper,
        String? errorText,
        void Function(String)? onChanged,
      }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.black87),
      decoration: _decoration(label).copyWith(
        helperText: helper,
        helperStyle: const TextStyle(color: Colors.black54),
        errorText: errorText,
      ),
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty)) {
          return 'Campo obrigatório';
        }
        return null;
      },
      onChanged: onChanged,
    );
  }

  Widget _buildNumericField(
      TextEditingController controller,
      String label, {
        String? helperText,
      }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.black87),
      decoration: _decoration(label).copyWith(
        helperText: helperText,
        helperStyle: const TextStyle(color: Colors.black54),
      ),
    );
  }

  Widget _buildReadOnlyField(
      TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      style: const TextStyle(color: Colors.black54),
      decoration: _decoration(label),
    );
  }

  Widget _buildDateField() {
    return TextFormField(
      controller: _birthDateController,
      readOnly: true,
      style: const TextStyle(color: Colors.black87),
      decoration: _decoration("Data de nascimento").copyWith(
        suffixIcon:
        const Icon(Icons.calendar_today, color: Colors.black54),
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
      dropdownColor: Colors.white,
      decoration: _decoration("Gênero"),
      items: const [
        DropdownMenuItem(value: "Feminino", child: Text("Feminino")),
        DropdownMenuItem(value: "Masculino", child: Text("Masculino")),
        DropdownMenuItem(value: "Outro", child: Text("Outro")),
      ],
      onChanged: (v) => setState(() => _selectedGender = v),
      style: const TextStyle(color: Colors.black87),
    );
  }

  Widget _buildCepField() {
    return TextFormField(
      controller: _cepController,
      keyboardType: TextInputType.number,
      maxLength: 9,
      style: const TextStyle(color: Colors.black87),
      decoration: _decoration("CEP (ex: 22713-350)").copyWith(
        counterText: "",
        suffixIcon: _isSearchingCep
            ? const Padding(
          padding: EdgeInsets.all(10),
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        )
            : IconButton(
          icon: const Icon(Icons.search, color: Colors.black54),
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
        if (_isFormattingCep) return;

        final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.length > 8) return;

        String formatted = digits;
        if (digits.length > 5) {
          formatted = "${digits.substring(0, 5)}-${digits.substring(5)}";
        }

        _isFormattingCep = true;
        _cepController.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
        _isFormattingCep = false;

        if (digits.length == 8) {
          _buscarCep();
        } else {
          setState(() {
            _cepResumo = null;
            _cityController.clear();
            _stateController.clear();
          });
        }
      },
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.black54),
    filled: true,
    fillColor: Colors.white,
    enabledBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      borderRadius: BorderRadius.circular(12),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: Color(0xFFFF6D00), width: 1.5),
      borderRadius: BorderRadius.circular(12),
    ),
  );
}

// Botão laranja com fonte branca
final ButtonStyle _primaryBtn = ElevatedButton.styleFrom(
  backgroundColor: const Color(0xFFFF6D00),
  foregroundColor: Colors.white,
  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
);

class _GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final double blur;
  final double opacity;
  const _GlassContainer({
    required this.child,
    this.padding,
    this.borderRadius = 16,
    this.blur = 16,
    this.opacity = 0.06,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding ?? const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            border:
            Border.all(color: Colors.black.withOpacity(0.04)),
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 16,
                spreadRadius: 1,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
