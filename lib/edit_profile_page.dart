import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class EditProfilePage extends StatefulWidget {
  final String userId;
  const EditProfilePage({super.key, required this.userId});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
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
  String? _currentUsername; // para não bloquear o mesmo username
  DateTime? _lastUsernameChange;

  String? _cepResumo;

  static const _orange = Color(0xFFFF6D00);

  // ---------- PAÍS / CÓDIGO POSTAL ----------
  String _selectedCountry = 'BR';

  static const Map<String, String> _countryNames = {
    'BR': 'Brasil',
    'US': 'Estados Unidos',
    'PT': 'Portugal',
    'GB': 'Reino Unido',
    'CA': 'Canadá',
    'DE': 'Alemanha',
    'FR': 'França',
    'ES': 'Espanha',
  };

  bool get _isBrazil => _selectedCountry == 'BR';

  String get _postalLabel {
    switch (_selectedCountry) {
      case 'US':
        return 'ZIP Code (ex: 10001 ou 10001-0001)';
      case 'CA':
        return 'Postal Code (ex: K1A 0B1)';
      case 'GB':
        return 'Postcode (ex: SW1A 1AA)';
      case 'PT':
        return 'Código Postal (ex: 1000-001)';
      case 'DE':
        return 'PLZ (ex: 10115)';
      case 'FR':
        return 'Code Postal (ex: 75008)';
      case 'ES':
        return 'Código Postal (ex: 28013)';
      case 'BR':
      default:
        return 'CEP (ex: 22713-350)';
    }
  }

  RegExp get _postalRegex {
    switch (_selectedCountry) {
      case 'BR':
        return RegExp(r'^\d{5}-?\d{3}$'); // 12345-678
      case 'US':
        return RegExp(r'^\d{5}(-\d{4})?$'); // 12345 ou 12345-6789
      case 'CA':
        return RegExp(r'^[A-Za-z]\d[A-Za-z][ -]?\d[A-Za-z]\d$'); // K1A 0B1
      case 'GB':
        return RegExp(r'^(GIR 0AA|[A-Z]{1,2}\d[A-Z\d]?\s?\d[A-Z]{2})$',
            caseSensitive: false);
      case 'PT':
        return RegExp(r'^\d{4}-\d{3}$'); // 1234-567
      case 'DE':
      case 'FR':
      case 'ES':
        return RegExp(r'^\d{5}$'); // 5 dígitos
      default:
        return RegExp(r'^.{3,12}$'); // fallback simples
    }
  }

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _birthDateController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _weeklyGoalController.dispose();
    _cepController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingData() async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();

      final data = doc.data() ?? {};

      _currentUsername = (data['username'] as String?)?.trim();

      // país salvo (se não existir, mantém BR)
      final savedCountry = (data['country'] as String?)?.trim();
      if (savedCountry != null && savedCountry.isNotEmpty) {
        _selectedCountry = savedCountry;
      }

      if (data['usernameLastChange'] is Timestamp) {
        _lastUsernameChange = (data['usernameLastChange'] as Timestamp).toDate();
      }

      _displayNameController.text = (data['displayName'] ?? '').toString();
      _usernameController.text = _currentUsername ?? '';
      _birthDateController.text = (data['birthDate'] ?? '').toString();
      _weightController.text = (data['weight'] ?? '').toString();
      _heightController.text = (data['height'] ?? '').toString();
      _weeklyGoalController.text = (data['weeklyGoal'] ?? '').toString();
      _cepController.text = (data['cep'] ?? '').toString();
      _cityController.text = (data['city'] ?? '').toString();
      _stateController.text = (data['state'] ?? '').toString();
      _selectedGender = (data['gender'] ?? '') as String?;

      if (_cityController.text.isNotEmpty && _stateController.text.isNotEmpty) {
        _cepResumo = _isBrazil
            ? 'Local atual: ${_cityController.text} - ${_stateController.text}'
            : 'Local atual: ${_cityController.text} - ${_stateController.text}';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar perfil: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _usernameExists(String username) async {
    // Se o usuário não mudou o username, não precisa checar
    if (_currentUsername != null &&
        _currentUsername!.toLowerCase() == username.toLowerCase()) {
      return false;
    }

    final result = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: username.toLowerCase())
        .limit(1)
        .get();
    return result.docs.isNotEmpty;
  }

  Future<void> _buscarCep() async {
    if (!_isBrazil) return;

    final cep = _cepController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cep.length != 8) return;

    setState(() => _isSearchingCep = true);
    try {
      final response =
      await http.get(Uri.parse('https://viacep.com.br/ws/$cep/json/'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data.containsKey('erro') && data['erro'] == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('CEP não encontrado.')),
            );
          }
        } else {
          final cidade = data['localidade'] ?? '';
          final uf = data['uf'] ?? '';
          final rua = data['logradouro'] ?? '';

          setState(() {
            _cityController.text = cidade;
            _stateController.text = uf;
            _cepResumo = [
              if (rua.isNotEmpty) rua,
              if (cidade.isNotEmpty) cidade,
              if (uf.isNotEmpty) uf,
            ].join(' - ');
          });
        }
      }
    } catch (e) {
      debugPrint("Erro ao buscar CEP: $e");
    } finally {
      if (mounted) setState(() => _isSearchingCep = false);
    }
  }

  Future<void> _saveProfile() async {
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

    // Verifica se o usuário está REALMENTE mudando o @
    final bool isUsernameChanging = _currentUsername == null
        ? username.isNotEmpty
        : _currentUsername!.toLowerCase() != username.toLowerCase();

    if (isUsernameChanging && _lastUsernameChange != null) {
      final now = DateTime.now();
      final diff = now.difference(_lastUsernameChange!);

      if (diff.inDays < 30) {
        final diasRestantes = 30 - diff.inDays;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Você só poderá alterar o nome de usuário novamente em '
                    '$diasRestantes dia(s).',
              ),
            ),
          );
        }
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _usernameError = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'Usuário não autenticado.';

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .set({
        'displayName': _displayNameController.text.trim(),
        'username': username,
        'birthDate': _birthDateController.text.trim(),
        'gender': _selectedGender,
        'weight': double.tryParse(_weightController.text.trim()) ?? 0,
        'height': double.tryParse(_heightController.text.trim()) ?? 0,
        'weeklyGoal': double.tryParse(_weeklyGoalController.text.trim()) ?? 0,

        // localização
        'country': _selectedCountry,
        'cep': _cepController.text.trim(), // postal/zip/cep
        'city': _cityController.text.trim(),
        'state': _stateController.text.trim(),

        'updatedAt': FieldValue.serverTimestamp(),

        // Só atualiza a data caso o @ tenha sido realmente alterado
        if (isUsernameChanging)
          'usernameLastChange': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Atualiza também o displayName no Auth
      await user.updateDisplayName(_displayNameController.text.trim());
      await user.reload();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil atualizado com sucesso!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar perfil: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // AppBar custom
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.black87),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    "Editar perfil",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: _CardContainer(
                  padding: const EdgeInsets.all(20),
                  borderRadius: 22,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        _buildTextField(
                            _displayNameController, "Nome completo", false),
                        const SizedBox(height: 10),
                        _buildTextField(
                          _usernameController,
                          "Nome de usuário (sem @)",
                          true,
                          helper: "Esse é o @ que outros jogadores irão ver.",
                          errorText: _usernameError,
                        ),
                        const SizedBox(height: 10),
                        _buildDateField(),
                        const SizedBox(height: 10),
                        _buildDropdownGender(),
                        const SizedBox(height: 10),
                        _buildNumericField(_weightController, "Peso (kg)"),
                        const SizedBox(height: 10),
                        _buildNumericField(_heightController, "Altura (cm)"),
                        const SizedBox(height: 10),
                        _buildNumericField(
                            _weeklyGoalController, "Meta semanal (km)"),
                        const SizedBox(height: 10),

                        // Localização
                        _buildCountryDropdown(),
                        const SizedBox(height: 10),
                        _buildPostalField(),

                        if (_cepResumo != null) ...[
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _cepResumo!,
                              style: const TextStyle(
                                  color: Colors.black54, fontSize: 12),
                            ),
                          ),
                        ],

                        const SizedBox(height: 10),

                        // Cidade/Estado:
                        // BR: readOnly (preenchido pelo ViaCEP)
                        // Outros: editável e obrigatório (pode ajustar se quiser)
                        Row(
                          children: [
                            Expanded(
                              child: _isBrazil
                                  ? _buildReadOnlyField(
                                  _cityController, "Cidade")
                                  : _buildTextField(
                                  _cityController, "Cidade", true),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _isBrazil
                                  ? _buildReadOnlyField(
                                  _stateController, "Estado/UF")
                                  : _buildTextField(
                                  _stateController, "Estado/Região", true),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        _isLoading
                            ? const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(_orange),
                        )
                            : SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ButtonStyle(
                              backgroundColor:
                              MaterialStateProperty.all(_orange),
                              foregroundColor: MaterialStateProperty.all(
                                  Colors.white),
                              padding: MaterialStateProperty.all(
                                const EdgeInsets.symmetric(
                                    horizontal: 32, vertical: 14),
                              ),
                              shape: MaterialStateProperty.all(
                                RoundedRectangleBorder(
                                  borderRadius:
                                  BorderRadius.circular(14),
                                ),
                              ),
                            ),
                            onPressed: _saveProfile,
                            icon: const Icon(Icons.check_circle_outline,
                                color: Colors.white),
                            label: const Text(
                              'Salvar alterações',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Campos reutilizáveis ----------

  Widget _buildTextField(
      TextEditingController controller,
      String label,
      bool required, {
        String? helper,
        String? errorText,
      }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.black87),
      decoration: _decoration(label).copyWith(
        helperText: helper,
        helperStyle: const TextStyle(color: Colors.black54, fontSize: 12),
        errorText: errorText,
      ),
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty)) {
          return 'Campo obrigatório';
        }
        return null;
      },
    );
  }

  Widget _buildReadOnlyField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      style: const TextStyle(color: Colors.black54),
      decoration: _decoration(label),
    );
  }

  Widget _buildNumericField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.black87),
      decoration: _decoration(label),
    );
  }

  Widget _buildDateField() {
    return TextFormField(
      controller: _birthDateController,
      readOnly: true,
      style: const TextStyle(color: Colors.black87),
      decoration: _decoration("Data de nascimento").copyWith(
        suffixIcon: const Icon(Icons.calendar_today, color: Colors.black54),
      ),
      onTap: () async {
        final locale = _selectedCountry == 'US'
            ? const Locale('en', 'US')
            : const Locale('pt', 'BR');

        final date = await showDatePicker(
          context: context,
          locale: locale, // 👈 resolve calendário americano
          initialDate: DateTime(2000),
          firstDate: DateTime(1950),
          lastDate: DateTime.now(),
        );

        if (date != null) {
          final format = _selectedCountry == 'US'
              ? 'MM/dd/yyyy'
              : 'dd/MM/yyyy';

          _birthDateController.text =
              DateFormat(format).format(date);
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

  // ---------- País ----------
  Widget _buildCountryDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedCountry,
      dropdownColor: Colors.white,
      decoration: _decoration("País"),
      items: _countryNames.entries
          .map(
            (e) => DropdownMenuItem(
          value: e.key,
          child: Text(e.value),
        ),
      )
          .toList(),
      onChanged: (v) {
        if (v == null) return;
        setState(() {
          _selectedCountry = v;

          // reseta infos ao trocar o país
          _cepController.clear();
          _cepResumo = null;
          _cityController.clear();
          _stateController.clear();
        });
      },
      style: const TextStyle(color: Colors.black87),
    );
  }

  // ---------- Postal / Zip / CEP ----------
  Widget _buildPostalField() {
    final bool numericKeyboard = _isBrazil ||
        _selectedCountry == 'US' ||
        _selectedCountry == 'DE' ||
        _selectedCountry == 'FR' ||
        _selectedCountry == 'ES';

    return TextFormField(
      controller: _cepController,
      keyboardType: numericKeyboard ? TextInputType.number : TextInputType.text,
      textCapitalization: (_selectedCountry == 'CA' || _selectedCountry == 'GB')
          ? TextCapitalization.characters
          : TextCapitalization.none,
      maxLength: _isBrazil ? 9 : (_selectedCountry == 'US' ? 10 : 12),
      style: const TextStyle(color: Colors.black87),
      decoration: _decoration(_postalLabel).copyWith(
        counterText: "",
        suffixIcon: _isBrazil
            ? (_isSearchingCep
            ? const Padding(
          padding: EdgeInsets.all(10),
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(_orange),
            ),
          ),
        )
            : IconButton(
          icon: const Icon(Icons.search, color: Colors.black54),
          onPressed: _buscarCep,
        ))
            : null,
      ),
      validator: (value) {
        // Guideline 5.1.1(v) - CEP/Postal code agora é opcional
        if (value == null || value.trim().isEmpty) {
          return null;
        }

        final v = value.trim();

        // CA/GB: remove espaços pra validar melhor
        final normalized =
        (_selectedCountry == 'CA' || _selectedCountry == 'GB')
            ? v.replaceAll(' ', '')
            : v;

        if (!_postalRegex.hasMatch(normalized)) {
          return _isBrazil ? "CEP inválido" : "Código postal inválido";
        }
        return null;
      },
      onChanged: (value) {
        // NÃO-BR: formata leve
        if (!_isBrazil) {
          if (_selectedCountry == 'CA') {
            final raw =
            value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
            String formatted = raw;
            if (raw.length > 3) {
              formatted = "${raw.substring(0, 3)} ${raw.substring(3)}";
            }
            _cepController.value = TextEditingValue(
              text: formatted,
              selection: TextSelection.collapsed(offset: formatted.length),
            );
          } else if (_selectedCountry == 'GB') {
            final formatted = value.toUpperCase();
            _cepController.value = TextEditingValue(
              text: formatted,
              selection: TextSelection.collapsed(offset: formatted.length),
            );
          }
          return;
        }

        // BR: quando completar o formato "99999-999", chama ViaCEP
        if (value.length == 9) _buscarCep();
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
      borderSide: const BorderSide(color: _orange, width: 1.8),
      borderRadius: BorderRadius.circular(12),
    ),
  );
}

// Card “neutro” no padrão branco/preto/laranja
class _CardContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;

  const _CardContainer({
    required this.child,
    this.padding,
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
