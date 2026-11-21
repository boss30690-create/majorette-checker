import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MajoretteCheckerApp());

class MajoretteCheckerApp extends StatelessWidget {
  const MajoretteCheckerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Majorette Lot Checker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.amber,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _lotController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String _apiKey = '';
  File? _selectedImage;
  String _resultText = 'ถ่ายรูปก้นไข่ / ขอบตลับ หรือพิมพ์รหัส BKxxxxxx เพื่อเช็กรุ่นรถในล็อต';
  bool _isLoading = false;
  List> _history = [];

  @override
  void initState() {
    super.initState();
    _loadLocalData();
  }

  @override
  void dispose() {
    _lotController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString('gemini_api_key') ?? '';
    final savedHistoryRaw = prefs.getString('scan_history') ?? '[]';
    final List<dynamic> decoded = jsonDecode(savedHistoryRaw);

    if (!mounted) return;
    setState(() {
      _apiKey = savedKey;
      _history = decoded.map((e) => Map<String, String>.from(e)).toList();
    });
  }

  Future<void> _saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', key.trim());
    if (!mounted) return;
    setState(() => _apiKey = key.trim());
  }

  Future<void> _addHistory(String title, String detail) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final updated = [
      {'title': title, 'date': dateStr, 'detail': detail},
      ..._history,
    ].take(30).toList();

    await prefs.setString('scan_history', jsonEncode(updated));
    if (!mounted) return;
    setState(() => _history = updated);
  }

  void _showApiKeyDialog() {
    final controller = TextEditingController(text: _apiKey);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ตั้งค่า Gemini API Key'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'วาง AIzaSy... ที่นี่',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () {
              _saveApiKey(controller.text);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('บันทึก API Key เรียบร้อย')),
              );
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1280,
    );
    if (picked == null) return;

    setState(() {
      _selectedImage = File(picked.path);
    });
    await _analyzeLot();
  }

  Future<void> _analyzeLot() async {
    if (_apiKey.isEmpty) {
      _showApiKeyDialog();
      return;
    }

    final manualText = _lotController.text.trim();
    if (_selectedImage == null && manualText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาถ่ายรูปหรือพิมพ์รหัสล็อตก่อนครับ')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _resultText = 'กำลังอ่านรหัสและค้นหาข้อมูลรีวิวล่าสุด...';
    });

    try {
      final List> parts = [
        {
          'text': '''คุณคือผู้เชี่ยวชาญการสะสมรถเหล็ก Majorette ในประเทศไทย
งานของคุณ:
1. ระบุรหัสล็อตการผลิต (รูปแบบ BKxxxxxx) และสีเปลือกไข่หรือลักษณะตลับล้อจากภาพหรือข้อความที่ให้มา (ข้อมูลเพิ่มเติมจากผู้ใช้: "$manualText")
2. ค้นหาข้อมูลการแกะกล่องและรีวิวจากนักสะสมไทยสำหรับรหัสล็อตนี้
3. สรุปออกมาให้อ่านง่ายเวลาเดินเลือกหน้าชั้นวาง 7-Eleven ได้แก่:
   - รหัสล็อตและวันที่ผลิต
   - รายชื่อรุ่นรถและสีตัวถังที่ดรอปในล็อตนี้ (เน้นระบุว่ามีตัว Chase Car ล้อยางปนอยู่ไหม)
   - ทริคคัดรุ่นหน้าชั้นวางแบบสั้นๆ (สีเปลือกไข่, การส่องไฟดูสีสะท้อน, น้ำหนัก/แรงเขย่า)'''
        }
      ];

      if (_selectedImage != null) {
        final bytes = await _selectedImage!.readAsBytes();
        parts.add({
          'inline_data': {
            'mime_type': 'image/jpeg',
            'data': base64Encode(bytes),
          }
        });
      }

      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_apiKey',
      );

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {'parts': parts}
          ],
          'tools': [
            {'google_search': {}}
          ]
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode != 200) {
        final errMsg = data['error']?['message'] ?? 'เกิดข้อผิดพลาดในการเชื่อมต่อ';
        setState(() => _resultText = 'API Error: $errMsg');
        return;
      }

      final candidateParts =
          data['candidates']?[0]?['content']?['parts'] as List<dynamic>? ?? [];
      final output = candidateParts
          .map((p) => p['text']?.toString() ?? '')
          .join('\n')
          .trim();

      final finalOutput =
          output.isEmpty ? 'ไม่พบข้อมูลของรหัสนี้ ลองพิมพ์รหัสเพิ่มในช่องด้านบน' : output;

      setState(() => _resultText = finalOutput);

      final historyTitle = manualText.isNotEmpty
          ? manualText
          : 'สแกนจากรูปภาพ (${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')})';
      await _addHistory(historyTitle, finalOutput);
    } catch (e) {
      setState(() => _resultText = 'เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Majorette Lot Checker'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.key,
              color: _apiKey.isEmpty ? Colors.redAccent : Colors.amber,
            ),
            tooltip: 'ตั้งค่า API Key',
            onPressed: _showApiKeyDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('ถ่ายรูปไข่/ล้อ'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('เลือกรูป'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _lotController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      hintText: 'พิมพ์รหัส เช่น BK170826 ไข่สีน้ำตาล',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isLoading ? null : _analyzeLot,
                  child: const Text('เช็ก'),
                ),
              ],
            ),
            if (_selectedImage != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  _selectedImage!,
                  height: 160,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SelectableText(
                        _resultText,
                        style: const TextStyle(fontSize: 15, height: 1.5),
                      ),
              ),
            ),
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'ประวัติที่เคยเช็ก (ดูย้อนหลังแบบออฟไลน์ได้)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              ..._history.map(
                (item) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(item['title'] ?? ''),
                    subtitle: Text(item['date'] ?? ''),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      setState(() {
                        _selectedImage = null;
                        _resultText = item['detail'] ?? '';
                      });
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
