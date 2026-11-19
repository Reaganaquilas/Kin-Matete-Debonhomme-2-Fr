(function () {
  const config = {
    url: 'https://grrxlasibdntcjuqqfjl.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdycnhsYXNpYmRudGNqdXFxZmpsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkwNTAyMjUsImV4cCI6MjEwNDYyNjIyNX0.njcj0kHqjv6hwyLgJZ-6WP8DEUrTcofQ_-_0pkaBfDY',
    assemblyId: '55954'
  };

  const hasValidAnonKey = Boolean(
    config.anonKey &&
    config.anonKey !== 'PUBLIC_ANON_KEY' &&
    config.anonKey !== 'YOUR_ANON_KEY' &&
    config.anonKey !== 'replace-me'
  );

  const supabaseFactory = typeof window !== 'undefined' && window.supabase && typeof window.supabase.createClient === 'function'
    ? window.supabase
    : null;

  function buildClient() {
    if (!supabaseFactory || !config.url || !hasValidAnonKey) return null;
    return supabaseFactory.createClient(config.url, config.anonKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true
      }
    });
  }

  function hasRealSupabaseShape() {
    const urlLooksValid = /^https:\/\/[-a-z0-9]+\.supabase\.co\/?$/i.test(config.url || '');
    const anonLooksValid = /^(?:sb_[A-Za-z0-9_-]+|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)$/i.test(config.anonKey || '');
    return Boolean(config.url && config.anonKey && urlLooksValid && anonLooksValid);
  }

  async function validateSupabaseProject(client) {
    if (!client || !config.url || !hasValidAnonKey) return false;
    if (!hasRealSupabaseShape()) return false;
    return true;
  }

  const initialState = {
    config,
    configured: false,
    mode: 'local-only',
    client: null,
    status: 'Supabase non disponible – mode local uniquement'
  };

  window.appAuth = initialState;

  const client = buildClient();
  if (client) {
    initialState.client = client;
    validateSupabaseProject(client).then(isConfigured => {
      initialState.configured = isConfigured;
      initialState.mode = isConfigured ? 'supabase' : 'local-only';
      initialState.status = isConfigured ? 'Supabase prêt' : 'Supabase non disponible – mode local uniquement';
      if (!isConfigured) {
        initialState.client = null;
      }
    }).catch(() => {
      initialState.configured = false;
      initialState.mode = 'local-only';
      initialState.client = null;
      initialState.status = 'Supabase non disponible – mode local uniquement';
    });
  }

  window.appAuth.validate = async function validateAppAuth() {
    if (!client || !config.url || !hasValidAnonKey) {
      initialState.configured = false;
      initialState.mode = 'local-only';
      initialState.client = null;
      initialState.status = 'Supabase non disponible – mode local uniquement';
      return false;
    }

    const isConfigured = await validateSupabaseProject(client);
    initialState.configured = isConfigured;
    initialState.mode = isConfigured ? 'supabase' : 'local-only';
    initialState.status = isConfigured ? 'Supabase prêt' : 'Supabase non disponible – mode local uniquement';
    if (!isConfigured) {
      initialState.client = null;
    }
    return isConfigured;
  };
})();
