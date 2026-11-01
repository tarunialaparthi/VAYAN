import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleTestPage extends StatefulWidget {
  const BleTestPage({super.key});

  @override
  State<BleTestPage> createState() => _BleTestPageState();
}

class _BleTestPageState extends State<BleTestPage> {
  // ESP32 BLE UUIDs
  final Guid serviceUUID = Guid("12345678-1234-1234-1234-1234567890AB");

  final Guid characteristicUUID = Guid("ABCD1234-5678-1234-1234-1234567890AB");

  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? sensorCharacteristic;

  StreamSubscription<List<ScanResult>>? scanSubscription;
  StreamSubscription<List<int>>? dataSubscription;

  List<ScanResult> devices = [];

  Map<String, dynamic> sensorData = {};

  bool isScanning = false;
  bool isConnected = false;

  String status = "Not connected";

  @override
  void initState() {
    super.initState();
    checkBluetooth();
  }

  Future<void> checkBluetooth() async {
    final state = await FlutterBluePlus.adapterState.first;

    if (!mounted) return;

    setState(() {
      status = state == BluetoothAdapterState.on
          ? "Bluetooth is ON. Ready to scan."
          : "Please turn ON Bluetooth.";
    });
  }

  // SCAN FOR ESP32
  Future<void> startScan() async {
    try {
      setState(() {
        devices.clear();
        isScanning = true;
        status = "Searching for VAYAN ESP32...";
      });

      scanSubscription?.cancel();

      scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        if (!mounted) return;

        setState(() {
          devices = results.where((result) {
            return result.device.platformName == "VAYAN_ESP32";
          }).toList();
        });
      });

      await FlutterBluePlus.startScan(
        withNames: ["VAYAN_ESP32"],
        timeout: const Duration(seconds: 10),
      );

      if (!mounted) return;

      setState(() {
        isScanning = false;

        if (devices.isEmpty) {
          status = "ESP32 not found. Try scanning again.";
        } else {
          status = "ESP32 found!";
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isScanning = false;
        status = "Scan error: $e";
      });
    }
  }

  // CONNECT TO ESP32
  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      setState(() {
        status = "Connecting to ESP32...";
      });

      await FlutterBluePlus.stopScan();

      await device.connect(license: License.nonprofit);

      connectedDevice = device;

      // Request a larger MTU for JSON notifications.
      try {
        await device.requestMtu(247);
      } catch (_) {
        // Continue if MTU negotiation is unavailable.
      }

      // Discover ESP32 services.
      List<BluetoothService> services = await device.discoverServices();

      for (BluetoothService service in services) {
        if (service.uuid == serviceUUID) {
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            if (characteristic.uuid == characteristicUUID) {
              sensorCharacteristic = characteristic;
            }
          }
        }
      }

      if (sensorCharacteristic == null) {
        throw Exception("VAYAN sensor characteristic not found.");
      }

      // Enable notifications.
      await sensorCharacteristic!.setNotifyValue(true);

      dataSubscription = sensorCharacteristic!.onValueReceived.listen((value) {
        try {
          final receivedText = utf8.decode(value);
          final decodedData = jsonDecode(receivedText);

          if (!mounted) return;

          if (decodedData is Map<String, dynamic>) {
            setState(() {
              sensorData = decodedData;
            });
          }
        } catch (e) {
          debugPrint("Sensor data parsing error: $e");
        }
      });

      if (!mounted) return;

      setState(() {
        isConnected = true;
        status = "Connected to VAYAN ESP32";
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isConnected = false;
        status = "Connection failed: $e";
      });
    }
  }

  // DISCONNECT
  Future<void> disconnectDevice() async {
    await dataSubscription?.cancel();

    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
    }

    if (!mounted) return;

    setState(() {
      isConnected = false;
      connectedDevice = null;
      sensorCharacteristic = null;
      sensorData.clear();
      status = "Disconnected";
    });
  }

  Widget sensorTile(String title, String key) {
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: Text(
          sensorData[key]?.toString() ?? "--",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  @override
  void dispose() {
    scanSubscription?.cancel();
    dataSubscription?.cancel();

    if (connectedDevice != null) {
      connectedDevice!.disconnect();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("VAYAN BLE Test")),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // CONNECTION STATUS
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(
                      isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                      size: 45,
                      color: isConnected ? Colors.green : Colors.blue,
                    ),

                    const SizedBox(height: 10),

                    Text(status, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // SCAN BUTTON
            ElevatedButton(
              onPressed: isScanning || isConnected ? null : startScan,

              child: Text(isScanning ? "Scanning..." : "Scan for ESP32"),
            ),

            const SizedBox(height: 15),

            // AVAILABLE DEVICES
            const Text(
              "Available Devices",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            ...devices.map((result) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.bluetooth),
                  title: Text(result.device.platformName),
                  subtitle: Text(result.device.remoteId.toString()),
                  trailing: ElevatedButton(
                    onPressed: isConnected
                        ? null
                        : () => connectToDevice(result.device),
                    child: const Text("Connect"),
                  ),
                ),
              );
            }),

            const SizedBox(height: 20),

            if (isConnected) ...[
              ElevatedButton(
                onPressed: disconnectDevice,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text("Disconnect"),
              ),

              const SizedBox(height: 20),

              const Text(
                "LIVE MPU6050 DATA",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              sensorTile("Accelerometer X", "accel_x"),
              sensorTile("Accelerometer Y", "accel_y"),
              sensorTile("Accelerometer Z", "accel_z"),

              sensorTile("Gyroscope X", "gyro_x"),
              sensorTile("Gyroscope Y", "gyro_y"),
              sensorTile("Gyroscope Z", "gyro_z"),

              sensorTile("Total Steps", "total_steps"),

              sensorTile("Average Step Interval", "average_step_interval_ms"),

              sensorTile("Attempted Movements", "attempted_movement_count"),

              sensorTile("Direction Changes", "direction_change_count"),

              sensorTile("Status", "status"),
            ],
          ],
        ),
      ),
    );
  }
}
