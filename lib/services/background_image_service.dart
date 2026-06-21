import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

// Handles copying a user-picked gallery photo into the app's own permanent
// storage directory, so the note/folder background survives even if the
// original photo is later deleted or moved on the user's device.
//
// Background paths are stored using a simple prefix scheme:
//   "asset:assets/backgrounds/dusty_blue.jpg"  -> bundled preset, load via Image.asset
//   "file:/data/.../app_flutter/backgrounds/abc123.jpg" -> user upload, load via Image.file
class BackgroundImageService {
  BackgroundImageService._();
  static final BackgroundImageService instance = BackgroundImageService._();

  final ImagePicker _picker = ImagePicker();

  // Opens the device photo gallery, copies the chosen image into a
  // dedicated "backgrounds" folder inside app storage, and returns the
  // "file:" prefixed path to store on the Note/Category. Returns null if
  // the user cancelled the picker.
  Future<String?> pickAndStoreFromGallery() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80, // re-compress on the way in, keeps Hive box lean
    );
    if (picked == null) return null;

    final appDir = await getApplicationDocumentsDirectory();
    final backgroundsDir = Directory('${appDir.path}/backgrounds');
    if (!await backgroundsDir.exists()) {
      await backgroundsDir.create(recursive: true);
    }

    final ext = picked.path.split('.').last;
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';
    final savedPath = '${backgroundsDir.path}/$fileName';

    await File(picked.path).copy(savedPath);

    return 'file:$savedPath';
  }

  // Deletes a previously stored user-uploaded background file from disk.
  // Safe to call on a preset ("asset:...") path — it's a no-op in that case.
  Future<void> deleteIfUserUpload(String? backgroundImagePath) async {
    if (backgroundImagePath == null || !backgroundImagePath.startsWith('file:')) {
      return;
    }
    final path = backgroundImagePath.substring('file:'.length);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}