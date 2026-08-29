import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

const String FIREBASE_URL = "https://taxialbalad-85453-default-rtdb.europe-west1.firebasedatabase.app/drivers";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    home: DriverApp(),
    debugShowCheckedModeBanner: false,
  ));
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  service.on('setDriver').listen((event) {
    if (event != null && event['driverKey'] != null) {
      String driverKey = event['driverKey'];
      
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2,
        ),
      ).listen((Position pos) {
        http.patch(
          Uri.parse("$FIREBASE_URL/$driverKey.json"),
          body: json.encode({
            'lat': pos.latitude,
            'lng': pos.longitude,
            'lastGpsUpdate': DateTime.now().millisecondsSinceEpoch,
          }),
        );
      });
    }
  });

  service.on('stopService').listen((event) {
    service.stopSelf();
  });
}

class DriverApp extends StatefulWidget {
  const DriverApp({super.key});

  @override
  State<DriverApp> createState() => _DriverAppState();
}

class _DriverAppState extends State<DriverApp> {
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  bool isOnline = false;
  String driverName = "";

  Future<void> startTracking(String key, String name) async {
    await Permission.notification.request();
    await Permission.locationAlways.request();

    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'taxi_location_channel',
        initialNotificationTitle: 'كابتن تكسي البلد',
        initialNotificationContent: 'خدمة التتبع المباشر تعمل في الخلفية',
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(),
    );

    await service.startService();
    service.invoke('setDriver', {'driverKey': key});

    setState(() {
      isOnline = true;
      driverName = name;
    });
  }

  void handleLogin() async {
    String p = _phone.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    String pass = _pass.text.trim();
    if (p.isEmpty || pass.isEmpty) return;

    if (p.startsWith('0')) p = '963${p.substring(1)}';
    else if (!p.startsWith('963')) p = '963$p';

    try {
      final res = await http.get(Uri.parse("$FIREBASE_URL.json"));
      if (res.statusCode == 200 && res.body != "null") {
        Map data = json.decode(res.body);
        String? matchKey;
        String? matchName;

        data.forEach((k, v) {
          String cleanP = (v['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
          if (cleanP.contains(p) || p.contains(cleanP)) {
            if (v['password'].toString() == pass) {
              matchKey = k;
              matchName = v['name'] ?? 'كابتن';
            }
          }
        });

        if (matchKey != null) {
          await startTracking(matchKey!, matchName!);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("رقم الهاتف أو الرمز غير صحيح")),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("خطأ: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: const Text("تكسي البلد | تطبيق الكابتن"),
        backgroundColor: const Color(0xFFfcba03),
        foregroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: isOnline
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 90),
                    const SizedBox(height: 20),
                    Text("مرحباً بك كابتن $driverName", style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    const Text("أنت الآن أونلاين والموقع يرسل في الخلفية حتى مع إغلاق الشاشة", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 15)),
                    const SizedBox(height: 40),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size.fromHeight(55)),
                      onPressed: () {
                        FlutterBackgroundService().invoke('stopService');
                        setState(() => isOnline = false);
                      },
                      child: const Text("إيقاف الاستقبال والعمل", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "رقم الهاتف",
                      labelStyle: TextStyle(color: Color(0xFFfcba03)),
                      prefixText: "+963 ",
                      prefixStyle: TextStyle(color: Colors.white),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFfcba03))),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "رمز المرور (PIN)",
                      labelStyle: TextStyle(color: Color(0xFFfcba03)),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFfcba03))),
                    ),
                  ),
                  const SizedBox(height: 25),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFfcba03),
                      minimumSize: const Size.fromHeight(55),
                    ),
                    onPressed: handleLogin,
                    child: const Text("تسجيل الدخول وبدء العمل", style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
      ),
    );
  }
}
