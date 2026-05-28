import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import '../models/report_model.dart';
import '../widgets/multi_select_dialog.dart';
import '../services/school_service.dart';
import '../services/technician_service.dart';
import '../services/google_sheets_service.dart';
import '../utils/app_constants.dart';
import '../models/school_model.dart';
import '../models/technician_model.dart';
import '../models/employee_model.dart';
import '../services/employee_service.dart';
import '../widgets/app_ui.dart';

class UnifiedReportScreen extends StatefulWidget {
  final ReportModel? existingReport;
  final String loggedUser;

  const UnifiedReportScreen({super.key, this.existingReport, required this.loggedUser});

  @override
  State<UnifiedReportScreen> createState() => _UnifiedReportScreenState();
}

class _UnifiedReportScreenState extends State<UnifiedReportScreen> {
  final _formKey = GlobalKey<FormState>();

  DateTime? _selectedDate;
  String? _selectedSchool;
  String? _selectedSchoolAddress;
  String? _selectedSchoolCity;
  String? _selectedSchoolInep;
  String? _gre;
  String? _selectedResponsible;

  String? _filterRegional;
  String? _filterCity;

  List<String> _selectedSubjects = [];
  List<String> _selectedTechnicians = [];

  final _observationsController = TextEditingController();

  final List<PhotoItem> _selectedPhotos = [];
  final ImagePicker _picker = ImagePicker();

  late SignatureController _signatureController;

  final SchoolService _schoolService = SchoolService();
  final TechnicianService _technicianService = TechnicianService();

  final List<String> _mockSubjects = [
    'Análise Técnica',
    'Manutenção Corretiva',
    'Manutenção Preventiva',
    'Internet Offline',
    'Instalação de Softwares',
    'Cabeamento Estruturado',
    'Redefinição de Senha',
    'Filtro de Conteúdo / Firewall',
    'Backup de Dados'
  ];

  bool get _isTechnicalAnalysis => _selectedSubjects.contains('Análise Técnica');

  late final TextEditingController _schoolSearchController;
  late final FocusNode _schoolSearchFocusNode;

  bool _isLoadingTechnicians = false;
  String? _techniciansLoadError;
  List<TechnicianModel> _availableTechnicians = [];

  bool _isLoadingSchools = false;
  String? _schoolsLoadError;
  List<SchoolModel> _availableSchools = [];

  String _normalize(String? value) {
    if (value == null) return '';
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâãäå]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõöø]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll('ç', 'c')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _normalizeFilterText(String value) => _normalize(value);

  bool _sameFilterText(String? left, String? right) {
    return _normalize(left) == _normalize(right);
  }

  bool _containsFilterText(Iterable<String> values, String? selected) {
    final normalized = _normalize(selected);
    if (normalized.isEmpty) return false;
    return values.any((value) => _normalize(value) == normalized);
  }

  Future<void> _loadTechnicians() async {
    if (!mounted) return;
    setState(() {
      _isLoadingTechnicians = true;
      _techniciansLoadError = null;
    });

    try {
      await _technicianService.loadTechnicians();
      
      try {
        await _technicianService.syncTechniciansFromCloud();
      } catch (e) {
        debugPrint('Erro ao sincronizar técnicos da nuvem: $e');
      }

      if (!mounted) return;
      setState(() {
        _availableTechnicians = List<TechnicianModel>.from(_technicianService.technicians)
          ..sort((a, b) => _normalize(a.name).compareTo(_normalize(b.name)));
        _isLoadingTechnicians = false;
      });
    } catch (e, stack) {
      debugPrint('Erro ao carregar técnicos da aba Técnicos: $e');
      debugPrintStack(stackTrace: stack);

      if (!mounted) return;
      setState(() {
        _availableTechnicians = List<TechnicianModel>.from(_technicianService.technicians)
          ..sort((a, b) => _normalize(a.name).compareTo(_normalize(b.name)));
        _isLoadingTechnicians = false;
        _techniciansLoadError = e.toString();
      });
    }
  }

  Future<void> _loadSchools() async {
    if (!mounted) return;
    setState(() {
      _isLoadingSchools = true;
      _schoolsLoadError = null;
    });

    try {
      await _schoolService.loadSchoolsIfNeeded();

      if (!mounted) return;
      setState(() {
        _availableSchools = List<SchoolModel>.from(_schoolService.schools)
          ..sort((a, b) => _normalize(a.name).compareTo(_normalize(b.name)));
        _isLoadingSchools = false;
      });
    } catch (e, stack) {
      debugPrint('Erro ao carregar escolas: $e');
      debugPrintStack(stackTrace: stack);

      if (!mounted) return;
      setState(() {
        _availableSchools = List<SchoolModel>.from(_schoolService.schools)
          ..sort((a, b) => _normalize(a.name).compareTo(_normalize(b.name)));
        _isLoadingSchools = false;
        _schoolsLoadError = e.toString();
      });
    }
  }

  List<String> get _availableRegionals {
    final set = <String>{};
    for (final s in _availableSchools) {
      final gre = s.gre.trim();
      if (gre.isNotEmpty) set.add(gre);
    }

    if (set.isEmpty) {
      set.addAll(Constants.regionals.where((r) => r.trim().isNotEmpty));
    }

    final list = set.toList();
    list.sort((a, b) => _normalize(a).compareTo(_normalize(b)));
    return list;
  }

  List<SchoolModel> get _schoolsBySelectedRegional {
    final reg = _normalize(_filterRegional);
    if (reg.isEmpty) return _availableSchools;
    return _availableSchools.where((s) => _normalize(s.gre) == reg).toList();
  }

  List<String> get _availableCities {
    final set = <String>{};
    for (final s in _schoolsBySelectedRegional) {
      final city = s.city.trim();
      if (city.isNotEmpty) set.add(city);
    }

    if (set.isEmpty && _availableSchools.isEmpty) {
      set.addAll(Constants.paraibaMunicipalities.where((c) => c.trim().isNotEmpty));
    }

    final list = set.toList();
    list.sort((a, b) => _normalize(a).compareTo(_normalize(b)));
    return list;
  }

  List<SchoolModel> _getFilteredSchools(String query) {
    var result = List<SchoolModel>.from(_availableSchools);
    final reg = _normalizeFilterText(_filterRegional ?? '');
    final city = _normalizeFilterText(_filterCity ?? '');
    final q = _normalizeFilterText(query);

    if (reg.isNotEmpty) {
      result = result
          .where((s) => _normalizeFilterText(s.gre) == reg)
          .toList();
    }

    if (city.isNotEmpty) {
      result = result
          .where((s) => _normalizeFilterText(s.city) == city)
          .toList();
    }

    if (q.isNotEmpty) {
      result = result.where((s) {
        return _normalizeFilterText(s.name).contains(q) ||
            _normalizeFilterText(s.inep).contains(q);
      }).toList();
    }

    result.sort((a, b) {
      final greCompare = _normalize(a.gre).compareTo(_normalize(b.gre));
      if (greCompare != 0) return greCompare;

      final cityCompare = _normalize(a.city).compareTo(_normalize(b.city));
      if (cityCompare != 0) return cityCompare;

      return _normalize(a.name).compareTo(_normalize(b.name));
    });

    return result;
  }

  List<String> _regionalsForCity(String? city) {
    final normalizedCity = _normalizeFilterText(city ?? '');
    if (normalizedCity.isEmpty) return [];

    final citySchools = _availableSchools
        .where((s) => _normalizeFilterText(s.city) == normalizedCity)
        .toList();

    if (citySchools.any((s) => s.gre.trim().isEmpty)) return [];

    final regionals = citySchools
        .map((s) => s.gre.trim())
        .where((gre) => gre.isNotEmpty)
        .toSet()
        .toList();

    regionals.sort((a, b) => _normalize(a).compareTo(_normalize(b)));
    return regionals;
  }

  void _handleRegionalChanged(String? regional) {
    setState(() {
      _filterRegional = regional;

      if (_filterCity != null &&
          !_containsFilterText(_availableCities, _filterCity)) {
        _filterCity = null;
      }

      _clearSelectedSchool();
    });
  }

  void _handleCityChanged(String? city) {
    setState(() {
      _filterCity = city;

      if (_normalizeFilterText(_filterRegional ?? '').isEmpty) {
        final cityRegionals = _regionalsForCity(city);
        if (cityRegionals.length == 1) {
          _filterRegional = cityRegionals.first;
        }
      }

      _clearSelectedSchool();
    });
  }

  void _clearSelectedSchool({bool clearSchoolText = true}) {
    _selectedSchool = null;
    _selectedSchoolAddress = null;
    _selectedSchoolCity = null;
    _selectedSchoolInep = null;
    _gre = null;
    if (clearSchoolText) {
      _schoolSearchController.clear();
    }
  }


  @override
  void initState() {
    super.initState();
    _schoolSearchController = TextEditingController();
    _schoolSearchFocusNode = FocusNode();
    _signatureController = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );

    if (widget.existingReport != null) {
      final r = widget.existingReport!;
      _selectedDate = r.visitDate;
      _selectedSchool = r.schoolName;
      _selectedSchoolAddress = r.schoolAddress;
      _selectedSchoolCity = r.schoolCity;
      _selectedSubjects = List.from(r.subjects);
      _observationsController.text = r.observations ?? '';
      _gre = r.gre;
      _selectedPhotos.addAll(r.photos.map((p) => PhotoItem(path: p.path, comment: p.comment)));
      _selectedTechnicians = List.from(r.technicians);
      _selectedResponsible = r.responsiblePerson;
      
      _filterRegional = r.gre;
      _filterCity = r.schoolCity;
      _schoolSearchController.text = r.schoolName;

      // Carregar INEP do relatório existente
      _selectedSchoolInep = r.schoolInep;

      // Tentar inferir a cidade e INEP para relatórios antigos caso estejam vazios
      if ((_selectedSchoolCity == null || _selectedSchoolCity!.trim().isEmpty) && _selectedSchool != null) {
        try {
          final schoolNameLower = _selectedSchool!.trim().toLowerCase();
          final school = SchoolService().schools.firstWhere(
            (s) => s.name.trim().toLowerCase() == schoolNameLower,
          );
          if (school.city.trim().isNotEmpty) {
            _selectedSchoolCity = school.city.trim();
            _filterCity = _selectedSchoolCity;
          }
          if (_selectedSchoolInep == null || _selectedSchoolInep!.trim().isEmpty) {
            _selectedSchoolInep = school.inep.trim();
          }
        } catch (_) {}
      }

      // Fallback: buscar INEP pelo nome via GoogleSheetsService
      if (_selectedSchoolInep == null || _selectedSchoolInep!.trim().isEmpty) {
        _selectedSchoolInep = GoogleSheetsService.findInepBySchoolName(_selectedSchool);
      }
    }

    _loadSchools();
    _loadTechnicians();
  }

  void _presentDatePicker() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme,
          ),
          child: child!,
        );
      },
    );
    if (pickedDate != null) {
      setState(() => _selectedDate = pickedDate);
    }
  }

  void _openMultiSelect(String title, List<String> options, List<String> selected, Function(List<String>) onConfirm) async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => MultiSelectDialog(
        title: title,
        options: options,
        initialSelectedOptions: selected,
      ),
    );

    if (result != null) {
      setState(() => onConfirm(result));
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(source: source, imageQuality: 80);
      if (pickedFile != null) {
        setState(() => _selectedPhotos.add(PhotoItem(path: pickedFile.path, comment: '')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar foto: $e')));
    }
  }

  void _submitData() async {
    if (_formKey.currentState!.validate() && _selectedDate != null && _selectedSchool != null) {
      Uint8List? sigBytes;
      if (_signatureController.isNotEmpty) {
        sigBytes = await _signatureController.toPngBytes();
      } else if (widget.existingReport != null) {
        sigBytes = widget.existingReport!.signatureBytes;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A assinatura é obrigatória para novos relatórios.')),
        );
        return;
      }

      final report = ReportModel(
        id: widget.existingReport?.id ?? DateTime.now().toString(),
        isTechnicalAnalysis: _isTechnicalAnalysis,
        creator: widget.existingReport?.creator ?? widget.loggedUser,
        schoolName: _selectedSchool!,
        schoolAddress: _selectedSchoolAddress,
        schoolCity: _selectedSchoolCity,
        schoolInep: _selectedSchoolInep,
        visitDate: _selectedDate!,
        subjects: _selectedSubjects,
        observations: _observationsController.text,
        gre: _gre,
        photos: _selectedPhotos,
        technicians: _selectedTechnicians,
        responsiblePerson: !_isTechnicalAnalysis ? _selectedResponsible : null,
        signatureBytes: sigBytes,
        signatureUrl: widget.existingReport?.signatureUrl,
      );

      if (!mounted) return;
      Navigator.of(context).pop(report);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha todos os campos obrigatórios.')),
      );
    }
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final isEditing = widget.existingReport != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isEditing ? theme.colorScheme.tertiaryContainer : theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  isEditing ? 'Edição' : 'Novo',
                  style: TextStyle(
                    color: isEditing ? theme.colorScheme.onTertiaryContainer : theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isEditing ? 'Editar Relatório' : 'Novo Relatório',
            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Preencha as informações da visita técnica',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSection() {
    final theme = Theme.of(context);
    final hasError = _selectedDate == null && _formKey.currentState != null && !_formKey.currentState!.validate();

    return SectionCard(
      title: 'Data do Chamado',
      child: InkWell(
        onTap: _presentDatePicker,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Data do chamado',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: Icon(Icons.calendar_month_rounded, color: theme.colorScheme.primary),
            errorText: hasError ? 'Selecione a data da visita' : null,
          ),
          child: Text(
            _selectedDate == null ? 'Selecione a data...' : DateFormat('dd/MM/yyyy').format(_selectedDate!),
            style: TextStyle(
              fontSize: 16,
              color: _selectedDate == null ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRegionalFilterField() {
    return DropdownButtonFormField<String>(
      key: ValueKey('regional_$_filterRegional'),
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Filtrar por Regional',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        prefixIcon: const Icon(Icons.map_outlined),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      initialValue: _containsFilterText(_availableRegionals, _filterRegional)
          ? _filterRegional
          : null,
      items: [
        const DropdownMenuItem(
          value: null,
          child: Text('Todas as Regionais'),
        ),
        ..._availableRegionals.map(
          (regional) => DropdownMenuItem(
            value: regional,
            child: Text(regional, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: _handleRegionalChanged,
    );
  }

  Widget _buildCityFilterField() {
    return DropdownButtonFormField<String>(
      key: ValueKey('city_$_filterCity'),
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Filtrar por Município',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        prefixIcon: const Icon(Icons.location_city_outlined),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      initialValue:
          _containsFilterText(_availableCities, _filterCity) ? _filterCity : null,
      items: [
        const DropdownMenuItem(
          value: null,
          child: Text('Todos os Municípios'),
        ),
        ..._availableCities.map(
          (city) => DropdownMenuItem(
            value: city,
            child: Text(city, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: _handleCityChanged,
    );
  }

  Widget _buildSchoolCounterChip(IconData icon, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSchoolSection() {
    final theme = Theme.of(context);
    final isLargeScreen = MediaQuery.of(context).size.width > 600;
    final filteredSchoolCount =
        _getFilteredSchools(_schoolSearchController.text).length;

    return SectionCard(
      title: 'Escola',
      icon: Icons.school_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isLoadingSchools) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Carregando base de escolas...'),
                  ],
                ),
              ),
            ),
          ] else if (_availableSchools.isEmpty && _schoolsLoadError != null) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(Icons.error_outline, color: theme.colorScheme.error, size: 40),
                    const SizedBox(height: 12),
                    Text('Erro ao carregar escolas: $_schoolsLoadError', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _loadSchools,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar Novamente'),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isLargeScreen)
                    Row(
                      children: [
                        Expanded(child: _buildRegionalFilterField()),
                        const SizedBox(width: 12),
                        Expanded(child: _buildCityFilterField()),
                      ],
                    )
                  else ...[
                    _buildRegionalFilterField(),
                    const SizedBox(height: 12),
                    _buildCityFilterField(),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _buildSchoolCounterChip(
                        Icons.location_city_outlined,
                        '${_availableCities.length} município(s)',
                      ),
                      _buildSchoolCounterChip(
                        Icons.school_outlined,
                        '$filteredSchoolCount escola(s)',
                      ),
                      if (_filterRegional != null || _filterCity != null)
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _filterRegional = null;
                              _filterCity = null;
                              _clearSelectedSchool();
                            });
                          },
                          icon: const Icon(Icons.clear_all_rounded, size: 16),
                          label: const Text('Limpar Filtros'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            if (_filterRegional != null && _schoolsBySelectedRegional.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                child: Text(
                  'Nenhuma escola cadastrada para esta regional.',
                  style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              )
            else if (_filterRegional != null && _filterCity != null && _getFilteredSchools('').isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                child: Text(
                  'Nenhuma escola encontrada para este município.',
                  style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),

            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                return Autocomplete<SchoolModel>(
                  textEditingController: _schoolSearchController,
                  focusNode: _schoolSearchFocusNode,
                  displayStringForOption: (option) => option.name,
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    return _getFilteredSchools(textEditingValue.text);
                  },
                  onSelected: (SchoolModel selection) {
                    setState(() {
                      _selectedSchool = selection.name;
                      _gre = selection.gre;
                      _selectedSchoolAddress = selection.address;
                      _selectedSchoolCity = selection.city;
                      _selectedSchoolInep = selection.inep;
                      if (_filterRegional == null || _filterRegional!.isEmpty) {
                        _filterRegional =
                            _containsFilterText(_availableRegionals, selection.gre)
                                ? selection.gre
                                : null;
                      }
                      if (_filterCity == null || _filterCity!.isEmpty) {
                        _filterCity =
                            _containsFilterText(_availableCities, selection.city)
                                ? selection.city
                                : null;
                      }
                      _schoolSearchController.text = selection.name;
                    });
                  },
                  fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        labelText: 'Buscar Escola (Nome ou INEP)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: theme.colorScheme.surface,
                        prefixIcon: const Icon(Icons.school_outlined),
                        suffixIcon: const Icon(Icons.search_rounded),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      onEditingComplete: onEditingComplete,
                      validator: (value) => _selectedSchool == null ? 'Selecione uma escola da lista' : null,
                      onChanged: (v) {
                        setState(() {
                          if (_selectedSchool != null &&
                              !_sameFilterText(v, _selectedSchool)) {
                            _clearSelectedSchool(clearSchoolText: false);
                          }
                        });
                      },
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 8.0,
                        borderRadius: BorderRadius.circular(12),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: 250, maxWidth: constraints.maxWidth),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: options.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (BuildContext context, int index) {
                              final option = options.elementAt(index);
                              return ListTile(
                                title: Text(option.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('${option.inep} • ${option.city}\n${option.gre}'),
                                onTap: () => onSelected(option),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                );
              }
            ),
            if (_selectedSchool != null) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Escola Selecionada',
                              style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.map_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Regional: ${_gre ?? "N/A"}',
                              style: TextStyle(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.location_on_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_selectedSchoolAddress ?? "N/A"} - ${_selectedSchoolCity ?? "N/A"}',
                              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_isTechnicalAnalysis) ...[
              const SizedBox(height: 16),
              TextFormField(
                key: ValueKey('gre_$_gre'),
                initialValue: _gre,
                decoration: InputDecoration(
                  labelText: 'GRE (Gerência Regional de Educação)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.account_balance_outlined),
                ),
                onChanged: (v) => _gre = v,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSubjectsAndTechniciansSection() {
    final theme = Theme.of(context);

    return SectionCard(
      title: 'Motivos e Equipe',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _openMultiSelect('Motivo do Chamado', _mockSubjects, _selectedSubjects, (res) => _selectedSubjects = res),
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Motivos do Chamado',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: Icon(Icons.category_outlined, color: theme.colorScheme.primary),
                suffixIcon: Icon(Icons.add_circle_outline, color: theme.colorScheme.primary),
              ),
              child: _selectedSubjects.isEmpty
                  ? Text('Selecionar motivos', style: TextStyle(fontSize: 16, color: theme.colorScheme.onSurfaceVariant))
                  : Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _selectedSubjects.map((s) => Chip(
                        label: Text(s, style: const TextStyle(fontSize: 12)),
                        backgroundColor: theme.colorScheme.secondaryContainer,
                        side: BorderSide.none,
                      )).toList(),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () {
              if (_isLoadingTechnicians) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Carregando técnicos...')),
                );
                return;
              }

              if (_availableTechnicians.isEmpty && _techniciansLoadError != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Erro ao carregar técnicos da aba Técnicos: $_techniciansLoadError'),
                    action: SnackBarAction(
                      label: 'Tentar novamente',
                      onPressed: _loadTechnicians,
                    ),
                  ),
                );
                return;
              }

              if (_availableTechnicians.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Nenhum técnico encontrado na aba Técnicos.'),
                    action: SnackBarAction(
                      label: 'Recarregar',
                      onPressed: _loadTechnicians,
                    ),
                  ),
                );
                return;
              }

              final setOfNames = _availableTechnicians
                  .map((t) => t.name.trim())
                  .where((name) => name.isNotEmpty)
                  .toSet();

              // Preservar técnicos antigos selecionados mesmo se não estiverem na lista atual
              for (var existingName in _selectedTechnicians) {
                if (existingName.trim().isNotEmpty) {
                  setOfNames.add(existingName.trim());
                }
              }

              final technicianNames = setOfNames.toList()
                ..sort((a, b) => _normalize(a).compareTo(_normalize(b)));

              _openMultiSelect('Técnico(s)', technicianNames, _selectedTechnicians, (res) => _selectedTechnicians = res);
            },
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Técnicos',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: Icon(Icons.engineering_outlined, color: theme.colorScheme.primary),
                suffixIcon: _isLoadingTechnicians
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.add_circle_outline, color: theme.colorScheme.primary),
              ),
              child: _selectedTechnicians.isEmpty
                  ? Text('Selecionar técnicos', style: TextStyle(fontSize: 16, color: theme.colorScheme.onSurfaceVariant))
                  : Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _selectedTechnicians.map((t) => Chip(
                        avatar: Icon(Icons.person_rounded, size: 16, color: theme.colorScheme.onSecondaryContainer),
                        label: Text(t, style: const TextStyle(fontSize: 12)),
                        backgroundColor: theme.colorScheme.secondaryContainer,
                        side: BorderSide.none,
                      )).toList(),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsibleSection() {
    if (_isTechnicalAnalysis) return const SizedBox.shrink();

    return SectionCard(
      title: 'Responsável',
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Autocomplete<EmployeeModel>(
            displayStringForOption: (option) => option.name,
            optionsBuilder: (TextEditingValue textEditingValue) {
              final q = textEditingValue.text.trim();
              if (q.length < 2) return const Iterable<EmployeeModel>.empty();
              final service = EmployeeService();
              if (RegExp(r'^\d+$').hasMatch(q)) {
                final res = service.all.where((e) => e.matricula.startsWith(q)).take(15).toList();
                res.sort((a, b) {
                  if (a.matricula == q) return -1;
                  if (b.matricula == q) return 1;
                  return a.matricula.compareTo(b.matricula);
                });
                return res;
              }
              return service.searchByName(q).take(15);
            },
            onSelected: (EmployeeModel selection) {
              setState(() {
                _selectedResponsible = selection.name;
              });
            },
            fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
              if (_selectedResponsible != null && controller.text != _selectedResponsible && !focusNode.hasFocus) {
                controller.text = _selectedResponsible!;
              }
              return TextFormField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  labelText: 'Responsável pela escola (Matrícula ou Nome)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.person_search_outlined),
                  suffixIcon: const Icon(Icons.search_rounded),
                ),
                onEditingComplete: onEditingComplete,
                validator: (value) => _selectedResponsible == null ? 'Campo obrigatório' : null,
                onChanged: (v) {
                  if (_selectedResponsible != null && v != _selectedResponsible) {
                    setState(() => _selectedResponsible = null);
                  }
                },
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 8.0,
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: 250, maxWidth: constraints.maxWidth),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: options.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        final option = options.elementAt(index);
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.badge_outlined)),
                          title: Text(option.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text('Matrícula: ${option.matricula}', style: const TextStyle(fontSize: 12)),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          );
        }
      ),
    );
  }

  Widget _buildObservationsSection() {
    return SectionCard(
      title: 'Diagnóstico / Observações',
      child: TextFormField(
        controller: _observationsController,
        maxLines: 5,
        minLines: 5,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: 'Descreva os detalhes da visita',
          hintText: 'Ex: Foi realizada a manutenção...',
          alignLabelWithHint: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(bottom: 80), // Alinha o ícone no topo
            child: Icon(Icons.notes_outlined),
          ),
        ),
        validator: (value) => (value == null || value.trim().isEmpty) ? 'Campo obrigatório' : null,
      ),
    );
  }

  Widget _buildPhotosSection() {
    final theme = Theme.of(context);
    final isLargeScreen = MediaQuery.of(context).size.width > 600;
    final bool canUseCamera = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    return SectionCard(
      title: 'Anexos Fotográficos',
      child: Column(
        children: [
          if (isLargeScreen)
            Row(
              children: [
                if (canUseCamera) ...[
                  Expanded(child: _buildPhotoButton(Icons.camera_alt_outlined, 'Câmera', ImageSource.camera)),
                  const SizedBox(width: 16),
                ],
                Expanded(child: _buildPhotoButton(Icons.photo_library_outlined, 'Galeria', ImageSource.gallery)),
              ],
            )
          else ...[
            if (canUseCamera) ...[
              _buildPhotoButton(Icons.camera_alt_outlined, 'Câmera', ImageSource.camera),
              const SizedBox(height: 12),
            ],
            _buildPhotoButton(Icons.photo_library_outlined, 'Galeria', ImageSource.gallery),
          ],
          if (_selectedPhotos.isNotEmpty) ...[
            const SizedBox(height: 24),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _selectedPhotos.length,
              itemBuilder: (ctx, idx) {
                final photo = _selectedPhotos[idx];
                return Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: isLargeScreen 
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPhotoPreview(photo, idx, theme),
                          const SizedBox(width: 16),
                          Expanded(child: _buildPhotoComment(photo, theme)),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildPhotoPreview(photo, idx, theme),
                          const SizedBox(height: 12),
                          _buildPhotoComment(photo, theme),
                        ],
                    ),
                  ),
                );
              },
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildPhotoButton(IconData icon, String label, ImageSource source) {
    return OutlinedButton.icon(
      onPressed: () => _pickImage(source),
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minimumSize: const Size(double.infinity, 50),
      ),
    );
  }

  Widget _buildPhotoPreview(PhotoItem photo, int idx, ThemeData theme) {
    final path = photo.path.trim();
    final bool isNetwork = path.startsWith('http://') || path.startsWith('https://');
    final bool isBase64 = path.startsWith('data:image') ||
        (RegExp(r'^[a-zA-Z0-9+/=]+$').hasMatch(path) && path.length > 100);

    Widget imageWidget;
    final placeholder = Container(
      width: 100,
      height: 100,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(Icons.broken_image_outlined, color: theme.colorScheme.onSurfaceVariant),
    );

    if (isBase64) {
      try {
        final clean = path.contains(',') ? path.split(',').last : path;
        imageWidget = Image.memory(base64Decode(clean), width: 100, height: 100, fit: BoxFit.cover);
      } catch (_) {
        imageWidget = placeholder;
      }
    } else if (isNetwork || kIsWeb) {
      imageWidget = Image.network(
        path,
        width: 100,
        height: 100,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => placeholder,
      );
    } else {
      imageWidget = Image.file(
        File(path),
        width: 100,
        height: 100,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => placeholder,
      );
    }
      
    return Stack(
      alignment: Alignment.topRight,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: imageWidget,
        ),
        GestureDetector(
          onTap: () => setState(() => _selectedPhotos.removeAt(idx)),
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: theme.colorScheme.error, shape: BoxShape.circle),
            child: Icon(Icons.close_rounded, size: 16, color: theme.colorScheme.onError),
          ),
        )
      ],
    );
  }

  Widget _buildPhotoComment(PhotoItem photo, ThemeData theme) {
    return TextFormField(
      initialValue: photo.comment,
      maxLines: 3,
      minLines: 3,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: 'Comentário da Foto',
        alignLabelWithHint: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: theme.colorScheme.surface,
      ),
      onChanged: (v) => photo.comment = v,
    );
  }

  Widget _buildSignatureSection() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SectionCard(
      title: _isTechnicalAnalysis ? 'Assinatura do Técnico' : 'Assinatura do Responsável',
      child: Column(
        children: [
          if (widget.existingReport != null && widget.existingReport!.signatureBytes != null && _signatureController.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.tertiary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: theme.colorScheme.tertiary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Assinatura salva anteriormente. Desenhe abaixo apenas se quiser alterar a assinatura atual.',
                      style: TextStyle(color: theme.colorScheme.tertiary, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Container(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.draw_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Text('Área de Assinatura', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: () => _signatureController.clear(),
                        icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                        label: const Text('Limpar'),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: Size.zero,
                        ),
                      ),
                    ],
                  ),
                ),
                Signature(
                  controller: _signatureController,
                  height: 180,
                  backgroundColor: isDark ? const Color(0xFFE0E0E0) : theme.colorScheme.surface,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: PrimaryActionButton(
        label: widget.existingReport != null ? 'Atualizar Relatório' : 'Salvar Relatório',
        icon: Icons.save_rounded,
        onPressed: _submitData,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Formulário de Relatório'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  _buildDateSection(),
                  _buildSchoolSection(),
                  _buildSubjectsAndTechniciansSection(),
                  _buildResponsibleSection(),
                  _buildObservationsSection(),
                  _buildPhotosSection(),
                  _buildSignatureSection(),
                  _buildSubmitButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _schoolSearchController.dispose();
    _schoolSearchFocusNode.dispose();
    _observationsController.dispose();
    _signatureController.dispose();
    super.dispose();
  }
}
