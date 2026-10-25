(function (root, factory) {
    'use strict';
    const api = factory(root);
    if (typeof module !== 'undefined' && module.exports) {
        module.exports = api;
    } else {
        root.SpotifyControlPerformanceOverlay = api;
        api.installFromGlobalConfig();
    }
})(typeof globalThis !== 'undefined' ? globalThis : this, function (root) {
    'use strict';

    const BYPASS_KEY = 'spotify-control-performance-overlay-bypass-v1';

    function toPathname(href) {
        if (href && typeof href === 'object' && typeof href.pathname === 'string') return href.pathname;
        if (typeof href !== 'string') return '';
        try {
            return new URL(href, root.location ? root.location.href : 'https://spotify.local/').pathname;
        } catch (_) {
            return href.split(/[?#]/, 1)[0] || '';
        }
    }

    function routeMatches(pathname, target) {
        return (target.routePrefixes || []).some((prefix) => pathname === prefix || pathname.startsWith(prefix + '/'));
    }

    function findTarget(pathname, targets) {
        return targets.find((target) => routeMatches(pathname, target)) || null;
    }

    function waitUntil(predicate, timeoutMs, intervalMs) {
        const started = Date.now();
        return new Promise((resolve, reject) => {
            const tick = () => {
                let ready = false;
                try { ready = Boolean(predicate()); } catch (_) { ready = false; }
                if (ready) return resolve();
                if (Date.now() - started >= timeoutMs) return reject(new Error('readiness-timeout'));
                root.setTimeout(tick, intervalMs);
            };
            tick();
        });
    }

    async function waitUntilAsync(predicate, timeoutMs, intervalMs) {
        const started = Date.now();
        for (;;) {
            try { if (await predicate()) return; } catch (_) {}
            if (Date.now() - started >= timeoutMs) throw new Error('readiness-timeout');
            await new Promise((resolve) => root.setTimeout(resolve, intervalMs));
        }
    }

    function localStorageValue(key) {
        try {
            if (root.Spicetify && root.Spicetify.LocalStorage) return root.Spicetify.LocalStorage.get(key);
        } catch (_) {}
        return null;
    }

    async function playlistMakerReady(timeoutMs) {
        const workflowKey = 'playlist-maker:workflows';
        const artistGenresKey = 'playlist-maker:artist-genres';
        await waitUntil(() => {
            const workflows = localStorageValue(workflowKey);
            const genres = localStorageValue(artistGenresKey);
            const workflowsDone = workflows === null || workflows === undefined || workflows === '' || workflows === '[]';
            const genresDone = genres === null || genres === undefined || genres === '';
            return workflowsDone && genresDone;
        }, timeoutMs, 25);

        if (root.indexedDB && typeof root.indexedDB.databases === 'function') {
            await waitUntilAsync(async () => {
                const dbs = await root.indexedDB.databases();
                return !dbs.some((db) => db && db.name === artistGenresKey);
            }, timeoutMs, 25);
        }
    }

    function defaultReadiness(target) {
        const readiness = target.readiness || {};
        const timeoutMs = readiness.timeoutMs || 10000;
        if (readiness.kind === 'global-property') {
            return waitUntil(() => Boolean(root[readiness.property]), timeoutMs, 25);
        }
        if (readiness.kind === 'playlist-maker-migrations') return playlistMakerReady(timeoutMs);
        return Promise.resolve();
    }

    function defaultLoadScript(target) {
        return new Promise((resolve, reject) => {
            const script = root.document.createElement('script');
            script.src = target.src;
            script.dataset.spotifyControlPerformanceOverlay = target.id;
            script.onload = resolve;
            script.onerror = () => reject(new Error('script-load-failed:' + target.id));
            (root.document.head || root.document.documentElement).appendChild(script);
        });
    }

    function createController(options) {
        const targets = options.targets || [];
        const loadScript = options.loadScript || defaultLoadScript;
        const readiness = options.readiness || defaultReadiness;
        const states = new Map();
        targets.forEach((target) => states.set(target.id, { status: 'unloaded', promise: null }));

        function getState(id) {
            const state = states.get(id);
            return state ? state.status : 'unknown';
        }

        function ensureLoaded(target) {
            const state = states.get(target.id);
            if (!state) return Promise.reject(new Error('unknown-target:' + target.id));
            if (state.status === 'loaded' || state.status === 'eager') return Promise.resolve();
            if (state.promise) return state.promise;
            state.status = 'loading';
            state.promise = Promise.resolve()
                .then(() => loadScript(target))
                .then(() => readiness(target))
                .then(() => { state.status = 'loaded'; state.promise = null; })
                .catch((error) => { state.status = 'failed'; state.promise = null; throw error; });
            return state.promise;
        }

        function markEager(id) {
            const state = states.get(id);
            if (state) { state.status = 'eager'; state.promise = null; }
        }

        return { targets, ensureLoaded, getState, markEager };
    }

    function readBypassSet() {
        try {
            const raw = root.sessionStorage && root.sessionStorage.getItem(BYPASS_KEY);
            return raw ? new Set(JSON.parse(raw)) : new Set();
        } catch (_) { return new Set(); }
    }

    function addBypass(id) {
        try {
            const set = readBypassSet();
            set.add(id);
            root.sessionStorage.setItem(BYPASS_KEY, JSON.stringify(Array.from(set)));
        } catch (_) {}
    }

    function parserTimeEagerFallback(config, controller) {
        if (!root.document || typeof root.document.write !== 'function') return;
        const current = root.location ? root.location.pathname : '';
        const bypass = readBypassSet();
        for (const target of config.targets) {
            if (bypass.has(target.id) || routeMatches(current, target)) {
                const safeSrc = String(target.src).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
                root.document.write('<script src="' + safeSrc + '" data-spotify-control-performance-overlay-eager="' + target.id + '"></script>');
                controller.markEager(target.id);
            }
        }
    }

    function waitForHistory(timeoutMs) {
        return waitUntil(() => Boolean(root.Spicetify && root.Spicetify.Platform && root.Spicetify.Platform.History), timeoutMs, 25)
            .then(() => root.Spicetify.Platform.History);
    }

    function notifyFailure(target, error) {
        try {
            if (root.Spicetify && typeof root.Spicetify.showNotification === 'function') {
                root.Spicetify.showNotification('Spotify Control performance optimization was bypassed for ' + target.id + '; reloading original behavior.', true, 5000);
            }
        } catch (_) {}
        if (root.console && typeof root.console.error === 'function') root.console.error('[SpotifyControlPerformanceOverlay]', target.id, error);
    }

    function installHistoryGuard(history, controller) {
        if (!history || history.__spotifyControlPerformanceOverlayWrapped) return;
        const originalPush = history.push.bind(history);
        const originalReplace = history.replace.bind(history);
        const guarded = (original) => function (href) {
            const target = findTarget(toPathname(href), controller.targets);
            if (!target || controller.getState(target.id) === 'loaded' || controller.getState(target.id) === 'eager') {
                original(href);
                return;
            }
            controller.ensureLoaded(target)
                .then(() => original(href))
                .catch((error) => {
                    notifyFailure(target, error);
                    addBypass(target.id);
                    if (root.location && typeof root.location.reload === 'function') root.location.reload();
                });
        };
        history.push = guarded(originalPush);
        history.replace = guarded(originalReplace);
        Object.defineProperty(history, '__spotifyControlPerformanceOverlayWrapped', { value: true, configurable: false, enumerable: false });
    }

    function installLinkPreloader(controller) {
        if (!root.document || typeof root.document.addEventListener !== 'function') return;
        const preload = (event) => {
            const node = event.target && event.target.closest ? event.target.closest('a[href]') : null;
            if (!node) return;
            const target = findTarget(toPathname(node.href || node.getAttribute('href')), controller.targets);
            if (target) controller.ensureLoaded(target).catch(() => {});
        };
        root.document.addEventListener('pointerdown', preload, true);
        root.document.addEventListener('focusin', preload, true);
    }

    function installFromGlobalConfig() {
        const config = root.__spotifyControlPerformanceOverlayConfig;
        if (!config || config.schema !== 1 || !Array.isArray(config.targets) || config.targets.length === 0) return null;
        const controller = createController({ targets: config.targets });
        parserTimeEagerFallback(config, controller);
        installLinkPreloader(controller);
        waitForHistory(15000)
            .then((history) => installHistoryGuard(history, controller))
            .catch((error) => { if (root.console && typeof root.console.error === 'function') root.console.error('[SpotifyControlPerformanceOverlay] history unavailable', error); });
        return controller;
    }

    return {
        BYPASS_KEY,
        toPathname,
        routeMatches,
        findTarget,
        waitUntil,
        waitUntilAsync,
        createController,
        installHistoryGuard,
        parserTimeEagerFallback,
        installFromGlobalConfig,
    };
});
