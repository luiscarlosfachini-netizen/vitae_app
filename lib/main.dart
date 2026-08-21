import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const VitaeApp());
}

class VitaeApp extends StatelessWidget {
  const VitaeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vitae',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101921),
        primaryColor: Colors.tealAccent,
        colorScheme: const ColorScheme.dark(
          primary: Colors.tealAccent,
          secondary: Colors.orangeAccent,
          surface: Color(0xFF1A2632),
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  String userName = "Luis Fachini";
  double weightCurrent = 103.0;
  double weightTarget = 84.0;
  double weightStart = 105.0;
  double heightCm = 180.0;
  double bodyFatPercent = 30.3;
  DateTime targetDate = DateTime(2026, 12, 31);
  DateTime startDate = DateTime(2026, 7, 12);

  List<Map<String, dynamic>> fastingHistory = [
    {'id': 1, 'date': '20/08/2026', 'duration': '16h 00m', 'target': '16h'},
    {'id': 2, 'date': '19/08/2026', 'duration': '18h 30m', 'target': '18h'},
  ];

  List<Map<String, dynamic>> weightHistory = [
    {'id': 1, 'date': '12/07/2026', 'weight': 105.0},
    {'id': 2, 'date': '20/08/2026', 'weight': 103.0},
  ];

  List<Map<String, dynamic>> runHistory = [
    {'id': 1, 'date': '20/08/2026', 'distance': '5.20 km', 'time': '28m 10s', 'pace': '5:25 /km', 'calories': '320 kcal'},
  ];

  bool isRunning = false;
  Timer? runTimer;
  int runSeconds = 0;
  double runDistanceKm = 0.0;
  double runTargetDistance = 5.0;
  Position? lastPosition;

  void toggleRun() async {
    if (isRunning) {
      runTimer?.cancel();
      double paceMinutes = runDistanceKm > 0 ? (runSeconds / 60) / runDistanceKm : 0.0;
      int pMin = paceMinutes.toInt();
      int pSec = ((paceMinutes - pMin) * 60).toInt();
      int calories = (runDistanceKm * 65).toInt();

      final now = DateTime.now();
      setState(() {
        runHistory.insert(0, {
          'id': DateTime.now().millisecondsSinceEpoch,
          'date': '${now.day}/${now.month}/${now.year}',
          'distance': '${runDistanceKm.toStringAsFixed(2)} km',
          'time': '${runSeconds ~/ 60}m ${runSeconds % 60}s',
          'pace': '$pMin:${pSec.toString().padLeft(2, '0')} /km',
          'calories': '$calories kcal',
        });
        isRunning = false;
        runSeconds = 0;
        runDistanceKm = 0.0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Corrida salva no histórico!')),
      );
    } else {
      if (!kIsWeb) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
      }

      setState(() {
        isRunning = true;
        runSeconds = 0;
        runDistanceKm = 0.0;
      });

      runTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
        setState(() => runSeconds++);

        if (!kIsWeb) {
          try {
            Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
            if (lastPosition != null) {
              double meters = Geolocator.distanceBetween(
                lastPosition!.latitude, lastPosition!.longitude,
                pos.latitude, pos.longitude,
              );
              if (meters > 2.0) {
                setState(() {
                  runDistanceKm += meters / 1000.0;
                });
              }
            }
            lastPosition = pos;
          } catch (_) {}
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      FastingTab(
        history: fastingHistory,
        onFinishFasting: (entry) {
          setState(() => fastingHistory.insert(0, entry));
        },
        onDeleteFasting: (id) {
          setState(() => fastingHistory.removeWhere((item) => item['id'] == id));
        },
      ),
      DiaryTab(
        userName: userName,
        weightCurrent: weightCurrent,
        weightTarget: weightTarget,
        weightStart: weightStart,
        targetDate: targetDate,
        startDate: startDate,
        heightCm: heightCm,
        bodyFatPercent: bodyFatPercent,
        weightHistory: weightHistory,
        onProfileUpdate: (name, cur, tar, height, fat, sDate, tDate) {
          setState(() {
            userName = name;
            weightCurrent = cur;
            weightTarget = tar;
            heightCm = height;
            bodyFatPercent = fat;
            startDate = sDate;
            targetDate = tDate;
            final now = DateTime.now();
            weightHistory.insert(0, {
              'id': DateTime.now().millisecondsSinceEpoch,
              'date': '${now.day}/${now.month}/${now.year}',
              'weight': cur
            });
          });
        },
        onDeleteWeight: (id) {
          setState(() => weightHistory.removeWhere((item) => item['id'] == id));
        },
        onAddWeight: (newWeight) {
          final now = DateTime.now();
          setState(() {
            weightCurrent = newWeight;
            weightHistory.insert(0, {
              'id': DateTime.now().millisecondsSinceEpoch,
              'date': '${now.day}/${now.month}/${now.year}',
              'weight': newWeight
            });
          });
        },
      ),
      RunTab(
        history: runHistory,
        isRunning: isRunning,
        seconds: runSeconds,
        distanceKm: runDistanceKm,
        targetDistance: runTargetDistance,
        onToggleRun: toggleRun,
        onUpdateTarget: (newTarget) => setState(() => runTargetDistance = newTarget),
        onDeleteRun: (id) {
          setState(() => runHistory.removeWhere((item) => item['id'] == id));
        },
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (idx) => setState(() => _currentIndex = idx),
        selectedItemColor: Colors.tealAccent,
        unselectedItemColor: Colors.grey,
        backgroundColor: const Color(0xFF0D141C),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.timer), label: 'Jejum'),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: 'Diário'),
          BottomNavigationBarItem(icon: Icon(Icons.directions_run), label: 'Corrida'),
        ],
      ),
    );
  }
}

class FastingTab extends StatefulWidget {
  final List<Map<String, dynamic>> history;
  final Function(Map<String, dynamic>) onFinishFasting;
  final Function(int) onDeleteFasting;

  const FastingTab({
    super.key,
    required this.history,
    required this.onFinishFasting,
    required this.onDeleteFasting,
  });

  @override
  State<FastingTab> createState() => _FastingTabState();
}

class _FastingTabState extends State<FastingTab> {
  bool _isFasting = false;
  int _targetHours = 16;
  Timer? _timer;
  int _elapsedSeconds = 0;

  final List<Map<String, String>> _allPhases = [
    {
      'range': '0h - 2h',
      'title': 'Digestão Ativa',
      'desc': 'O corpo digere os alimentos. A glicose no sangue e a insulina sobem para estocar energia.'
    },
    {
      'range': '2h - 8h',
      'title': 'Estabilização de Glicemia',
      'desc': 'Insulina começa a cair. O corpo passa a usar o glicogênio armazenado no fígado como combustível.'
    },
    {
      'range': '8h - 12h',
      'title': 'Transição & Queima de Gordura',
      'desc': 'O glicogênio está se esgotando. O metabolismo desacelera o consumo de açúcar e ativa a queima de gordura.'
    },
    {
      'range': '12h - 18h',
      'title': 'Cetose & Autofagia Inicial',
      'desc': 'Gordura vira corpos cetônicos para o cérebro. Inicia a reciclagem de células velhas e danificadas (autofagia).'
    },
    {
      'range': '18h+',
      'title': 'Autofagia Profunda & HGH',
      'desc': 'Limpeza celular maximizada, redução de inflamação e elevação do Hormônio do Crescimento (HGH).'
    },
  ];

  void _toggleFasting() {
    if (_isFasting) {
      _timer?.cancel();
      int hrs = _elapsedSeconds ~/ 3600;
      int mins = (_elapsedSeconds % 3600) ~/ 60;
      final now = DateTime.now();
      widget.onFinishFasting({
        'id': DateTime.now().millisecondsSinceEpoch,
        'date': '${now.day}/${now.month}/${now.year}',
        'duration': '${hrs}h ${mins}m',
        'target': '${_targetHours}h',
      });
      setState(() {
        _isFasting = false;
        _elapsedSeconds = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jejum encerrado e registrado!')),
      );
    } else {
      setState(() {
        _isFasting = true;
        _elapsedSeconds = 0;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _elapsedSeconds++);
      });
    }
  }

  int _getCurrentPhaseIndex(double hours) {
    if (hours < 2) return 0;
    if (hours < 8) return 1;
    if (hours < 12) return 2;
    if (hours < 18) return 3;
    return 4;
  }

  void _showHistoryModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2632),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Histórico de Jejuns", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                const SizedBox(height: 12),
                Expanded(
                  child: widget.history.isEmpty
                      ? const Center(child: Text("Nenhum jejum registrado."))
                      : ListView.builder(
                          itemCount: widget.history.length,
                          itemBuilder: (c, idx) {
                            final item = widget.history[idx];
                            return Card(
                              color: Colors.white10,
                              child: ListTile(
                                leading: const Icon(Icons.check_circle, color: Colors.tealAccent),
                                title: Text("Duração: ${item['duration']}"),
                                subtitle: Text("Data: ${item['date']} | Meta: ${item['target']}"),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                                  onPressed: () {
                                    widget.onDeleteFasting(item['id']);
                                    setModalState(() {});
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int totalTargetSecs = _targetHours * 3600;
    int remainingSecs = max(0, totalTargetSecs - _elapsedSeconds);
    double elapsedHours = _elapsedSeconds / 3600.0;
    int activePhaseIdx = _getCurrentPhaseIndex(elapsedHours);

    String formatTime(int secs) {
      int h = secs ~/ 3600;
      int m = (secs % 3600) ~/ 60;
      int s = secs % 60;
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jejum Intermitente'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(icon: const Icon(Icons.bar_chart, color: Colors.tealAccent), onPressed: _showHistoryModal),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButton<int>(
              value: _targetHours,
              dropdownColor: const Color(0xFF1A2632),
              style: const TextStyle(color: Colors.white, fontSize: 16),
              items: [12, 14, 16, 18, 20, 24].map((h) {
                return DropdownMenuItem(value: h, child: Text('Protocolo $h horas'));
              }).toList(),
              onChanged: _isFasting ? null : (val) => setState(() => _targetHours = val!),
            ),
            const SizedBox(height: 20),
            Center(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _isFasting ? Colors.tealAccent : Colors.grey, width: 8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_isFasting ? "Em progresso" : "Pronto", style: const TextStyle(fontSize: 16, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Text(formatTime(_elapsedSeconds), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                    if (_isFasting) ...[
                      const SizedBox(height: 10),
                      Text("Restante:", style: TextStyle(color: Colors.orangeAccent.shade100, fontSize: 12)),
                      Text(formatTime(remainingSecs), style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                    ]
                  ],
                ),
              ),
            ),
            const SizedBox(height: 25),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isFasting ? Colors.redAccent : Colors.tealAccent,
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: _toggleFasting,
              child: Text(
                _isFasting ? 'CONCLUIR JEJUM' : 'INICIAR JEJUM',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const SizedBox(height: 25),
            
            // Fases do Jejum (Carrossel Horizontal)
            Row(
              children: const [
                Icon(Icons.bolt, color: Colors.tealAccent),
                SizedBox(width: 8),
                Text("Estágios Metabólicos do Jejum", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _allPhases.length,
                itemBuilder: (ctx, idx) {
                  bool isCurrent = _isFasting && idx == activePhaseIdx;
                  final phase = _allPhases[idx];

                  return Container(
                    width: 260,
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isCurrent ? Colors.teal.withOpacity(0.2) : const Color(0xFF1A2632),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrent ? Colors.tealAccent : Colors.white10,
                        width: isCurrent ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(phase['range']!, style: TextStyle(color: isCurrent ? Colors.tealAccent : Colors.orangeAccent, fontWeight: FontWeight.bold)),
                            if (isCurrent)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.tealAccent, borderRadius: BorderRadius.circular(4)),
                                child: const Text("ATUAL", style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                              )
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(phase['title']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 6),
                        Text(
                          phase['desc']!,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DiaryTab extends StatelessWidget {
  final String userName;
  final double weightCurrent;
  final double weightTarget;
  final double weightStart;
  final DateTime targetDate;
  final DateTime startDate;
  final double heightCm;
  final double bodyFatPercent;
  final List<Map<String, dynamic>> weightHistory;
  final Function(String, double, double, double, double, DateTime, DateTime) onProfileUpdate;
  final Function(int) onDeleteWeight;
  final Function(double) onAddWeight;

  const DiaryTab({
    super.key,
    required this.userName,
    required this.weightCurrent,
    required this.weightTarget,
    required this.weightStart,
    required this.targetDate,
    required this.startDate,
    required this.heightCm,
    required this.bodyFatPercent,
    required this.weightHistory,
    required this.onProfileUpdate,
    required this.onDeleteWeight,
    required this.onAddWeight,
  });

  void _openProfileDialog(BuildContext context) {
    final nameController = TextEditingController(text: userName);
    final curController = TextEditingController(text: weightCurrent.toString());
    final tarController = TextEditingController(text: weightTarget.toString());
    final hController = TextEditingController(text: heightCm.toString());
    final fatController = TextEditingController(text: bodyFatPercent.toString());

    DateTime selectedStart = startDate;
    DateTime selectedTarget = targetDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A2632),
            title: const Text("Configurações do Perfil"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: "Nome")),
                  TextField(controller: curController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Peso Atual (kg)")),
                  TextField(controller: tarController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Peso Meta (kg)")),
                  TextField(controller: hController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Altura (cm)")),
                  TextField(controller: fatController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Gordura Corporal (%)")),
                  const SizedBox(height: 15),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Data de Início"),
                    subtitle: Text("${selectedStart.day}/${selectedStart.month}/${selectedStart.year}"),
                    trailing: const Icon(Icons.calendar_today, color: Colors.tealAccent),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedStart,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) setDialogState(() => selectedStart = picked);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Data de Objetivo"),
                    subtitle: Text("${selectedTarget.day}/${selectedTarget.month}/${selectedTarget.year}"),
                    trailing: const Icon(Icons.flag, color: Colors.tealAccent),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedTarget,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) setDialogState(() => selectedTarget = picked);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
              ElevatedButton(
                onPressed: () {
                  onProfileUpdate(
                    nameController.text,
                    double.tryParse(curController.text) ?? weightCurrent,
                    double.tryParse(tarController.text) ?? weightTarget,
                    double.tryParse(hController.text) ?? heightCm,
                    double.tryParse(fatController.text) ?? bodyFatPercent,
                    selectedStart,
                    selectedTarget,
                  );
                  Navigator.pop(ctx);
                },
                child: const Text("Salvar"),
              )
            ],
          );
        },
      ),
    );
  }

  void _openAddWeightDialog(BuildContext context) {
    final controller = TextEditingController(text: weightCurrent.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2632),
        title: const Text("Digite seu peso"),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: "Novo Peso (kg)"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () {
              double? val = double.tryParse(controller.text);
              if (val != null) {
                onAddWeight(val);
              }
              Navigator.pop(ctx);
            },
            child: const Text("Salvar"),
          )
        ],
      ),
    );
  }

  void _showReportDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2632),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Histórico de Pesagens", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                const SizedBox(height: 12),
                Expanded(
                  child: weightHistory.isEmpty
                      ? const Center(child: Text("Nenhuma pesagem registrada."))
                      : ListView.builder(
                          itemCount: weightHistory.length,
                          itemBuilder: (c, idx) {
                            final item = weightHistory[idx];
                            return Card(
                              color: Colors.white10,
                              child: ListTile(
                                leading: const Icon(Icons.monitor_weight, color: Colors.tealAccent),
                                title: Text("${item['weight']} kg"),
                                subtitle: Text("Data: ${item['date']}"),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                                  onPressed: () {
                                    onDeleteWeight(item['id']);
                                    setModalState(() {});
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double totalWeightToLose = weightStart - weightTarget;
    double weightLost = weightStart - weightCurrent;
    double remainingWeight = weightCurrent - weightTarget;
    double progressPercent = totalWeightToLose > 0 ? (weightLost / totalWeightToLose).clamp(0.0, 1.0) : 0.0;

    int totalDaysPlanned = targetDate.difference(startDate).inDays;
    int daysPassed = DateTime.now().difference(startDate).inDays;
    double plannedPercent = totalDaysPlanned > 0 ? (daysPassed / totalDaysPlanned).clamp(0.0, 1.0) : 0.0;

    double heightMeters = heightCm / 100;
    double imc = weightCurrent / (heightMeters * heightMeters);
    String imcStatus = "Normal";
    if (imc >= 30) imcStatus = "Obeso Classe I";
    else if (imc >= 25) imcStatus = "Sobrepeso";

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diário Vitae'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(icon: const Icon(Icons.bar_chart, color: Colors.tealAccent), onPressed: () => _showReportDialog(context)),
          IconButton(icon: const Icon(Icons.settings, color: Colors.tealAccent), onPressed: () => _openProfileDialog(context)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          children: [
            Text(userName, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    const Text("Começar", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text("${weightStart.toStringAsFixed(1)} kg", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text("IMC: ${(weightStart / (heightMeters * heightMeters)).toStringAsFixed(1)}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    Text("${startDate.day}/${startDate.month}/${startDate.year}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade700, width: 4),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Atual", style: TextStyle(color: Colors.yellow, fontSize: 12)),
                      Text("${weightCurrent.toStringAsFixed(1)} kg", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Column(
                  children: [
                    const Text("Objetivo", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text("${weightTarget.toStringAsFixed(1)} kg", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text("IMC: ${(weightTarget / (heightMeters * heightMeters)).toStringAsFixed(1)}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    Text("${targetDate.day}/${targetDate.month}/${targetDate.year}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 25),
            const Divider(color: Colors.white24),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  const SizedBox(width: 80, child: Text("Progresso", style: TextStyle(color: Colors.grey))),
                  Expanded(child: LinearProgressIndicator(value: progressPercent, color: Colors.white, backgroundColor: Colors.white12)),
                  const SizedBox(width: 10),
                  Text("${(progressPercent * 100).toStringAsFixed(1)}%"),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  const SizedBox(width: 80, child: Text("Planejado", style: TextStyle(color: Colors.grey))),
                  Expanded(child: LinearProgressIndicator(value: plannedPercent, color: Colors.white, backgroundColor: Colors.white12)),
                  const SizedBox(width: 10),
                  Text("${(plannedPercent * 100).toStringAsFixed(1)}%"),
                ],
              ),
            ),
            const Divider(color: Colors.white24),
            const SizedBox(height: 10),
            const Text("Estatísticas atuais", style: TextStyle(color: Colors.yellow, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn("Gordura corporal", "${bodyFatPercent.toStringAsFixed(1)} %"),
                _buildStatColumn("Você perdeu", "${weightLost.toStringAsFixed(1)} kg"),
                _buildStatColumn("Remanescente", "${remainingWeight.toStringAsFixed(1)} kg"),
              ],
            ),
            const SizedBox(height: 20),
            Text("IMC: ${imc.toStringAsFixed(1)}   $imcStatus", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.tealAccent)),
            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white24,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _openAddWeightDialog(context),
              child: const Text("Digite seu peso", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, String val) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(val, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class RunTab extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  final bool isRunning;
  final int seconds;
  final double distanceKm;
  final double targetDistance;
  final VoidCallback onToggleRun;
  final Function(double) onUpdateTarget;
  final Function(int) onDeleteRun;

  const RunTab({
    super.key,
    required this.history,
    required this.isRunning,
    required this.seconds,
    required this.distanceKm,
    required this.targetDistance,
    required this.onToggleRun,
    required this.onUpdateTarget,
    required this.onDeleteRun,
  });

  void _showSetGoalDialog(BuildContext context) {
    final controller = TextEditingController(text: targetDistance.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2632),
        title: const Text("Definir Meta de Corrida"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: "Distância (km)"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () {
              onUpdateTarget(double.tryParse(controller.text) ?? targetDistance);
              Navigator.pop(ctx);
            },
            child: const Text("Definir"),
          )
        ],
      ),
    );
  }

  void _showHistoryModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2632),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Histórico de Corridas", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                const SizedBox(height: 12),
                Expanded(
                  child: history.isEmpty
                      ? const Center(child: Text("Nenhuma corrida realizada."))
                      : ListView.builder(
                          itemCount: history.length,
                          itemBuilder: (c, idx) {
                            final item = history[idx];
                            return Card(
                              color: Colors.white10,
                              child: ListTile(
                                leading: const Icon(Icons.directions_run, color: Colors.tealAccent),
                                title: Text("${item['distance']} - ${item['time']}"),
                                subtitle: Text("Pace: ${item['pace']} | ${item['calories']} (${item['date']})"),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                                  onPressed: () {
                                    onDeleteRun(item['id']);
                                    setModalState(() {});
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double paceMinutes = distanceKm > 0 ? (seconds / 60) / distanceKm : 0.0;
    int pMin = paceMinutes.toInt();
    int pSec = ((paceMinutes - pMin) * 60).toInt();
    int calories = (distanceKm * 65).toInt();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Corrida & Caminhada'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(icon: const Icon(Icons.bar_chart, color: Colors.tealAccent), onPressed: () => _showHistoryModal(context)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ActionChip(
              avatar: const Icon(Icons.flag, color: Colors.tealAccent),
              label: Text("Meta: ${targetDistance.toStringAsFixed(1)} km"),
              onPressed: () => _showSetGoalDialog(context),
            ),
            const SizedBox(height: 30),
            Text(
              distanceKm.toStringAsFixed(2),
              style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold, color: Colors.tealAccent),
            ),
            const Text("QUILÔMETROS", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricColumn("Tempo", "${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}"),
                _buildMetricColumn("Pace Médio", "$pMin:${pSec.toString().padLeft(2, '0')} /km"),
                _buildMetricColumn("Calorias", "$calories kcal"),
              ],
            ),
            const Spacer(),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isRunning ? Colors.redAccent : Colors.tealAccent,
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: onToggleRun,
              child: Text(
                isRunning ? 'PARAR & SALVAR' : 'INICIAR ATIVIDADE',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricColumn(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
