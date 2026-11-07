import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  // VAYAN BLE identifiers.
  // These same UUIDs must be used in the ESP32 firmware.
  static final Guid serviceUuid = Guid("12345678-1234-1234-1234-1234567890AB");

  static final Guid characteristicUuid = Guid(
    "ABCD1234-5678-1234-1234-1234567890AB",
  );

  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? dataCharacteristic;

  StreamSubscription<List<ScanResult>>? scanSubscription;
  StreamSubscription<List<int>>? dataSubscription;
  StreamSubscription<BluetoothConnectionState>? connectionSubscription;

  final StreamController<Map<String, dynamic>> _dataController =
      StreamController<Map<String, dynamic>>.broadcast();

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Stream<Map<String, dynamic>> get sensorDataStream => _dataController.stream;

  Stream<bool> get connectionStream => _connectionController.stream;

  bool get isConnected => connectedDevice != null;

  // Scan for the VAYAN ESP32.
  Future<void> scanAndConnect() async {
    try {
      await FlutterBluePlus.stopScan();

      await scanSubscription?.cancel();

      scanSubscription = FlutterBluePlus.onScanResults.listen(
        (results) async {
          for (final result in results) {
            final name = result.advertisementData.advName;

            if (name == "VAYAN_ESP32") {
              await FlutterBluePlus.stopScan();

              await connectToDevice(result.device);
              break;
            }
          }
        },
        onError: (error) {
          debugPrint("BLE scan error: $error");
        },
      );

      FlutterBluePlus.cancelWhenScanComplete(scanSubscription!);

      await FlutterBluePlus.startScan(
        withNames: ["VAYAN_ESP32"],
        timeout: const Duration(seconds: 15),
      );
    } catch (error) {
      debugPrint("Could not start BLE scan: $error");
      rethrow;
    }
  }

  // Connect to ESP32.
  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      connectedDevice = device;

      connectionSubscription?.cancel();

      connectionSubscription = device.connectionState.listen((state) {
        final connected = state == BluetoothConnectionState.connected;

        _connectionController.add(connected);

        if (!connected) {
          dataCharacteristic = null;
        }
      });

      device.cancelWhenDisconnected(
        connectionSubscription!,
        delayed: true,
        next: true,
      );

      await device.connect(license: License.nonprofit);

      // Discover ESP32 BLE services.
      final services = await device.discoverServices();

      for (final service in services) {
        if (service.uuid == serviceUuid) {
          for (final characteristic in service.characteristics) {
            if (characteristic.uuid == characteristicUuid) {
              dataCharacteristic = characteristic;

              await enableNotifications(characteristic);
              return;
            }
          }
        }
      }

      throw Exception("VAYAN BLE characteristic not found on ESP32.");
    } catch (error) {
      debugPrint("BLE connection error: $error");
      _connectionController.add(false);
      rethrow;
    }
  }

  // Receive sensor readings from ESP32.
  Future<void> enableNotifications(
    BluetoothCharacteristic characteristic,
  ) async {
    await dataSubscription?.cancel();

    dataSubscription = characteristic.onValueReceived.listen(
      (value) {
        try {
          final receivedText = utf8.decode(value);

          final Map<String, dynamic> sensorData = jsonDecode(receivedText);

          _dataController.add(sensorData);
        } catch (error) {
          debugPrint("Could not decode sensor data: $error");
          debugPrint("Received bytes: $value");
        }
      },
      onError: (error) {
        debugPrint("BLE data reception error: $error");
      },
    );

    connectedDevice?.cancelWhenDisconnected(dataSubscription!);

    await characteristic.setNotifyValue(true);
  }

  // Disconnect from ESP32.
  Future<void> disconnect() async {
    try {
      await FlutterBluePlus.stopScan();

      await dataSubscription?.cancel();
      await connectionSubscription?.cancel();

      await connectedDevice?.disconnect();

      connectedDevice = null;
      dataCharacteristic = null;

      _connectionController.add(false);
    } catch (error) {
      debugPrint("BLE disconnect error: $error");
    }
  }

  // Release resources.
  Future<void> dispose() async {
    await disconnect();
    await scanSubscription?.cancel();

    await _dataController.close();
    await _connectionController.close();
  }
}
