(function initializeAdminAuthorization() {
  const connection = window.aadhyantSupabase;
  const client = connection?.client;
  let intervalId = null;

  const normalizeAuthorization = (row) => ({
    authorized: Boolean(row?.authorized), bootstrap_admin: Boolean(row?.bootstrap_admin),
    staff_profile_id: row?.staff_profile_id || null, display_name: row?.display_name || '',
    active: Boolean(row?.active), roles: Array.isArray(row?.roles) ? row.roles : [],
    admin_shell_access: Boolean(row?.admin_shell_access), staff_management_access: Boolean(row?.staff_management_access)
  });

  const getAuthorization = async () => {
    if (!connection?.isConfigured || !client) return { session: null, authorization: null, error: new Error('Supabase is not configured.') };
    const { data: sessionData, error: sessionError } = await client.auth.getSession();
    if (sessionError || !sessionData.session) return { session: null, authorization: null, error: sessionError || null };
    const { data, error } = await client.rpc('get_current_staff_session');
    const row = Array.isArray(data) ? data[0] : data;
    return { session: sessionData.session, authorization: error ? null : normalizeAuthorization(row), error };
  };

  const requireAccess = async (redirect = './login.html') => {
    const result = await getAuthorization();
    if (!result.session || result.error || !result.authorization?.admin_shell_access) {
      window.location.replace(redirect); return null;
    }
    return result;
  };

  const stopMonitoring = () => { if (intervalId) window.clearInterval(intervalId); intervalId = null; };
  const monitorAccess = (onAuthorized, redirect = './login.html') => {
    stopMonitoring(); let checking = false;
    const check = async () => {
      if (checking || document.hidden) return;
      checking = true;
      try {
        const result = await getAuthorization();
        if (!result.session || result.error || !result.authorization?.admin_shell_access) {
          stopMonitoring(); window.location.replace(redirect); return;
        }
        onAuthorized?.(result);
      } finally { checking = false; }
    };
    client.auth.onAuthStateChange((event) => {
      if (event === 'SIGNED_OUT') { stopMonitoring(); window.location.replace(redirect); }
      else if (event === 'TOKEN_REFRESHED' || event === 'USER_UPDATED' || event === 'SIGNED_IN') window.setTimeout(check, 0);
    });
    document.addEventListener('visibilitychange', () => { if (!document.hidden) check(); });
    window.addEventListener('focus', check);
    window.addEventListener('storage', (event) => { if (event.key?.includes('auth-token')) check(); });
    intervalId = window.setInterval(check, 60000);
    return stopMonitoring;
  };

  window.aadhyantAdminAuth = Object.freeze({ getAuthorization, requireAccess, monitorAccess, stopMonitoring });
}());
