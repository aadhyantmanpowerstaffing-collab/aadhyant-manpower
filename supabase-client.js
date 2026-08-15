(function initializeSupabaseClient() {
  const config = window.AADHYANT_CONFIG || {};
  const hasPlaceholders = !config.supabaseUrl
    || !config.supabasePublishableKey
    || config.supabaseUrl.includes('YOUR_SUPABASE_')
    || config.supabasePublishableKey.includes('YOUR_SUPABASE_');

  const api = {
    client: null,
    isConfigured: false,
    configurationMessage: 'Online submission is temporarily unavailable. Please use WhatsApp or email instead.'
  };

  if (!hasPlaceholders && window.supabase?.createClient) {
    try {
      const usesAuthenticatedPortal = window.location.pathname.includes('/admin/')
        || window.location.pathname.includes('/company/');
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
