# Campaign Sender — Deploy Runbook (owner-run)

The campaign cloud functions are written and tested but NOT live until this
deploy runs. Until then, campaigns created in the manager sit at status
"pending" forever (harmless).

## What gets deployed

Two new functions in `functions/` (fan repo):
- `onCampaignCreated` — fires the moment the manager creates a send-now
  campaign; delivers it and marks it `sent`.
- `processScheduledCampaigns` — runs every 5 minutes; delivers scheduled
  campaigns whose time has arrived.

Existing functions (match alerts, Stripe) are redeployed unchanged.

## Pre-checks (already done by Claude)

- `npm run build` (tsc) — clean
- `npm test` — 94/94 pass
- Topic names verified in parity with the fan app
  (`all_users`, `sport_<Category>`, `event_<EventId>`)

## The deploy (run from the repo that has the merged functions/)

```
cd <fan repo>/functions
npm install
npm run build
firebase deploy --only functions:onCampaignCreated,functions:processScheduledCampaigns
```

(Or `firebase deploy --only functions` to redeploy everything.)

Notes:
- Requires being logged into the Firebase CLI on the infinite-sports-app
  project (`firebase login`, `firebase use infinite-sports-app`).
- `processScheduledCampaigns` is a scheduled function — first deploy may ask
  to enable Cloud Scheduler; answer yes. It's in Google's free tier at this
  frequency/scale.

## Smoke test after deploy

1. Fan app on a phone: Settings → make sure a category (e.g. Futsal) is ON.
2. Manager → Notifications → compose: audience "Sport: Futsal",
   title "Test", Send now → confirm.
3. Push should arrive on the phone within seconds; campaign history shows
   status `sent`.
4. Schedule one 6–7 minutes out; it should flip to `sent` within ~5 minutes
   of its time and the push arrive.
5. Tap the push: if the campaign linked an event, the event page opens.

## Rollback

`firebase functions:delete onCampaignCreated processScheduledCampaigns`
removes the senders; campaign docs stay in the DB untouched.
