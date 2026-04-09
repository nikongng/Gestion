import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

/// Sur le web, `image_picker` avec compression ne ouvre souvent pas le dialogue fichiers
/// (Chrome). `file_picker` + `<input type="file">` est fiable.
Future<XFile?> pickProfileImageFile() async {
  if (kIsWeb) {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.single;
    final bytes = f.bytes;
    if (bytes == null) return null;
    final name = f.name.isNotEmpty ? f.name : 'image.jpg';
    return XFile.fromData(bytes, name: name);
  }

  return ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 88,
  );
}
