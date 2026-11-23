# sleeptongshu 0.4.4: notifications and remembered login

## What changes

- The sleep homepage retains daily reading, goodnight cards, the real sleep summary and course recommendations.
- Notification routes: `content/<published-id>` opens that article/course/card, `goodnight` opens the goodnight card, `sleep-summary` opens the latest real local sleep record, `classroom` opens the classroom. Notification routes remain pending across the login screen. Missing/unpublished content shows a fallback message; it is not replaced with bundled content.
- Foreground notifications support banners, sound and Notification Center. Notification delivery still depends on iOS settings, APNs and connectivity; an APNs acceptance is not proof of display.
- Daily-content subscription includes summary reminders. Bedtime has its own subscription. Local and remote schedules remain separate to avoid duplicate reminders. System permission is requested when the user enables reminders and saves settings.
- Summary notifications use generic text; private health values appear only after opening the App. A server summary campaign skips accounts without a real sleep duration.

## Persistent login

`AccountSession` stores optional `refreshToken`/`refreshExpiresAt` in the existing Keychain item alongside the short-lived access token. Passwords are never saved. The shared API client coalesces renewals before authenticated calls, including calls with a captured current token. `/auth/me` verifies restored identity. Network failures preserve Keychain data and show a reconnect action instead of asking for the password again.

The backend adds:

| Endpoint | Authentication / body | Result |
| --- | --- | --- |
| `POST /api/v1/auth/refresh` | JSON `{ "refresh_token": "opaque credential" }` | Existing token response plus `refresh_token`, `refresh_expire_at` |
| `POST /api/v1/auth/session` | Valid Bearer JWT | Upgrade a still-valid old login without a password |

Login includes the same additive fields. Default remembered duration: 90 days, configurable with `REFRESH_TOKEN_EXPIRE_DAYS`; it is a fixed expiry, not an unlimited rolling login. The opaque credential is retryable, hashed in the database and never accepted as an access token. Logout revokes the current device session and its issued access tokens; password reset invalidates all sessions via `token_version`. Disabled accounts and rejected/expired credentials require login. Turning off “remember login” keeps the session only in memory. A previously expired legacy token cannot be upgraded without signing in once.

Old backend deployments remain compatible but cannot provide renewal until WorkBuddy deploys the new backend. Only a temporary network problem preserves a credential; an actual authenticated 401 clears the session. Old-account requests cannot sign out a new account or restore a session after logout.

## Real APNs configuration required

The current iPhone provisioning profile is from a **Personal Team** and does not contain `aps-environment`. Xcode explicitly rejected a Push Notifications build on 2026-11-23 because Personal Teams do not support that capability. Therefore this release must not be described as having delivered a real remote notification to that phone.

1. Use an Apple Developer Program team supporting Push Notifications and enable that capability on `com.rocgrey.sleeptongshu`.
2. Regenerate signing profiles. Build either existing project with `CODE_SIGN_ENTITLEMENTS=Configuration/PushHealthKit.entitlements SLEEP_PUSH_ENABLED=YES SLEEP_APNS_ENVIRONMENT=sandbox` for development. Keep the matching Team and bundle identifier. The combined entitlement preserves HealthKit. For TestFlight/App Store set `aps-environment` to `production` and `SLEEP_APNS_ENVIRONMENT=production`.
3. Default builds retain HealthKit-only signing and `SLEEP_PUSH_ENABLED=NO` so free-team installs still work. `Configuration/ServiceLocal.xcconfig` is ignored; its example contains no secrets. Do not commit keys or private configs.
4. Configure APNs key ID, team ID, topic/bundle ID and .p8 private key through the existing restricted admin configuration or environment variables. Do not paste these into Git or chat.
5. App: Sleep classroom → Settings → Reminders → enable remote notifications and desired daily/bedtime subscriptions → Save → allow system notifications. Reopening the App registers the token again and syncs preferences; logout unregisters the phone.

## WorkBuddy deployment handoff

Use the changes in the existing `Rocgrey/sleep_tongshu_web` repository; retain the current deployment domain, database and all credentials. Back up the database before deploying. The only new table is `login_sessions`; the existing additive `Base.metadata.create_all` startup migration creates it. Do not recreate health tables or reset users. Keep the existing JWT `SECRET_KEY` unchanged so existing sessions remain valid.

The admin “推送” drawer now has **立即推送** as a separate explicit action. It creates a draft then calls `POST /api/v1/admin/push-plans/{id}/send-now`. Only admins may call it; it respects opt-in but does not wait until the user's daily reminder minute. Retries on the same plan are idempotent. APNs not configured returns 503, never fake success. Delivery status is visible separately and never contains device tokens. A plan/device pair is claimed in the database before contacting APNs; uncertain network results are not automatically resent.

FastAPI startup starts a 30-second scheduled-push scanner; no extra process is required on WorkBuddy. `PUSH_SCHEDULER_ENABLED=false` disables this scanner if operating a separately managed worker. Multiple scans use the unique delivery constraint to avoid duplicate attempts. Queued immediate plans are also recovered after a restart. Publish/edit operations never send notifications themselves.

## Acceptance checks

Use synthetic accounts locally: login → quit/reopen → `/me` → expire access token → concurrent requests share one refresh → logout → refresh and other JWTs from the device fail. Another device remains valid. Check offline restore/retry, remember-off, disabled account and password-reset invalidation.

With real APNs signing/configuration: subscribe on one test phone, create a generic article/card/summary draft and explicitly push; check delivery response, banner/Notification Center and tapping while foreground/background/terminated. Check login continuation, repeated taps, unpublished content and opt-out. Do not broadcast test campaigns to all real users. True APNs delivery remains unverified until the paid-team configuration is available.

## Verification results, 2026-11-23

- 227 iOS unit tests completed with zero failures, one existing skip; two notification-route UI tests passed on iPhone SE simulator (login → native goodnight / sleep summary).
- Signed Ring-project device build succeeded as 0.4.4 (25); installed in place and launched on the connected iPhone. All 76 pre-existing sleep-record identities remained after installation. No App uninstall or database reset.
- 158 backend tests passed; a subsequent focused run of 22 session/push tests passed. JavaScript syntax check passed.
- Read-only live OpenAPI check confirmed the new session/refresh/send-now endpoints still need WorkBuddy deployment. No real APNs message was claimed sent; the explicit signed-Push build failed because the current Personal Team does not support that capability.
- UI screenshots are **simulator test routes and synthetic sleep data**, not evidence of real notification delivery: [goodnight](screenshots/v044/goodnight-test-route.png), [summary](screenshots/v044/sleep-summary-synthetic.png).
- Xcode emitted a simulator diagnostic-collection warning about `simctl` after the successful tests; test results reported `TEST SUCCEEDED`. Existing unrelated project edits and screenshots were left unstaged.
