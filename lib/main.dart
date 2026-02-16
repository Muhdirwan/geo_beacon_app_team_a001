import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MaterialApp(
    home: AttendanceScanner(),
    debugShowCheckedModeBanner: false,
  ));
}

class AttendanceScanner extends StatefulWidget {
  const AttendanceScanner({super.key});
  @override
  State<AttendanceScanner> createState() => _AttendanceScannerState();
}

class _AttendanceScannerState extends State<AttendanceScanner> {
  final Map<String, Map<String, dynamic>> _beacons = {};
  bool _isScanning = false;
  final double _attendanceThreshold = 5.0;

  @override
  void initState() {
    super.initState();
    _startEverything();
  }

  // Logic to stop and restart the system
  Future<void> _handleRefresh() async {
    // 1. Stop hardware scan first and WAIT for it to finish
    await FlutterBluePlus.stopScan(); 
    
    // 2. Clear UI and data state
    if (mounted) {
      setState(() {
        _isScanning = false;
        _beacons.clear(); // Clear the attendance list
      });
    }

    // 3. Small "Cooldown" delay (500ms)
    // This gives the Bluetooth antenna time to reset its internal cache
    await Future.delayed(const Duration(milliseconds: 500));

    // 4. Re-run the start sequence with fresh hardware
    await _startEverything(); 
  }

  Future<void> _startEverything() async {
    // 1. Request Permissions
    await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    // 2. Setup the listener
    FlutterBluePlus.onScanResults.listen((List<ScanResult> results) {
      for (ScanResult r in results) {
        _processScanResult(r);
      }
    });

    // 3. Start Scanning (SAFE VERSION: no scanMode parameter)
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(minutes: 5), // Scan for 5 mins
        androidUsesFineLocation: true,
      );
      if (mounted) setState(() => _isScanning = true);
    } catch (e) {
      debugPrint("Error starting scan: $e"); 
    }
  }

  void _processScanResult(ScanResult r) {
    if (r.advertisementData.manufacturerData.containsKey(76)) {
      var data = r.advertisementData.manufacturerData[76]!;
      if (data.length >= 23 && data[0] == 0x02 && data[1] == 0x15) {
        String uuid = data.sublist(2, 18).map((e) => e.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
        int txPower = data[22] - 256; 
        double distanceValue = _calculateDistanceValue(r.rssi, txPower);

        if (mounted) {
          setState(() {
            bool wasAttended = _beacons[r.device.remoteId.str]?['status'] == "Attended";
            bool isClose = distanceValue <= _attendanceThreshold;
            _beacons[r.device.remoteId.str] = {
              'uuid': uuid,
              'distance': distanceValue.toStringAsFixed(2),
              'status': (wasAttended || isClose) ? "Attended" : "Nearby",
            };
          });
        }
      }
    }
  }

  double _calculateDistanceValue(int rssi, int txPower) {
    if (rssi == 0) return 99.0;
    double ratio = rssi * 1.0 / txPower;
    return (ratio < 1.0) ? pow(ratio, 10).toDouble() : (0.89976) * pow(ratio, 7.7095) + 0.111;
  }

  @override
  Widget build(BuildContext context) {
    var beaconList = _beacons.values.toList();
    beaconList.sort((a, b) => b['status'].compareTo(a['status']));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Beacon Attendance"), 
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          // THE REFRESH BUTTON
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Reset Attendance List",
            onPressed: _handleRefresh,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isScanning) const LinearProgressIndicator(color: Colors.orange),
          Expanded(
            child: beaconList.isEmpty
                ? const Center(child: Text("Scanning for beacons...\nTap refresh to reset."))
                : ListView.builder(
                    itemCount: beaconList.length,
                    itemBuilder: (context, i) {
                      final b = beaconList[i];
                      bool isAttended = b['status'] == "Attended";
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        color: isAttended ? Colors.green.shade50 : Colors.white,
                        child: ListTile(
                          leading: Icon(isAttended ? Icons.check_circle : Icons.person_search, 
                                       color: isAttended ? Colors.green : Colors.grey),
                          title: Text("ID: ${b['uuid'].substring(0, 8)}..."),
                          subtitle: Text("Distance: ${b['distance']}m"),
                          trailing: Chip(
                            label: Text(b['status']), 
                            backgroundColor: isAttended ? Colors.green : Colors.orange,
                            labelStyle: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}