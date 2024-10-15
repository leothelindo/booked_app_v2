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

class _TeleprompterScreenState extends State<TeleprompterScreen> with SingleTickerProviderStateMixin {
  int currentLineIndex = 0;
  late ScrollController _scrollController;
  List<String> lines = [];
  FlutterTts flutterTts = FlutterTts();
  stt.SpeechToText _speech = stt.SpeechToText();
  bool isListening = false;
  bool ttsSpeaking = false;
  double _fontSize = 20.0;
  bool isPlaying = false;
  bool isCompleted = false;
  String recordedText = '';
  late AnimationController _scrollAnimationController;
  late Animation<double> _scrollAnimation;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    lines = widget.text.split('\n');
    _initSpeech();
    _initTts();
    _initScrollAnimation();
  }

  void _initScrollAnimation() {
    _scrollAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _scrollAnimation = CurvedAnimation(
      parent: _scrollAnimationController,
      curve: Curves.easeInOut,
    );
  }

  Future<void> _initSpeech() async {
    await _speech.initialize();
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    flutterTts.setCompletionHandler(() {
      if (isPlaying) {
        _moveToNextLine();
      }
    });
  }

  void _togglePlayPauseRestart() {
    if (isCompleted) {
      _restart();
    } else {
      setState(() {
        isPlaying = !isPlaying;
      });
      if (isPlaying) {
        _processCurrentLine();
      } else {
        flutterTts.stop();
        _speech.stop();
      }
    }
  }

  void _restart() {
    setState(() {
      currentLineIndex = 0;
      isPlaying = true;
      isCompleted = false;
      recordedText = '';
    });
    _scrollToCurrentLine(animate: false);
    _processCurrentLine();
  }

  void _processCurrentLine() async {
    if (currentLineIndex >= lines.length) {
      setState(() {
        isPlaying = false;
        isCompleted = true;
      });
      return;
    }

    String line = lines[currentLineIndex];

    if (line.contains(RegExp(r'\[.*\]'))) {
      await _waitForUserToSpeak(line);
    } else {
      await _speakLine(line);
    }
  }

  Future<void> _speakLine(String line) async {
    if (!isPlaying) return;
    await flutterTts.speak(line);
  }

  Future<void> _waitForUserToSpeak(String line) async {
    if (!isPlaying) return;
    String lineWithoutBrackets = line.replaceAll(RegExp(r'[\[\]]'), '');
    setState(() {
      isListening = true;
      recordedText = '';
    });

    bool recognized = false;
    await _speech.listen(
      onResult: (result) {
        setState(() {
          recordedText = result.recognizedWords;
        });
        _updateScrollPosition(result.recognizedWords, lineWithoutBrackets);
        if (result.finalResult) {
          if (_isCloseEnough(result.recognizedWords, lineWithoutBrackets)) {
            recognized = true;
            _speech.stop();
            _moveToNextLine();
          }
        }
      },
    );

    await Future.delayed(Duration(seconds: 5));
    if (isListening && !recognized) {
      _speech.stop();
      setState(() {
        isListening = false;
      });
    }
  }

  void _updateScrollPosition(String spoken, String expected) {
    double progress = _calculateProgress(spoken, expected);
    double targetScroll = currentLineIndex * (_fontSize * 2) + ((_fontSize * 2) * progress);
    _scrollController.animateTo(
      targetScroll,
      duration: Duration(milliseconds: 100),
      curve: Curves.easeInOut,
    );
  }

  double _calculateProgress(String spoken, String expected) {
    List<String> spokenWords = spoken.toLowerCase().split(' ');
    List<String> expectedWords = expected.toLowerCase().split(' ');
    int matchingWords = spokenWords.where((word) => expectedWords.contains(word)).length;
    return (matchingWords / expectedWords.length).clamp(0.0, 1.0);
  }

  bool _isCloseEnough(String spoken, String expected) {
    String cleanSpoken = spoken.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    String cleanExpected = expected.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');

    List<String> spokenWords = cleanSpoken.split(' ');
    List<String> expectedWords = cleanExpected.split(' ');

    int matchingWords = spokenWords.where((word) => expectedWords.contains(word)).length;

    return matchingWords >= (expectedWords.length * 0.7);
  }

  void _moveToNextLine() {
    if (!isPlaying) return;
    setState(() {
      if (currentLineIndex < lines.length - 1) {
        currentLineIndex++;
        _scrollToCurrentLine();
      } else {
        isPlaying = false;
        isCompleted = true;
      }
    });
    if (isPlaying) {
      _processCurrentLine();
    }
  }

  void _scrollToCurrentLine({bool animate = true}) {
    double targetScroll = currentLineIndex * (_fontSize * 2);
    if (animate) {
      _scrollAnimationController.reset();
      _scrollAnimation = Tween<double>(
        begin: _scrollController.offset,
        end: targetScroll,
      ).animate(_scrollAnimationController);
      _scrollAnimationController.forward();
      _scrollAnimation.addListener(() {
        _scrollController.jumpTo(_scrollAnimation.value);
      });
    } else {
      _scrollController.jumpTo(targetScroll);
    }
  }

  void _changeFontSize(double delta) {
    setState(() {
      _fontSize = (_fontSize + delta).clamp(10.0, 40.0);
      _scrollToCurrentLine();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Teleprompter Demo')),
      body: Stack(
        children: [
          Positioned.fill(
            child: ClipRect(
              child: CustomPaint(
                painter: FadeOutPainter(),
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: lines.length,
                  itemBuilder: (context, index) {
                    return Container(
                      padding: EdgeInsets.all(8.0),
                      color: index == currentLineIndex ? Colors.yellow.withOpacity(0.3) : Colors.transparent,
                      child: Text(
                        lines[index],
                        style: TextStyle(fontSize: _fontSize),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 100,
            child: Column(
              children: [
                FloatingActionButton(
                  heroTag: 'increase_font',
                  onPressed: () => _changeFontSize(2.0),
                  child: Icon(Icons.add),
                ),
                SizedBox(height: 16),
                FloatingActionButton(
                  heroTag: 'decrease_font',
                  onPressed: () => _changeFontSize(-2.0),
                  child: Icon(Icons.remove),
                ),
              ],
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'play_pause_restart',
              onPressed: _togglePlayPauseRestart,
              child: Icon(isCompleted ? Icons.replay : (isPlaying ? Icons.pause : Icons.play_arrow)),
            ),
          ),
          if (isListening)
            Positioned(
              left: 128,
              bottom: 16,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.7,
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Listening...',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      recordedText,
                      style: TextStyle(color: Colors.white),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            left: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'next_line',
              onPressed: () {
                if (isListening) {
                  _speech.stop();
                }
                _moveToNextLine();
              },
              child: Icon(Icons.skip_next),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _scrollAnimationController.dispose();
    flutterTts.stop();
    _speech.stop();
    super.dispose();
  }
}

class FadeOutPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final Gradient gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.white, Colors.white.withOpacity(0.0)],
      stops: [0.0, 0.1],
    );
    final Paint paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}