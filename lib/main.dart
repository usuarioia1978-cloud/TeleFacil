import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TeleFacilApp());
}

class TeleFacilApp extends StatelessWidget {
  const TeleFacilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TeleFácil',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFE50914),
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
        cardColor: const Color(0xFF1E1E1E),
      ),
      home: const HomeScreen(),
    );
  }
}

class Channel {
  final String id;
  final String name;
  final String url;
  final String logo;
  final String group;

  Channel({
    required this.id,
    required this.name,
    required this.url,
    required this.logo,
    required this.group,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String m3uUrl = "https://iptv-org.github.io/iptv/countries/ar.m3u";
  
  List<Channel> allChannels = [];
  Set<String> favoriteIds = {};
  bool isLoading = true;
  String errorMessage = "";
  String searchQuery = "";
  String selectedCategory = "★ Favoritos";

  @override
  void initState() {
    super.initState();
    _loadFavoritesAndData();
  }

  Future<void> _loadFavoritesAndData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedFavs = prefs.getStringList('favorite_channels') ?? [];
    final savedUrl = prefs.getString('custom_m3u_url');
    if (savedUrl != null && savedUrl.isNotEmpty) {
      m3uUrl = savedUrl;
    }

    setState(() {
      favoriteIds = savedFavs.toSet();
    });

    _fetchM3U();
  }

  Future<void> _toggleFavorite(Channel ch) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (favoriteIds.contains(ch.url)) {
        favoriteIds.remove(ch.url);
      } else {
        favoriteIds.add(ch.url);
      }
    });
    await prefs.setStringList('favorite_channels', favoriteIds.toList());
  }

  Future<void> _fetchM3U() async {
    setState(() {
      isLoading = true;
      errorMessage = "";
    });

    try {
      final res = await http.get(Uri.parse(m3uUrl));
      if (res.statusCode == 200) {
        final parsed = _parseM3U(res.body);
        setState(() {
          allChannels = parsed;
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = "Error al descargar lista (código ${res.statusCode})";
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = "No se pudo conectar a la lista: $e";
        isLoading = false;
      });
    }
  }

  List<Channel> _parseM3U(String content) {
    final List<Channel> list = [];
    final lines = content.split('\n');
    String currentName = "";
    String currentGroup = "General";
    String currentLogo = "";

    final regName = RegExp(r',(.+)$');
    final regGroup = RegExp(r'group-title="([^"]+)"');
    final regLogo = RegExp(r'tvg-logo="([^"]+)"');

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i].trim();
      if (line.startsWith("#EXTINF:")) {
        final matchName = regName.firstMatch(line);
        if (matchName != null) {
          currentName = matchName.group(1)?.trim() ?? "Sin nombre";
        }
        final matchGroup = regGroup.firstMatch(line);
        if (matchGroup != null) {
          currentGroup = matchGroup.group(1)?.trim() ?? "General";
        } else {
          currentGroup = "General";
        }
        final matchLogo = regLogo.firstMatch(line);
        if (matchLogo != null) {
          currentLogo = matchLogo.group(1)?.trim() ?? "";
        } else {
          currentLogo = "";
        }
      } else if (line.isNotEmpty && !line.startsWith("#")) {
        if (currentName.isNotEmpty) {
          list.add(Channel(
            id: line,
            name: currentName,
            url: line,
            logo: currentLogo,
            group: currentGroup,
          ));
          currentName = "";
          currentGroup = "General";
          currentLogo = "";
        }
      }
    }
    return list;
  }

  void _showSettingsDialog() {
    final textController = TextEditingController(text: m3uUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Configuración de Lista M3U"),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            hintText: "Pegá la URL de tu lista M3U",
            labelText: "Enlace M3U",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              final newUrl = textController.text.trim();
              if (newUrl.isNotEmpty) {
                await prefs.setString('custom_m3u_url', newUrl);
                setState(() {
                  m3uUrl = newUrl;
                });
                Navigator.pop(ctx);
                _fetchM3U();
              }
            },
            child: const Text("Guardar y Recargar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Set<String> groups = {"★ Favoritos", "Todos"};
    for (var ch in allChannels) {
      if (ch.group.isNotEmpty) groups.add(ch.group);
    }
    final categoryList = groups.toList();

    List<Channel> filtered = allChannels.where((ch) {
      final matchesSearch = ch.name.toLowerCase().contains(searchQuery.toLowerCase());
      if (!matchesSearch) return false;

      if (selectedCategory == "★ Favoritos") {
        return favoriteIds.contains(ch.url);
      } else if (selectedCategory == "Todos") {
        return true;
      } else {
        return ch.group == selectedCategory;
      }
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.tv, color: Colors.redAccent, size: 28),
            SizedBox(width: 8),
            Text(
              "TeleFácil",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Recargar canales",
            onPressed: _fetchM3U,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: "Configurar lista",
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
            child: TextField(
              style: const TextStyle(fontSize: 18),
              onChanged: (val) => setState(() => searchQuery = val),
              decoration: InputDecoration(
                hintText: "Buscar canal...",
                prefixIcon: const Icon(Icons.search, size: 26),
                filled: true,
                fillColor: const Color(0xFF242424),
                contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: categoryList.length,
              itemBuilder: (ctx, idx) {
                final cat = categoryList[idx];
                final isSelected = cat == selectedCategory;
                final isFavTab = cat == "★ Favoritos";

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : Colors.grey[400],
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: isFavTab ? Colors.amber[800] : Colors.redAccent[700],
                    backgroundColor: const Color(0xFF2A2A2A),
                    onSelected: (selected) {
                      if (selected) setState(() => selectedCategory = cat);
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.redAccent),
                        SizedBox(height: 16),
                        Text("Cargando canales...", style: TextStyle(fontSize: 18)),
                      ],
                    ),
                  )
                : errorMessage.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 60),
                              const SizedBox(height: 12),
                              Text(errorMessage, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _fetchM3U,
                                child: const Text("Reintentar"),
                              )
                            ],
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  selectedCategory == "★ Favoritos" ? Icons.star_border : Icons.tv_off,
                                  size: 70,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  selectedCategory == "★ Favoritos"
                                      ? "No agregaste ningún favorito todavía.\n¡Tocá la estrella en cualquier canal para guardarlo acá!"
                                      : "No se encontraron canales en esta sección.",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) {
                              final ch = filtered[i];
                              final isFav = favoriteIds.contains(ch.url);

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 5),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PlayerScreen(channel: ch),
                                      ),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 55,
                                          height: 55,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2C2C2C),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: ch.logo.isNotEmpty
                                              ? ClipRRect(
                                                  borderRadius: BorderRadius.circular(10),
                                                  child: Image.network(
                                                    ch.logo,
                                                    fit: BoxFit.contain,
                                                    errorBuilder: (_, __, ___) => const Icon(Icons.tv, color: Colors.white60),
                                                  ),
                                                )
                                              : const Icon(Icons.tv, color: Colors.white60, size: 30),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                ch.name,
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                ch.group,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[400],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          iconSize: 32,
                                          icon: Icon(
                                            isFav ? Icons.star : Icons.star_border,
                                            color: isFav ? Colors.amber : Colors.grey[600],
                                          ),
                                          onPressed: () => _toggleFavorite(ch),
                                        ),
                                        const Icon(Icons.play_circle_fill, color: Colors.redAccent, size: 36),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  final Channel channel;
  const PlayerScreen({super.key, required this.channel});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.channel.url),
      );

      await _videoController.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoController,
        autoPlay: true,
        isLive: true,
        showControls: true,
        fullScreenByDefault: false,
        allowFullScreen: true,
        aspectRatio: _videoController.value.aspectRatio,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              "Error al reproducir señal:\n$errorMessage",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          );
        },
      );
      setState(() {});
    } catch (e) {
      setState(() {
        _hasError = true;
      });
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _videoController.dispose();
    _chewieController?.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.channel.name),
      ),
      body: Center(
        child: _hasError
            ? Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.signal_wifi_connected_no_internet_4, color: Colors.orange, size: 50),
                    const SizedBox(height: 12),
                    const Text(
                      "La señal de este canal no está disponible temporalmente.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Volver a la lista"),
                    ),
                  ],
                ),
              )
            : _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
                ? Chewie(controller: _chewieController!)
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Colors.redAccent),
                      SizedBox(height: 16),
                      Text("Sintonizando canal...", style: TextStyle(color: Colors.white, fontSize: 17)),
                    ],
                  ),
      ),
    );
  }
}
