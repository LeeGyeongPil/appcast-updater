/// 한국어 CLI 메시지. 키는 `messages_en.dart` 와 정확히 같아야 한다.
library;

const Map<String, String> messagesKo = {
  'help.main': '''appcast {version} - 릴리스 서명과 Sparkle 방식 업데이트 피드 점검 도구

사용법: appcast [--lang en|ko] <명령> [옵션]

명령:
  keygen       Ed25519 서명 키 만들기 (Sparkle 호환)
  pubkey       키 파일의 공개키 출력
  sign         릴리스 파일 서명 (Sparkle sign_update 와 같은 출력)
  verify       릴리스 파일의 서명 확인
  add          appcast 파일에 릴리스 추가 (없으면 새로 만듦)
  sign-feed    appcast 파일에 서명 (SURequireSignedFeed)
  verify-feed  appcast 파일 또는 주소의 서명 확인
  check        어떤 설치가 어떤 업데이트를 받는지 확인 (--explain 은 못 받는 이유까지 설명)

공통 옵션:
  --lang en|ko   이 도구의 언어 (기본: APPCAST_UPDATER_LANG, 그다음 LC_ALL, LC_MESSAGES, LANG)
  --version      버전 출력
  -h, --help     이 도움말 (명령 뒤에 붙여도 됨)

명령별 옵션은 'appcast <명령> --help' 로 확인하세요.
키 파일은 --ed-key-file <파일> 로 읽습니다. '-' 를 쓰면 표준 입력에서 키를 읽습니다.
종료 코드: 0 성공, 1 검증 실패 또는 파일 문제, 2 사용법 오류, 3 키 문제.''',
  'help.keygen': '''사용법: appcast keygen --out <파일>

새 Ed25519 키를 만듭니다. 개인키(Sparkle 2 형식인 32바이트 시드의 base64)는 <파일> 에 저장하고,
공개키는 앱에 붙여 넣을 줄과 함께 출력합니다. 이미 있는 파일은 절대 덮어쓰지 않습니다.''',
  'help.pubkey': '''사용법: appcast pubkey --ed-key-file <파일|->

공개키(SUPublicEDKey 값)를 출력합니다. 32바이트 키와 옛 96바이트 키 모두 됩니다.''',
  'help.sign': '''사용법: appcast sign <파일> --ed-key-file <파일|-> [-p]

Sparkle sign_update 와 똑같이 sparkle:edSignature="..." length="..." 를 출력합니다.
  -p   서명만 출력''',
  'help.verify':
      '''사용법: appcast verify <파일> <서명> (--public-key <base64> | --ed-key-file <파일|->)

서명이 파일과 맞으면 종료 코드 0, 아니면 1.''',
  'help.add':
      '''사용법: appcast add <appcast.xml> --file <릴리스 파일> --url <다운로드 주소> --version <빌드 번호>
                   --ed-key-file <파일|-> [옵션]

릴리스 파일에 서명하고 피드 맨 위에 새 항목을 넣습니다. 피드가 없으면 새로 만듭니다.
옵션:
  --short-version <글>          사용자에게 보이는 버전
  --title <글>                  항목 제목 (피드를 새로 만들 때는 피드 제목)
  --os <이름>                   예: windows-x64, macos
  --channel <이름>              이 항목의 채널 (생략하면 기본 채널)
  --min-system <버전>           최소 시스템 버전
  --max-system <버전>           최대 시스템 버전
  --phased-interval <초>        단계적 배포 간격
  --critical                    중요 업데이트로 표시
  --critical-below <버전>       이 버전보다 낮은 설치에서만 중요
  --notes-url <주소>            릴리스 노트 링크
  --installer-arguments <글>    설치 프로그램에 넘길 인자
  --pub-date <날짜>             RFC 822 또는 ISO 8601 날짜 (기본: 지금)
  --replace                     같은 버전·os 항목을 교체
  --keep <N>                    os·채널별 최신 N개만 유지
                                (기본: 전부 유지, 분기 항목 유지:
                                minimumAutoupdateVersion)
  --sign-feed                   끝나고 피드에도 서명
피드가 바뀌면 피드 서명이 지워집니다. --sign-feed 를 쓰거나 이어서 sign-feed 를 실행하세요.''',
  'help.sign-feed': '''사용법: appcast sign-feed <appcast.xml> --ed-key-file <파일|->

피드 끝에 sparkle-signatures 주석을 붙이거나 교체합니다. 이 주석이 앞의 피드 본문에 서명합니다.''',
  'help.verify-feed':
      '''사용법: appcast verify-feed <appcast.xml|주소> (--public-key <base64> | --ed-key-file <파일|->)

피드 서명이 올바르면 종료 코드 0, 아니면 1.''',
  'help.check':
      '''사용법: appcast check <appcast.xml|주소> --current <버전> --os <이름> [옵션]

이 설치에 어떤 업데이트가 제안되는지 보여 줍니다.
옵션:
  --explain               고르지 않은 항목마다 이유를 나열
  --channel <이름들>      추가 채널, 쉼표로 구분
  --system-version <v>    최소·최대 시스템 버전 검사에 쓸 시스템 버전
  --group <0-6>           이 설치의 단계적 배포 그룹
  --user-initiated        사용자가 "업데이트 확인"을 누른 것처럼 처리
  --untagged-means <os>   sparkle:os 가 없는 항목을 이 os 로 취급
  --now <날짜>            현재 시각 대신 쓸 날짜 (ISO 8601)''',
  'err.unknown_option':
      '알 수 없는 옵션: {option}. "appcast {command} --help" 로 옵션을 확인하세요.',
  'err.unknown_command':
      '알 수 없는 명령: {command}. "appcast --help" 로 명령 목록을 확인하세요.',
  'err.missing_command': '명령이 없습니다. "appcast --help" 로 명령 목록을 확인하세요.',
  'err.missing_value': '{option} 옵션에는 값이 필요합니다.',
  'err.missing_option': '필수 옵션 {option} 이(가) 없습니다.',
  'err.missing_arg': '인자가 빠졌습니다: {arg}.',
  'err.extra_arg': '필요 없는 인자입니다: {arg}.',
  'err.bad_lang': '지원하지 않는 언어 "{value}" 입니다. en 또는 ko 를 쓰세요.',
  'err.bad_int': '{option} 옵션에는 정수가 필요합니다. 받은 값: "{value}".',
  'err.bad_keep': '--keep 옵션에는 1 이상의 정수가 필요합니다. 받은 값: "{value}".',
  'err.bad_date':
      '{option} 옵션에는 2026-11-12T00:00:00Z 같은 날짜가 필요합니다. 받은 값: "{value}".',
  'err.file_not_found': '파일을 찾을 수 없습니다: {path}',
  'err.cannot_read': '{path} 을(를) 읽을 수 없습니다.',
  'err.write_failed': '{path} 에 쓸 수 없습니다. 폴더가 있고 쓸 수 있는지 확인하세요.',
  'err.exists': '{path} 을(를) 덮어쓰지 않습니다. 다른 파일 이름을 쓰거나 먼저 지우세요.',
  'err.key_format':
      '{source} 은(는) 올바른 키 파일이 아닙니다. 32바이트 시드(또는 옛 96바이트 키)의 base64 여야 합니다.',
  'err.pubkey_format': '공개키가 32바이트의 올바른 base64 가 아닙니다.',
  'err.key_required': '키가 필요합니다. --ed-key-file <파일> (표준 입력은 -) 을 넘기세요.',
  'err.legacy_key':
      '옛 96바이트 개인키입니다. 공개키 출력과 검증은 되지만 이 키로 서명하는 것은 아직 지원하지 않습니다. Sparkle sign_update 로 서명하거나 "appcast keygen" 으로 새 키를 만드세요(앱에 넣은 공개키도 바뀝니다).',
  'err.feed_format.notXml':
      '{path} 은(는) 올바른 XML 이 아닙니다 (빈 파일이나 중간에 잘린 파일도 이렇게 보입니다).',
  'err.feed_format.noChannel':
      '{path} 은(는) XML 이지만 <channel> 요소가 없어 appcast 피드가 아닙니다.',
  'err.feed_format.notUtf8': '{path} 은(는) UTF-8 텍스트가 아닙니다. 피드를 UTF-8 로 저장하세요.',
  'err.download': '{path} 을(를) 가져오지 못했습니다. 주소와 연결을 확인하세요 (http:// 는 거부됩니다).',
  'err.duplicate':
      '{path} 에 {os} 용 버전 {version} 이(가) 이미 있습니다. 덮어쓰려면 --replace 를 쓰세요.',
  'word.stdin': '표준 입력',
  'word.any_os': '모든 OS',
  'word.default_channel': '기본',
  'ok.keygen_written': '개인키를 {path} 에 저장했습니다. 비밀로 보관하고 CI 비밀값으로 옮기세요.',
  'ok.keygen_public': '공개키: {key}',
  'ok.keygen_plist': 'Sparkle, Info.plist 에:',
  'ok.keygen_winsparkle': 'WinSparkle, 리소스 파일에:',
  'ok.keygen_dart': 'Dart:',
  'ok.verify_valid': '서명이 올바릅니다.',
  'fail.verify_invalid': '서명이 파일과 맞지 않습니다.',
  'fail.verify_malformed': '서명이 64바이트의 올바른 base64 가 아닙니다.',
  'ok.added': '{path} 에 {version} ({os}) 을(를) 추가했습니다.',
  'ok.pruned': '{path} 에서 오래된 항목 {count}개를 지웠습니다 (os/채널별 {keep}개 유지).',
  'warn.feed_unsigned':
      '피드가 바뀌어서 피드 서명을 지웠습니다. "appcast sign-feed {path}" 를 실행하세요 (또는 --sign-feed 사용).',
  'ok.feed_signed': '{path} 에 서명했습니다.',
  'ok.feed_valid': '{path} 의 피드 서명이 올바릅니다.',
  'fail.feed.missing': '피드에 서명이 없습니다.',
  'fail.feed.malformed': '서명 주석이 손상되었습니다.',
  'fail.feed.lengthMismatch': '서명한 뒤 피드가 바뀌었습니다 (길이가 다름).',
  'fail.feed.signatureInvalid': '서명한 뒤 피드가 바뀌었습니다 (서명이 맞지 않음).',
  'check.update': '받을 수 있는 업데이트: {label}',
  'check.critical': '설치된 버전에는 이 업데이트가 중요 업데이트입니다.',
  'check.file': '파일: {url}',
  'check.none': '업데이트 없음: 이 설치에 제안되는 더 새로운 버전이 없습니다.',
  'check.explain_head': '고르지 않은 항목:',
  'check.item_error.missingEnclosure':
      '항목 {index}번을 건너뛰었습니다: url 속성이 있는 <enclosure> 가 없습니다.',
  'check.item_error.badLength':
      '항목 {index}번을 건너뛰었습니다: <enclosure> 의 length 가 없거나 바이트 수(정수)가 아닙니다.',
  'check.item_error.missingVersion':
      '항목 {index}번을 건너뛰었습니다: sparkle:version 이 없습니다.',
  'check.item_error.badPhasedInterval':
      '항목 {index}번을 건너뛰었습니다: sparkle:phasedRolloutInterval 이 초 단위 숫자가 아닙니다.',
  'check.item_error.badPubDate':
      '항목 {index}번을 건너뛰었습니다: pubDate 가 RFC 822 날짜("Wed, 12 Nov 2026 00:00:00 +0000" 형식)가 아닙니다.',
  'why.wrongOs': '{expected} 용이고 이 설치는 {actual} 입니다',
  'why.channelNotAllowed': '"{expected}" 채널이 꺼져 있습니다 (--channel 로 추가)',
  'why.systemTooOld': '시스템 {expected} 이상이 필요한데 이 설치는 {actual} 입니다',
  'why.systemTooNew': '시스템 {expected} 이하가 필요한데 이 설치는 {actual} 입니다',
  'why.informational': '안내용 항목이라 설치할 파일이 없습니다',
  'why.notNewer': '설치된 버전 {actual} 보다 새롭지 않습니다',
  'why.rolloutNotYet': '단계적 배포: 그룹 {group} 은(는) {time} 부터 받습니다',
  'why.superseded': '더 새로운 항목이 선택되었습니다',
};
