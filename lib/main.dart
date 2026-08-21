import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }
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

  List<Map<String, dynamic>> fastingHistory = [];
  List<Map<String, dynamic>> weightHistory = [
    {'id': 1, 'date': '21/08/2026', 'weight': 103.0},
    {'id': 2, 'date': '12/07/2026', 'weight': 105.0},
  ];
  List<Map<String, dynamic>> runHistory = [];

  bool isRunning = false;
  Timer? runTimer;
  int runSeconds = 0;
  double runDistanceKm = 0.0;
  double runTargetDistance = 5.0;
  Position? lastPosition;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    if (!kIsWeb) {
      await [
        Permission.location,
        Permission.notification,
      ].request();
    }
  }

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
  DateTime? _fastingStartTime;

  final List<Map<String, String>> _allPhases = [
    {'range': '0h - 2h', 'title': 'Digestão Ativa', 'desc': 'O corpo digere os alimentos. A glicose e a insulina sobem.'},
    {'range': '2h - 8h', 'title': 'Estabilização de Glicemia', 'desc': 'Insulina cai. O corpo usa o glicogênio armazenado.'},
    {'range': '8h - 12h', 'title': 'Transição & Queima de Gordura', 'desc': 'Glicogênio esgotando. Ativação da queima de gordura.'},
    {'range': '12h - 18h', 'title': 'Cetose & Autofagia Inicial', 'desc': 'Gordura vira cetonas. Início da renovação celular.'},
    {'range': '18h+', 'title': 'Autofagia Profunda & HGH', 'desc': 'Limpeza celular maximizada e elevação do HGH.'},
  ];

  @override
  void initState() {
    super.initState();
    _loadFastingState();
  }

  Future<void> _loadFastingState() async {
    final prefs = await SharedPreferences.getInstance();
    final startTimeStr = prefs.getString('fasting_start_time');
    final target = prefs.getInt('fasting_target') ?? 16;

    if (startTimeStr != null) {
      final startTime = DateTime.parse(startTimeStr);
      final diff = DateTime.now().difference(startTime).inSeconds;

      setState(() {
        _isFasting = true;
        _fastingStartTime = startTime;
        _targetHours = target;
        _elapsedSeconds = diff;
      });

      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_fastingStartTime != null) {
        setState(() {
          _elapsedSeconds = DateTime.now().difference(_fastingStartTime!).inSeconds;
        });
        _showNotification();
      }
    });
  }

  Future<void> _showNotification() async {
    if (kIsWeb) return;
    int h = _elapsedSeconds ~/ 3600;
    int m = (_elapsedSeconds % 3600) ~/ 60;

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'fasting_channel',
      'Jejum em Andamento',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
    );

    const NotificationDetails details = NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      888,
      'Vitae - Jejum em Andamento',
      'Tempo decorrido: ${h}h ${m}m (Meta: ${_targetHours}h)',
      details,
    );
  }

  Future<void> _toggleFasting() async {
    final prefs = await SharedPreferences.getInstance();

    if (_isFasting) {
      _timer?.cancel();
      if (!kIsWeb) await flutterLocalNotificationsPlugin.cancel(888);

      int hrs = _elapsedSeconds ~/ 3600;
      int mins = (_elapsedSeconds % 3600) ~/ 60;
      final now = DateTime.now();

      widget.onFinishFasting({
        'id': DateTime.now().millisecondsSinceEpoch,
        'date': '${now.day}/${now.month}/${now.year}',
        'duration': '${hrs}h ${mins}m',
        'target': '${_targetHours}h',
      });

      await prefs.remove('fasting_start_time');
      await prefs.remove('fasting_target');

      setState(() {
        _isFasting = false;
        _elapsedSeconds = 0;
        _fastingStartTime = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jejum encerrado e registrado!')),
      );
    } else {
      final now = DateTime.now();
      await prefs.setString('fasting_start_time', now.toIso8601String());
      await prefs.setInt('fasting_target', _targetHours);

      setState(() {
        _isFasting = true;
        _fastingStartTime = now;
        _elapsedSeconds = 0;
      });

      _startTimer();
    }
  }

  int _getCurrentPhaseIndex(double hours) {
    if (hours < 2) return 0;
    if (hours < 8) return 1;
    if (hours < 12) return 2;
    if (hours < 18) return 3;
    return 4;
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
            const SizedBox(height: 25),
            Row(
              children: const [
                Icon(Icons.history, color: Colors.tealAccent),
                SizedBox(width: 8),
                Text("Histórico de Jejuns", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 10),
            widget.history.isEmpty
                ? const Text("Nenhum jejum registrado ainda.", style: TextStyle(color: Colors.grey))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: widget.history.length,
                    itemBuilder: (ctx, idx) {
                      final item = widget.history[idx];
                      return Card(
                        color: const Color(0xFF1A2632),
                        child: ListTile(
                          title: Text("Duração: ${item['duration']}"),
                          subtitle: Text("Data: ${item['date']} | Meta: ${item['target']}"),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () => widget.onDeleteFasting(item['id']),
                          ),
                        ),
                      );
                    },
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

  void _showEditProfileDialog(BuildContext context) {
    final nameCtrl = TextEditingController(text: userName);
    final curCtrl = TextEditingController(text: weightCurrent.toString());
    final tarCtrl = TextEditingController(text: weightTarget.toString());
    final heightCtrl = TextEditingController(text: heightCm.toString());
    final fatCtrl = TextEditingController(text: bodyFatPercent.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2632),
        title: const Text("Editar Perfil & Metas"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Nome")),
              TextField(controller: curCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Peso Atual (kg)")),
              TextField(controller: tarCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Meta de Peso (kg)")),
              TextField(controller: heightCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Altura (cm)")),
              TextField(controller: fatCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "% Gordura Corporal")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () {
              onProfileUpdate(
                nameCtrl.text,
                double.tryParse(curCtrl.text) ?? weightCurrent,
                double.tryParse(tarCtrl.text) ?? weightTarget,
                double.tryParse(heightCtrl.text) ?? heightCm,
                double.tryParse(fatCtrl.text) ?? bodyFatPercent,
                startDate,
                targetDate,
              );
              Navigator.pop(ctx);
            },
            child: const Text("Salvar"),
          ),
        ],
      ),
    );
  }

  void _showAddWeightDialog(BuildContext context) {
    final wCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2632),
        title: const Text("Registrar Novo Peso"),
        content: TextField(
          controller: wCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: "Novo Peso (kg)"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () {
              double? val = double.tryParse(wCtrl.text);
              if (val != null) onAddWeight(val);
              Navigator.pop(ctx);
            },
            child: const Text("Salvar"),
          ),
        ],
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

    String getImcClassification(double val) {
      if (val < 18.5) return "Abaixo do peso";
      if (val < 24.9) return "Peso normal";
      if (val < 29.9) return "Sobrepeso";
      if (val < 34.9) return "Obesidade Grau I";
      if (val < 39.9) return "Obesidade Grau II";
      return "Obesidade Grau III";
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diário Vitae'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.tealAccent),
            onPressed: () => _showEditProfileDialog(context),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(userName, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(children: [const Text("Começar", style: TextStyle(color: Colors.grey)), Text("${weightStart} kg", style: const TextStyle(fontWeight: FontWeight.bold))]),
                Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.tealAccent, width: 4)),
                  child: Center(child: Text("${weightCurrent} kg", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                ),
                Column(children: [const Text("Objetivo", style: TextStyle(color: Colors.grey)), Text("${weightTarget} kg", style: const TextStyle(fontWeight: FontWeight.bold))]),
              ],
            ),
            const SizedBox(height: 20),
            LinearProgressIndicator(value: progressPercent, color: Colors.tealAccent, backgroundColor: Colors.white10, minHeight: 10),
            const SizedBox(height: 8),
            Text("Progresso: ${(progressPercent * 100).toStringAsFixed(1)}% | Faltam ${remainingWeight.toStringAsFixed(1)} kg", style: const TextStyle(color: Colors.tealAccent)),
            const SizedBox(height: 25),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF1A2632), borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      children: [
                        const Text("IMC", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        Text(imc.toStringAsFixed(1), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
                        Text(getImcClassification(imc), style: const TextStyle(fontSize: 10, color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF1A2632), borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      children: [
                        const Text("Gordura Corporal", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        Text("${bodyFatPercent}%", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                        const Text("Estimativa Atual", style: TextStyle(fontSize: 10, color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Histórico de Pesagem", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ElevatedButton.icon(
                  onPressed: () => _showAddWeightDialog(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text("Novo Peso"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
                )
              ],
            ),
            const SizedBox(height: 10),
            weightHistory.isEmpty
                ? const Text("Nenhum registro de peso.", style: TextStyle(color: Colors.grey))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: weightHistory.length,
                    itemBuilder: (ctx, idx) {
                      final item = weightHistory[idx];
                      return Card(
                        color: const Color(0xFF1A2632),
                        child: ListTile(
                          title: Text("${item['weight']} kg"),
                          subtitle: Text("Data: ${item['date']}"),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () => onDeleteWeight(item['id']),
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    double paceMinutes = distanceKm > 0 ? (seconds / 60) / distanceKm : 0.0;
    int pMin = paceMinutes.toInt();
    int pSec = ((paceMinutes - pMin) * 60).toInt();
    int calories = (distanceKm * 65).toInt();

    String formatRunTime(int totalSecs) {
      int m = totalSecs ~/ 60;
      int s = totalSecs % 60;
      return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Corrida & GPS'), backgroundColor: Colors.transparent),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Center(
              child: Column(
                children: [
                  Text(distanceKm.toStringAsFixed(2), style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                  const Text("QUILÔMETROS", style: TextStyle(color: Colors.grey, letterSpacing: 2)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Column(
                        children: [
                          const Icon(Icons.timer, color: Colors.orangeAccent),
                          const SizedBox(height: 4),
                          Text(formatRunTime(seconds), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const Text("Tempo", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                      Column(
                        children: [
                          const Icon(Icons.speed, color: Colors.tealAccent),
                          const SizedBox(height: 4),
                          Text("$pMin:${pSec.toString().padLeft(2, '0')}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const Text("Pace (/km)", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                      Column(
                        children: [
                          const Icon(Icons.local_fire_department, color: Colors.redAccent),
                          const SizedBox(height: 4),
                          Text("$calories", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const Text("Kcal", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isRunning ? Colors.redAccent : Colors.tealAccent,
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: onToggleRun,
              child: Text(
                isRunning ? 'PARAR CORRIDA' : 'INICIAR CORRIDA',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const SizedBox(height: 30),
            Row(
              children: const [
                Icon(Icons.history, color: Colors.tealAccent),
                SizedBox(width: 8),
                Text("Histórico de Corridas", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 10),
            history.isEmpty
                ? const Text("Nenhuma corrida registrada ainda.", style: TextStyle(color: Colors.grey))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: history.length,
                    itemBuilder: (ctx, idx) {
                      final item = history[idx];
                      return Card(
                        color: const Color(0xFF1A2632),
                        child: ListTile(
                          title: Text("${item['distance']} - ${item['time']}"),
                          subtitle: Text("Data: ${item['date']} | Pace: ${item['pace']} | ${item['calories']}"),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () => onDeleteRun(item['id']),
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
