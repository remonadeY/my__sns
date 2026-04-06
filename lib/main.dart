import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'dart:io'; 
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; 
import 'package:flutter/gestures.dart'; 
import 'package:image_picker/image_picker.dart'; 
// ★修正：最新のスクリーンショット防止ライブラリ
import 'package:secure_application/secure_application.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }     
  runApp(const MyApp());
}

// --- 1. データモデル ---
class Post {
  final int? id;
  final String content;
  final String time;
  final int likeCount;
  final bool isLiked;
  final String? imagePath; 

  Post({
    this.id, 
    required this.content, 
    required this.time, 
    this.likeCount = 0, 
    this.isLiked = false,
    this.imagePath,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id, 
      'content': content, 
      'time': time, 
      'likeCount': likeCount, 
      'isLiked': isLiked ? 1 : 0,
      'imagePath': imagePath,
    };
  }

  factory Post.fromMap(Map<String, dynamic> map) {
    return Post(
      id: map['id'],
      content: map['content'],
      time: map['time'],
      likeCount: map['likeCount'],
      isLiked: map['isLiked'] == 1,
      imagePath: map['imagePath'],
    );
  }
}

// --- 2. データベース管理 ---
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String databasesPath = await getDatabasesPath();
    String path = p.join(databasesPath, 'sns_ver4.db'); 
    return await openDatabase(
      path, 
      version: 2, 
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE posts(id INTEGER PRIMARY KEY AUTOINCREMENT, content TEXT, time TEXT, likeCount INTEGER, isLiked INTEGER, imagePath TEXT)'
        );
      },
      onUpgrade: (db, oldVersion, newVersion) {
        if (oldVersion < 2) {
          db.execute('ALTER TABLE posts ADD COLUMN imagePath TEXT');
        }
      }
    );
  }

  Future<void> insertPost(Post post) async {
    final db = await database;
    await db.insert('posts', post.toMap());
  }

  Future<void> updatePost(Post post) async {
    final db = await database;
    await db.update('posts', post.toMap(), where: 'id = ?', whereArgs: [post.id]);
  }

  Future<void> deletePost(int id) async {
    final db = await database;
    await db.delete('posts', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Post>> getPosts() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('posts', orderBy: 'id DESC');
    return List.generate(maps.length, (i) => Post.fromMap(maps[i]));
  }
}

// --- 3. 検索画面ロジック ---
class PostSearchDelegate extends SearchDelegate {
  final List<Post> allPosts;
  final Widget Function(String) buildRichText; 
  PostSearchDelegate(this.allPosts, this.buildRichText);

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')
  ];
  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null)
  );
  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);
  @override
  Widget buildSuggestions(BuildContext context) {
    final suggestions = query.isEmpty 
        ? allPosts 
        : allPosts.where((post) => post.content.contains(query)).toList();
    return Container(
      color: const Color(0xFF15202B),
      child: ListView.builder(
        itemCount: suggestions.length,
        itemBuilder: (context, index) => ListTile(
          title: buildRichText(suggestions[index].content),
          subtitle: Text(suggestions[index].time, style: const TextStyle(color: Colors.grey)),
        ),
      ),
    );
  }
}

// 画像拡大画面
class ImageDetailPage extends StatelessWidget {
  final String imagePath;
  final String tag;

  const ImageDetailPage({super.key, required this.imagePath, required this.tag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, elevation: 0),
      body: Center(
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Hero(
            tag: tag,
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(File(imagePath), fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}

// --- 4. UI ---
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    // ★修正：アプリ全体を SecureApplication で包む
    return SecureApplication(
      nativeRemoveDelay: 100,
      child: Builder(builder: (context) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark, 
            primaryColor: Colors.blue, 
            scaffoldBackgroundColor: const Color(0xFF15202B), 
            useMaterial3: true
          ),
          home: const MyHomePage(),
        );
      }),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _controller = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  List<Post> posts = [];
  String? _selectedImagePath; 

  @override
  void initState() { 
    super.initState(); 
    _refreshPosts();
    // ★こだわり：起動直後にセキュリティ機能をONにする
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setSecureMode(true);
    });
  }


  void _setSecureMode(bool enable) {
    final secureContext = SecureApplicationProvider.of(context, listen: false);
    if (secureContext == null) return; // 安全策としてnullチェック

    if (enable) {
      // 画面を保護する（スクリーンショット禁止）
      secureContext.secure(); 
    } else {
      // 画面の保護を解除する
      secureContext.open(); // ← ここを 'unsecure' から 'open' に変更
    }
  }

  void _refreshPosts() async {
    final data = await DatabaseHelper().getPosts();
    setState(() => posts = data);
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _selectedImagePath = image.path);
    }
  }

  Future<bool?> _showDeleteDialog(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF15202B),
          title: const Text('投稿の削除', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('この投稿を削除してもよろしいですか？'),
          actions: <Widget>[
            TextButton(
              child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('削除', style: TextStyle(color: Colors.redAccent)),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
  }

  void _toggleLike(Post post) async {
    final newPost = Post(
      id: post.id,
      content: post.content,
      time: post.time,
      likeCount: post.isLiked ? post.likeCount - 1 : post.likeCount + 1,
      isLiked: !post.isLiked,
      imagePath: post.imagePath,
    );
    await DatabaseHelper().updatePost(newPost);
    _refreshPosts();
  }

  Widget _buildRichText(String text) {
    List<InlineSpan> spans = [];
    final words = text.split(RegExp(r'(\s+)'));
    for (var word in words) {
      if (word.startsWith('#')) {
        spans.add(TextSpan(
          text: word,
          style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
          recognizer: TapGestureRecognizer()..onTap = () {
            showSearch(context: context, delegate: PostSearchDelegate(posts, _buildRichText), query: word);
          },
        ));
      } else {
        spans.add(TextSpan(text: word, style: const TextStyle(color: Colors.white)));
      }
    }
    return RichText(text: TextSpan(children: spans, style: const TextStyle(fontSize: 16)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF15202B),
        title: const Text('自分だけの聖域', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search), 
            onPressed: () => showSearch(context: context, delegate: PostSearchDelegate(posts, _buildRichText))
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                final heroTag = 'image_${post.id}'; 

                return Dismissible(
                  key: Key(post.id.toString()),
                  confirmDismiss: (direction) async {
                    final result = await _showDeleteDialog(context);
                    return result ?? false;
                  },
                  onDismissed: (_) async {
                    if (post.id != null) {
                      await DatabaseHelper().deletePost(post.id!);
                      _refreshPosts();
                    }
                  },
                  background: Container(
                    color: Colors.redAccent, 
                    alignment: Alignment.centerRight, 
                    padding: const EdgeInsets.only(right: 20), 
                    child: const Icon(Icons.delete)
                  ),
                  child: ListTile(
                    leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.person)),
                    title: Text("自分   ${post.time}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildRichText(post.content),
                        if (post.imagePath != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ImageDetailPage(imagePath: post.imagePath!, tag: heroTag),
                                  ),
                                );
                              },
                              child: Hero(
                                tag: heroTag,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxHeight: 250),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Image.file(
                                        File(post.imagePath!), 
                                        fit: BoxFit.contain, 
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(children: [
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              post.isLiked ? Icons.favorite : Icons.favorite_border, 
                              color: post.isLiked ? Colors.pink : Colors.grey, 
                              size: 18
                            ),
                            onPressed: () => _toggleLike(post),
                          ),
                          const SizedBox(width: 4),
                          Text("${post.likeCount}", style: const TextStyle(color: Colors.grey)),
                        ]),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.image, 
                    color: _selectedImagePath != null ? Colors.blue : Colors.grey
                  ),
                  onPressed: _pickImage,
                ),
                Expanded(
                  child: TextField(
                    controller: _controller, 
                    decoration: InputDecoration(
                      hintText: "ここだけの本音を...", 
                      filled: true, 
                      fillColor: Colors.white10, 
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30), 
                        borderSide: BorderSide.none
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    )
                  )
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue), 
                  onPressed: () async {
                    if (_controller.text.isEmpty && _selectedImagePath == null) return;
                    await DatabaseHelper().insertPost(
                      Post(
                        content: _controller.text, 
                        time: DateFormat('MM/dd HH:mm').format(DateTime.now()),
                        imagePath: _selectedImagePath,
                      )
                    );
                    _controller.clear();
                    setState(() => _selectedImagePath = null);
                    _refreshPosts();
                  }
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}