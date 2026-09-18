import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'ffi_bindings.dart';
import 'stable_diffusion_processor.dart';

// Fixed revision and checksum: a downloaded model is never accepted by size alone.
const modelUrl = 'https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5/resolve/f03de32/v1-5-pruned-emaonly.safetensors?download=true';
const modelSha256 = '6ce0161689b3853acaa03779ec93eafe75a02f4ced659bee03f50797806fa2fa';
const modelName = 'v1-5-pruned-emaonly.safetensors';
const channel = MethodChannel('studio/device');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FFIBindings.initializeBindings('CPU');
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: Studio()));
}

class Studio extends StatefulWidget {
  const Studio({super.key});
  @override
  State<Studio> createState() => _StudioState();
}

class _StudioState extends State<Studio> {
  final prompt = TextEditingController();
  StableDiffusionProcessor? engine;
  StreamSubscription<Map<String, dynamic>>? resultSubscription;
  String character = 'Gênny';
  String status = 'A preparar o motor local';
  bool busy = false;
  bool ready = false;
  Uint8List? lastImage;
  String? modelPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => prepareModel());
  }

  void update(String message) {
    if (mounted) setState(() => status = message);
  }

  Future<bool> validModel(File file) async {
    if (!await file.exists()) return false;
    if (await file.length() < 2000000000) return false;
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == modelSha256;
  }

  Future<void> prepareModel() async {
    if (busy || ready) return;
    setState(() => busy = true);
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}/$modelName');
      if (!await validModel(file)) {
        if (await file.exists()) await file.delete();
        await downloadModel(file);
        update('A verificar o modelo…');
        if (!await validModel(file)) {
          await file.delete();
          throw StateError('A verificação do modelo falhou. Tente novamente.');
        }
      }
      modelPath = file.path;
      if (mounted) setState(() => ready = true);
      update('Motor preparado. Escreva um comando e toque em Criar.');
    } catch (e) {
      update('Preparação interrompida: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> downloadModel(File file) async {
    final partial = File('${file.path}.part');
    final start = await partial.exists() ? await partial.length() : 0;
    final free = await channel.invokeMethod<int>('freeBytes') ?? 0;
    // The source checkpoint occupies roughly 4.27 GB. Allow for output images.
    if (free < 4700000000 - start) {
      throw StateError('São necessários cerca de 5 GB livres no telemóvel.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(Uri.parse(modelUrl));
      if (start > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-');
      final response = await request.close();
      final append = start > 0 && response.statusCode == HttpStatus.partialContent &&
          response.headers.value(HttpHeaders.contentRangeHeader)?.startsWith('bytes $start-') == true;
      if (response.statusCode != HttpStatus.ok && response.statusCode != HttpStatus.partialContent) {
        throw HttpException('Servidor respondeu ${response.statusCode}');
      }
      if (response.statusCode == HttpStatus.partialContent && !append) {
        throw const HttpException('Retoma inválida do download');
      }
      final total = response.contentLength + (append ? start : 0);
      final sink = partial.openWrite(mode: append ? FileMode.append : FileMode.write);
      var received = append ? start : 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0 && received % 5000000 < chunk.length) {
            update('A descarregar o modelo: ${(100 * received / total).clamp(0, 100).toStringAsFixed(0)}%');
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (total > 0 && received != total) throw const HttpException('Download incompleto');
      await partial.rename(file.path);
    } finally {
      client.close();
    }
  }

  Future<void> generate() async {
    if (busy || !ready || modelPath == null) return;
    final description = prompt.text.trim();
    if (description.isEmpty) { update('Descreva a imagem primeiro.'); return; }
    setState(() { busy = true; lastImage = null; });
    try {
      update('A iniciar o motor no telemóvel…');
      await resultSubscription?.cancel();
      engine?.dispose();
      engine = StableDiffusionProcessor(
        modelPath: modelPath!, useFlashAttention: true,
        modelType: SDType.SD_TYPE_Q4_0, schedule: Schedule.DEFAULT,
        vaeTiling: true, isDiffusionModelType: false,
        onLog: (log) {
          if (log.level == -1 && mounted) {
            update('Erro do motor: ${log.message}');
            setState(() => busy = false);
          }
        },
        onProgress: (progress) => update('A criar imagem: ${progress.step}/${progress.totalSteps}'),
      );
      resultSubscription = engine!.generationResultStream.listen((result) async {
        final image = result['image'] as ui.Image;
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) { update('Falha ao guardar a imagem.'); return; }
        final data = bytes.buffer.asUint8List();
        final directory = await getApplicationDocumentsDirectory();
        final output = File('${directory.path}/studio_${DateTime.now().millisecondsSinceEpoch}.png');
        await output.writeAsBytes(data, flush: true);
        if (mounted) setState(() { lastImage = data; busy = false; status = 'Imagem criada e guardada no aplicativo.'; });
      });
      // This runtime reports model errors via onLog; generation runs in its own isolate.
      await engine!.generateImage(
        prompt: '$description, adult $character, photographic portrait, realistic lighting',
        negativePrompt: 'child, minor, extra limbs, malformed hands, blurry',
        width: 512, height: 512, sampleSteps: 12, sampleMethod: SampleMethod.EULER_A.index,
      );
    } catch (e) {
      update('Falha ao criar imagem: $e');
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> voice() async {
    try {
      final words = await channel.invokeMethod<String>('recognize');
      if (words != null && mounted) prompt.text = words;
    } catch (_) { update('Reconhecimento de voz indisponível neste aparelho.'); }
  }

  @override
  void dispose() {
    prompt.dispose(); resultSubscription?.cancel(); engine?.dispose(); super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Gênny & Sophie Studio')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Criação local no telemóvel. A primeira preparação necessita de internet e espaço livre.'),
      const SizedBox(height: 16),
      SegmentedButton<String>(segments: const [
        ButtonSegment(value: 'Gênny', label: Text('Gênny')),
        ButtonSegment(value: 'Sophie', label: Text('Sophie')),
      ], selected: {character}, onSelectionChanged: busy ? null : (selection) => setState(() => character = selection.first)),
      const SizedBox(height: 16),
      TextField(controller: prompt, maxLines: 4, decoration: const InputDecoration(
        border: OutlineInputBorder(), labelText: 'Descreva a imagem')),
      TextButton.icon(onPressed: busy ? null : voice, icon: const Icon(Icons.mic), label: const Text('Falar comando')),
      FilledButton(onPressed: busy ? null : ready ? generate : prepareModel,
        child: Text(ready ? 'CRIAR IMAGEM' : 'PREPARAR MODELO')),
      const SizedBox(height: 14), Text(status),
      if (busy) const LinearProgressIndicator(),
      if (lastImage != null) Padding(padding: const EdgeInsets.only(top: 20), child: Image.memory(lastImage!)),
    ])),
  );
}
