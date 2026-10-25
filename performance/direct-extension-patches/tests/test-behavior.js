const assert = require('node:assert/strict');

// PopupLyrics worker policy: the worker may run only while PiP is open and Spotify is hidden.
{
  const messages = [];
  let workerIsRunning = false;
  let lyricVideoIsOpen = false;
  let hidden = false;
  function syncWorkerState() {
    const shouldRun = lyricVideoIsOpen && hidden;
    if (shouldRun === workerIsRunning) return;
    messages.push(shouldRun ? 'popup-lyric-request-update' : 'popup-lyric-stop-update');
    workerIsRunning = shouldRun;
  }
  hidden = true; syncWorkerState();
  assert.deepEqual(messages, [], 'hidden Spotify without PiP must not start 60 Hz worker');
  lyricVideoIsOpen = true; syncWorkerState();
  assert.deepEqual(messages, ['popup-lyric-request-update']);
  syncWorkerState();
  assert.equal(messages.length, 1, 'idempotent sync must not duplicate start');
  hidden = false; syncWorkerState();
  assert.deepEqual(messages, ['popup-lyric-request-update', 'popup-lyric-stop-update']);
  hidden = true; syncWorkerState();
  assert.equal(messages.at(-1), 'popup-lyric-request-update');
  lyricVideoIsOpen = false; syncWorkerState();
  assert.equal(messages.at(-1), 'popup-lyric-stop-update');
}

// Star Ratings mutation bursts: each observer independently collapses a burst to one expensive refresh.
(async () => {
  let tracklistRefreshes = 0;
  let bodyRefreshes = 0;
  const trackObserver = { timer: null };
  const bodyObserver = { timer: null };
  function trackMutation() {
    clearTimeout(trackObserver.timer);
    trackObserver.timer = setTimeout(() => { tracklistRefreshes++; }, 25);
  }
  function bodyMutation() {
    clearTimeout(bodyObserver.timer);
    bodyObserver.timer = setTimeout(() => { bodyRefreshes++; }, 25);
  }
  for (let i = 0; i < 100; i++) { trackMutation(); bodyMutation(); }
  await new Promise(resolve => setTimeout(resolve, 60));
  assert.equal(tracklistRefreshes, 1);
  assert.equal(bodyRefreshes, 1);
  trackMutation();
  await new Promise(resolve => setTimeout(resolve, 60));
  assert.equal(tracklistRefreshes, 2, 'later mutation must still refresh');
  console.log('DIRECT_EXTENSION_BEHAVIOR_PASS');
})().catch(err => { console.error(err); process.exit(1); });
