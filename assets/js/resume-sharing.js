(function () {
  'use strict';
  const node = (tag, text = '') => { const el = document.createElement(tag); el.textContent = text; return el; };
  const rpc = async (client, name, args) => { const { data, error } = await client.rpc(name, args); if (error) throw error; return data; };
  const status = (root, text) => { const el = node('p', text); el.setAttribute('role', 'status'); el.setAttribute('aria-live', 'polite'); root.append(el); return el; };
  const button = (text, handler) => { const el = node('button', text); el.type = 'button'; el.className = 'button table-action admin-button admin-button-quiet'; el.addEventListener('click', handler); return el; };
  const ownedUrls = new Set();
  const pendingControls = new WeakSet();
  const clearFiles = () => { ownedUrls.forEach(url => URL.revokeObjectURL(url)); ownedUrls.clear(); };
  window.addEventListener('pagehide', clearFiles);
  const panel = (root, title) => { root.replaceChildren(node('h3', title)); return status(root, 'Loading…'); };
  const lockedAction = async (control, message, action, reload) => {
    if (control.disabled || pendingControls.has(control)) return;
    pendingControls.add(control);
    control.disabled = true; message.textContent = 'Saving…';
    try { if (await action() !== true) throw Error('Unconfirmed result'); if (control.isConnected) await reload(); }
    catch (_) { if (control.isConnected) { message.textContent = 'This change could not be saved. Reload the application and try again.'; control.disabled = false; } }
    finally { pendingControls.delete(control); }
  };
  async function candidate(root, client, requirementCode) {
    const message = panel(root, 'Resume sharing');
    try {
      const data = await rpc(client, 'get_candidate_resume_sharing', { p_requirement_code: requirementCode });
      if (!root.isConnected) return;
      root.replaceChildren(node('h3', 'Resume sharing'));
      if (!data?.recipients?.length) { status(root, 'No Company or Contractor is currently eligible to receive a resume for this application.'); return; }
      data.recipients.forEach(record => {
        const card = node('section'); card.append(node('h4', `${record.recipient_name} (${record.recipient_type})`));
        card.append(node('p', record.file_name || 'Upload a resume in Documents first.'));
        const feedback = status(card, record.shared ? 'Shared by Admin.' : record.consented ? 'Consent recorded. Waiting for Admin to verify and share this resume.' : 'Your resume has not been shared.');
        const args = { p_application_id: data.application_id, p_document_id: record.document_id, p_recipient_type: record.recipient_type, p_recipient_id: record.recipient_id };
        const reload = () => candidate(root, client, requirementCode);
        if (record.consented) {
          const withdraw = button('Withdraw consent', () => lockedAction(withdraw, feedback, () => rpc(client, 'set_candidate_resume_consent', { ...args, p_allow: false }), reload));
          card.append(withdraw);
        } else if (record.document_id) {
          const label = node('label'); const checkbox = document.createElement('input'); checkbox.type = 'checkbox'; checkbox.checked = false;
          label.append(checkbox, document.createTextNode(` I allow Admin to share this resume, including any contact details it contains, with ${record.recipient_name} for this application.`));
          const allow = button('Allow Admin to share', () => { if (checkbox.checked) return lockedAction(allow, feedback, () => rpc(client, 'set_candidate_resume_consent', { ...args, p_allow: true }), reload); });
          allow.disabled = true; checkbox.addEventListener('change', () => { allow.disabled = pendingControls.has(allow) || !checkbox.checked; });
          card.append(label, allow);
        }
        card.append(node('p', 'You can withdraw consent for future access. Already downloaded copies cannot be recalled. Other documents are not included.'));
        root.append(card);
      });
    } catch (_) { if (root.isConnected) message.textContent = 'Resume sharing is temporarily unavailable. Your application is unchanged.'; }
  }
  async function admin(root, client, applicationId) {
    const message = panel(root, 'Share Resume');
    try {
      const data = await rpc(client, 'admin_list_application_resume_sharing', { p_application_id: applicationId });
      if (!root.isConnected) return;
      root.replaceChildren(node('h3', 'Share Resume'));
      if (!data?.recipients?.length) { status(root, 'No eligible Company or Contractor for this application.'); return; }
      data.recipients.forEach(record => {
        const card = node('section'); card.append(node('h4', `${record.recipient_name} (${record.recipient_type})`), node('p', record.file_name || 'No active resume.'));
        const feedback = status(card, record.shared ? 'Shared with this recipient.' : !record.consented ? 'Candidate consent is required.' : !record.verified ? 'Verify the resume under Candidates → View before sharing.' : 'Ready for Admin sharing.');
        const change = (control, shared) => lockedAction(control, feedback, () => rpc(client, 'admin_set_application_resume_share', { p_consent_id: record.consent_id, p_revision: record.revision, p_share: shared }), () => admin(root, client, applicationId));
        if (record.has_grant) { const revoke = button('Stop sharing', () => change(revoke, false)); card.append(revoke); }
        else if (record.consented && record.verified) { const share = button('Share Resume', () => change(share, true)); card.append(share); }
        root.append(card);
      });
    } catch (_) { if (root.isConnected) message.textContent = 'Resume sharing is available only to authorized Admins. Reload if access has changed.'; }
  }
  async function tenant(root, client, applicationId, portal) {
    const message = panel(root, 'Resume');
    try {
      const rows = await rpc(client, 'get_shared_application_resume', { p_application_id: applicationId, p_portal: portal });
      if (!root.isConnected) return;
      root.replaceChildren(node('h3', 'Resume'));
      if (!rows?.length) { status(root, 'No resume has been made available by Admin for this application.'); return; }
      rows.forEach(record => {
        root.append(node('p', record.display_file_name)); const feedback = status(root, 'Shared by Admin with Candidate consent.');
        const view = button('View Resume', async () => {
          if (view.disabled) return; view.disabled = true; feedback.textContent = 'Opening resume…';
          const opened = window.open('about:blank', '_blank'); if (opened) opened.opener = null;
          try {
            const access = (await rpc(client, 'get_shared_application_resume_access', { p_application_id: applicationId, p_document_id: record.document_id, p_portal: portal }))?.[0];
            if (!access || access.bucket_name !== 'candidate-private') throw Error('Unavailable');
            // Authenticated download rechecks current Storage RLS. No public or signed URL is created by this UI.
            const { data, error } = await client.storage.from(access.bucket_name).download(access.object_name);
            if (error || !data || data.size < 1 || data.size > 10485760 || !view.isConnected) throw Error('Unavailable');
            const url = URL.createObjectURL(new Blob([data], { type: 'application/pdf' })); ownedUrls.add(url);
            if (opened) opened.location.replace(url);
            else { const link = node('a', 'Open downloaded resume'); link.href = url; link.target = '_blank'; link.rel = 'noopener noreferrer'; root.append(link); }
            setTimeout(() => { URL.revokeObjectURL(url); ownedUrls.delete(url); }, 60000);
            feedback.textContent = opened ? 'Resume opened. Use it only for this application.' : 'Resume downloaded. Use the link to open it.';
          } catch (_) { opened?.close(); if (view.isConnected) feedback.textContent = 'The resume is no longer available or could not be opened. Reload this application.'; }
          finally { if (view.isConnected) view.disabled = false; }
        }); root.append(view);
      });
    } catch (_) { if (root.isConnected) message.textContent = 'Resume access is unavailable for this account or application.'; }
  }
  window.AadhyantResumeSharing = Object.freeze({ candidate, admin, tenant });
}());
