### `lib/main.dart`

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

// Replace with your own URL where JSON is hosted publicly
// const String recipesJsonUrl =
//    'https://raw.githubusercontent.com/yourusername/yourrepo/main/recipes.json';

const String recipesJsonUrl ='https://github.com/Frejof/special-disco/blob/main/recipes.json';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await FirebaseAuth.instance.signInAnonymously(); // anonymous auth
  runApp(MyApp());
}

class Recipe {
  final String title;
  final String culture;
  final String image;
  final List<String> ingredients;
  final String instructions;

  Recipe({
    required this.title,
    required this.culture,
    required this.image,
    required this.ingredients,
    required this.instructions,
  });

  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      title: json['title'],
      culture: json['culture'],
      image: json['image'],
      ingredients: List<String>.from(json['ingredients']),
      instructions: json['instructions'],
    );
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cultural Recipes',
      theme: ThemeData(primarySwatch: Colors.deepOrange),
      home: RecipeSelectorPage(),
    );
  }
}

class RecipeSelectorPage extends StatefulWidget {
  @override
  _RecipeSelectorPageState createState() => _RecipeSelectorPageState();
}

class _RecipeSelectorPageState extends State<RecipeSelectorPage> {
  List<Recipe> allRecipes = [];
  List<Recipe> filteredRecipes = [];
  Recipe? selectedRecipe;
  String? selectedCulture;
  bool isLoading = true;
  String? errorMessage;

  final List<String> cultures = [
    'Italian',
    'Brazilian',
    // Add other cultures here
  ];

  @override
  void initState() {
    super.initState();
    fetchRecipesOnline();
  }

  Future<void> fetchRecipesOnline() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final response = await http.get(Uri.parse(recipesJsonUrl));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          allRecipes = data.map((json) => Recipe.fromJson(json)).toList();
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'Failed to load recipes: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error loading recipes: $e';
        isLoading = false;
      });
    }
  }

  void filterRecipes(String culture) {
    setState(() {
      selectedCulture = culture;
      filteredRecipes =
          allRecipes.where((recipe) => recipe.culture == culture).toList();
      selectedRecipe = null;
    });
  }

  void selectRecipe(Recipe recipe) {
    setState(() {
      selectedRecipe = recipe;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('Cultural Recipes')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: Text('Cultural Recipes')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(errorMessage!, style: TextStyle(color: Colors.red)),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: fetchRecipesOnline,
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (selectedRecipe == null) {
      // Show culture selector + recipe list
      return Scaffold(
        appBar: AppBar(
          title: Text('Cultural Recipes'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              DropdownButton<String>(
                hint: Text('Select a culture'),
                value: selectedCulture,
                onChanged: (value) {
                  if (value != null) filterRecipes(value);
                },
                items: cultures
                    .map((culture) => DropdownMenuItem<String>(
                          value: culture,
                          child: Text(culture),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 10),
              if (filteredRecipes.isNotEmpty)
                Expanded(
                  child: ListView.builder(
                    itemCount: filteredRecipes.length,
                    itemBuilder: (context, index) {
                      final recipe = filteredRecipes[index];
                      return Card(
                        child: ListTile(
                          title: Text(recipe.title),
                          onTap: () => selectRecipe(recipe),
                        ),
                      );
                    },
                  ),
                ),
              if (selectedCulture != null && filteredRecipes.isEmpty)
                Center(child: Text('No recipes found for $selectedCulture')),
            ],
          ),
        ),
      );
    } else {
      // Show recipe details + likes + comments
      return RecipeDetailsPage(
        recipe: selectedRecipe!,
        onBack: () {
          setState(() {
            selectedRecipe = null;
          });
        },
      );
    }
  }
}

class RecipeDetailsPage extends StatefulWidget {
  final Recipe recipe;
  final VoidCallback onBack;

  const RecipeDetailsPage({required this.recipe, required this.onBack, Key? key})
      : super(key: key);

  @override
  _RecipeDetailsPageState createState() => _RecipeDetailsPageState();
}

class _RecipeDetailsPageState extends State<RecipeDetailsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late CollectionReference likesCollection;
  late CollectionReference commentsCollection;

  int likesCount = 0;
  bool userLiked = false;
  List<Map<String, dynamic>> comments = [];

  final TextEditingController commentController = TextEditingController();
  bool isSendingComment = false;

  @override
  void initState() {
    super.initState();

    likesCollection = _firestore
        .collection('recipes')
        .doc(widget.recipe.title)
        .collection('likes');

    commentsCollection = _firestore
        .collection('recipes')
        .doc(widget.recipe.title)
        .collection('comments');

    _loadLikes();
    _loadComments();
  }

  Future<void> _loadLikes() async {
    final likesSnapshot = await likesCollection.get();
    final currentUserId = _auth.currentUser!.uid;
    final likedByUser =
        likesSnapshot.docs.any((doc) => doc.id == currentUserId);

    setState(() {
      likesCount = likesSnapshot.docs.length;
      userLiked = likedByUser;
    });
  }

  Future<void> _toggleLike() async {
    final currentUserId = _auth.currentUser!.uid;
    if (userLiked) {
      await likesCollection.doc(currentUserId).delete();
      setState(() {
        likesCount--;
        userLiked = false;
      });
    } else {
      await likesCollection.doc(currentUserId).set({'likedAt': FieldValue.serverTimestamp()});
      setState(() {
        likesCount++;
        userLiked = true;
      });
    }
  }

  Future<void> _loadComments() async {
    final snapshot = await commentsCollection.orderBy('createdAt').get();
    setState(() {
      comments = snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
          .toList();
    });
  }

  Future<void> _addComment(String text) async {
    if (text.trim().isEmpty) return;

    setState(() {
      isSendingComment = true;
    });

    final currentUserId = _auth.currentUser!.uid;

    // Add user comment
    final commentDoc = await commentsCollection.add({
      'userId': currentUserId,
      'text': text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'isBot': false,
    });

    // Add bot reply after user's comment
    await commentsCollection.add({
      'userId
```


': 'bot',
'text': 'Thanks for your comment!',
'createdAt': FieldValue.serverTimestamp(),
'isBot': true,
'replyTo': commentDoc.id,
});

```
commentController.clear();

// Reload comments to update UI
await _loadComments();

setState(() {
  isSendingComment = false;
});
```

}

Widget \_buildCommentTile(Map\<String, dynamic> comment) {
bool isBot = comment\['isBot'] == true;
return Container(
margin: EdgeInsets.symmetric(vertical: 4),
padding: EdgeInsets.all(8),
decoration: BoxDecoration(
color: isBot ? Colors.orange\[100] : Colors.grey\[200],
borderRadius: BorderRadius.circular(8),
),
child: Text(
comment\['text'] ?? '',
style: TextStyle(
fontStyle: isBot ? FontStyle.italic : FontStyle.normal,
color: isBot ? Colors.deepOrange : Colors.black87),
),
);
}

@override
Widget build(BuildContext context) {
final recipe = widget.recipe;

```
return Scaffold(
  appBar: AppBar(
    title: Text(recipe.title),
    leading: IconButton(
      icon: Icon(Icons.arrow_back),
      onPressed: widget.onBack,
    ),
  ),
  body: Padding(
    padding: const EdgeInsets.all(12.0),
    child: Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.network(recipe.image),
                const SizedBox(height: 12),
                Text(
                  recipe.title,
                  style:
                      TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ingredients:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                ...recipe.ingredients.map((i) => Text('• $i')),
                const SizedBox(height: 8),
                Text(
                  'Instructions:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(recipe.instructions),
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        userLiked ? Icons.favorite : Icons.favorite_border,
                        color: userLiked ? Colors.red : Colors.grey,
                      ),
                      onPressed: _toggleLike,
                    ),
                    Text('$likesCount likes'),
                  ],
                ),
                Divider(),
                Text(
                  'Comments:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18),
                ),
                SizedBox(height: 8),
                if (comments.isEmpty)
                  Text('No comments yet. Be the first!'),
                ...comments.map(_buildCommentTile).toList(),
                SizedBox(height: 80), // leave space for input box
              ],
            ),
          ),
        ),
        // Comment input
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding:
                EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: commentController,
                    decoration: InputDecoration(
                      hintText: 'Add a comment...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 16, vertical: 0),
                    ),
                    minLines: 1,
                    maxLines: 3,
                  ),
                ),
                SizedBox(width: 8),
                isSendingComment
                    ? CircularProgressIndicator()
                    : IconButton(
                        icon: Icon(Icons.send, color: Colors.deepOrange),
                        onPressed: () {
                          _addComment(commentController.text);
                        },
                      ),
              ],
            ),
          ),
        ),
      ],
    ),
  ),
);
```

}
}

