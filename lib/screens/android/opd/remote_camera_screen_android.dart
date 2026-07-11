import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import '../../../shared/services/sync_service.dart';
import '../../../shared/services/sync_queue_service.dart';
import '../../../shared/services/objectbox_service.dart';
import '../../../shared/models/patient_image.dart';
import '../../../objectbox.g.dart';
import '../../../theme/app_theme.dart';

class RemoteCameraScreenAndroid extends StatefulWidget {
  final String patientUhid;
  final String patientName;
  final String? hubIp; // If came from QR

  const RemoteCameraScreenAndroid({
    super.key,
    required this.patientUhid,
    required this.patientName,
    this.hubIp,
  });

  @override
  State<RemoteCameraScreenAndroid> createState() => _RemoteCameraScreenAndroidState();
}

class _RemoteCameraScreenAndroidState extends State<RemoteCameraScreenAndroid> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInit = false;
  bool _isCapturing = false;
  bool _isUploading = false;
  XFile? _capturedFile;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      _controller = CameraController(
        _cameras.first,
        ResolutionPreset.ultraHigh,
        enableAudio: false,
      );

      await _controller!.initialize();
      if (mounted) setState(() => _isInit = true);
    } catch (e) {
      debugPrint('Error init camera: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) return;

    setState(() => _isCapturing = true);
    try {
      final file = await _controller!.takePicture();
      setState(() {
        _capturedFile = file;
        _isCapturing = false;
      });
    } catch (e) {
      setState(() => _isCapturing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Capture failed: $e')),
      );
    }
  }

  Future<void> _upload() async {
    if (_capturedFile == null || _isUploading) return;

    setState(() => _isUploading = true);
    try {
      final sync = context.read<SyncService>();
      
      // If hubIp was provided (from QR), ensure we are connected to it
      if (widget.hubIp != null && sync.hubIp != widget.hubIp) {
        await sync.connect(widget.hubIp!);
      }

      // Query local patient ID from local ObjectBox database by UHID
      final patientBox = ObjectBoxService.instance.patientBox;
      final localPatient = patientBox.query(Patient_.uhid.equals(widget.patientUhid)).build().findFirst();
      final patientId = localPatient?.id ?? 0;

      // Copy image to a permanent local directory
      final appDocDir = await getApplicationDocumentsDirectory();
      final photoDir = Directory(patientId > 0
          ? '${appDocDir.path}/patient_photos/$patientId'
          : '${appDocDir.path}/patient_photos/temp_${widget.patientUhid}');
      if (!await photoDir.exists()) {
        await photoDir.create(recursive: true);
      }

      final fileName = '${DateTime.now().millisecondsSinceEpoch}_captured.jpg';
      final savedPath = '${photoDir.path}/$fileName';
      await File(_capturedFile!.path).copy(savedPath);

      final photo = PatientImage(
        patientId: patientId,
        imagePath: savedPath,
        category: 'Prescription Capture',
        date: DateTime.now(),
      );

      // Save PatientImage to local database
      ObjectBoxService.instance.patientImageBox.put(photo);

      // Attempt immediate upload
      bool uploadOk = false;
      try {
        uploadOk = await sync.pushPatientPhoto(photo, widget.patientUhid);
      } catch (e) {
        debugPrint('SyncService: Immediate photo upload failed, will queue: $e');
      }

      if (uploadOk) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Upload successful! Hub updated.')),
          );
          Navigator.pop(context);
        }
      } else {
        // Network failed or was slow - add to sync queue for background retry
        SyncQueueService.instance.addToQueue(
          entity: 'photo',
          action: 'create',
          data: {
            'id': photo.id,
            'patientId': patientId,
            'uhid': widget.patientUhid,
          },
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Saved locally! Photo will sync automatically when network is available.'),
              duration: Duration(seconds: 4),
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving photo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview OR Image Preview
          if (_capturedFile != null)
            Positioned.fill(
              child: Image.file(
                File(_capturedFile!.path),
                fit: BoxFit.contain,
              ),
            )
          else if (_isInit && _controller != null)
            Center(
              child: CameraPreview(_controller!),
            )
          else
            const Center(child: CircularProgressIndicator()),

          // Overlay Info
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Remote Camera Mode',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Patient: ${widget.patientName}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
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

          // Bottom Controls
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_capturedFile != null)
                  _buildPreviewControls()
                else
                  _buildCaptureControls(),
              ],
            ),
          ),

          if (_isUploading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Uploading full resolution...', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCaptureControls() {
    return GestureDetector(
      onTap: _takePhoto,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: Center(
          child: Container(
            width: 65,
            height: 65,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Retake
          Column(
            children: [
              IconButton(
                onPressed: () => setState(() => _capturedFile = null),
                icon: const Icon(LucideIcons.refreshCcw, color: Colors.white, size: 32),
              ),
              const Text('Retake', style: TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
          
          // Use Photo (Upload)
          GestureDetector(
            onTap: _upload,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Row(
                children: [
                  Icon(LucideIcons.upload, color: Colors.white),
                  SizedBox(width: 12),
                  Text('SEND TO PC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
