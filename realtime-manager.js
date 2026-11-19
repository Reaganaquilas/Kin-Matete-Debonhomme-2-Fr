(function () {
  const channels = new Map();
  const retryDelays = [2000, 5000, 10000, 30000];
  const logs = [];

  function normalizeKey(name) {
    return String(name || '').trim();
  }

  function safeUnsubscribe(channel) {
    if (!channel) return;
    try {
      if (typeof channel.unsubscribe === 'function') channel.unsubscribe();
    } catch (_) {
      // ignore cleanup errors; they are handled by reconnect logic
    }
  }

  function logEvent(event, details) {
    const entry = {
      time: new Date().toISOString(),
      event,
      details
    };
    logs.push(entry);
    if (logs.length > 50) logs.shift();
    if (window.console && typeof console.debug === 'function') {
      console.debug('[Realtime]', event, details);
    }
  }

  function ensureStatusElement() {
    let element = document.getElementById('appRealtimeStatus');
    if (element) return element;
    if (!document.body) {
      return null;
    }

    element = document.createElement('div');
    element.id = 'appRealtimeStatus';
    element.setAttribute('role', 'status');
    element.style.cssText = 'position:fixed;left:16px;right:16px;bottom:16px;z-index:2200;padding:10px 14px;border-radius:8px;border:1px solid #cbd9e0;background:#eef5f7;color:#214b63;font:600 12px/1.4 Arial,sans-serif;box-shadow:0 8px 20px rgba(0,0,0,.12);display:none;';
    document.body.appendChild(element);
    return element;
  }

  function updateStatus(text, isError) {
    const element = ensureStatusElement();
    if (!element) {
      if (document.readyState === 'loading') {
        window.addEventListener('DOMContentLoaded', () => updateStatus(text, isError), { once: true });
      }
      return;
    }
    if (!text) {
      element.style.display = 'none';
      element.textContent = '';
      return;
    }
    element.textContent = text;
    element.style.display = 'block';
    element.style.background = isError ? '#fff0f0' : '#eef5f7';
    element.style.borderColor = isError ? '#d9a5a5' : '#cbd9e0';
    element.style.color = isError ? '#7c2525' : '#214b63';
  }

  function ensureDebugControls() {
    let panel = document.getElementById('appRealtimeDebugPanel');
    if (panel) return panel;
    if (!document.body) {
      window.addEventListener('DOMContentLoaded', ensureDebugControls, { once: true });
      return null;
    }

    panel = document.createElement('div');
    panel.id = 'appRealtimeDebugPanel';
    panel.style.cssText = 'position:fixed;right:16px;bottom:72px;z-index:2300;display:flex;align-items:center;gap:8px;padding:8px 10px;border-radius:10px;border:1px solid #cbd9e0;background:rgba(255,255,255,0.92);box-shadow:0 10px 24px rgba(31,55,68,0.12);font:600 12px/1.4 Arial,sans-serif;color:#214b63;';

    const label = document.createElement('span');
    label.textContent = 'Realtime';
    label.style.opacity = '0.9';

    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = 'Forcer reconnexion';
    button.style.cssText = 'border:0;border-radius:6px;background:#214b63;color:#fff;padding:6px 10px;cursor:pointer;font:inherit;';
    button.addEventListener('click', () => {
      const manager = window.appRealtimeManager;
      if (!manager) return;
      manager.clearAll();
      updateStatus('Reconnexion Realtime demandée…', false);
      if (window.appAuth?.client) {
        logEvent('manual-reconnect-triggered', { total: manager.channels.size });
      }
      window.location.reload();
    });

    panel.append(label, button);
    document.body.appendChild(panel);
    return panel;
  }

  const manager = {
    channels,
    logs,

    ensureChannel(name, builder, options = {}) {
      const key = normalizeKey(name);
      const client = options.client || window.appAuth?.client;
      if (!client || !key) return null;

      const existing = this.channels.get(key);
      if (existing && existing.channel) {
        logEvent('channel-reused', { key });
        return existing.channel;
      }

      const channel = client.channel(key);
      const metadata = {
        channel,
        builder,
        retryIndex: 0,
        retryTimer: null,
        lastStatus: null,
        options
      };

      if (typeof builder === 'function') {
        builder(channel);
      }

      channel.subscribe(status => {
        metadata.lastStatus = status;
        logEvent('channel-status', { key, status });

        if (typeof options.onStatus === 'function') {
          options.onStatus(status);
        }

        if (status === 'SUBSCRIBED') {
          metadata.retryIndex = 0;
          updateStatus('Synchronisation en temps réel active.', false);
          return;
        }

        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          const delay = retryDelays[Math.min(metadata.retryIndex, retryDelays.length - 1)] || retryDelays[retryDelays.length - 1];
          metadata.retryIndex += 1;
          updateStatus(`Synchronisation Realtime en attente. Nouvelle tentative dans ${Math.round(delay / 1000)}s.`, true);
          logEvent('retry-scheduled', { key, delay, retryIndex: metadata.retryIndex });
          this.scheduleRetry(key, delay);
        }
      });

      this.channels.set(key, metadata);
      logEvent('channel-created', { key });
      return channel;
    },

    scheduleRetry(name, delay) {
      const key = normalizeKey(name);
      const entry = this.channels.get(key);
      if (!entry || entry.retryTimer) return;

      entry.retryTimer = window.setTimeout(() => {
        entry.retryTimer = null;
        const { options, channel: previousChannel, builder } = entry;
        const client = options.client || window.appAuth?.client;
        if (!client) return;

        this.clearChannel(key, { skipStatusUpdate: true });
        const replacement = client.channel(key);
        const nextEntry = {
          channel: replacement,
          builder,
          retryIndex: entry.retryIndex,
          retryTimer: null,
          lastStatus: null,
          options
        };

        if (typeof builder === 'function') {
          builder(replacement);
        }

        replacement.subscribe(status => {
          nextEntry.lastStatus = status;
          logEvent('retry-status', { key, status });

          if (typeof options.onStatus === 'function') {
            options.onStatus(status);
          }

          if (status === 'SUBSCRIBED') {
            nextEntry.retryIndex = 0;
            updateStatus('Synchronisation en temps réel active.', false);
            return;
          }

          if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
            const backoff = retryDelays[Math.min(nextEntry.retryIndex, retryDelays.length - 1)] || retryDelays[retryDelays.length - 1];
            nextEntry.retryIndex += 1;
            updateStatus(`Synchronisation Realtime en attente. Nouvelle tentative dans ${Math.round(backoff / 1000)}s.`, true);
            logEvent('retry-scheduled', { key, delay: backoff, retryIndex: nextEntry.retryIndex });
            this.scheduleRetry(key, backoff);
          }
        });

        safeUnsubscribe(previousChannel);
        this.channels.set(key, nextEntry);
        logEvent('retry-created', { key });
      }, delay);
    },

    clearChannel(name, options = {}) {
      const key = normalizeKey(name);
      const existing = this.channels.get(key);
      if (!existing) return;
      if (existing.retryTimer) {
        window.clearTimeout(existing.retryTimer);
        existing.retryTimer = null;
      }
      safeUnsubscribe(existing.channel);
      this.channels.delete(key);
      logEvent('channel-cleared', { key });
      if (!options.skipStatusUpdate) {
        updateStatus('', false);
      }
    },

    clearAll() {
      for (const key of Array.from(this.channels.keys())) {
        this.clearChannel(key, { skipStatusUpdate: true });
      }
      updateStatus('', false);
      logEvent('channels-cleared', { total: 0 });
    },

    hasChannel(name) {
      return this.channels.has(normalizeKey(name));
    },

    getLogs() {
      return [...logs];
    },

    forceReconnect(name, builder, options = {}) {
      const key = normalizeKey(name);
      if (!key) return;
      const entry = this.channels.get(key);
      const reconnectBuilder = typeof builder === 'function' ? builder : entry?.builder;
      const reconnectOptions = { ...entry?.options, ...options, client: options.client || entry?.options?.client || window.appAuth?.client };
      this.clearChannel(key, { skipStatusUpdate: true });
      logEvent('manual-reconnect', { key });
      updateStatus('Reconnexion Realtime demandée…', false);
      if (reconnectBuilder) {
        this.ensureChannel(key, reconnectBuilder, reconnectOptions);
      }
    }
  };

  ensureDebugControls();
  window.appRealtimeManager = manager;
  window.addEventListener('beforeunload', () => manager.clearAll());
})();
