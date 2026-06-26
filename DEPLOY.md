# 클라우드 배포 가이드 (Render 무료 티어) + 폰 앱 빌드

목표: 백엔드를 클라우드에서 돌려서, 설치한 폰 앱이 **어디서나** 동작하게 만들기
(LTE, 친구 폰, PC 꺼져 있어도). 그다음 그 주소를 박은 APK를 빌드한다.

모든 설정이 **환경변수**로만 동작하므로, 나중에 Railway/Fly로 옮길 때도
`DATABASE_URL`만 바꿔서 재배포하면 된다 — 코드 수정 없음.

---

## Part A — 백엔드를 Render에 올리기

### 1. GitHub에 코드 푸시
Render는 Git 저장소에서 배포한다. 프로젝트 루트(`CNO/`)에서:
```bash
git init
git add .
git commit -m "baccarat backend + flutter app"
# github.com 에서 빈 저장소를 하나 만든 뒤:
git remote add origin https://github.com/<아이디>/<저장소>.git
git branch -M main
git push -u origin main
```
(`node_modules/`, `data/`, `*.db`, Flutter `build/` 는 git에서 제외돼 있음)

### 2. 블루프린트로 서비스 생성
1. <https://render.com> 가입 (무료, GitHub 로그인이 가장 쉬움)
2. **New ▸ Blueprint** → GitHub 저장소 연결
3. Render가 `render.yaml`을 읽어 **웹 서비스 + 무료 Postgres**를 제안 → **Apply**
4. 첫 빌드/배포까지 약 3~5분 대기. 아래 같은 주소를 받는다:
   `https://baccarat-xxxx.onrender.com`

### 3. 살아있는지 확인
```bash
curl https://baccarat-xxxx.onrender.com/healthz   # -> ok
```
WebSocket 주소는 같은 호스트에 `wss://`:
`wss://baccarat-xxxx.onrender.com`

> 무료 티어 주의: 약 15분 동안 접속이 없으면 **잠자기** 상태가 되고, 잠든 뒤
> 첫 접속은 깨어나느라 30~50초 걸린다(콜드 스타트). 무료 Postgres는 수명
> 제한이 있다 — 프로토타입엔 충분하고, 준비되면 Railway(유료) 또는 새
> `DATABASE_URL`로 옮기면 된다.

---

## Part B — 클라우드 주소를 박아서 폰 앱 빌드

2단계에서 받은 진짜 주소로 APK를 빌드한다 (`wss://` 주의):
```bash
cd app
flutter build apk --release --dart-define=SERVER_URL=wss://baccarat-xxxx.onrender.com
```
APK 위치:
```
app/build/app/outputs/flutter-apk/app-release.apk
```

### 폰에 설치
- **USB:** 폰 연결 후 `flutter install`, 또는 APK를 폰으로 복사해서 탭
- **다운로드:** APK를 폰에서 접근 가능한 곳에 올려두고 폰 브라우저로 열기
- 첫 설치 때 **"알 수 없는 출처 설치 허용"** 을 묻는다 — 허용

앱을 열면 `wss://`로 클라우드 백엔드에 접속해서 **어디서나** 동작한다
(PC를 더 이상 켜둘 필요 없음).

---

## 나중에 Railway로 옮기기
1. Railway 프로젝트 + Postgres 생성
2. 이 저장소를 배포 (Railway가 Node 자동 인식, 시작 명령 `node src/server.ts`)
3. 환경변수 설정: `DATABASE_URL`(Railway Postgres), `DATABASE_SSL=true`
4. 새 주소로 APK 재빌드: `--dart-define=SERVER_URL=wss://...railway.app`

소스 변경 없음 — 앱은 설계상 어느 호스트로든 이식 가능하다.

## 환경변수 정리
| 변수 | 용도 |
|---|---|
| `PORT` | 리슨 포트 (호스트가 자동 설정, 로컬 기본 8080) |
| `DATABASE_URL` | Postgres 접속 문자열 → 영속 Postgres 지갑+계정 활성화 |
| `DATABASE_SSL` | `true`면 SSL로 접속 (대부분의 관리형 Postgres에 필요) |
| `BETTING_MS` / `SETTLE_DELAY_MS` / `PAUSE_MS` | 라운드 타이밍 |
