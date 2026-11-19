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
          return;
        }

        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          const delay = retryDelays[Math.min(metadata.retryIndex, retryDelays.length - 1)] || retryDelays[retryDelays.length - 1];
          metadata.retryIndex += 1;
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

        this.clearChannel(key);
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
            return;
          }

          if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
            const backoff = retryDelays[Math.min(nextEntry.retryIndex, retryDelays.length - 1)] || retryDelays[retryDelays.length - 1];
            nextEntry.retryIndex += 1;
            logEvent('retry-scheduled', { key, delay: backoff, retryIndex: nextEntry.retryIndex });
            this.scheduleRetry(key, backoff);
          }
        });

        safeUnsubscribe(previousChannel);
        this.channels.set(key, nextEntry);
        logEvent('retry-created', { key });
      }, delay);
    },

    clearChannel(name) {
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
    },

    clearAll() {
      for (const key of Array.from(this.channels.keys())) {
        this.clearChannel(key);
      }
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
      this.clearChannel(key);
      logEvent('manual-reconnect', { key });
      if (reconnectBuilder) {
        this.ensureChannel(key, reconnectBuilder, reconnectOptions);
      }
    }
  };

  window.appRealtimeManager = manager;
  window.addEventListener('beforeunload', () => manager.clearAll());
})();
