import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf_text/pdf_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Booked Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Booked Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String extractedText = "No text extracted yet.";
  TextEditingController _textEditingController = TextEditingController();
  FlutterTts flutterTts = FlutterTts();
  stt.SpeechToText _speech = stt.SpeechToText();
  bool isListening = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() {});
    }
  }

  Future<void> pickAndExtractText() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        String filePath = result.files.single.path!;

        PDFDoc doc = await PDFDoc.fromPath(filePath);

        String text = await doc.text;

        setState(() {
          extractedText = text;
          _textEditingController.text = text;
        });
      }
    } catch (e) {
      setState(() {
        extractedText = "Failed to extract text: $e";
        _textEditingController.text = "Failed to extract text: $e";
      });
    }
  }

  // Speaking function that skips lines marked with { }
  Future<void> speak() async {
    List<String> lines = _textEditingController.text.split('\n');
    for (String line in lines) {
      if (!line.contains(RegExp(r'{.*}'))) { // Skip marked lines
        await flutterTts.speak(line);
        await Future.delayed(Duration(seconds: 1));
      } else {
        // Wait for user input
        await _waitForUserInput();
      }
    }
  }

  // Wait for the user to speak or press a button
  Future<void> _waitForUserInput() async {
    setState(() {
      isListening = true;
    });
    
    // Start listening for user's input
    await _startListening();

    setState(() {
      isListening = false;
    });
  }

  Future<void> _startListening() async {
    await _speech.listen(
      onResult: (result) {
        if (result.recognizedWords.isNotEmpty) {
          // Stop listening once we detect any speech
          _speech.stop();
        }
      },
    );
    await Future.delayed(Duration(seconds: 10)); // Timeout
    _speech.stop();
  }

  // UI Components
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: TextField(
                  controller: _textEditingController,
                  maxLines: null,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'No text extracted yet.',
                  ),
                ),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: speak,
              child: Text("Speak Text"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TeleprompterScreen(
                      text: _textEditingController.text,
                    ),
                  ),
                );
              },
              child: Text("Open Teleprompter"),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: pickAndExtractText,
        tooltip: 'Pick PDF',
        child: const Icon(Icons.picture_as_pdf),
      ),
    );
  }
}

// Teleprompter screen with scrolling and highlighting
class TeleprompterScreen extends StatefulWidget {
  final String text;

  TeleprompterScreen({required this.text});

  @override
  _TeleprompterScreenState createState() => _TeleprompterScreenState();
}

class _TeleprompterScreenState extends State<TeleprompterScreen> {
  int currentLineIndex = 0;
  ScrollController _scrollController = ScrollController();
  List<String> lines = [];
  FlutterTts flutterTts = FlutterTts();
  stt.SpeechToText _speech = stt.SpeechToText();
  bool isListening = false;
  bool ttsSpeaking = false;
  
  // Initial font size
  double _fontSize = 20.0;

  @override
  void initState() {
    super.initState();
    lines = widget.text.split('\n'); // Split the input text into lines
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() {});
    }
  }

  // Highlight the current line and move to the next line when needed
  void highlightNextLine() async {
    if (currentLineIndex < lines.length) {
      String line = lines[currentLineIndex];

      if (line.contains(RegExp(r'\[.*\]'))) {
        // User needs to say this line
        await _waitForUserToSpeak(line);
      } else {
        // TTS speaks this line
        await _speakLine(line);
      }

      setState(() {
        if (currentLineIndex < lines.length - 1) {
          currentLineIndex++;
          _scrollController.animateTo(
            currentLineIndex * 40.0, // Adjust based on line height
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  // Speak the line using TTS
  Future<void> _speakLine(String line) async {
    ttsSpeaking = true;
    await flutterTts.speak(line);
    await flutterTts.awaitSpeakCompletion(true); // Wait until TTS finishes
    ttsSpeaking = false;
  }

  // Wait for the user to speak the line
  Future<void> _waitForUserToSpeak(String line) async {
    String lineWithoutBrackets = line.replaceAll(RegExp(r'[\[\]]'), ''); // Remove the square brackets
    setState(() {
      isListening = true;
    });

    await _speech.listen(onResult: (result) {
      if (result.recognizedWords.toLowerCase() == lineWithoutBrackets.toLowerCase()) {
        // User spoke the correct line
        _speech.stop();
      }
    });

    // Timeout in case user doesn't speak within 10 seconds
    await Future.delayed(Duration(seconds: 10));
    _speech.stop();

    setState(() {
      isListening = false;
    });
  }

  // Increase font size
  void _increaseFontSize() {
    setState(() {
      _fontSize += 2.0; // Increase by 2 points
    });
  }

  // Decrease font size
  void _decreaseFontSize() {
    setState(() {
      if (_fontSize > 10) _fontSize -= 2.0; // Decrease by 2 points but ensure it doesn't go below 10
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Teleprompter')),
      body: Stack(
        children: [
          // Teleprompter content
          Positioned.fill(
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: lines.length,
                    itemBuilder: (context, index) {
                      return Container(
                        padding: EdgeInsets.all(8.0),
                        color: index == currentLineIndex ? Colors.yellow : Colors.white,
                        child: Text(
                          lines[index],
                          style: TextStyle(fontSize: _fontSize),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          
          // Floating Action Buttons for font size control
          Positioned(
            right: 16,
            bottom: 100,
            child: Column(
              children: [
                // Increase font size button
                FloatingActionButton(
                  heroTag: 'increase_font',
                  onPressed: _increaseFontSize,
                  child: Icon(Icons.add),
                ),
                SizedBox(height: 16), // Spacing between buttons
                // Decrease font size button
                FloatingActionButton(
                  heroTag: 'decrease_font',
                  onPressed: _decreaseFontSize,
                  child: Icon(Icons.remove),
                ),
              ],
            ),
          ),
          
          // Play button for highlighting and scrolling
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'play',
              onPressed: highlightNextLine, // Start highlighting the lines
              child: Icon(Icons.play_arrow),
            ),
          ),
        ],
      ),
    );
  }
}
