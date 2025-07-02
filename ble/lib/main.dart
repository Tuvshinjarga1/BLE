import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Эрүүл мэнд',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const BleHomePage(),
    );
  }
}

class BleHomePage extends StatefulWidget {
  const BleHomePage({super.key});

  @override
  State<BleHomePage> createState() => _BleHomePageState();
}

class FitnessData {
  int? heartRate;
  int? stepCount;
  int? batteryLevel;
  String? deviceInfo;
  String? userName;
  DateTime lastUpdated = DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'heartRate': heartRate,
      'stepCount': stepCount,
      'batteryLevel': batteryLevel,
      'deviceInfo': deviceInfo,
      'userName': userName,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }
}

class _BleHomePageState extends State<BleHomePage> {
  BluetoothDevice? connectedDevice;
  List<BluetoothDevice> devicesList = [];
  bool isScanning = false;
  bool isLoading = false;
  String connectionStatus = 'Холбогдоогүй';
  String statusMessage = 'Төхөөрөмж хайж байна...';
  FitnessData fitnessData = FitnessData();
  List<BluetoothService> availableServices = [];

  // Samsung Galaxy Fit 3-ын алдартай service UUID-ууд
  static const String heartRateServiceUuid =
      "0000180d-0000-1000-8000-00805f9b34fb";
  static const String heartRateMeasurementUuid =
      "00002a37-0000-1000-8000-00805f9b34fb";
  static const String batteryServiceUuid =
      "0000180f-0000-1000-8000-00805f9b34fb";
  static const String batteryLevelUuid = "00002a19-0000-1000-8000-00805f9b34fb";
  static const String deviceInfoServiceUuid =
      "0000180a-0000-1000-8000-00805f9b34fb";
  static const String deviceNameUuid = "00002a00-0000-1000-8000-00805f9b34fb";

  // Хэрэглэгчийн нэр оруулах controller
  final TextEditingController userNameController = TextEditingController();
  String userName = 'Хэрэглэгч'; // Анхны утга

  @override
  void initState() {
    super.initState();
    _checkPermissions();

    // Хэрэглэгчийн нэр өөрчлөгдөх үед fitnessData шинэчлэх
    userNameController.addListener(() {
      setState(() {
        userName = userNameController.text.isNotEmpty
            ? userNameController.text
            : 'Хэрэглэгч';
        fitnessData.userName = userName;
      });
    });

    // Анхны утга тохируулах
    userNameController.text = userName;
    fitnessData.userName = userName;
  }

  Future<void> _checkPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
    }
  }

  void _startScan() async {
    if (!await FlutterBluePlus.isAvailable) {
      _showSnackBar('Bluetooth дэмжигдэхгүй байна');
      return;
    }

    if (!await FlutterBluePlus.isOn) {
      _showSnackBar('Bluetooth-г асаана уу');
      return;
    }

    setState(() {
      isScanning = true;
      devicesList.clear();
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      FlutterBluePlus.scanResults.listen((results) {
        setState(() {
          devicesList = results.map((r) => r.device).toList();
        });
      });

      await Future.delayed(const Duration(seconds: 15));
      await FlutterBluePlus.stopScan();
    } catch (e) {
      _showSnackBar('Скан хийхэд алдаа гарлаа: $e');
    }

    setState(() {
      isScanning = false;
    });
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      setState(() {
        connectionStatus = 'Холбогдож байна...';
      });

      await device.connect();

      setState(() {
        connectedDevice = device;
        connectionStatus =
            'Холбогдсон: ${device.name.isNotEmpty ? device.name : device.id.id}';
      });

      _showSnackBar('Амжилттай холбогдлоо!');

      // Сервисүүдийг олох
      await _discoverServices();

      // Автоматаар дата уншиж эхлэх
      await _startDataCollection();
    } catch (e) {
      setState(() {
        connectionStatus = 'Холболт амжилтгүй';
      });
      _showSnackBar('Холболт амжилтгүй: $e');
    }
  }

  Future<void> _discoverServices() async {
    if (connectedDevice == null) return;

    print('=== ОЛДСОН БҮГД СЕРВИСҮҮД ===');

    List<BluetoothService> services = await connectedDevice!.discoverServices();

    for (BluetoothService service in services) {
      print(
          'Сервис UUID: ${service.uuid.toString().toUpperCase().substring(4, 8)}');

      for (BluetoothCharacteristic characteristic in service.characteristics) {
        print(
            '  Characteristic UUID: ${characteristic.uuid.toString().toUpperCase().substring(4, 8)}');
        print('  Боломжууд: ${characteristic.properties}');

        if (characteristic.properties.read) {
          try {
            List<int> value = await characteristic.read();
            print('  Утга: $value');
            try {
              String stringValue = utf8.decode(value);
              print('  String утга: $stringValue');
            } catch (e) {
              print('  String-рүү хөрвүүлж чадсангүй');
            }
          } catch (e) {
            print('  Уншихад алдаа: $e');
          }
        }
      }
    }

    // Heart Rate notification тохируулах
    await _setupHeartRateNotification();

    // Samsung специфик дата унших
    await _readSamsungSpecificData();

    print('=== СЕРВИС ОЛДОО ===');
    await _readAllAvailableData();
  }

  Future<void> _setupHeartRateNotification() async {
    if (connectedDevice == null) return;

    try {
      List<BluetoothService> services =
          await connectedDevice!.discoverServices();

      for (BluetoothService service in services) {
        // Heart Rate сервис хайх (180D)
        if (service.uuid.toString().toUpperCase().contains('180D')) {
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            // Heart Rate Measurement characteristic (2A37)
            if (characteristic.uuid.toString().toUpperCase().contains('2A37')) {
              print('❤️ Heart Rate notification тохируулж байна...');

              if (characteristic.properties.notify) {
                await characteristic.setNotifyValue(true);

                characteristic.value.listen((value) {
                  if (value.isNotEmpty) {
                    // Heart Rate дата parse хийх
                    int heartRate = _parseHeartRate(value);
                    setState(() {
                      fitnessData.heartRate = heartRate;
                    });
                    print('❤️ Heart Rate шинэчлэгдлээ: $heartRate bpm');

                    // Веб серверт дата илгээх
                    _sendDataToWebServer();
                  }
                });
                print('❤️ Heart Rate notification идэвхжлээ!');
              }
            }
          }
        }
      }
    } catch (e) {
      print('Heart Rate notification тохируулахад алдаа: $e');
    }
  }

  int _parseHeartRate(List<int> data) {
    if (data.isEmpty) return 0;

    // Standard Heart Rate дата формат
    if (data.length >= 2) {
      // 16-bit утга эсвэл 8-bit утга шалгах
      if ((data[0] & 0x01) == 0) {
        // 8-bit heart rate
        return data[1];
      } else {
        // 16-bit heart rate
        return (data[2] << 8) | data[1];
      }
    }

    return data[0]; // Fallback
  }

  Future<void> _startDataCollection() async {
    print('=== ДАТА ЦУГЛУУЛЖ ЭХЭЛЖ БАЙНА ===');

    // Эхлээд бүх боломжтой characteristic-уудаас дата уншиж үзэх
    await _readAllAvailableData();

    // Дараа нь стандарт service-үүдээс уншиж үзэх
    await _readHeartRate();
    await _readBatteryLevel();
    await _readDeviceInfo();

    // Heart rate notification асаах
    await _enableHeartRateNotifications();

    // Samsung-ийн тусгай service-үүдээс уншиж үзэх
    await _readSamsungSpecificData();
  }

  Future<void> _readAllAvailableData() async {
    if (connectedDevice == null) return;

    setState(() {
      isLoading = true;
      statusMessage = 'Бүх дата цуглуулж байна...';
    });

    print('=== ДАТА ЦУГЛУУЛЖ ЭХЭЛЖ БАЙНА ===');
    print('=== БҮГД CHARACTERISTIC-УУДААС ДАТА УНШИЖ БАЙНА ===');

    try {
      List<BluetoothService> services =
          await connectedDevice!.discoverServices();

      for (BluetoothService service in services) {
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          if (characteristic.properties.read) {
            try {
              List<int> value = await characteristic.read();
              String serviceUuid =
                  service.uuid.toString().toUpperCase().substring(4, 8);
              String charUuid =
                  characteristic.uuid.toString().toUpperCase().substring(4, 8);

              print('Service $serviceUuid -> Char $charUuid: $value');

              // Батарей мэдээлэл таних
              if (value.isNotEmpty && value[0] >= 0 && value[0] <= 100) {
                print('🔋 Боломжит батарей олдлоо: ${value[0]}%');
                setState(() {
                  fitnessData.batteryLevel = value[0];
                });
              }

              // Step count эрэх гэж үзэх (том тоо байвал)
              if (value.length >= 2) {
                int possibleSteps = (value[1] << 8) | value[0];
                if (possibleSteps > 100 && possibleSteps < 50000) {
                  print('👟 Боломжит алхам: $possibleSteps');
                  setState(() {
                    fitnessData.stepCount = possibleSteps;
                  });
                }
              }
            } catch (e) {
              print(
                  'Characteristic ${characteristic.uuid.toString().substring(4, 8)} уншихад алдаа: $e');
            }
          }
        }
      }

      setState(() {
        statusMessage = 'Дата цуглуулж дууслаа';
        fitnessData.lastUpdated = DateTime.now();
      });
    } catch (e) {
      setState(() {
        statusMessage = 'Дата цуглуулахад алдаа: $e';
      });
      print('Дата цуглуулахад алдаа: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _readHeartRate() async {
    if (connectedDevice == null) return;

    setState(() {
      isLoading = true;
      statusMessage = 'Зүрхний цохилт уншиж байна...';
    });

    try {
      List<BluetoothService> services =
          await connectedDevice!.discoverServices();

      for (BluetoothService service in services) {
        if (service.uuid.toString().toUpperCase().contains('180D')) {
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            if (characteristic.uuid.toString().toUpperCase().contains('2A37')) {
              if (characteristic.properties.notify) {
                // Notification тохируулах
                await characteristic.setNotifyValue(true);
                print('❤️ Heart Rate notification тохирууллаа');

                setState(() {
                  statusMessage =
                      'Heart Rate notification идэвхжсэн. Дата хүлээж байна...';
                });

                // Notification дата сонсох
                characteristic.value.listen((value) {
                  if (value.isNotEmpty) {
                    int heartRate = _parseHeartRate(value);
                    setState(() {
                      fitnessData.heartRate = heartRate;
                      statusMessage = 'Heart Rate: $heartRate bpm';
                    });

                    // Веб серверт дата илгээх
                    _sendDataToWebServer();
                  }
                });
              } else if (characteristic.properties.read) {
                // Read хийж үзэх
                List<int> value = await characteristic.read();
                int heartRate = _parseHeartRate(value);

                setState(() {
                  fitnessData.heartRate = heartRate;
                  statusMessage = 'Heart Rate уншлаа: $heartRate bpm';
                });
              }

              return; // Heart Rate олдлоо
            }
          }
        }
      }

      setState(() {
        statusMessage = 'Heart Rate сервис олдсонгүй';
      });
    } catch (e) {
      setState(() {
        statusMessage = 'Heart Rate унших алдаа: $e';
      });
      print('Heart Rate унших алдаа: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _enableHeartRateNotifications() async {
    try {
      BluetoothCharacteristic? hrCharacteristic =
          _findCharacteristic(heartRateServiceUuid, heartRateMeasurementUuid);

      if (hrCharacteristic != null && hrCharacteristic.properties.notify) {
        await hrCharacteristic.setNotifyValue(true);

        hrCharacteristic.value.listen((value) {
          if (value.isNotEmpty) {
            int heartRate = value.length > 1 ? value[1] : value[0];
            setState(() {
              fitnessData.heartRate = heartRate;
              fitnessData.lastUpdated = DateTime.now();
            });
            print('Шинэ зүрхний цохилт: $heartRate bpm');
          }
        });

        _showSnackBar('Зүрхний цохилт автомат хэмжиж эхэллээ');
      }
    } catch (e) {
      print('Heart rate notification асаахад алдаа: $e');
    }
  }

  Future<void> _readBatteryLevel() async {
    if (connectedDevice == null) return;

    setState(() {
      isLoading = true;
      statusMessage = 'Батарей уншиж байна...';
    });

    try {
      List<BluetoothService> services =
          await connectedDevice!.discoverServices();
      bool batteryFound = false;

      for (BluetoothService service in services) {
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          if (characteristic.properties.read) {
            try {
              List<int> value = await characteristic.read();

              // Батарейн утга шалгах (0-100 хооронд байх ёстой)
              if (value.isNotEmpty && value[0] >= 0 && value[0] <= 100) {
                // Characteristic UUID-г шалгах
                String charUuid = characteristic.uuid.toString().toUpperCase();

                // Стандарт батарей сервис эсвэл боломжит батарей утга
                if (charUuid.contains('2A19') || // Стандарт батарей
                    charUuid.contains('2AA6') || // Samsung батарей
                    charUuid.contains('2B29') || // Generic Battery
                    (value[0] > 0 && value[0] <= 100)) {
                  // Логик батарей утга

                  setState(() {
                    fitnessData.batteryLevel = value[0];
                    statusMessage = 'Батарей: ${value[0]}%';
                  });

                  print(
                      '🔋 Батарей олдлоо: ${value[0]}% (Characteristic: ${charUuid.substring(4, 8)})');
                  batteryFound = true;
                  break;
                }
              }
            } catch (e) {
              // Characteristic уншихад алдаа - дараагийн рүү
              continue;
            }
          }
        }
        if (batteryFound) break;
      }

      if (!batteryFound) {
        setState(() {
          statusMessage = 'Батарейн мэдээлэл олдсонгүй';
        });
      }
    } catch (e) {
      setState(() {
        statusMessage = 'Батарей унших алдаа: $e';
      });
      print('Батарей унших алдаа: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _readDeviceInfo() async {
    try {
      BluetoothCharacteristic? deviceCharacteristic =
          _findCharacteristic(deviceInfoServiceUuid, deviceNameUuid);

      if (deviceCharacteristic != null) {
        List<int> value = await deviceCharacteristic.read();
        if (value.isNotEmpty) {
          String deviceInfo = utf8.decode(value);
          setState(() {
            fitnessData.deviceInfo = deviceInfo;
          });
          print('Төхөөрөмж: $deviceInfo');
        }
      }
    } catch (e) {
      print('Device info уншихад алдаа: $e');
    }
  }

  Future<void> _readSamsungSpecificData() async {
    print('=== SAMSUNG ТУСГАЙ СЕРВИСҮҮДЭЭС УНШИЖ БАЙНА ===');

    // Samsung-ийн тусгай UUID-ууд
    List<String> samsungServiceUuids = [
      "0000fee0-0000-1000-8000-00805f9b34fb", // Samsung тусгай сервис
      "0000fee1-0000-1000-8000-00805f9b34fb",
      "0000fec9-0000-1000-8000-00805f9b34fb",
      "4f63756c-7573-2054-6872-65656120527e", // Oculus/Samsung
    ];

    for (String serviceUuid in samsungServiceUuids) {
      BluetoothService? service = _findService(serviceUuid);
      if (service != null) {
        print('Samsung тусгай сервис олдлоо: ${service.uuid}');
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          if (characteristic.properties.read) {
            try {
              List<int> value = await characteristic.read();
              print('Samsung дата: ${characteristic.uuid} -> $value');

              // Шинжилж үзэх
              _analyzeSamsungData(characteristic.uuid.toString(), value);
            } catch (e) {
              print('Samsung characteristic уншихад алдаа: $e');
            }
          }

          // Notification боломжтой бол асаах
          if (characteristic.properties.notify) {
            try {
              await characteristic.setNotifyValue(true);
              characteristic.value.listen((value) {
                print('Samsung notification: ${characteristic.uuid} -> $value');
                _analyzeSamsungData(characteristic.uuid.toString(), value);
              });
            } catch (e) {
              print('Samsung notification асаахад алдаа: $e');
            }
          }
        }
      }
    }
  }

  void _analyzeSamsungData(String characteristicUuid, List<int> value) {
    if (value.isEmpty) return;

    // Heart rate мэт дата шинжих
    if (value.length >= 2) {
      int possibleHeartRate = value[1];
      if (possibleHeartRate > 40 && possibleHeartRate < 200) {
        setState(() {
          fitnessData.heartRate = possibleHeartRate;
          fitnessData.lastUpdated = DateTime.now();
        });
        _showSnackBar('Зүрхний цохилт олдлоо: $possibleHeartRate bpm');
      }
    }

    // Battery level шинжих
    if (value.length == 1 && value[0] <= 100) {
      setState(() {
        fitnessData.batteryLevel = value[0];
      });
      _showSnackBar('Батарей олдлоо: ${value[0]}%');
    }

    // Step count шинжих (4 байтын integer)
    if (value.length >= 4) {
      int steps = 0;
      // Little endian болон big endian аль алиар нь оролдох
      int stepsLE =
          (value[3] << 24) | (value[2] << 16) | (value[1] << 8) | value[0];
      int stepsBE =
          (value[0] << 24) | (value[1] << 16) | (value[2] << 8) | value[3];

      if (stepsLE > 0 && stepsLE < 100000) {
        steps = stepsLE;
      } else if (stepsBE > 0 && stepsBE < 100000) {
        steps = stepsBE;
      }

      if (steps > 0) {
        setState(() {
          fitnessData.stepCount = steps;
        });
        _showSnackBar('Алхамын тоо олдлоо: $steps');
      }
    }
  }

  BluetoothService? _findService(String serviceUuid) {
    for (BluetoothService service in availableServices) {
      if (service.uuid.toString().toLowerCase() == serviceUuid.toLowerCase()) {
        return service;
      }
    }
    return null;
  }

  BluetoothCharacteristic? _findCharacteristic(
      String serviceUuid, String characteristicUuid) {
    for (BluetoothService service in availableServices) {
      if (service.uuid.toString().toLowerCase() == serviceUuid.toLowerCase()) {
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          if (characteristic.uuid.toString().toLowerCase() ==
              characteristicUuid.toLowerCase()) {
            return characteristic;
          }
        }
      }
    }
    return null;
  }

  void _disconnect() async {
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      setState(() {
        connectedDevice = null;
        connectionStatus = 'Холбогдоогүй';
        availableServices.clear();
        fitnessData = FitnessData();
      });
      _showSnackBar('Холболт тасарлаа');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool _isSamsungFit(BluetoothDevice device) {
    String deviceName = device.name.toLowerCase();
    return deviceName.contains('fit') ||
        deviceName.contains('samsung') ||
        deviceName.contains('galaxy');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Эрүүл мэнд'),
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8FAFF),
              Color(0xFFE8F4FD),
              Color(0xFFF0F9FF),
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Холболтын төлөв карт
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white,
                      Colors.blue.shade50,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: connectedDevice != null
                                  ? Colors.green.shade100
                                  : Colors.red.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              connectedDevice != null
                                  ? Icons.bluetooth_connected
                                  : Icons.bluetooth_disabled,
                              color: connectedDevice != null
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Холболтын төлөв',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  connectionStatus,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(
                                        color: connectedDevice != null
                                            ? Colors.green.shade700
                                            : Colors.red.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Хэрэглэгчийн нэр оруулах карт
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white,
                      Colors.purple.shade50,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.person,
                              color: Colors.purple.shade700,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Хэрэглэгчийн нэр',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: userNameController,
                        decoration: InputDecoration(
                          hintText: 'Таны нэрийг оруулна уу...',
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                          prefixIcon:
                              Icon(Icons.edit, color: Colors.purple.shade600),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: Colors.purple.shade200, width: 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: Colors.purple.shade400, width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.purple.shade600, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Web дашборд дээр "$userName" нэртэй харагдана',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Colors.purple.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Fitness датаны карт
              if (connectedDevice != null) ...[
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white,
                        Colors.green.shade50,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.favorite,
                                color: Colors.green.shade700,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Fitness дата',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildModernDataItem(
                                '💗',
                                '${fitnessData.heartRate ?? "--"} bpm',
                                'Зүрхний цохилт',
                                Colors.red),
                            _buildModernDataItem(
                                '🔋',
                                '${fitnessData.batteryLevel ?? "--"}%',
                                'Батарей',
                                Colors.blue),
                            _buildModernDataItem(
                                '👟',
                                '${fitnessData.stepCount ?? "--"}',
                                'Алхам',
                                Colors.purple),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (fitnessData.deviceInfo != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.devices,
                                    color: Colors.green.shade600, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'Төхөөрөмж: ${fitnessData.deviceInfo}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Colors.green.shade700,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.update,
                                  color: Colors.grey.shade600, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                'Сүүлд шинэчлэгдсэн: ${_formatTime(fitnessData.lastUpdated)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Colors.grey.shade700,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Статус мэдээлэл
              if (statusMessage.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.blue.shade50,
                        Colors.indigo.shade50,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.info_outline,
                          color: Colors.blue.shade700,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          statusMessage,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Товчлууруудын хэсэг
              Row(
                children: [
                  _buildActionButton('Холбох', _startScan),
                  _buildActionButton('❤️ Зүрх',
                      connectedDevice != null ? _readHeartRate : null),
                  _buildActionButton('🔋 Батарей',
                      connectedDevice != null ? _readBatteryLevel : null),
                ],
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  _buildActionButton('📊 Бүх дата',
                      connectedDevice != null ? _readAllAvailableData : null),
                  _buildActionButton(
                      '🔍 Samsung',
                      connectedDevice != null
                          ? _readSamsungSpecificData
                          : null),
                  _buildActionButton(
                      '❌ Салах', connectedDevice != null ? _disconnect : null,
                      color: Colors.red),
                ],
              ),

              // Төхөөрөмжийн жагсаалт
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.bluetooth_searching,
                            color: Colors.orange.shade700,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Олдсон төхөөрөмжүүд',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 300, // Fixed height for the device list
                child: devicesList.isEmpty
                    ? Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Icon(
                                  Icons.bluetooth_disabled,
                                  size: 48,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Төхөөрөмж олдсонгүй',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade700,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Төхөөрөмж хайхын тулд дээрх товчийг дарна уу.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Colors.grey.shade600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const ClampingScrollPhysics(),
                        itemCount: devicesList.length,
                        itemBuilder: (context, index) {
                          final device = devicesList[index];
                          final deviceName = device.name.isNotEmpty
                              ? device.name
                              : 'Нэргүй төхөөрөмж';
                          final isSamsungFit = _isSamsungFit(device);
                          final isConnected = connectedDevice?.id == device.id;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: isConnected
                                    ? [
                                        Colors.green.shade50,
                                        Colors.green.shade100
                                      ]
                                    : isSamsungFit
                                        ? [
                                            Colors.blue.shade50,
                                            Colors.blue.shade100
                                          ]
                                        : [Colors.white, Colors.grey.shade50],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: isConnected
                                      ? Colors.green.withOpacity(0.2)
                                      : isSamsungFit
                                          ? Colors.blue.withOpacity(0.1)
                                          : Colors.grey.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                              border: Border.all(
                                color: isConnected
                                    ? Colors.green.withOpacity(0.3)
                                    : isSamsungFit
                                        ? Colors.blue.withOpacity(0.3)
                                        : Colors.grey.withOpacity(0.2),
                                width: 1.5,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              leading: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isConnected
                                      ? Colors.green.shade200
                                      : isSamsungFit
                                          ? Colors.blue.shade200
                                          : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  isConnected
                                      ? Icons.check_circle
                                      : isSamsungFit
                                          ? Icons.watch
                                          : Icons.bluetooth,
                                  color: isConnected
                                      ? Colors.green.shade700
                                      : isSamsungFit
                                          ? Colors.blue.shade700
                                          : Colors.grey.shade600,
                                  size: 24,
                                ),
                              ),
                              title: Text(
                                deviceName,
                                style: TextStyle(
                                  fontWeight: isSamsungFit || isConnected
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  color: isConnected
                                      ? Colors.green.shade800
                                      : Colors.grey.shade800,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    device.id.id,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  if (isSamsungFit)
                                    Container(
                                      margin: const EdgeInsets.only(top: 6),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '⭐ Samsung Fit төрөл',
                                        style: TextStyle(
                                          color: Colors.blue.shade700,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  if (isConnected)
                                    Container(
                                      margin: const EdgeInsets.only(top: 6),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '✅ Холбогдсон',
                                        style: TextStyle(
                                          color: Colors.green.shade700,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              trailing: isConnected
                                  ? Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade200,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Icon(
                                        Icons.check_circle,
                                        color: Colors.green.shade700,
                                        size: 20,
                                      ),
                                    )
                                  : Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.blue.shade400,
                                            Colors.blue.shade600,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.blue.withOpacity(0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: IconButton(
                                        icon: const Icon(Icons.link,
                                            color: Colors.white),
                                        onPressed: () =>
                                            _connectToDevice(device),
                                      ),
                                    ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernDataItem(
      String emoji, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: color.withOpacity(0.2), width: 1),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(String text, VoidCallback? onPressed,
      {Color? color}) {
    final buttonColor = color ?? Colors.blue;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          borderRadius: BorderRadius.circular(12),
          elevation: onPressed != null ? 4 : 0,
          shadowColor: buttonColor.withOpacity(0.3),
          child: Container(
            decoration: BoxDecoration(
              gradient: onPressed != null
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        buttonColor,
                        buttonColor.withOpacity(0.8),
                      ],
                    )
                  : LinearGradient(
                      colors: [
                        Colors.grey.shade300,
                        Colors.grey.shade400,
                      ],
                    ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: onPressed != null
                    ? buttonColor.withOpacity(0.3)
                    : Colors.grey.shade400,
                width: 1,
              ),
            ),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: onPressed != null
                          ? Colors.white
                          : Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    connectedDevice?.disconnect();
    userNameController.dispose(); // Controller цэвэрлэх
    super.dispose();
  }

  // Web серверт дата илгээх функц
  Future<void> _sendDataToWebServer() async {
    try {
      // Next.js серверийн health API endpoint
      const String webServerUrl =
          'https://health-monitoring-web.vercel.app/api/health';
      // const String webServerUrl = 'http://192.168.1.63:3000/api/health';

      // Одоогийн цаг, өдрийг авах
      DateTime now = DateTime.now();
      String timeLabel =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      String dateLabel =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final response = await http.post(
        Uri.parse(webServerUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'userId': connectedDevice?.id.id ?? 'unknown_device',
          'heartRate': fitnessData.heartRate ?? 0,
          'stepCount': fitnessData.stepCount ?? 0,
          'battery': fitnessData.batteryLevel ?? 0,
          'timestamp': now.toIso8601String(),
          'userName':
              fitnessData.userName ?? userName, // Хэрэглэгчийн нэр илгээх
          'timeLabel': timeLabel,
          'dateLabel': dateLabel,
          'deviceName': connectedDevice?.name ?? 'Тодорхойгүй төхөөрөмж',
        }),
      );

      if (response.statusCode == 200) {
        print('✅ Веб серверт дата илгээгдлээ - ${fitnessData.userName}');
        setState(() {
          statusMessage = '✅ ${fitnessData.userName}-ын дата илгээгдлээ';
        });
      } else {
        print('❌ Веб серверт илгээхэд алдаа: ${response.statusCode}');
        setState(() {
          statusMessage = '❌ Серверт илгээхэд алдаа: ${response.statusCode}';
        });
      }
    } catch (e) {
      print('❌ Веб серверт холболт алдаа: $e');
      setState(() {
        statusMessage = '❌ Холболт алдаа: $e';
      });
    }
  }
}
