import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

const String FIREBASE_URL = "https://taxialbalad-85453-default-rtdb.europe-west1.firebasedatabase.app/drivers";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(const MaterialApp(
    home: DriverApp(),
    debugShowCheckedModeBanner: false,
  ));
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationTitle: "تكسي البلد | كابتن",
      notificationContent: "جاري تتبع الموقع في الخلفية بشكل مستمر",
      initialNotificationTitle: "تكسي البلد",
      initialNotificationContent: "جاري بدء الخدمة...",
    ),
    iosConfiguration: IosConfiguration(),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 3,
    ),
  ).listen((Position pos) {
    service.invoke('update_location', {
      'lat': pos.latitude,
      'lng': pos.longitude,
    });
  });
}

class DriverApp extends StatefulWidget {
  const DriverApp({super.key});

  @override
  State<DriverApp> createState() => _DriverAppState();
}

class _DriverAppState extends State<DriverApp> {
  final _phoneController = TextEditingController();
  final _passController = TextEditingController();
  bool isWorking = false;
  String? driverFbKey;
  String driverName = "";

  void loginAndStart() async {
    String phone = _phoneController.text.trim();
    String pass = _passController.text.trim();

    if (phone.isEmpty || pass.isEmpty) return;

    if (!phone.startsWith('963')) {
      if (phone.startsWith('0')) phone = '963${phone.substring(1)}';
      else phone = '963$phone';
    }

    try {
      final res = await http.get(Uri.parse("$FIREBASE_URL.json"));
      if (res.statusCode == 200 && res.body != "null") {
        final Map<String, dynamic> data = json.decode(res.body);
        data.forEach((key, val) {
          if (val['phone'] != null && val['phone'].toString().contains(phone)) {
            if (val['password'].toString() == pass) {
              driverFbKey = key;
              driverName = val['name'] ?? 'كابتن';
            }
          }
        });

        if (driverFbKey != null) {
          LocationPermission permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }

          final service = FlutterBackgroundService();
          await service.startService();

          FlutterBackgroundService().on('update_location').listen((event) {
            if (event != null && driverFbKey != null) {
              http.patch(
                Uri.parse("$FIREBASE_URL/$driverFbKey.json"),
                body: json.encode({
                  'lat': event['lat'],
                  'lng': event['lng'],
                  'lastGpsUpdate': DateTime.now().millisecondsSinceEpoch,
                }),
              );
            }
          });

          setState(() => isWorking = true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("رقم الهاتف أو كلمة المرور غير صحيحة")),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("خطأ في الاتصال: $e")),
      );
    }
  }

  void stopWork() async {
    final service = FlutterBackgroundService();
    service.invoke("stopService");
    setState(() => isWorking = false);
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
        padding: const EdgeInsets.all(20),
        child: isWorking
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_outline, color: Colors.green, size: 90),
                    const SizedBox(height: 15),
                    Text(
                      "مرحباً بك كابتن $driverName\nأنت الآن أونلاين والموقع يرسل في الخلفية",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 35),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size.fromHeight(50)),
                      onPressed: stopWork,
                      child: const Text("إيقاف العمل والخروج", style: TextStyle(fontSize: 18, color: Colors.white)),
                    )
                  ],
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "رقم الهاتف",
                      labelStyle: TextStyle(color: Color(0xFFfcba03)),
                      prefixText: "+963 ",
                      prefixStyle: TextStyle(color: Colors.white),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _passController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "كلمة المرور (PIN)",
                      labelStyle: TextStyle(color: Color(0xFFfcba03)),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 25),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFfcba03),
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: loginAndStart,
                    child: const Text("تسجيل الدخول وبدء العمل", style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
      ),
    );
  }
}
