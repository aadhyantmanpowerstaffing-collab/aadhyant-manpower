(function initializeSupabaseClient() {
  const config = window.AADHYANT_CONFIG || {};
  const expectedOriginMatches = typeof config.expectedOrigin === 'string'
    && window.location.origin === config.expectedOrigin;
  let supabaseBindingMatches = false;
  try {
    const parsedUrl = new URL(config.supabaseUrl);
    supabaseBindingMatches = parsedUrl.protocol === 'https:'
      && parsedUrl.hostname === `${config.supabaseProjectRef}.supabase.co`
      && /^[a-z0-9]{20}$/.test(config.supabaseProjectRef || '')
      && (parsedUrl.pathname === '' || parsedUrl.pathname === '/');
  } catch (_error) {
    supabaseBindingMatches = false;
  }
  const hasPlaceholders = !config.supabaseUrl
    || !config.supabasePublishableKey
    || config.supabaseUrl.includes('YOUR_SUPABASE_')
    || config.supabasePublishableKey.includes('YOUR_SUPABASE_')
    || !expectedOriginMatches
    || !supabaseBindingMatches;

  const api = {
    client: null,
    isConfigured: false,
    configurationMessage: expectedOriginMatches
      ? 'Online submission is temporarily unavailable. Please use WhatsApp or email instead.'
      : 'Online access is unavailable from this site origin.'
  };

  if (!hasPlaceholders && window.supabase?.createClient) {
    try {
      const usesAuthenticatedPortal = window.location.pathname.includes('/admin/')
        || window.location.pathname.includes('/company/')
        || window.location.pathname.includes('/contractor/')
        || window.location.pathname.includes('/candidate/portal/');
      api.client = window.supabase.createClient(config.supabaseUrl, config.supabasePublishableKey, {
        auth: usesAuthenticatedPortal
          ? { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
          : { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }
      });
      api.isConfigured = true;
      api.configurationMessage = '';
    } catch (_error) {
      // Keep the public page usable through its existing WhatsApp and email fallbacks.
    }
  }

  window.aadhyantSupabase = Object.freeze(api);
}());
