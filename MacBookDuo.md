# MacBook Duo

앱 이름: MacBook Duo
번들 ID: io.github.jinnyday0719.macbookduo

Stage 1 소스와 앱은 그대로 보존합니다. 새 앱은 Sources/MacBookDuo의
독립 타깃이며 Stage 1의 센서와 셰이더를 복사한 시점부터 별도로 개발합니다.

## 빌드

```sh
zsh build-app.sh
```

결과: Build/MacBook Duo.app
Stage 1 실행: swift run MacBookDuoStage1

## 현재 동작

- 설정의 로그인 시 자동 시작 체크박스로 macOS 로그인 항목 등록/해제. SMAppService.mainApp을 사용하며 실제 시스템 상태를 표시. 승인이 필요한 경우 로그인 항목 설정으로 안내.

- Dock 아이콘 없이 메뉴바에 상주. 앱 실행 직후 자동으로 권한·센서·효과를 준비하며, 메뉴에는 설정과 MacBook Duo 종료만 표시.
- 설정 창을 닫아도 앱은 계속 실행. 메뉴/설정 조작 중에는 효과를 잠시 숨김.
- 화면 기록 권한을 사용하며 녹화 파일/오디오를 저장하거나 전송하지 않음.
- 최초 실행 시 화면 기록 권한 요청을 자동으로 표시. 허용하지 않은 경우 설정 창에서 시스템 권한 화면을 다시 열 수 있음.
- 본체 디스플레이만 ScreenCaptureKit으로 캡처.
- 자기 앱 전체(효과 창과 제어 창)를 제외해 재귀 캡처 방지.
- 최신 캡처 버퍼를 Core Video Metal 텍스처로 연결하고 GPU 완료까지 유지.
- 최초 실행부터 1.5초간 기본 ±2° 이내로 유지된 각도의 평균을 반올림하여 기준으로 자동 저장.
- 안정 판정은 구간 첫 각도를 고정 중심으로 사용. 허용 범위를 벗어나거나 센서가 0.5초 이상 끊기면 다시 측정.
- 0°부터 180°까지 어느 각도든 기준으로 저장. 기준이 0°일 때는 효과를 숨겨 0으로 나누지 않음.
- 효과 적용 여부와 관계없이 안정된 각도로 기준을 갱신. 화면을 낮춘 자세로 유지해도 새 기준이 됨.
- 같은 기준은 다시 저장하지 않음. 허용 오차는 안정 판정에만 적용.
- 유지 시간은 1.5초로 고정하며 기존 유지 시간 저장값은 사용하지 않음. 기준 안정 판정은 기본 ±2°로 처리.
- 설정에서 효과 데드존 0/1/2°를 선택. 선택한 데드존만큼 기준보다 닫힌 경우 효과를 적용하지 않으며, 그 이상부터 연속적으로 효과를 적용.
- 기존 기준보다 2° 이상 더 펼치면 새 기준을 즉시 적용. 기준보다 닫힌 각도에서 1.5초 유지해 기준이 바뀌는 경우에는 0.32초 동안 기준 평면과 블러를 보간해 전환.
- 저장된 기준이 없으면 특정 각도가 설정된 유지 시간 동안 안정적으로 유지될 때 기준을 자동 저장한 뒤 효과를 시작.
- 기존 투영/공간별 블러, 목표 렌더 주기 120fps 유지.
- 기준 각도 이상 또는 센서 오류에는 효과 숨김. 중지/잠자기/화면 구성 변경/캡처 오류 시 해제.
- 잠자기에서 돌아온 뒤 센서와 화면 효과를 자동으로 다시 준비.
- 메뉴의 MacBook Duo 종료로 종료.

`1.0.0` 공개 배포본은 Developer ID 서명과 Apple 공증을 거친 DMG로 제공됩니다.
공개 배포용 패키징은 `MACBOOKDUO_SIGNING_IDENTITY`와
`MACBOOKDUO_NOTARY_PROFILE`을 지정한 뒤 `package-release.sh`를 실행합니다.
공증 키체인 프로파일의 이름이나 서명 인증서 정보는 저장소에 포함하지 않습니다.
실제 화면 권한, 색상/전환, 전체 화면 앱 위 표시, 실측 프레임률은 사용자 테스트 대상입니다.
캡처 보호 콘텐츠와 잠금 화면은 일반 데스크톱 캡처와 동일하게 동작한다고 보장하지 않습니다.

공식 API 근거:
- https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos
- https://developer.apple.com/documentation/screencapturekit/sccontentfilter
- https://developer.apple.com/documentation/corevideo/cvmetaltexturecachecreatetexturefromimage
