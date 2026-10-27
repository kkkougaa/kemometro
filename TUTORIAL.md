# 처음부터 끝까지: 윈도우만으로 아이폰에 올리기

지금 상태: 코드는 다 있고, 한 번도 빌드 안 됨, git 커밋 안 됨. 아래를 순서대로.

## 0. 준비물 (한 번만)

- GitHub 개인 계정 (회사 조직 말고)
- 윈도우 PC 에 git (이미 있음), 아이폰 케이블
- [Sideloadly](https://sideloadly.io) 와 iTunes(애플 공식 설치판, MS 스토어판 말고)
- 서울 열린데이터광장 인증키 ([신청 페이지](https://data.seoul.go.kr/dataList/OA-12764/F/1/datasetView.do) → 인증키 신청 → 바로 발급)

## 1. GitHub 에 올리기 (5분)

1. github.com → New repository → 이름 `train-live`, Public, README 없이 Create.
2. PowerShell 에서:
   ```bash
   cd C:\Users\neogul\train-live
   git add -A
   git commit -m "train-live: live activity app"
   git branch -M main
   git remote add origin https://github.com/<내계정>/train-live.git
   git push -u origin main
   ```
   처음 push 땐 GitHub 로그인 창이 뜬다.

## 2. 빌드 기다리기 (10~15분)

1. 저장소 → Actions 탭 → "Build unsigned IPA" 가 돌고 있다. `build` 와 `simulator` 두 job.
2. 초록 체크면 아래 Artifacts 에서 받는다.
   - `TrainLive-unsigned-ipa` → 압축 풀면 `TrainLive-1.0-unsigned.ipa`
   - `simulator-shots` → `01-preview.png`(앱 안 디자인 미리보기), `02-demo.mp4`(등장 애니메이션), `03/04-island-*.png`(아일랜드)
3. 빨간 X 면 job 을 눌러 "오류 요약" 단계를 펼치거나 `build-log` 아티팩트를 받아서 그대로 붙여 주면 고친다. 첫 빌드는 한두 번 왕복할 가능성이 있다.

## 3. 아이폰에 설치 (5분)

1. 아이폰을 케이블로 연결하고 "이 컴퓨터를 신뢰" 를 누른다.
2. Sideloadly 실행 → ipa 를 창에 끌어다 놓기 → Apple ID 입력 → Start → Apple ID 비밀번호(2단계 인증 코드) 입력.
   - 무료 계정이면 "Advanced Options" 는 기본값 그대로. 앱 + 위젯 익스텐션 두 개가 서명된다.
3. 아이폰 설정 → 일반 → VPN 및 기기 관리 → 내 Apple ID → 신뢰.

## 4. 앱 설정 (3분)

1. "열차 위치" 앱을 연다. 위치 권한 창이 뜨면 허용.
2. 설정 앱 → 열차 위치 → 위치 → **항상** 으로 바꾼다. (앱 안 권한 칸에 "항상" 으로 초록색이 되면 OK)
3. 설정 앱 → 열차 위치 → 라이브 활동 켜짐 확인.
4. 앱 → API 키 칸에 인증키 붙여넣기.
5. 판교를 눌러 "지금 열차로 방면 확인" → "신사행" 이 체크돼 있는지 보고, 아니면 신사행 버튼을 누른다. 논현도 광교행으로.
6. "지금 미리보기" 를 누르고 홈으로 나간다. 다이내믹 아일랜드에 뜨고 5초마다 움직이다 3분 뒤 사라지면 성공.
7. 아일랜드를 길게 눌러 "탑승" 을 누르면 추적 모드로 바뀐다. 역마다 "내릴 역" 을 넣어 두면 남은 역 수가 나온다(신분당선).

## 5. 실제 출근길

판교역 500m 안에 들어가면 자동으로 뜬다. 안 뜨면 앱 → 권한 칸의 "마지막 이벤트" 와 "기록" 을 보고 알려 달라.
- 위치가 "항상" 이 아니면 앱이 꺼진 상태에서 못 깨어난다.
- 저전력 모드면 진입 감지가 늦다.
- 같은 역은 5분 안에 다시 안 뜬다(설정에서 조절).

## 6. 7일마다

무료 계정 서명은 7일이면 만료된다. 3번만 다시 하면 되고 설정은 남는다.

## 고치고 싶을 때

코드를 바꾸고 `git add -A && git commit -m "..." && git push` 하면 Actions 가 다시 돌고, 새 ipa 를 3번으로 다시 넣는다.
모양만 볼 땐 `preview/index.html` 을 브라우저로 열면 동작 흐름 목업이 있고, 아이폰에선 앱 → 표시 → 디자인 미리보기.
