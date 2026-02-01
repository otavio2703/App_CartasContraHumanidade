import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jogo APP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0b0910),
        primaryColor: const Color(0xFF7000ff),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7000ff),
          secondary: Color(0xFF9f55ff),
          surface: Color(0xFF1a1625),
          background: Color(0xFF0b0910),
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF22202b),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF33303d)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF33303d)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF7000ff)),
          ),
          hintStyle: const TextStyle(color: Color(0xFF555555)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        ),
      ),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late IO.Socket socket;

  String view = 'LOGIN';
  String playerName = '';
  String roomCode = '';
  String errorMessage = '';
  String? selectedAvatar;
  String? fcmToken; // FCM Token

  List<dynamic> hand = [];
  String currentQuestion = "";
  bool isJudge = false;
  List<dynamic> tableCards = [];
  Map<String, dynamic>? winnerInfo;
  List<dynamic> players = [];

  // List of all 39 avatar filenames
  final List<String> avatarAssets = [
    "actor-chaplin-comedy.png", "afro-avatar-male-2.png", "afro-avatar-male.png", "afro-boy-child.png",
    "afro-female-person.png", "animal-avatar-bear.png", "animal-avatar-mutton.png", "anime-away-face.png",
    "artist-avatar-marilyn.png", "avatar-avocado-food.png", "avatar-bad-breaking.png", "avatar-batman-comics.png",
    "avatar-boy-kid.png", "avatar-boy-male.png", "avatar-bug-insect.png", "avatar-cacti-cactus.png",
    "avatar-child-girl.png", "avatar-coffee-cup.png", "avatar-dead-monster.png", "avatar-einstein-professor.png",
    "avatar-elderly-grandma.png", "avatar-female-portrait-2.png", "avatar-female-portrait.png", "avatar-joker-squad.png",
    "avatar-lazybones-sloth.png", "avatar-male-ozzy.png", "avatar-male-president.png", "avatar-man-person.png",
    "avatar-nun-sister.png", "avatar-person-pilot.png", "beard-hipster-male.png", "boy-indian-kid.png",
    "builder-helmet-worker.png", "child-girl-kid.png", "christmas-clous-santa.png", "fighter-luchador-man.png",
    "friday-halloween-jason.png", "indian-male-man.png", "male-man-old.png"
  ];

  @override
  void initState() {
    super.initState();
    initSocket();
    setupFCM();
  }

  void setupFCM() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission(
      alert: true, badge: true, sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
       print("FCM Authorized");
       String? token = await messaging.getToken();
       setState(() {
         fcmToken = token;
       });
       print("FCM Token: $fcmToken");
    }
    
    // Subscribe to global topic
    await messaging.subscribeToTopic('updates');
    print("Subscribed to topic: updates");
    
    // Listen for foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('Got a message whilst in the foreground!');
        if (message.notification != null) {
          // Show dialog if desired
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(message.notification?.title ?? 'Notificação'),
                content: Text(message.notification?.body ?? ''),
                actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text("OK"))],
              )
            );
          }
        }
    });
  }

  void initSocket() {
    socket = IO.io('https://meu-jogo-server.onrender.com', 
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .enableAutoConnect()
            .build()
    );

    socket.onConnect((_) {});
    
    socket.on('error', (msg) {
      if (mounted) setState(() => errorMessage = msg.toString());
    });

    socket.on('joined-success', (_) {
      if (mounted) {
        setState(() {
          view = 'LOBBY';
          errorMessage = '';
          // Subscribe to Room Topic
          FirebaseMessaging.instance.subscribeToTopic('room_${roomCode.toUpperCase()}');
          print("Subscribed to topic: room_${roomCode.toUpperCase()}");
        });
      }
    });

    socket.on('update-players', (data) {
       if (mounted) setState(() => players = List<dynamic>.from(data));
    });

    socket.on('your-hand', (data) => setState(() => hand = data));

    socket.on('round-start', (data) {
      setState(() {
        currentQuestion = data['question'];
        isJudge = (data['judgeId'] == socket.id);
        view = isJudge ? 'JUDGING_WAIT' : 'PICKING';
        tableCards = [];
        errorMessage = '';
      });
    });

    socket.on('start-judging', (data) {
      setState(() {
        tableCards = List<dynamic>.from(data);
        view = isJudge ? 'JUDGING_ACT' : 'JUDGING_VIEW';
      });
    });

    socket.on('update-table', (data) {
       setState(() {
         tableCards = List<dynamic>.from(data);
         if (tableCards.isNotEmpty) {
           if (isJudge && view == 'JUDGING_WAIT') view = 'JUDGING_ACT';
           if (!isJudge && view == 'WAITING_OTHERS') view = 'JUDGING_VIEW';
         }
       });
    });

    socket.on('round-winner', (data) {
      setState(() {
        winnerInfo = data;
        view = 'RESULT_VIEW';
      });
    });
    
    socket.on('notification', (data) {
       if (mounted) {
         showDialog(
           context: context,
           builder: (ctx) => AlertDialog(
             backgroundColor: const Color(0xFF1a1625),
             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
             title: Row(
               children: const [
                 Icon(Icons.notifications_active, color: Color(0xFF7000ff)),
                 SizedBox(width: 8),
                 Text("Aviso do Host", style: TextStyle(color: Colors.white)),
               ],
             ),
             content: Text(data['message']?.toString() ?? '', style: const TextStyle(color: Colors.white70, fontSize: 16)),
             actions: [
               TextButton(
                 onPressed: () => Navigator.pop(ctx),
                 child: const Text("Entendido", style: TextStyle(color: Color(0xFF7000ff), fontWeight: FontWeight.bold)),
               )
             ],
           ),
         );
       }
    });

    socket.on('game-ended', (data) {
       // Optional: Handle Max Points reached Game Over in App
       // For now, just show result view differently or ignore
    });
  }

  void _showAvatarSelectionModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a1625),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Column(
              children: [
                const SizedBox(height: 20),
                const Text("Escolha seu Avatar", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 20),
                Expanded(
                  child: GridView.builder(
                    controller: controller,
                    padding: const EdgeInsets.all(20),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3, 
                        crossAxisSpacing: 15, 
                        mainAxisSpacing: 15
                    ),
                    itemCount: avatarAssets.length,
                    itemBuilder: (ctx, index) {
                      final assetName = avatarAssets[index];
                      return GestureDetector(
                        onTap: () {
                          setState(() => selectedAvatar = assetName);
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                             shape: BoxShape.circle,
                             border: Border.all(color: Colors.white24),
                             image: DecorationImage(image: AssetImage('assets/avatars/$assetName'))
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          }
        );
      },
    );
  }

  void joinRoom() {
    if (playerName.isEmpty || roomCode.isEmpty) return;
    socket.emit('join-room', {
      'roomCode': roomCode.trim().toUpperCase(), 
      'playerName': playerName,
      'avatar': selectedAvatar,
      'fcmToken': fcmToken // Send Token
    });
  }

  void playCard(String cardText) {
    socket.emit('play-card', {'roomCode': roomCode.trim().toUpperCase(), 'cardText': cardText});
    setState(() => view = 'WAITING_OTHERS');
  }

  void handleJudgeTap(int index) {
    if (!isJudge) return;
    
    final card = tableCards[index];
    final bool isRevealed = card['revealed'] ?? false;

    if (!isRevealed) {
      socket.emit('reveal-card', {'roomCode': roomCode.trim().toUpperCase(), 'index': index});
    } else {
      showDialog(
        context: context, 
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1a1625),
          title: const Text("Escolher Vencedor", style: TextStyle(color: Colors.white)),
          content: Text("Confirmar esta carta como vencedora?\n\n\"${card['text']}\"", style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx), 
              child: const Text("Cancelar", style: TextStyle(color: Colors.white54))
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7000ff)),
              onPressed: () {
                 Navigator.pop(ctx);
                 socket.emit('choose-winner', {'roomCode': roomCode.trim().toUpperCase(), 'cardIndex': index});
              }, 
              child: const Text("Confirmar", style: TextStyle(color: Colors.white))
            ),
          ],
        )
      );
    }
  }

  void leaveRoom() {
      // Unsubscribe from room topic
      if (roomCode.isNotEmpty) {
          FirebaseMessaging.instance.unsubscribeFromTopic('room_${roomCode.toUpperCase()}');
          print("Unsubscribed from topic: room_${roomCode.toUpperCase()}");
          // Optionally notify server
          // socket.emit('leave-room', roomCode); 
      }
      
      setState(() {
          view = 'LOGIN';
          // roomCode = ''; // Keep roomCode if they want to rejoin quickly? No, simpler to clear.
      });
  }

  @override
  Widget build(BuildContext context) {
    final bool showHeader = view != 'LOGIN';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (showHeader) _buildTopBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    String title = "Lobby";
    if (view == 'PICKING') title = "Sua Vez";
    if (view == 'WAITING_OTHERS') title = "Aguardando...";
    if (view.startsWith('JUDGING')) title = "Julgamento";
    if (view == 'RESULT_VIEW') title = "Resultado";

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: leaveRoom,
          ),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Icon(Icons.settings, color: Colors.white),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (view) {
      case 'LOGIN':
        return _buildLoginScreen();
      case 'LOBBY':
        return _buildLobbyScreen();
      case 'PICKING':
        return _buildPickingScreen();
      case 'WAITING_OTHERS':
        return _buildWaitingScreen();
      case 'JUDGING_WAIT': 
      case 'JUDGING_ACT':
      case 'JUDGING_VIEW':
        return _buildJudgingScreen();
      case 'RESULT_VIEW':
        return _buildResultScreen();
      default:
        return const Center(child: CircularProgressIndicator());
    }
  }

  // --- SCREENS ---

  Widget _buildLoginScreen() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white), 
                onPressed: (){}, 
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
              ),
              if (fcmToken != null)
                IconButton(
                  icon: const Icon(Icons.copy_all, color: Colors.white54),
                  tooltip: "Copiar Token FCM",
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: fcmToken!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Token FCM copiado para a área de transferência!'))
                    );
                    print("TOKEN FCM COPIADO: $fcmToken");
                  },
                ),
            ],
          ),
          const SizedBox(height: 20),
          RichText(
            text: const TextSpan(
              style: TextStyle(fontSize: 48, fontWeight: FontWeight.w800, height: 0.9, color: Colors.white),
              children: [
                TextSpan(text: "Entre no\n"),
                TextSpan(text: "Void."),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text("Ou apenas uma sala de jogo. Tanto faz.", style: TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 30),

          // Avatar Picker (Template)
          Center(
            child: GestureDetector(
              onTap: _showAvatarSelectionModal,
              child: Stack(
                children: [
                   Container(
                     width: 100,
                     height: 100,
                     decoration: BoxDecoration(
                       shape: BoxShape.circle,
                       color: const Color(0xFF22202b),
                       border: Border.all(color: const Color(0xFF7000ff), width: 2),
                       image: selectedAvatar != null 
                           ? DecorationImage(image: AssetImage('assets/avatars/$selectedAvatar'), fit: BoxFit.cover)
                           : null,
                     ),
                     child: selectedAvatar == null 
                         ? const Icon(Icons.person_outline, color: Colors.white54, size: 40)
                         : null,
                   ),
                   Positioned(
                     bottom: 0, right: 0,
                     child: Container(
                       padding: const EdgeInsets.all(6),
                       decoration: const BoxDecoration(color: Color(0xFF7000ff), shape: BoxShape.circle),
                       child: const Icon(Icons.edit, size: 14, color: Colors.white),
                     ),
                   )
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Center(child: Text("Escolher Avatar", style: TextStyle(color: Colors.grey, fontSize: 12))),

          const SizedBox(height: 20),
          
          const Text("APELIDO", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          TextField(
            onChanged: (v) => playerName = v,
            decoration: const InputDecoration(hintText: "Como te chamam?"),
            style: const TextStyle(color: Colors.white),
          ),
          
          const SizedBox(height: 20),
          
          const Text("CÓDIGO DA SALA", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          TextField(
            onChanged: (v) => roomCode = v,
            decoration: const InputDecoration(hintText: "EX: BOLD-DOG-99"),
            style: const TextStyle(color: Colors.white),
          ),

          if (errorMessage.isNotEmpty) ...[
            const SizedBox(height: 20),
             Container(
               padding: const EdgeInsets.all(12),
               decoration: BoxDecoration(color: Colors.red.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
               child: Text(errorMessage, style: const TextStyle(color: Colors.redAccent)),
             )
          ],

          const SizedBox(height: 30),
          
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: joinRoom,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7000ff),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                elevation: 5,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text("Entrar", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward, color: Colors.white)
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildLobbyScreen() {
    return Column(
      children: [
        const SizedBox(height: 20),
        Text("Sala #${roomCode.toUpperCase()}", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const Text("Aguardando o host iniciar...", style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 30),
        
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text("Jogadores", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text("Sala Pública", style: TextStyle(color: Color(0xFF7000ff), fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 10),
        
        Expanded(
          child: ListView.separated(
            itemCount: players.isEmpty ? 1 : players.length, 
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              if (players.isEmpty) return _buildPlayerListItem(playerName, true, selectedAvatar);
              final p = players[i];
              return _buildPlayerListItem(p['name'] ?? 'Desconhecido', p['name'] == playerName, p['avatar']);
            },
          ),
        ),
        
        SizedBox(
          width: double.infinity,
          height: 55,
          child: ElevatedButton.icon(
             onPressed: (){},
             icon: const Icon(Icons.person_add, color: Colors.white),
             label: const Text("Convidar Amigos", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
             style: ElevatedButton.styleFrom(
               backgroundColor: const Color(0xFF7000ff),
               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
             ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF22202b),
            borderRadius: BorderRadius.circular(16)
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text("Regras: Clássico", style: TextStyle(fontWeight: FontWeight.bold)),
                  Text("Primeiro a 10 vence. 60s/rodada.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
              const Icon(Icons.info_outline, color: Colors.grey),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildPlayerListItem(String name, bool isMe, String? avatar) {
    // Logic to resolve avatar:
    // 1. If it's a filename string (endsWith .png), load from Assets.
    // 2. If it's base64 (older version), load memory.
    // 3. Else fallback text.
    
    ImageProvider? imageProvider;
    if (avatar != null && avatar.isNotEmpty) {
       if (avatar.toLowerCase().endsWith('.png')) {
          imageProvider = AssetImage('assets/avatars/$avatar');
       } else {
          // Fallback for legacy base64 if any
          try {
             // imageProvider = MemoryImage(base64Decode(avatar)); 
             // Ignoring legacy base64 for now as per requirement to use templates
          } catch(e){}
       }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: isMe ? Border.all(color: const Color(0xFF7000ff)) : null,
      ),
      child: Row(
        children: [
          CircleAvatar(
             backgroundColor: Colors.primaries[name.length % Colors.primaries.length], 
             radius: 18,
             backgroundImage: imageProvider,
             child: imageProvider == null ? Text(name.isNotEmpty ? name[0].toUpperCase() : "?") : null,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(name + (isMe ? " (Você)" : ""), style: TextStyle(fontWeight: isMe ? FontWeight.bold : FontWeight.normal))),
          if (isMe) 
             const Icon(Icons.check_circle, color: Color(0xFF7000ff), size: 18)
          else
             const Text("PRONTO", style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold))
        ],
      ),
    );
  }

  Widget _buildPickingScreen() {
    return Column(
      children: [
        const SizedBox(height: 10),
        const Text("Rodada X", style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 10),
        
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF33303d)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("A PERGUNTA", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.5)),
              const SizedBox(height: 16),
              Text(currentQuestion, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.3)),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF333333), borderRadius: BorderRadius.circular(6)),
                  child: const Text("CAH", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                ),
              )
            ],
          ),
        ),
        
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Sua Mão", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text("${hand.length} CARTAS", style: const TextStyle(color: Color(0xFF7000ff), fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 16),
        
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: hand.length,
            separatorBuilder: (_,__) => const SizedBox(width: 12),
            itemBuilder: (ctx, i) => GestureDetector(
              onTap: () => playCard(hand[i]),
              child: Container(
                width: 150,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hand[i], style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold, height: 1.2)),
                    const Align(
                      alignment: Alignment.bottomRight, 
                      child: Icon(Icons.style, color: Colors.black26, size: 20)
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildWaitingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 200,
            height: 8,
            decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(4)),
            child: Align(alignment: Alignment.centerLeft, child: Container(width: 120, height: 8, decoration: BoxDecoration(color: const Color(0xFF7000ff), borderRadius: BorderRadius.circular(4)))),
          ),
          const SizedBox(height: 40),
          const CircularProgressIndicator(color: Color(0xFF7000ff)),
          const SizedBox(height: 30),
          const Text("Reticulando splines...", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          const Text("A maioria leva 2 minutos, mas seus amigos são... especiais.", style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildJudgingScreen() {
    return Column(
      children: [
         Text(isJudge ? "Você é o Juiz!" : "O Juiz está escolhendo...", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
         const SizedBox(height: 16),
         Container(
           padding: const EdgeInsets.all(16),
           decoration: BoxDecoration(
             border: Border.all(color: Colors.grey.withOpacity(0.3)),
             borderRadius: BorderRadius.circular(12)
           ),
           child: Text(currentQuestion, style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
         ),
         const SizedBox(height: 20),
         Expanded(
           child: GridView.builder(
             gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.75,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
             ),
             itemCount: tableCards.length,
             itemBuilder: (ctx, i) {
                final card = tableCards[i];
                final bool revealed = card['revealed'] ?? false;
                
                return GestureDetector(
                  onTap: () => handleJudgeTap(i),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: revealed ? Colors.white : const Color(0xFF1a1625),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: revealed ? Colors.white : const Color(0xFF7000ff)),
                      boxShadow: [
                         if (revealed) BoxShadow(color: Colors.white.withOpacity(0.1), blurRadius: 10)
                      ]
                    ),
                    child: revealed ? 
                       Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                             Text(card['text'], style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
                             if (isJudge) const Align(alignment: Alignment.bottomRight, child: Icon(Icons.check_circle_outline, color: Color(0xFF7000ff)))
                          ],
                       )
                       : const Center(child: Text("?", style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Color(0xFF7000ff)))),
                  ),
                );
             },
           ),
         ),
      ],
    );
  }

  Widget _buildResultScreen() {
    List<dynamic> scores = [];
    String? winnerAvatar;
    
    if (winnerInfo != null && winnerInfo!['scores'] != null) {
        scores = List<dynamic>.from(winnerInfo!['scores']);
        // Sort by score desc
        scores.sort((a,b) => (b['score'] ?? 0).compareTo(a['score'] ?? 0));

        final winnerObj = scores.firstWhere(
           (p) => p['name'] == winnerInfo!['winnerName'], 
           orElse: () => null
        );
        if (winnerObj != null) winnerAvatar = winnerObj['avatar'];
    }

    ImageProvider? getAvatarImage(String? av) {
       if (av != null && av.isNotEmpty && av.toLowerCase().endsWith('.png')) {
           return AssetImage('assets/avatars/$av');
       }
       return null;
    }

    return Column(
      children: [
         const SizedBox(height: 20),
         // WINNER SECTION
         Center(
           child: Container(
             width: 120, height: 120, 
             decoration: BoxDecoration(
               shape: BoxShape.circle, 
               border: Border.all(color: const Color(0xFF7000ff), width: 4), 
               color: const Color(0xFF22202b),
               image: winnerAvatar != null 
                  ? DecorationImage(image: getAvatarImage(winnerAvatar)!, fit: BoxFit.cover)
                  : null
             ),
             child: (winnerAvatar == null || winnerAvatar!.isEmpty) 
               ? Center(child: Text(winnerInfo!['winnerName'][0].toUpperCase(), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold))) 
               : null,
           ),
         ),
         const SizedBox(height: 10),
         Center(child: Text("${winnerInfo!['winnerName']} venceu!", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold))),
         const Center(child: Text("Ganhou +1 ponto.", style: TextStyle(color: Colors.grey))),
         
         const SizedBox(height: 20),
         
         // WINNING CARD
         Container(
           margin: const EdgeInsets.symmetric(horizontal: 24),
           width: double.infinity,
           padding: const EdgeInsets.all(20),
           decoration: BoxDecoration(
             color: const Color(0xFF7000ff),
             borderRadius: BorderRadius.circular(20),
             boxShadow: [BoxShadow(color: const Color(0xFF7000ff).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))]
           ),
           child: Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
                const Text("A COMBINAÇÃO VENCEDORA", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white54)),
                const SizedBox(height: 10),
                Text("\"${winnerInfo!['winningCard']}\"", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
             ],
           ),
         ),

         const SizedBox(height: 30),
         
         // SCOREBOARD LIST
         const Padding(
           padding: EdgeInsets.symmetric(horizontal: 24),
           child: Align(alignment: Alignment.centerLeft, child: Text("Placar", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
         ),
         const SizedBox(height: 10),

         Expanded(
           child: ListView.separated(
             padding: const EdgeInsets.symmetric(horizontal: 24),
             itemCount: scores.length,
             separatorBuilder: (_, __) => const SizedBox(height: 8),
             itemBuilder: (ctx, i) {
                final p = scores[i];
                final bool isWinner = p['name'] == winnerInfo!['winnerName'];
                final image = getAvatarImage(p['avatar']);
                
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                     color: isWinner ? const Color(0xFF7000ff).withOpacity(0.2) : Colors.white.withOpacity(0.05),
                     borderRadius: BorderRadius.circular(12),
                     border: isWinner ? Border.all(color: const Color(0xFF7000ff)) : null,
                  ),
                  child: Row(
                    children: [
                       CircleAvatar(
                         radius: 18,
                         backgroundColor: Colors.primaries[p['name'].length % Colors.primaries.length],
                         backgroundImage: image,
                         child: image == null ? Text(p['name'][0].toUpperCase()) : null,
                       ),
                       const SizedBox(width: 12),
                       Expanded(
                         child: Text(
                           p['name'], 
                           style: TextStyle(fontWeight: isWinner ? FontWeight.bold : FontWeight.normal, color: isWinner ? const Color(0xFFae66ff) : Colors.white)
                         )
                       ),
                       Text("${p['score']} pts", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                );
             },
           ),
         ),
         
         const SizedBox(height: 20),
         Padding(
           padding: const EdgeInsets.symmetric(horizontal: 24),
           child: SizedBox(
             width: double.infinity,
             height: 55,
             child: ElevatedButton(
               onPressed: () => setState(() => view = 'LOBBY'), 
               style: ElevatedButton.styleFrom(
                 backgroundColor: const Color(0xFF7000ff),
                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))
               ),
               child: const Text("Próxima Rodada", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
             ),
           ),
         ),
         const SizedBox(height: 20),
      ],
    );
  }
}
