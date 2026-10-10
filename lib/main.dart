import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'backend.dart';
import 'config.dart';
import 'state/session.dart';
import 'ui/account_page.dart';
import 'ui/home_page.dart';
import 'ui/library_page.dart';
import 'ui/login_page.dart';
import 'ui/logo.dart';
import 'ui/project_page.dart';

Future<void> main() async {
  await Backend.start();
  runApp(const IntroNewsApp());
}

class IntroNewsApp extends StatelessWidget {
  const IntroNewsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => Session(),
      child: MaterialApp(
        title: 'IntroNews',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(AppColors.paper),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(AppColors.navy),
            primary: const Color(AppColors.navy),
            secondary: const Color(AppColors.news),
          ),
          fontFamilyFallback: const [
            'Malgun Gothic',
            'Apple SD Gothic Neo',
            'Noto Sans KR',
            'sans-serif',
          ],
          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        ),
        home: const RootPage(),
      ),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int section = 0;
  String? projectId;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    if (!session.ready || (session.user != null && !session.signedIn)) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!session.signedIn) return LoginPage(session: session);
    final narrow = MediaQuery.sizeOf(context).width < 720;
    final body = projectId != null
        ? ProjectPage(
            key: ValueKey(projectId),
            projectId: projectId!,
            onExit: () => setState(() => projectId = null),
          )
        : switch (section) {
            1 => const LibraryPage(),
            2 => AccountPage(session: session),
            _ => HomePage(onOpen: (id) => setState(() => projectId = id)),
          };
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            width: narrow ? 168 : 220,
            section: projectId != null ? 0 : section,
            session: session,
            onSelect: _select,
          ),
          Expanded(child: body),
        ],
      ),
    );
  }

  void _select(int index) {
    if (index == 3) {
      context.read<Session>().signOut();
      return;
    }
    setState(() {
      section = index;
      projectId = null;
    });
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.width,
    required this.section,
    required this.session,
    required this.onSelect,
  });

  final double width;
  final int section;
  final Session session;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      color: const Color(AppColors.navy),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              child: IntroNewsLogo(onDark: true, markSize: width < 200 ? 28 : 36),
            ),
            _pill(0, '프로젝트'),
            _pill(2, '마이페이지'),
            _pill(1, '이미지 라이브러리'),
            _pill(3, '로그아웃', logout: true),
          ],
        ),
      ),
    );
  }

  Widget _pill(int index, String label, {bool logout = false}) {
    final selected = !logout && section == index;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Material(
        color: const Color(AppColors.news),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: logout ? () => session.signOut() : () => onSelect(index),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: selected ? Border.all(color: Colors.white, width: 2) : null,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}
