import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '自分専用SNS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF15202B),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'タイムライン'),
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
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  
  List<Map<String, dynamic>> posts = [];
  String userName = '自分';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? postData = prefs.getString('my_posts');
    final String? savedName = prefs.getString('user_name');
    
    setState(() {
      if (postData != null) {
        posts = List<Map<String, dynamic>>.from(json.decode(postData));
      }
      if (savedName != null) {
        userName = savedName;
      }
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('my_posts', json.encode(posts));
    await prefs.setString('user_name', userName);
  }

  // ★テキストを解析して、ハッシュタグだけ青くするウィジェットを作る
  Widget _buildRichText(String text) {
    List<InlineSpan> spans = [];
    // スペースで区切って単語ごとにチェック
    final words = text.split(RegExp(r'(\s+)'));

    for (var word in words) {
      if (word.startsWith('#')) {
        // ハッシュタグなら青色
        spans.add(TextSpan(
          text: word,
          style: const TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold),
        ));
      } else {
        // 普通の文字なら白
        spans.add(TextSpan(text: word, style: const TextStyle(color: Colors.white)));
      }
    }

    return RichText(
      text: TextSpan(children: spans, style: const TextStyle(fontSize: 16)),
    );
  }

  void _showDeleteAllDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('全消去の確認'),
          content: const Text('すべての投稿を削除しますか？\nこの操作は取り消せません。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
            TextButton(
              onPressed: () {
                setState(() => posts.clear());
                _saveData();
                Navigator.pop(context);
              },
              child: const Text('すべて削除', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        );
      },
    );
  }

  void _showNameEditDialog() {
    _nameController.text = userName;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('ユーザー名の変更'),
          content: TextField(controller: _nameController, decoration: const InputDecoration(hintText: "新しい名前を入力")),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
            ElevatedButton(
              onPressed: () {
                setState(() => userName = _nameController.text);
                _saveData();
                Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  void _addNewPost() {
    if (_controller.text.isEmpty) return;
    setState(() {
      String formattedTime = DateFormat('MM/dd HH:mm').format(DateTime.now());
      posts.insert(0, {
        'text': _controller.text,
        'time': formattedTime,
        'isLiked': false,
        'likeCount': 0,
        'author': userName,
      });
      _controller.clear();
    });
    _saveData();
    FocusScope.of(context).unfocus();
  }

  void _toggleLike(int index) {
    setState(() {
      posts[index]['isLiked'] = !posts[index]['isLiked'];
      posts[index]['likeCount'] = posts[index]['isLiked'] 
          ? posts[index]['likeCount'] + 1 
          : posts[index]['likeCount'] - 1;
    });
    _saveData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('全 ${posts.length} 件の投稿', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF15202B),
        leading: IconButton(icon: const Icon(Icons.delete_sweep, color: Colors.redAccent), onPressed: _showDeleteAllDialog),
        actions: [IconButton(icon: const Icon(Icons.settings), onPressed: _showNameEditDialog)],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                return Dismissible(
                  key: UniqueKey(),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) {
                    setState(() => posts.removeAt(index));
                    _saveData();
                  },
                  background: Container(
                    color: Colors.redAccent,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  child: Container(
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white12, width: 0.5))),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.person, color: Colors.white)),
                      title: Row(
                        children: [
                          Text(post['author'] ?? userName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Text(post['time']!, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                      // ★ここを _buildRichText に差し替え！
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          _buildRichText(post['text']!), 
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              InkWell(
                                onTap: () => _toggleLike(index),
                                child: Row(
                                  children: [
                                    Icon(
                                      post['isLiked'] ? Icons.favorite : Icons.favorite_border,
                                      size: 18,
                                      color: post['isLiked'] ? Colors.pink : Colors.grey,
                                    ),
                                    const SizedBox(width: 4),
                                    Text('${post['likeCount']}', style: const TextStyle(color: Colors.grey)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(color: Color(0xFF15202B), border: Border(top: BorderSide(color: Colors.white12))),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (value) => _addNewPost(),
                    decoration: InputDecoration(
                      hintText: '$userNameとして投稿...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.white10,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      border: BorderRadius.circular(30).borderSideNone,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton.small(
                  onPressed: _addNewPost,
                  backgroundColor: Colors.blue,
                  child: const Icon(Icons.send, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension BorderRadiusExtension on BorderRadius {
  get borderSideNone => OutlineInputBorder(borderRadius: this, borderSide: BorderSide.none);
}