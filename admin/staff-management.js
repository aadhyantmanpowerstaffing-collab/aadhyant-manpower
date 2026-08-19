(function initializeStaffManagementModule() {
  const roles = ['super_admin', 'admin', 'recruiter', 'operations', 'viewer'];
  const readable = (value) => String(value || '').replaceAll('_', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());
  const correlationId = () => window.crypto?.randomUUID?.() || null;
  const setMessage = (element, text, type = '') => { element.textContent = text; element.classList.toggle('is-error', type === 'error'); element.classList.toggle('is-success', type === 'success'); };

  const initialize = ({ client, authorization }) => {
    const panel = document.querySelector('[data-panel="staff"]'); const tab = document.querySelector('[data-tab="staff"]');
    if (!panel || !tab || !authorization.staff_management_access) return;
    tab.hidden = false;
    const body = panel.querySelector('[data-staff-list]'); const empty = panel.querySelector('[data-staff-empty]');
    const message = panel.querySelector('[data-staff-message]'); const createForm = panel.querySelector('[data-create-staff-form]');
    const canManageElevated = authorization.bootstrap_admin || authorization.roles.includes('super_admin');
    const call = async (name, parameters) => { const { data, error } = await client.rpc(name, parameters); if (error) throw error; return data; };

    const load = async () => {
      setMessage(message, 'Loading staff accounts…');
      const { data, error } = await client.rpc('list_internal_staff');
      if (error) { setMessage(message, 'Staff accounts could not be loaded.', 'error'); return; }
      const staff = data || []; body.replaceChildren(); empty.hidden = staff.length > 0;
      staff.forEach((record) => {
        const row = document.createElement('tr');
        const nameCell = document.createElement('td'); const nameInput = document.createElement('input');
        nameInput.value = record.display_name || ''; nameInput.maxLength = 160; nameInput.setAttribute('aria-label', `Display name for ${record.email}`); nameCell.append(nameInput);
        const emailCell = document.createElement('td'); emailCell.textContent = record.email || '—';
        const statusCell = document.createElement('td'); const statusSelect = document.createElement('select');
        ['active', 'suspended', 'inactive'].forEach((status) => { const option = document.createElement('option'); option.value = status; option.textContent = readable(status); option.selected = record.status === status; statusSelect.append(option); });
        const targetIsElevated = (record.roles || []).some((role) => role === 'super_admin' || role === 'admin'); statusSelect.disabled = targetIsElevated && !canManageElevated; statusCell.append(statusSelect);
        const roleCell = document.createElement('td'); const roleList = document.createElement('div'); roleList.className = 'staff-role-list';
        roles.forEach((role) => {
          const label = document.createElement('label'); const checkbox = document.createElement('input'); checkbox.type = 'checkbox'; checkbox.checked = (record.roles || []).includes(role); checkbox.disabled = (role === 'super_admin' || role === 'admin') && !canManageElevated;
          checkbox.addEventListener('change', async () => {
            checkbox.disabled = true; setMessage(message, 'Updating staff role…');
            try { await call(checkbox.checked ? 'grant_staff_role' : 'revoke_staff_role', { p_user_id: record.user_id, p_role: role, p_correlation_id: correlationId() }); setMessage(message, `${readable(role)} role ${checkbox.checked ? 'granted' : 'revoked'}.`, 'success'); await load(); }
            catch (_error) { checkbox.checked = !checkbox.checked; setMessage(message, 'The role change was denied or could not be saved.', 'error'); }
            finally { checkbox.disabled = false; }
          });
          label.append(checkbox, document.createTextNode(readable(role))); roleList.append(label);
        }); roleCell.append(roleList);
        const datesCell = document.createElement('td'); datesCell.textContent = `Created ${new Date(record.created_at).toLocaleDateString()} · Updated ${new Date(record.updated_at).toLocaleDateString()}`;
        const actionsCell = document.createElement('td'); const save = document.createElement('button'); save.type = 'button'; save.className = 'admin-button admin-button-secondary'; save.textContent = 'Save Profile'; save.disabled = targetIsElevated && !canManageElevated;
        save.addEventListener('click', async () => {
          save.disabled = true; setMessage(message, 'Saving staff profile…');
          try {
            if (nameInput.value.trim() !== record.display_name) await call('update_internal_staff_profile', { p_user_id: record.user_id, p_display_name: nameInput.value.trim(), p_correlation_id: correlationId() });
            if (statusSelect.value !== record.status) await call('set_staff_active_state', { p_user_id: record.user_id, p_status: statusSelect.value, p_correlation_id: correlationId() });
            setMessage(message, 'Staff profile saved.', 'success'); await load();
          } catch (_error) { setMessage(message, 'The profile change was denied or could not be saved.', 'error'); }
          finally { save.disabled = false; }
        }); actionsCell.append(save);
        [nameCell, emailCell, statusCell, roleCell, datesCell, actionsCell].forEach((cell) => row.append(cell)); body.append(row);
      });
      if (staff.length) setMessage(message, '');
    };

    const initialRole = createForm.elements.initialRole;
    if (!canManageElevated) Array.from(initialRole.options).forEach((option) => { if (option.value === 'super_admin' || option.value === 'admin') option.remove(); });
    createForm.addEventListener('submit', async (event) => {
      event.preventDefault(); if (!createForm.checkValidity()) { createForm.reportValidity(); return; }
      const button = createForm.querySelector('button[type="submit"]'); button.disabled = true; setMessage(message, 'Creating staff profile…');
      try {
        const id = await call('create_internal_staff', { p_email: createForm.elements.email.value.trim().toLowerCase(), p_display_name: createForm.elements.displayName.value.trim(), p_correlation_id: correlationId() });
        await call('grant_staff_role', { p_user_id: id, p_role: initialRole.value, p_correlation_id: correlationId() });
        createForm.reset(); setMessage(message, 'Staff profile created and initial role granted.', 'success'); await load();
      } catch (_error) { setMessage(message, 'The profile could not be created. Confirm the Auth user exists and is not a tenant identity.', 'error'); }
      finally { button.disabled = false; }
    });
    panel.querySelector('[data-refresh-staff]').addEventListener('click', load); load();
  };
  window.aadhyantStaffManagement = Object.freeze({ initialize });
}());
