import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

import 'ffi_bindings.dart';
import 'stable_diffusion_processor.dart';
import 'img2img_processor.dart';

// Fixed revision and checksum: a downloaded model is never accepted by size alone.
const modelUrl = 'https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5/resolve/f03de32/v1-5-pruned-emaonly.safetensors?download=true';
const modelSha256 = '6ce0161689b3853acaa03779ec93eafe75a02f4ced659bee03f50797806fa2fa';
const modelName = 'v1-5-pruned-emaonly.safetensors';
const channel = MethodChannel('studio/device');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FFIBindings.initializeBindings('CPU');
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true, brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF101018),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFAE87FF), brightness: Brightness.dark),
    ), home: const Studio()));
}

class Studio extends StatefulWidget {
  const Studio({super.key});
  @override
  State<Studio> createState() => _StudioState();
}

class _StudioState extends State<Studio> {
  final prompt = TextEditingController();
  dynamic engine;
  XFile? reference;
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
        await downloadWithRetries(file);
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
      if (e is SocketException || e is HttpException || e is TimeoutException) {
        update('A ligação foi interrompida. Toque em Preparar modelo para continuar de onde parou.');
      } else {
        update('Preparação interrompida: $e');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> downloadWithRetries(File file) async {
    final partial = File('${file.path}.part');
    var previousSize = await partial.exists() ? await partial.length() : 0;
    var stalled = 0;
    for (var attempt = 1; attempt <= 100; attempt++) {
      try {
        await downloadModel(file);
        return;
      } catch (e) {
        if (e is! SocketException && e is! HttpException && e is! TimeoutException) rethrow;
        final size = await partial.exists() ? await partial.length() : 0;
        stalled = size > previousSize ? 0 : stalled + 1;
        previousSize = size;
        if (stalled >= 8 || attempt == 100) rethrow;
        update('A ligação caiu. A retomar automaticamente…');
        await Future.delayed(Duration(seconds: (attempt * 2).clamp(2, 15).toInt()));
      }
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
      engine = reference == null ? StableDiffusionProcessor(
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
      ) : Img2ImgProcessor(
        modelPath: modelPath!, useFlashAttention: true,
        modelType: SDType.SD_TYPE_Q4_0, schedule: Schedule.DEFAULT,
        vaeTiling: true, isDiffusionModelType: false,
        onLog: (log) {
          if (log.level == -1 && mounted) {
            update('Erro do motor: ${log.message}');
            setState(() => busy = false);
          }
        },
        onProgress: (progress) => update('A editar imagem: ${progress.step}/${progress.totalSteps}'),
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
      final fullPrompt = '$description, adult $character, photographic portrait, realistic lighting';
      if (reference == null) {
        await (engine as StableDiffusionProcessor).generateImage(
          prompt: fullPrompt, negativePrompt: 'child, minor, extra limbs, malformed hands, blurry',
          width: 512, height: 512, sampleSteps: 12, sampleMethod: SampleMethod.EULER_A.index,
        );
      } else {
        final decoded = img.decodeImage(await reference!.readAsBytes());
        if (decoded == null) throw StateError('A foto de referência não pôde ser aberta.');
        final resized = img.copyResize(decoded, width: 512, height: 512);
        final rgb = Uint8List(512 * 512 * 3);
        var index = 0;
        for (var y = 0; y < 512; y++) {
          for (var x = 0; x < 512; x++) {
            final pixel = resized.getPixel(x, y);
            rgb[index++] = pixel.r.toInt();
            rgb[index++] = pixel.g.toInt();
            rgb[index++] = pixel.b.toInt();
          }
        }
        await (engine as Img2ImgProcessor).generateImg2Img(
          inputImageData: rgb, inputWidth: 512, inputHeight: 512, channel: 3,
          outputWidth: 512, outputHeight: 512, prompt: fullPrompt,
          negativePrompt: 'child, minor, extra limbs, malformed hands, blurry',
          sampleSteps: 12, sampleMethod: SampleMethod.EULER_A.index, strength: 0.5,
        );
      }
    } catch (e) {
      update('Falha ao criar imagem: $e');
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickReference() async {
    try {
      final selected = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (selected != null && mounted) setState(() => reference = selected);
    } catch (e) { update('Não foi possível abrir a fotografia: $e'); }
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

  Widget characterCard(String name, String subtitle, Color accent) {
    final selected = character == name;
    return Expanded(child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: busy ? null : () => setState(() => character = name),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.18) : const Color(0xFF1B1B27),
          border: Border.all(color: selected ? accent : const Color(0xFF343341), width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(backgroundColor: accent.withOpacity(0.25), radius: 20,
            child: Text(name.substring(0, 1), style: TextStyle(color: accent, fontWeight: FontWeight.bold))),
          const SizedBox(height: 16),
          Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFFB8B6C8))),
        ]),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(22, 22, 22, 32), children: [
      const Text('GÊNNY & SOPHIE', style: TextStyle(letterSpacing: 2.6, color: Color(0xFFC7B0FF),
        fontSize: 13, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('Studio', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      const Text('Imagina. Descreve. Cria no teu telemóvel.',
        style: TextStyle(fontSize: 14, color: Color(0xFFB8B6C8))),
      const SizedBox(height: 30),
      const Text('Escolhe a personagem', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      Row(children: [
        characterCard('Gênny', 'Olhos verdes', const Color(0xFF9BBEFF)),
        const SizedBox(width: 12),
        characterCard('Sophie', 'Olhos azuis', const Color(0xFFE9A6DA)),
      ]),
      const SizedBox(height: 26),
      const Text('A tua ideia', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      TextField(controller: prompt, maxLines: 4, minLines: 3,
        decoration: InputDecoration(hintText: 'Como queres a fotografia?',
          filled: true, fillColor: const Color(0xFF1B1B27),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFF343341))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFF343341))))),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: busy ? null : pickReference,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(reference == null ? 'Referência' : 'Foto escolhida', overflow: TextOverflow.ellipsis))),
        const SizedBox(width: 10),
        Expanded(child: OutlinedButton.icon(onPressed: busy ? null : voice,
          icon: const Icon(Icons.mic_none), label: const Text('Falar'))),
      ]),
      if (reference != null) Align(alignment: Alignment.centerLeft,
        child: TextButton.icon(onPressed: busy ? null : () => setState(() => reference = null),
          icon: const Icon(Icons.close, size: 16), label: Text(reference!.name,
            maxLines: 1, overflow: TextOverflow.ellipsis))),
      const SizedBox(height: 18),
      SizedBox(height: 56, child: FilledButton.icon(
        onPressed: busy ? null : ready ? generate : prepareModel,
        icon: Icon(ready ? Icons.auto_awesome : Icons.download_outlined),
        label: Text(ready ? 'CRIAR IMAGEM' : 'PREPARAR MODELO',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.6)))),
      const SizedBox(height: 18),
      Container(padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFF1B1B27), borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(busy ? Icons.hourglass_top : ready ? Icons.check_circle_outline : Icons.info_outline,
            size: 18, color: const Color(0xFFC7B0FF)), const SizedBox(width: 10),
            Expanded(child: Text(status, style: const TextStyle(fontSize: 13, height: 1.4)))]),
          if (busy) const Padding(padding: EdgeInsets.only(top: 14), child: LinearProgressIndicator()),
        ])),
      if (lastImage != null) ...[
        const SizedBox(height: 26),
        const Text('A tua criação', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.memory(lastImage!)),
      ],
      const SizedBox(height: 18),
      const Text('O modelo é descarregado uma vez. Depois, as imagens são criadas no telemóvel.',
        textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF898798))),
    ])),
  );
}
