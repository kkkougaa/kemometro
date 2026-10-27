# kemometro (TrainLive)

역에 가까워지면 정해 둔 방면 열차가 몇 역 전인지 **라이브 액티비티**(다이내믹 아일랜드 + 잠금화면)로 떴다가 3분 뒤 사라지는 iOS 앱. 띄워 둔 동안 5초마다 갱신.
기본값은 판교(신사행)·논현(광교행), 앱 안에서 역·방면·반경·시간을 바꿀 수 있다.

맥이 없어도 된다. 빌드는 GitHub Actions 의 macOS 러너가 하고, 무서명 ipa 를 Sideloadly 로 무료 개발자 계정 서명해 넣는다.

## 구조

```
project.yml                 XcodeGen 정의(타깃·Info.plist·ATS 예외). .xcodeproj 는 CI 에서 생성
Shared/                     앱·위젯 공용
  TrainActivityAttributes   라이브 액티비티 데이터(역·노선·방면, 열차 목록, phase)
  TrackView                 RouteProgressView: 노선 진행 바 + 전동차 마커(SF Symbol tram.fill). n 이 바뀌면 스프링으로 미끄러짐
  Lines                     노선표·색·배지
TrainLive/                  앱
  LocationMonitor           역마다 원형 지오펜스. 진입 → ActivityController
  ActivityController        조회 → 액티비티 시작(열차 화면 밖) → 0.35초 뒤 실제 위치로 → 5초마다 갱신 → 3분 뒤 종료
  SubwayAPI / TrainStatus   서울시 실시간 도착정보 호출·파싱(Scriptable 위젯과 같은 규칙)
  Models                    Place(역·방면·좌표·반경·시간), AppConfig, UserDefaults 저장
  ContentView               설정 화면. 키, 역 목록, 권한, "지금 미리보기"
  DesignPreviewView         라이브 액티비티 뷰를 앱 안에서 그려 보는 화면(-preview 로 바로 진입)
  ActivityViews (Shared)    잠금화면 배너·아일랜드 조각. 위젯과 미리보기가 같은 뷰를 쓴다
  DemoData (Shared)         키 없이 쓰는 가짜 열차, 실행 플래그(-preview, -demo)
TrainLiveWidget/            위젯 익스텐션: 잠금화면 배너 + 다이내믹 아일랜드(확장·컴팩트·미니멀)
preview/index.html          동작 흐름 HTML 목업(지오펜스 → 등장 → 갱신 → 소멸). 디자인 규격의 기준
.github/workflows/build.yml 무서명 ipa 빌드 + 시뮬레이터 스크린샷·영상
```

## 동작

1. 앱이 `Place` 마다 `CLCircularRegion`(기본 500m) 을 건다. 위치 권한은 **항상** 이어야 앱이 꺼진 상태에서도 깨어난다.
2. 반경에 들어오면 iOS 가 앱을 백그라운드로 띄우고 `didEnterRegion` 이 불린다.
3. `ActivityController` 가 위치 업데이트를 켜서 앱을 깨워 두고(백그라운드 location 모드), API 를 조회해 라이브 액티비티를 띄운다.
   처음엔 열차를 선로 오른쪽 바깥에 둔 상태(phase 0)로 띄우고 0.35초 뒤 실제 자리로 갱신해, 시스템 등장 애니메이션 위에 열차가 미끄러져 들어오는 효과를 낸다.
4. 보여주는 동안 5초마다 다시 조회해 열차를 움직이고, 3분이 되면 `end(dismissalPolicy: .immediate)` 로 치운다.
   iOS 가 중간에 백그라운드 실행을 끊으면 `end(dismissalPolicy: .after(endsAt))` 로 넘겨 시스템이 제시간에 치운다.
5. 같은 역은 5분(설정) 안에 다시 띄우지 않는다. 지오펜스가 경계에서 튀는 것 방지.
6. **탑승**: 액티비티의 "탑승" 버튼(`BoardTrainIntent`, LiveActivityIntent 라 앱 프로세스에서 실행)을 누르면 접근 루프가 액티비티를
   추적 루프에 넘긴다. 노선별 열차 위치 API(`realtimePosition/0/100/{노선명}`)에서 열차 번호로 내 열차를 찾고, 못 찾으면 탑승역에 있는
   열차를 고른다. `Shared/StationOrders.swift` 의 역 순서표로 다음 역·남은 역 수·도착을 계산한다(신분당선만 있음, 다른 노선은 지금 역만).
   15초마다 갱신, "하차"·90분에 종료. 목적지·빠른 환승·도착 표시는 없다(현재 위치만). 타는 동안 위치 업데이트로 앱을 깨워 둔다.

알아 둘 것
- 띄워 둔 3분 동안은 위치를 계속 받으므로 상태 표시줄에 위치 화살표가 켜진다. 끝나면 끈다.
- API 호출은 역당 3분 × 5초 = 약 36번. 하루 출퇴근 2역이면 150번 안팎으로 일 1,000건 한도 안.
- 지오펜스 진입 감지는 보통 수십 초, 저전력 모드면 더 늦다. 반경을 500m 로 둔 이유.
- 무료 개발자 계정: 7일마다 다시 서명해 설치해야 하고, 푸시는 못 쓴다(이 앱은 푸시 없이 동작).

## ipa 만들기 (GitHub Actions)

1. 개인 GitHub 에 저장소를 하나 만든다(공개면 macOS 러너 분량 무제한, 비공개는 월 한도 있음).
2. 이 폴더를 올린다.
   ```bash
   git init && git add -A && git commit -m "train-live"
   git branch -M main
   git remote add origin https://github.com/<계정>/train-live.git
   git push -u origin main
   ```
3. GitHub → Actions → "Build unsigned IPA" 가 돌고 나면 Artifacts 에서 `TrainLive-unsigned-ipa` 를 받는다. 실패하면 `build-log` 아티팩트와 "오류 요약" 단계를 본다.

같은 워크플로의 `simulator` job 이 맥 없이 모양을 확인하는 용도다. 시뮬레이터용으로 다시 빌드해 iPhone Pro 시뮬레이터에 깔고
- `-preview` 로 실행해 앱 안 **디자인 미리보기** 화면(잠금화면 배너·아일랜드 펼침·컴팩트·미니멀)을 `01-preview.png` 로,
- `-demo` 로 실행해 가짜 열차로 라이브 액티비티를 띄운 뒤 설정 앱으로 빠져나가 아일랜드에 뜬 모습을 `03/04-*.png` 로, 등장부터 열차가 한 칸 다가오는 갱신까지를 `02-demo.mp4` 로

`simulator-shots` 아티팩트에 올린다. 펼친 아일랜드와 잠금화면은 터치가 필요해 자동으로 못 찍으니 미리보기 화면 쪽을 본다.
앱 안에서도 설정 → 표시 → 디자인 미리보기로 같은 화면을 열 수 있고, "다시 재생"으로 등장 애니메이션을 반복한다.

데모 모드는 실행 인자 `-demo` 또는 환경변수 `TRAINLIVE_DEMO=1` 이면 켜지고, 키 없이 첫 번째 역을 `Shared/DemoData.swift` 의 가짜 열차로 띄운다.

## 아이폰에 넣기 (Sideloadly)

1. PC 에 iTunes(애플 공식 설치판)와 [Sideloadly](https://sideloadly.io) 를 설치하고 아이폰을 USB 로 연결한다.
2. Sideloadly 에 ipa 를 끌어다 놓고 Apple ID 를 넣고 Start. 앱과 위젯 익스텐션 둘 다 서명한다(무료 계정은 일주일에 앱 ID 10개 제한, 이 앱은 2개 쓴다).
3. 아이폰 설정 → 일반 → VPN 및 기기 관리 → 내 Apple ID 를 신뢰.
4. 앱을 열어 API 키를 넣고, 위치 권한을 허용한 뒤 설정 → kemometro → 위치 → **항상** 으로 바꾼다. 라이브 액티비티도 켜 둔다.
5. 역을 눌러 "지금 열차로 방면 확인"으로 신사행/광교행이 맞는지 보고, "지금 미리보기"로 띄워 본다. 홈으로 나가면 다이내믹 아일랜드에 보인다.

7일이 지나면 Sideloadly 로 다시 설치하면 된다(설정은 남는다).

## 데이터

서울시 실시간 지하철 도착정보 `http://swopenAPI.seoul.go.kr/api/subway/{KEY}/json/realtimeStationArrival/0/60/{역명}`.
http 전용이라 `project.yml` 의 ATS 예외에 도메인을 넣어 두었다. `arvlCd` 0 진입 · 1 도착 · 2 출발(숨김) · 3~5 전역 · 99 운행 중, `[n]번째 전역` 에서 n 을 읽는다.
