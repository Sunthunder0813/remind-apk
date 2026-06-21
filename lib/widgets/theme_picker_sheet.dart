import 'package:flutter/material.dart';
import '../services/background_image_service.dart';

// The 12 bundled preset backgrounds, stored in assets/backgrounds/.
// Display names are just the filename with underscores swapped for
// spaces and title-cased, purely for the tooltip/accessibility label.
const List<String> kPresetBackgroundFiles = [
  'dusty_blue',
  'sage_grain',
  'terracotta_wash',
  'lavender_blur',
  'cream_paper',
  'charcoal_dots',
  'blush_gradient',
  'mustard_lines',
  'teal_blur',
  'coral_wash',
  'stone_grain',
  'plum_gradient',
];

String _presetAssetPath(String fileName) => 'assets/backgrounds/$fileName.jpg';

String _presetLabel(String fileName) => fileName
    .split('_')
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');

// Bottom sheet shown when the user wants to set/change a background image
// for one or more selected notes/folders. Returns the chosen background
// path string (already prefixed with "asset:" or "file:"), or null if the
// user picked "Remove background" or dismissed without choosing.
//
// Usage:
//   final result = await showThemePickerSheet(context);
//   if (result != null) { ... apply result.backgroundPath to selection ... }
class ThemePickerResult {
  final String? backgroundPath; // null means "remove background"
  const ThemePickerResult(this.backgroundPath);
}

Future<ThemePickerResult?> showThemePickerSheet(
  BuildContext context, {
  bool showRemoveOption = false,
}) {
  return showModalBottomSheet<ThemePickerResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF2C2831),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _ThemePickerSheetContent(showRemoveOption: showRemoveOption),
  );
}

class _ThemePickerSheetContent extends StatefulWidget {
  final bool showRemoveOption;
  const _ThemePickerSheetContent({required this.showRemoveOption});

  @override
  State<_ThemePickerSheetContent> createState() => _ThemePickerSheetContentState();
}

class _ThemePickerSheetContentState extends State<_ThemePickerSheetContent> {
  bool _isUploading = false;

  Future<void> _pickFromGallery() async {
    setState(() => _isUploading = true);
    final path = await BackgroundImageService.instance.pickAndStoreFromGallery();
    if (!mounted) return;
    setState(() => _isUploading = false);
    if (path != null) {
      Navigator.pop(context, ThemePickerResult(path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Choose a Background',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),

            // Upload from gallery tile
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _isUploading ? null : _pickFromGallery,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF3C3541),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    _isUploading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          )
                        : Icon(Icons.add_photo_alternate_outlined, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      _isUploading ? 'Uploading...' : 'Upload your own photo',
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),
            Text(
              'PRESETS',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: Colors.white.withOpacity(0.4),
              ),
            ),
            const SizedBox(height: 10),

            SizedBox(
              height: 280,
              child: GridView.builder(
                physics: const BouncingScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.75,
                ),
                itemCount: kPresetBackgroundFiles.length,
                itemBuilder: (context, index) {
                  final fileName = kPresetBackgroundFiles[index];
                  final assetPath = _presetAssetPath(fileName);
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(
                      context,
                      ThemePickerResult('asset:$assetPath'),
                    ),
                    child: Tooltip(
                      message: _presetLabel(fileName),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          assetPath,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) => Container(
                            color: Colors.white10,
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image_outlined,
                                size: 18, color: Colors.white30),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            if (widget.showRemoveOption) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => Navigator.pop(context, const ThemePickerResult(null)),
                  icon: const Icon(Icons.layers_clear_outlined, color: Colors.redAccent),
                  label: const Text(
                    'Remove background',
                    style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
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