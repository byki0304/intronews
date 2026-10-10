class AppConfig {
  static const projectId = 'intronews';
  static const region = 'asia-northeast3';
  static const adminEmail = 'nfriend02@naver.com';
  static const maxProposedCharacters = 12;
  static const maxGeneratedCharacters = 9;
  static const textModel = 'gemini-3.8-flash';
  static const imageModel = 'gemini-3-pro-image';
  static const flowWebUrl = 'https://labs.google/fx/tools/flow';
  static const packageName = 'com.example.intronews';
  static const anonymousProjectsPersist = true;
  static const useEmulators = bool.fromEnvironment('USE_EMULATORS');

  static const sceneIds = [
    '01',
    '02',
    '03',
    '04',
    '05',
    '06',
    '07',
    '08',
    '09',
    '10',
  ];

  static const stepTitles = [
    '자료 준비',
    '스토리보드',
    '장면 카드',
    '캐릭터',
    '본편 프롬프트',
    '오프닝 프롬프트',
    '클로징 프롬프트',
    '완성 패키지',
  ];
}

class AppColors {
  static const navy = 0xFF0B1F3A;
  static const news = 0xFFF5A623;
  static const lecture = 0xFF1F8A70;
  static const paper = 0xFFF6F3EC;
  static const ink = 0xFF142033;
}
