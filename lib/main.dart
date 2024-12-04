import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() {
  runApp(const GenerativeAIApp());
}

// Main Application Widget
class GenerativeAIApp extends StatelessWidget {
  const GenerativeAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VyAI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: const Color.fromARGB(255, 171, 222, 244),
        ),
        useMaterial3: true,
      ),
      home: const ChatScreen(title: 'Victor\'s AI'),
    );
  }
}

// Chat Screen Widget
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.title});
  final String title;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: const ChatWidget(apiKey: String.fromEnvironment('API_KEY')),
    );
  }
}

// Chat Widget
class ChatWidget extends StatefulWidget {
  const ChatWidget({required this.apiKey, super.key});
  final String apiKey;

  @override
  State<ChatWidget> createState() => _ChatWidgetState();
}

class _ChatWidgetState extends State<ChatWidget> {
  late final GenerativeModel _model;
  late final ChatSession _chat;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFieldFocus = FocusNode();
  final List<({Image? image, String? text, bool fromUser})> _generatedContent = [];
  bool _loading = false;

  final String _promptTemplate = "You're a witty AI who loves to make people laugh. Be humorous and playful in your responses:";

  @override
  void initState() {
    super.initState();
    _model = GenerativeModel(
      model: 'gemini-1.5-pro',
      apiKey: widget.apiKey,
    );
    _chat = _model.startChat();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 750),
        curve: Curves.easeOutCirc,
      ),
    );
  }

  Future<void> _sendChatMessage(String message) async {
    if (message.trim().isEmpty) return;

    setState(() {
      _loading = true;
      _generatedContent.add((image: null, text: message, fromUser: true));
    });

    try {
      final response = await _chat.sendMessage(
        Content.text('$_promptTemplate $message'),
      );
      final text = response.text;

      if (text != null) {
        setState(() {
          _generatedContent.add((image: null, text: text, fromUser: false));
        });
      } else {
        _showError('No response from API.');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() {
        _loading = false;
        _textController.clear();
        _textFieldFocus.requestFocus();
      });
      _scrollDown();
    }
  }

  Future<void> _sendImagePrompt(String message) async {
    if (message.trim().isEmpty) return;

    setState(() {
      _loading = true;
    });

    try {
      final content = [
        Content.multi([
          TextPart('$_promptTemplate $message'),
          DataPart(
            'image/jpeg',
            (await rootBundle.load('assets/images/example.jpg')).buffer.asUint8List(),
          ),
        ])
      ];

      final response = await _model.generateContent(content);
      final text = response.text;

      if (text != null) {
        setState(() {
          _generatedContent.add((image: null, text: text, fromUser: false));
        });
      } else {
        _showError('No response from API.');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() {
        _loading = false;
        _textController.clear();
      });
      _scrollDown();
    }
  }

  Future<void> _playTextToSpeech(String text) async {
    final player = AudioPlayer();
    try {
      final response = await http.post(
        Uri.parse('https://api.elevenlabs.io/v1/text-to-speech'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${String.fromEnvironment('ELEVEN_LABS_API_KEY')}',
        },
        body: json.encode({'text': text}),
      );

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        await player.setAudioSource(MyCustomSource(bytes));
        await player.play();
      } else {
        _showError('TTS API failed: ${response.body}');
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _showError(String message) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Something went wrong'),
          content: SingleChildScrollView(
            child: SelectableText(message),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _generatedContent.length,
              itemBuilder: (context, index) {
                final content = _generatedContent[index];
                return MessageWidget(
                  text: content.text,
                  image: content.image,
                  isFromUser: content.fromUser,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    focusNode: _textFieldFocus,
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Enter a prompt...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                    ),
                    onSubmitted: _sendChatMessage,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _sendChatMessage(_textController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Message Widget
class MessageWidget extends StatelessWidget {
  const MessageWidget({this.image, this.text, required this.isFromUser, super.key});
  final Image? image;
  final String? text;
  final bool isFromUser;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: isFromUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (image != null) image! else _buildTextMessage(context),
      ],
    );
  }

  Widget _buildTextMessage(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isFromUser
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.secondary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: MarkdownBody(data: text ?? ''),
    );
  }
}

// Custom Audio Source
class MyCustomSource extends StreamAudioSource {
  final List<int> bytes;
  MyCustomSource(this.bytes);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= bytes.length;
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(bytes.sublist(start, end)),
      contentType: 'audio/mpeg',
    );
  }
}
