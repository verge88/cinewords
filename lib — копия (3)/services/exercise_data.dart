/// Локальные данные для упражнений: минимальные пары, тематические кластеры,
/// банки предложений для cloze / sentence builder / tense transformation.
class ExerciseData {
  // ─── Минимальные пары (фонематический слух) ───
  static const List<MinimalPair> minimalPairs = [
    MinimalPair(a: 'ship', b: 'sheep', contrast: 'ɪ vs iː'),
    MinimalPair(a: 'bit', b: 'beat', contrast: 'ɪ vs iː'),
    MinimalPair(a: 'live', b: 'leave', contrast: 'ɪ vs iː'),
    MinimalPair(a: 'fit', b: 'feet', contrast: 'ɪ vs iː'),
    MinimalPair(a: 'cat', b: 'cut', contrast: 'æ vs ʌ'),
    MinimalPair(a: 'bag', b: 'bug', contrast: 'æ vs ʌ'),
    MinimalPair(a: 'hat', b: 'hut', contrast: 'æ vs ʌ'),
    MinimalPair(a: 'pen', b: 'pan', contrast: 'e vs æ'),
    MinimalPair(a: 'bed', b: 'bad', contrast: 'e vs æ'),
    MinimalPair(a: 'thin', b: 'sin', contrast: 'θ vs s'),
    MinimalPair(a: 'thank', b: 'sank', contrast: 'θ vs s'),
    MinimalPair(a: 'this', b: 'dis', contrast: 'ð vs d'),
    MinimalPair(a: 'vest', b: 'west', contrast: 'v vs w'),
    MinimalPair(a: 'very', b: 'wary', contrast: 'v vs w'),
    MinimalPair(a: 'rice', b: 'lice', contrast: 'r vs l'),
    MinimalPair(a: 'right', b: 'light', contrast: 'r vs l'),
    MinimalPair(a: 'walk', b: 'work', contrast: 'ɔː vs ɜː'),
    MinimalPair(a: 'pull', b: 'pool', contrast: 'ʊ vs uː'),
    MinimalPair(a: 'full', b: 'fool', contrast: 'ʊ vs uː'),
    MinimalPair(a: 'cot', b: 'caught', contrast: 'ɒ vs ɔː'),
  ];

  // ─── Семантические кластеры ───
  static const List<ClusterSet> clusterSets = [
    ClusterSet(
      title: 'Food, Transport, Emotions',
      clusters: [
        Cluster(name: 'food', emoji: '🍽️', words: [
          'apple', 'bread', 'cheese', 'soup', 'pasta',
        ]),
        Cluster(name: 'transport', emoji: '🚗', words: [
          'car', 'bus', 'train', 'bicycle', 'plane',
        ]),
        Cluster(name: 'emotions', emoji: '😊', words: [
          'happy', 'sad', 'angry', 'proud', 'afraid',
        ]),
      ],
    ),
    ClusterSet(
      title: 'House, Nature, Work',
      clusters: [
        Cluster(name: 'house', emoji: '🏠', words: [
          'kitchen', 'bedroom', 'window', 'floor', 'roof',
        ]),
        Cluster(name: 'nature', emoji: '🌳', words: [
          'tree', 'river', 'mountain', 'beach', 'forest',
        ]),
        Cluster(name: 'work', emoji: '💼', words: [
          'meeting', 'salary', 'office', 'colleague', 'deadline',
        ]),
      ],
    ),
    ClusterSet(
      title: 'Animals, Body, Time',
      clusters: [
        Cluster(name: 'animals', emoji: '🐾', words: [
          'dog', 'lion', 'eagle', 'wolf', 'rabbit',
        ]),
        Cluster(name: 'body', emoji: '🫀', words: [
          'finger', 'shoulder', 'knee', 'elbow', 'tongue',
        ]),
        Cluster(name: 'time', emoji: '⏰', words: [
          'morning', 'tonight', 'yesterday', 'minute', 'century',
        ]),
      ],
    ),
  ];

  // ─── Cloze предложения (4 варианта, один верный) ───
  static const List<ClozeItem> clozeItems = [
    ClozeItem(
      sentence: 'She ___ to school every day.',
      options: ['go', 'goes', 'going', 'went'],
      correctIndex: 1,
    ),
    ClozeItem(
      sentence: 'I ___ a movie last night.',
      options: ['watch', 'watched', 'watching', 'watches'],
      correctIndex: 1,
    ),
    ClozeItem(
      sentence: 'They have ___ in London for ten years.',
      options: ['live', 'lives', 'lived', 'living'],
      correctIndex: 2,
    ),
    ClozeItem(
      sentence: 'There ___ many books on the shelf.',
      options: ['is', 'are', 'be', 'was'],
      correctIndex: 1,
    ),
    ClozeItem(
      sentence: 'If it rains, I ___ stay home.',
      options: ['will', 'would', 'am', 'do'],
      correctIndex: 0,
    ),
    ClozeItem(
      sentence: 'He is the ___ student in the class.',
      options: ['good', 'better', 'best', 'goodest'],
      correctIndex: 2,
    ),
    ClozeItem(
      sentence: 'I look forward ___ hearing from you.',
      options: ['to', 'for', 'at', 'on'],
      correctIndex: 0,
    ),
    ClozeItem(
      sentence: 'She ___ never been to Paris.',
      options: ['have', 'has', 'had', 'is'],
      correctIndex: 1,
    ),
    ClozeItem(
      sentence: 'Could you ___ me with this box?',
      options: ['help', 'helping', 'helps', 'helped'],
      correctIndex: 0,
    ),
    ClozeItem(
      sentence: 'The book ___ I read was amazing.',
      options: ['who', 'which', 'where', 'whose'],
      correctIndex: 1,
    ),
  ];

  // ─── Sentence Builder (расставить слова) ───
  static const List<String> sentenceBank = [
    'I usually drink coffee in the morning',
    'She has been working here for five years',
    'They are going to the cinema tonight',
    'My brother plays football every weekend',
    'The cat is sleeping on the sofa',
    'We had dinner at a nice restaurant',
    'He cannot speak French very well',
    'Can you tell me where the station is',
    'I would like a cup of tea please',
    'There is a beautiful park near my house',
    'She forgot to bring her umbrella',
    'They have lived in this city since 2020',
  ];

  // ─── Трансформация времён ───
  static const List<TenseItem> tenseItems = [
    TenseItem(
      base: 'I eat breakfast every morning.',
      from: 'Present Simple',
      to: 'Past Simple',
      answers: ['I ate breakfast every morning.'],
    ),
    TenseItem(
      base: 'She writes a letter to her friend.',
      from: 'Present Simple',
      to: 'Present Continuous',
      answers: ['She is writing a letter to her friend.'],
    ),
    TenseItem(
      base: 'They play football in the park.',
      from: 'Present Simple',
      to: 'Past Continuous',
      answers: ['They were playing football in the park.'],
    ),
    TenseItem(
      base: 'He works at a bank.',
      from: 'Present Simple',
      to: 'Future Simple',
      answers: [
        'He will work at a bank.',
        "He'll work at a bank.",
      ],
    ),
    TenseItem(
      base: 'I read a book yesterday.',
      from: 'Past Simple',
      to: 'Present Perfect',
      answers: [
        'I have read a book.',
        "I've read a book.",
      ],
    ),
    TenseItem(
      base: 'We watch a movie tonight.',
      from: 'Present Simple',
      to: 'Future Continuous',
      answers: [
        'We will be watching a movie tonight.',
        "We'll be watching a movie tonight.",
      ],
    ),
    TenseItem(
      base: 'She drinks tea.',
      from: 'Present Simple',
      to: 'Past Perfect',
      answers: ['She had drunk tea.'],
    ),
    TenseItem(
      base: 'They live in Berlin.',
      from: 'Present Simple',
      to: 'Present Perfect',
      answers: [
        'They have lived in Berlin.',
        "They've lived in Berlin.",
      ],
    ),
  ];

  // ─── Тексты для тап-читалки и слова-невидимки ───
  static const List<ReaderText> readerTexts = [
    ReaderText(
      title: 'Morning Routine',
      body:
          'Every morning I wake up at seven. I open the window and listen to '
          'the birds singing in the garden. After a quick shower I make a cup '
          'of coffee and read the latest news on my phone. Sometimes I write '
          'down a few thoughts in my journal before starting work.',
    ),
    ReaderText(
      title: 'A Walk in the Park',
      body:
          'On Sunday afternoon we decided to take a long walk in the park. '
          'The trees were turning yellow and the air smelled of autumn. '
          'Children were running between the benches and a couple of dogs '
          'chased a tennis ball across the field. We sat on the grass and '
          'shared a thermos of warm tea.',
    ),
    ReaderText(
      title: 'Travel Diary',
      body:
          'Yesterday I arrived in Lisbon. The streets are narrow and full of '
          'colourful tiles. I had grilled fish for lunch near the harbour and '
          'watched the boats sailing in the distance. In the evening a street '
          'musician was playing fado, and I felt the city slowly opening up '
          'to me.',
    ),
  ];

  // ─── Диктант с пробелами ───
  static const List<DictationItem> dictationItems = [
    DictationItem(
      sentence: 'The early bird catches the worm in the morning',
    ),
    DictationItem(
      sentence: 'Practice makes perfect when you stay consistent',
    ),
    DictationItem(
      sentence: 'A journey of a thousand miles begins with a single step',
    ),
    DictationItem(
      sentence: 'Better late than never but never late is better',
    ),
    DictationItem(
      sentence: 'Actions speak louder than words in any language',
    ),
    DictationItem(
      sentence: 'Time flies when you are having fun with friends',
    ),
  ];

  // ─── Shadow repetition фразы ───
  static const List<String> shadowPhrases = [
    'Could you please repeat that more slowly?',
    'I would like a cup of tea, please.',
    'How much does this cost?',
    'Where is the nearest bus stop?',
    'It was nice meeting you today.',
    'Thank you very much for your help.',
    'I think we should leave now.',
    'What do you usually do on weekends?',
    'The weather is really nice today.',
    'I am looking forward to seeing you again.',
  ];
}

class MinimalPair {
  final String a;
  final String b;
  final String contrast;
  const MinimalPair({required this.a, required this.b, required this.contrast});
}

class ClusterSet {
  final String title;
  final List<Cluster> clusters;
  const ClusterSet({required this.title, required this.clusters});
}

class Cluster {
  final String name;
  final String emoji;
  final List<String> words;
  const Cluster({required this.name, required this.emoji, required this.words});
}

class ClozeItem {
  final String sentence; // contains "___"
  final List<String> options;
  final int correctIndex;
  const ClozeItem({
    required this.sentence,
    required this.options,
    required this.correctIndex,
  });
}

class TenseItem {
  final String base;
  final String from;
  final String to;
  final List<String> answers;
  const TenseItem({
    required this.base,
    required this.from,
    required this.to,
    required this.answers,
  });
}

class ReaderText {
  final String title;
  final String body;
  const ReaderText({required this.title, required this.body});
}

class DictationItem {
  final String sentence;
  const DictationItem({required this.sentence});
}
