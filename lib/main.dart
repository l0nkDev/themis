import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:http/http.dart' as http;
import 'tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

// For the testing purposes, you should probably use https://pub.dev/packages/uuid.
String randomString() {
  final random = Random.secure();
  final values = List<int>.generate(16, (i) => random.nextInt(255));
  return base64UrlEncode(values);
}


void main() async{
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: MyHomePage(),
      );
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final List<types.Message> _messages = [];
  final _user = const types.User(id: '82091008-a484-4a89-ae75-a22bf8d6f3ac');
  final _ai = const types.User(id: '82091008-a586-4a89-ae75-a22bf8d6f3ac');
  late Tts tts = Tts();
  
  late TextEditingController _ip = TextEditingController();
  late TextEditingController _model = TextEditingController();

  stt.SpeechToText _speechToText = stt.SpeechToText();
  bool speechEnabled = false;
  String _responseContent = "";
  String _lastWords = '';

  @override
  initState() {
    super.initState();
    tts.init();
    _initSpeech();
    _ip.value = TextEditingValue(text: "10.0.2.2:5000");
    _model.value = TextEditingValue(text: "deepseek-r1:7b");
  }

    void changedLanguageDropDownItem(String? selectedType) {
    setState(() {
      tts.language = selectedType;
      tts.setLanguage(tts.language!);
      if (tts.isAndroid) {
        tts
            .isLanguageInstalled(tts.language!)
            .then((value) => tts.isCurrentLanguageInstalled = (value as bool));
      }
    });
  }

  void _initSpeech() async {
    speechEnabled = await _speechToText.initialize();
    setState(() {});
  }

    void _startListening() async {
    await _speechToText.listen(onResult: _onSpeechResult, partialResults: false, localeId: "es_ES");
    setState(() {});
  }

    void _stopListening() async {
    await _speechToText.stop();
    setState(() {});
  }

    void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      _lastWords = result.recognizedWords;
    });
    final textMessage = types.TextMessage(
      author: _user,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: randomString(),
      text: _lastWords,
    );
    _addMessage(textMessage);
    makeRequest(_lastWords);
  }

  @override
  void dispose() {
    super.dispose();
    tts.stop();
  }


  @override
  Widget build(BuildContext context) => Scaffold(
        body: Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: 
                    TextField(
                      controller: _ip,
                      decoration: 
                        InputDecoration(
                          border: OutlineInputBorder()
                        ),
                    )
                  ),
                  Expanded(
                    child: 
                      TextField(
                        controller: _model,
                        decoration: 
                          InputDecoration(
                            border: OutlineInputBorder()
                          ),
                      )
                    ),
                ],
              ),
              Expanded(
                child: Chat(
                  messages: _messages,
                  onSendPressed: _handleSendPressed,
                  user: _user,
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed:
              // If not yet listening for speech start, otherwise stop
              _speechToText.isNotListening ? _startListening : _stopListening,
          tooltip: 'Listen',
          child: Icon(_speechToText.isNotListening ? Icons.mic_off : Icons.mic),
        )
  );

  void _addMessage(types.Message message) {
    setState(() {
      _messages.insert(0, message);
    });
  }

  void _addAnswer(String answer) {
    _addMessage(
      types.TextMessage(
        author: _ai,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        id: randomString(),
        text: answer,
      )
    );
  }

  void _handleSendPressed(types.PartialText message) {
    final textMessage = types.TextMessage(
      author: _user,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: randomString(),
      text: message.text,
    );
    print("button pressed!");
    _addMessage(textMessage);
    makeRequest(message.text);
  }

  Future<void> makeRequest(String text) async {
    print("sending '${text}' as request...");
    print("receiving response");

    Map<String,String> headers = {
      'Content-type' : 'application/json', 
      'Accept': 'application/json',
    };

    _addAnswer("Cargando...");

    var response = await http.post(Uri.http(_ip.text, 'api/chat'), 
    headers: headers,
    body: 
    '''
      {
        "model": "${_model.text}",
        "messages": [
          {
            "role": "system",
            "content": "Answer in Spanish. Absolutely under no circumstance use English in your answer."
          },
          {
            "role": "user",
            "content": "$text"
          }
        ],
        "prompt": "$text",
        "stream": false
      }
    '''
    );
    print(response.body);
    var decodedResponse = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    String res = decodedResponse['message']['content'].split('</think>')[0].substring(2);
    _addAnswer(res);
    _messages.removeAt(1);
    tts.newVoiceText = res;
    changedLanguageDropDownItem("es_ES");
    tts.run();
  }

  void _streamedResponseListen(List<int> stream) {
    var json = jsonDecode(utf8.decode(stream)) as Map;
    _responseContent += json['message']['content'];
    print(_responseContent);
  }

  void _streamedResponseOnDone() {
    _responseContent = _responseContent.split('</think>')[1].substring(2);
    _addAnswer(_responseContent);
    _messages.removeAt(1);
    tts.newVoiceText = _responseContent;
    tts.run();
  }
}