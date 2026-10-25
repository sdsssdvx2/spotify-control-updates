'use strict';

const assert = require('assert');

const session = new Map();
global.location = {
    href: 'https://open.spotify.local/home',
    pathname: '/home',
    reloadCount: 0,
    reload() { this.reloadCount += 1; },
};
global.sessionStorage = {
    getItem(key) { return session.has(key) ? session.get(key) : null; },
    setItem(key, value) { session.set(key, String(value)); },
};

const overlay = require('../lazy-custom-app-loader.js');

const betterLocal = {
    id: 'better-local-files',
    src: 'extensions/better-local-files/extension.js',
    routePrefixes: ['/better-local-files'],
    readiness: { kind: 'global-property', property: 'localTracksService', timeoutMs: 1000 },
};
const playlistMaker = {
    id: 'playlist-maker',
    src: 'extensions/playlist-maker/extension.js',
    routePrefixes: ['/playlist-maker'],
    readiness: { kind: 'playlist-maker-migrations', timeoutMs: 1000 },
};

function delay(ms = 0) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main() {
    assert.strictEqual(overlay.toPathname('/playlist-maker?x=1#y'), '/playlist-maker');
    assert.strictEqual(overlay.toPathname({ pathname: '/better-local-files/album/1' }), '/better-local-files/album/1');
    assert.strictEqual(overlay.routeMatches('/better-local-files', betterLocal), true);
    assert.strictEqual(overlay.routeMatches('/better-local-files/album/1', betterLocal), true);
    assert.strictEqual(overlay.routeMatches('/better-local-files-extra', betterLocal), false);
    assert.strictEqual(overlay.findTarget('/playlist-maker/new', [betterLocal, playlistMaker]).id, 'playlist-maker');

    // Concurrent navigation/preload requests must share exactly one original script load.
    let resolveLoad;
    let loadCalls = 0;
    let readinessCalls = 0;
    const controller = overlay.createController({
        targets: [betterLocal],
        loadScript: () => {
            loadCalls += 1;
            return new Promise((resolve) => { resolveLoad = resolve; });
        },
        readiness: async () => { readinessCalls += 1; },
    });
    const p1 = controller.ensureLoaded(betterLocal);
    const p2 = controller.ensureLoaded(betterLocal);
    assert.strictEqual(p1, p2, 'concurrent ensureLoaded calls must deduplicate');
    assert.strictEqual(controller.getState('better-local-files'), 'loading');
    await delay();
    assert.strictEqual(typeof resolveLoad, 'function', 'synthetic load resolver must be installed after promise microtask');
    resolveLoad();
    await Promise.all([p1, p2]);
    assert.strictEqual(loadCalls, 1);
    assert.strictEqual(readinessCalls, 1);
    assert.strictEqual(controller.getState('better-local-files'), 'loaded');
    await controller.ensureLoaded(betterLocal);
    assert.strictEqual(loadCalls, 1, 'loaded target must not load twice');

    // Programmatic History.push is void in the upstream Pithaya history contract; guard delays only target routes.
    let resolveGuardLoad;
    const guardController = overlay.createController({
        targets: [betterLocal],
        loadScript: () => new Promise((resolve) => { resolveGuardLoad = resolve; }),
        readiness: async () => {},
    });
    const calls = [];
    const history = {
        push(href) { calls.push(['push', href]); },
        replace(href) { calls.push(['replace', href]); },
    };
    overlay.installHistoryGuard(history, guardController);
    history.push('/better-local-files');
    assert.strictEqual(calls.length, 0, 'target navigation must wait for original extension');
    await delay();
    assert.strictEqual(typeof resolveGuardLoad, 'function', 'guard load resolver must be installed after promise microtask');
    resolveGuardLoad();
    await delay();
    await delay();
    assert.deepStrictEqual(calls, [['push', '/better-local-files']]);
    history.replace('/home');
    assert.deepStrictEqual(calls[1], ['replace', '/home'], 'non-target route stays synchronous');

    // Loader failure never enters a route with a missing dependency; it arms one-session eager fallback and reloads.
    global.location.reloadCount = 0;
    session.clear();
    const failController = overlay.createController({
        targets: [playlistMaker],
        loadScript: async () => { throw new Error('synthetic-load-failure'); },
        readiness: async () => {},
    });
    const failCalls = [];
    const failHistory = {
        push(href) { failCalls.push(href); },
        replace(href) { failCalls.push(href); },
    };
    overlay.installHistoryGuard(failHistory, failController);
    failHistory.push('/playlist-maker');
    await delay();
    await delay();
    assert.strictEqual(failCalls.length, 0, 'failed dependency must not enter app route');
    assert.strictEqual(global.location.reloadCount, 1, 'failed dependency triggers eager-fallback reload');
    const bypass = JSON.parse(session.get(overlay.BYPASS_KEY));
    assert.deepStrictEqual(bypass, ['playlist-maker']);

    // Deep link/bypass is restored at parser time using the untouched original script path.
    const writes = [];
    global.document = { write(value) { writes.push(value); } };
    global.location.pathname = '/better-local-files/album/123';
    session.clear();
    const eagerController = overlay.createController({ targets: [betterLocal] });
    overlay.parserTimeEagerFallback({ schema: 1, targets: [betterLocal] }, eagerController);
    assert.strictEqual(eagerController.getState('better-local-files'), 'eager');
    assert.strictEqual(writes.length, 1);
    assert.ok(writes[0].includes('extensions/better-local-files/extension.js'));
    assert.ok(writes[0].endsWith('</script>'), 'parser fallback must emit a real closing script tag');

    // Target-specific readiness: Better Local Files waits for its required global service.
    delete global.localTracksService;
    const readinessController = overlay.createController({
        targets: [betterLocal],
        loadScript: async () => {
            setTimeout(() => { global.localTracksService = {}; }, 10);
        },
    });
    await readinessController.ensureLoaded(betterLocal);
    assert.strictEqual(readinessController.getState('better-local-files'), 'loaded');

    // Playlist Maker observable legacy migrations must be gone before route entry.
    const storage = new Map([
        ['playlist-maker:workflows', '[{"name":"legacy"}]'],
        ['playlist-maker:artist-genres', '{}'],
    ]);
    global.Spicetify = {
        LocalStorage: {
            get(key) { return storage.has(key) ? storage.get(key) : null; },
        },
    };
    let dbPresent = true;
    global.indexedDB = {
        async databases() { return dbPresent ? [{ name: 'playlist-maker:artist-genres' }] : []; },
    };
    const migrationController = overlay.createController({
        targets: [playlistMaker],
        loadScript: async () => {
            setTimeout(() => {
                storage.delete('playlist-maker:workflows');
                storage.delete('playlist-maker:artist-genres');
                dbPresent = false;
            }, 10);
        },
    });
    await migrationController.ensureLoaded(playlistMaker);
    assert.strictEqual(migrationController.getState('playlist-maker'), 'loaded');

    console.log('PERFORMANCE OVERLAY NODE TESTS PASS');
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
