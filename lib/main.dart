import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:dart_openai/dart_openai.dart';

// For the testing purposes, you should probably use https://pub.dev/packages/uuid.
String randomString() {
  final random = Random.secure();
  final values = List<int>.generate(16, (i) => random.nextInt(255));
  return base64UrlEncode(values);
}

void main() {
  OpenAI.apiKey = "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";
  OpenAI.requestsTimeOut = Duration(seconds: 120);
  OpenAI.baseUrl = "https://openrouter.ai/api";
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

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Chat(
          messages: _messages,
          onSendPressed: _handleSendPressed,
          user: _user,
        ),
      );

  void _addMessage(types.Message message) {
    setState(() {
      _messages.insert(0, message);
    });
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
    final SystemMessage = OpenAIChatCompletionChoiceMessageModel(
      content: [
        OpenAIChatCompletionChoiceMessageContentItemModel.text(
          "Answer in Spanish.",
        ),
      ],
      role: OpenAIChatMessageRole.assistant,
    );
    final userMessage = OpenAIChatCompletionChoiceMessageModel(
      content: [
        OpenAIChatCompletionChoiceMessageContentItemModel.text(
          text,
        ),
      ],
      role: OpenAIChatMessageRole.user,
    );
    final chatStream = OpenAI.instance.chat.createStream(
      model: "deepseek/deepseek-r1-zero:free",
      messages: [
        SystemMessage,
        userMessage,
      ],
    );
    print("receiving response");
    String response = "";
    chatStream.listen(
      (streamChatCompletion) {
        final content = streamChatCompletion.choices.first.delta.content;
        final String tmp =(content.toString());
        response = response + tmp.substring(69, tmp.length-2);
        print(response);
      },
      onDone: () {
        print("done.");
        print(_messages);
        _addMessage(
          types.TextMessage(
            author: _ai,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            id: randomString(),
            text: response.substring(7, response.length-1),
          )
        );
      }
    );
  }
}