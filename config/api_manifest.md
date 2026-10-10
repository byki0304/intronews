# API manifest

비밀 값은 적지 않는다. 키 원문은 `functions/.env`에만 둔다.

## Gemini API

- 용도: 시놉시스, 장면 카드, 조연 캐릭터 프롬프트, 16:9 영상 프롬프트, 음악 프롬프트, 조연 이미지 1장. PDF도 이 API로 전달한다.
- 발급 위치: Google AI Studio, `generativelanguage.googleapis.com`
- 값 위치: `functions/.env`의 `GEMINI_API_KEY`
- 모델 이름: `GEMINI_TEXT_MODEL=gemini-3.8-flash` (thinking high), `GEMINI_IMAGE_MODEL=gemini-3-pro-image` (세로 3:4, 2K)
- 텍스트는 이 키로 호출된다. 이미지 모델은 Gemini API 무료 한도가 없다. Google AI Pro 앱 구독과 API 결제 계정은 별개이며, 이미지 생성은 AI Studio에서 이 키의 프로젝트에 결제 계정을 연결해야 한다.
- 호출 위치: Cloud Functions만. Flutter 앱, 웹 번들, Firestore에는 키를 넣지 않는다.

## Google Flow 웹

- 용도: 사용자가 확정 프롬프트와 참조 이미지를 붙여 16:9 영상을 만든다. 앱은 영상을 생성하지 않는다.
- 주소: `FLOW_WEB_URL=https://labs.google/fx/tools/flow`
- 값 위치: `functions/.env`, `lib/config.dart`

## Firebase

- 프로젝트 ID: `intronews`
- 리전: `asia-northeast3`
- 패키지 이름: `com.example.intronews`
- 관리자 이메일: `nfriend02@naver.com` (`allowlist`의 admin, active)
- 조연 제안 상한: 12, 생성 상한: 9
- 익명 프로젝트 유지: true
- 클라이언트 구성: `flutterfire configure`가 만드는 `lib/firebase_options.dart`
- Functions 런타임: 배포 환경의 기본 자격 증명. 서비스 계정 JSON은 저장소에 넣지 않는다.
- 배포 대상: Hosting, Firestore rules, Storage rules, Functions

로컬 수정은 Firebase 에뮬레이터와 `flutter run` 웹 서버를 함께 쓴다. 앱 주소는 `http://localhost:8080` 이다. Auth 에뮬레이터는 이 호스트에서만 페이지 시작 전에 연결된다.

쓰지 않는 것: Google Flow API 키, Flow Music API 키, Premiere API, OpenAI API, Vercel 토큰.
