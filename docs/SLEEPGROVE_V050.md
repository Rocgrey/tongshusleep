# SleepGrove 0.5.0 (26)

## 使用说明

- 还是原来的 App，只把英文名字改为 SleepGrove，不清空睡眠或健康记录。
- 底部依次为「睡眠、科普、助眠、掌心安睡仪、用户中心」。
- 蓝牙和手机监测：在睡眠首页点「监测与设备」，或从用户中心进入。
- 趋势和身体状态：睡眠首页点「趋势」「健康」；已读取的数据也显示在摘要中。
- 科普里可看原有课程、阅读文章和补充睡眠自评；助眠里可找呼吸、声音和晚安卡。
- 24 种声音都是本机合成，名字中的风雨只是听感描述，不是自然录音。
- 现有三个外观主题继续可用；在「用户中心 → 设置 → 外观」切换。
- 系统健康的真实读取、蓝牙同步、锁屏录音与远程通知仍需要分别做真机验证。
- 此轮不覆盖安装手机 App，不部署生产服务器；下面记录具体技术范围和检查方法。

## Version And Scope

- Same iOS app and Bundle ID: `com.rocgrey.sleeptongshu`. SwiftData, Keychain,
  HealthKit, BIO/ring data, account APIs and automatic uploads remain in place.
- Baseline: iOS `645ad35`, protected by existing tag `v0.4.4`.
- GitHub main checked and incorporated through `3cea1ad`; the four intervening
  commits add Android code. Android files are not modified by this redesign.
- Development branch: `codex/sleepgrove-redesign`. This branch is not merged into main.
- Existing local Xcode capability formatting/team edits and the unrelated
  `docs/screenshots/v031/health-refresh.png` are not part of the redesign commit.
- Project path: `/Users/ts/Documents/Codex/2026-10-23/app-10pro-app-ios-app-app`.

## Navigation Map

| Previous module | New entry | Existing implementation / data |
| --- | --- | --- |
| Sleep and home recommendations | Sleep | Real records, stages, night vitals, daily reading, goodnight and courses |
| Monitoring and devices | Sleep shortcuts / User Center | Existing phone monitoring, Bluetooth, SDK and local data |
| Trends | Sleep shortcuts and 7/30-day home chart | Existing source-separated sleep, efficiency, regularity and steps |
| Health | Sleep shortcuts and activity/recovery summary | Existing read-only HealthKit store and exploratory age calculation |
| Classroom courses and reading | Learn (科普) | Existing `content/items` catalog, chapters, full playback and landscape |
| Self assessment | Learn → 自评 | Attach an existing AIS total to a real night; no new questionnaire |
| Breathing, noise, goodnight | Relax (助眠) | Native pages and existing notification routes |
| Products | 掌心安睡仪 | Published product records and validated JD external links |
| Account and settings | 用户中心 | Existing Keychain session, sync switch, appearance, reminders and audio |

No new backend endpoints are required. Publishing/unpublishing continues through
the existing backend. The product and relaxation tabs refresh while active using
the same 60-second catalog policy, support pull-to-refresh and show cache errors.
CDN file uploads alone still do not create published courses.

## Interaction And Visual Design

- English display name and login/home branding: **SleepGrove**. Chinese branding
  has not been renamed without confirmation. Project/scheme names remain unchanged.
- Five system tabs: 睡眠 / 科普 / 助眠 / 掌心安睡仪 / 用户中心.
- Same green/neutral design variables as the supplied `classroom-preview`.
  Blue/purple stage colors, rose vitals, and amber reminders remain distinct.
- Home starts with the current night, actual duration, a stage overview and target;
  recommendations move below the sleep data. Existing detailed charts are preserved.
- Adds source-consistent 7/30-day duration chart; activity/recovery charts use only
  available system-health observations. No missing data is manufactured.
- The existing exploratory age can appear in the health summary, explicitly labelled
  unvalidated; no new age algorithm or score has been added.
- Courses and product images reuse existing catalog assets; the original platform
  is not reintroduced as a WebView. Product images still open validated JD links.
- Large accessibility fonts switch grids to fewer columns; dark-mode action colors
  are lightened for readability. Standard sheets have an explicit return button.
- The ring SDK client now lives with root stores so dismissing a module does not
  recreate the client mid-read. Existing date caching and lazy chart layout remain.

## Relaxation

- 4/7/8 breathing retains the existing timing rules, adds optional phase cues and
  pauses its timeline when inactive. Cues do not play during monitoring or noise playback.
- 24 **procedurally synthesized textures**, with different filters/envelopes.
  Wind/rain/water names describe an impression, not recordings. No external audio
  licenses or downloads are implied. Rendering runs away from the UI thread.
- Existing pause/resume, volume, timer, last-ten-second fade, lock-screen controls
  and recording/playback conflict management are preserved.
- This release does **not** automatically start the microphone in the background.
  Bedtime notifications invite the user to open the app and explicitly start monitoring.
- No unvalidated claim to detect wakefulness and issue a second reminder. Remote
  APNs still requires the existing paid-team/signing/backend configuration.
- No new paid memberships, orders, stories or questionnaires without real content.

## Build And Test

Xcode is installed at `/Users/ts/Downloads/Xcode.app`. On this Mac:

```sh
export DEVELOPER_DIR=/Users/ts/Downloads/Xcode.app/Contents/Developer
xcodebuild -project sleeptongshu.xcodeproj -scheme sleeptongshu \
  -destination 'platform=iOS Simulator,name=sleeptongshu Compact UI' \
  -derivedDataPath work/sleepgrove-build test \
  -only-testing:sleeptongshuTests CODE_SIGNING_ALLOWED=NO
xcodebuild -project sleeptongshu-Ring.xcodeproj -scheme sleeptongshu-Ring \
  -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
```

For normal simulator use open `sleeptongshu.xcodeproj`, choose scheme
`sleeptongshu`, and Run. For a device with the ring SDK use
`sleeptongshu-Ring.xcodeproj` and the matching scheme, preserving the original
team and application identifier. Vendor setup instructions in the README still apply.
No production deployment, database migration or physical-phone overwrite is
performed as part of this redesign.

## Manual Acceptance

1. Sleep: switch source/date, inspect duration, stage timeline, vitals and 7/30-day chart.
2. Open monitoring from Sleep; reconnect device; close and reopen while reading.
   Verify saved data and automatic synchronization remain intact.
3. Open Health, explicitly read authorized data, then return to Sleep. Real HealthKit
   authorization/read and background audio still require an iPhone.
4. Learn: play a real course, choose a chapter, enter/leave landscape; read articles.
5. Relax: start/pause/end breathing; choose a noise before starting playback; change
   volume, pause/resume, leave the page, and confirm the timer still ends playback.
6. Products: check published records, tap image/link, and confirm the JD destination.
7. User Center: open account, settings, themes and reminders. Verify restart restores
   remembered login. Check notification cold launch and post-login continuation.

Screenshots in `docs/screenshots/v050` use explicitly labelled simulator test
records and bundled content, not a claim of reading new real health measurements.

## Validation Record

- Final unit suite: 230 tests, 1 environment-dependent live-backend test skipped,
  0 failures. Covers existing auth, imports, deduplication, uploads, BIO processing,
  plus new route mapping, 24 bounded/distinct noise textures and theme contrast.
- Simulator UI checked on iPhone SE (third generation) and iPhone 17e, iOS 27.2:
  five tabs, device sleep/steps, phone-only account registration, account/profile,
  notification continuation after login, native courses, chapter changes,
  landscape playback, themes and dark accessibility-sized text.
- Health UI regression covers shared read/update, repeat-read deduplication,
  empty results, bed-only records, unspecified sleep, complete stages, source
  details and large fonts. Foreground module queries are scoped so background
  copies of the same health controls are not mistaken for the visible controls.
- Ordinary simulator build and vendor-enabled ring generic-iOS build succeed.
  The device build was unsigned; it is not an installation or signing validation.
- `git diff --check` and staged private-key/token pattern scan are clean.
- Live-content publication E2E is **not** claimed this turn. The old optional
  inspection fixture contains stale published IDs. That test now requires
  `SLEEP_RUN_LIVE_CONTENT_TESTS=1` and a newly captured local fixture; by default
  it skips rather than treating removed test content as an App regression.
- No new real HealthKit/Bluetooth read, background/lock-screen audio session,
  hardware latency measurement, JD checkout or remote APNs delivery was verified
  on a physical phone this turn. Existing backend APIs are reused without a Web
  change, production deployment or database migration.

## Scope Still Requiring Follow-Up

- Scheduled microphone recording from a suspended/terminated App is not added.
  The supported path is a bedtime reminder followed by explicit user action.
- No reliable sleep/wake detector is available for a second reminder; no reminder
  pretends to know the user is awake.
- Self assessment reuses only the existing AIS-total editor. An in-App questionnaire,
  paid course checkout, memberships/orders and bedtime stories require approved
  content/contracts and are not fabricated for the redesign.
- Paid Apple team/APNs setup and real device acceptance remain separate tasks.
