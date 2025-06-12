import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

// Add the extension here (before the class)
extension ReshapeList on List {
  List reshape(List<int> shape) {
    if (shape.isEmpty) return this;
    if (shape.length == 1) return this;
    
    final totalElements = shape.reduce((a, b) => a * b);
    if (totalElements != length) {
      throw ArgumentError('Total elements mismatch in reshape');
    }
    List result = this;
    for (var i = shape.length - 1; i > 0; i--) {
      final newLength = length ~/ shape[i];
      result = List.generate(newLength, 
          (index) => result.sublist(index * shape[i], (index + 1) * shape[i]));
    }
    
    return result;
  }
}

class FaceService {
  static const String modelPath = 'assets/mobile_face_net.tflite';
  static Interpreter? _interpreter;
  static const double _verificationThreshold = 0.6; // Typical threshold for face verification


  static Future<void> init() async {
    try {
      final options = InterpreterOptions();
      _interpreter = await Interpreter.fromAsset(modelPath, options: options);
      _interpreter!.allocateTensors();
    } catch (e) {
      debugPrint('Initialization error: $e');
      rethrow;
    }
  }

static Future<Float32List> getFaceEmbedding(String imagePath) async {
  if (_interpreter == null) await init();

  try {
    final imageBytes = await File(imagePath).readAsBytes();
    final image = img.decodeImage(imageBytes)!;
    final input = _create4DInputTensor(image);

      // Fix output tensor handling
    final output = ReshapeList(List.filled(128, 0.0)).reshape([1, 128]);
    _interpreter!.run(input, output);
    
  // Convert to Float32List and normalize
    final embedding = Float32List.fromList(output[0]);
    final normalized = normalizeEmbedding(embedding);

    if (normalized.length != 128) {
      throw Exception('Invalid embedding length: ${normalized.length}');
    }

    debugPrint('Embedding type: ${normalized.runtimeType}');
    debugPrint('First 5 values: ${normalized.sublist(0, 5)}');

    return normalized;
  } catch (e) {
    debugPrint('Inference error: $e');
    rethrow;
  }
}


  static List<List<List<List<double>>>> _create4DInputTensor(img.Image image) {
    final processed = img.copyResize(image, width: 112, height: 112);

    return List.generate(
      1,
      (_) => List.generate(
        112,
        (y) => List.generate(112, (x) {
          final pixel = processed.getPixel(x, y);
          return [
            (pixel.r - 128) * 0.0078125,
            (pixel.g - 128) * 0.0078125,
            (pixel.b - 128) * 0.0078125,
          ];
        }),
      ),
    );
  }

    static Float32List normalizeEmbedding(Float32List embedding) {
    // Calculate vector length
    double sum = 0.0;
    for (final value in embedding) {
      sum += value * value;
    }
    final length = sqrt(sum);

    // Normalize to unit vector
    return Float32List.fromList(
      embedding.map((v) => v / length).toList()
    );
  }
  
  static bool verifyFace(Float32List storedEmbedding, Float32List currentEmbedding) {
    if (storedEmbedding.length != 128 || currentEmbedding.length != 128) {
      throw Exception('Invalid embedding dimensions');
    }
    
    // Calculate cosine similarity
    double similarity = 0.0;
    for (int i = 0; i < 128; i++) {
      similarity += storedEmbedding[i] * currentEmbedding[i];
    }
      // Ensure similarity is within valid range [-1, 1]
 // similarity = similarity.clamp(-1.0, 1.0);
  
    debugPrint('Face similarity score: $similarity');
    
    // Return true if similarity is above threshold
    return similarity >= _verificationThreshold;
  }
}
