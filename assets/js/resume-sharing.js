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
  const layouts = new WeakMap();
  const selectedGroups = new WeakMap();
  const panel = (root, title) => {
    layouts.get(root)?.forEach(group => group.clear());
    root.setAttribute('data-application-sharing', '');
    root.replaceChildren(node('h3', title)); return status(root, 'Loading…');
  };
  const lockedAction = async (control, message, action, reload) => {
    if (control.disabled || pendingControls.has(control)) return;
    pendingControls.add(control);
    control.disabled = true; message.textContent = 'Saving…';
    try { if (await action() !== true) throw Error('Unconfirmed result'); if (control.isConnected) await reload(); }
    catch (_) { if (control.isConnected) { message.textContent = 'This change could not be saved. Reload the application and try again.'; control.disabled = false; } }
    finally { pendingControls.delete(control); }
  };
  const title = 'Documents and joining details';
  const fields = { account_holder_name: 'Account holder', bank_name: 'Bank', bank_account_number: 'Account number', bank_account_last4: 'Saved account ending', ifsc: 'IFSC', has_existing_uan: 'Existing UAN', uan_number: 'UAN number', has_existing_esic_ip: 'Existing ESIC IP', esic_ip_number: 'ESIC IP number' };
  const categories = [['document', 'Documents'], ['bank', 'Bank details'], ['uan', 'UAN (PF)'], ['esic', 'ESIC']];
  function groupedItems(root, records, adminMode = false) {
    const recipients = new Map(), groups = [], entries = [];
    records.forEach(record => {
      const key = adminMode ? JSON.stringify([record.recipient_type, record.recipient_id]) : 'recipient';
      if (!recipients.has(key)) recipients.set(key, []);
      recipients.get(key).push(record);
    });
    recipients.forEach((items, recipientKey) => {
      const recipient = node('section'); recipient.className = 'sharing-recipient';
      if (adminMode) {
        const heading = node('h4', items[0].recipient_name); heading.className = 'sharing-recipient-name';
        const type = node('span', items[0].recipient_type === 'company' ? 'Company' : 'Contractor'); type.className = 'sharing-recipient-type';
        heading.append(type); recipient.append(heading);
      }
      root.append(recipient);
      categories.forEach(([kind, label]) => {
        const matches = items.filter(record => record.item_kind === kind);
        if (!matches.length) return;
        const key = `${recipientKey}:${kind}`, element = node('details'), summary = node('summary'), body = node('div');
        element.className = 'sharing-group'; element.setAttribute('data-sharing-category', kind);
        body.className = 'sharing-group-body';
        const labelNode = node('span', label); labelNode.className = 'sharing-group-label';
        const shared = matches.filter(record => record.shared).length;
        const ready = matches.filter(record => record.available && !record.shared).length;
        const meta = node('span', adminMode
          ? [shared && `${shared} shared`, ready && `${ready} ready`, matches.length - shared - ready > 0 && `${matches.length - shared - ready} unavailable`].filter(Boolean).join(' · ')
          : kind === 'document' ? `${matches.length} shared` : 'Shared by Admin');
        meta.className = 'sharing-group-meta'; summary.append(labelNode, meta); element.append(summary, body); recipient.append(element);
        const cleaners = new Set();
        const group = { element, key, clear: () => cleaners.forEach(clear => clear()), track: clear => cleaners.add(clear) };
        groups.push(group);
        element.addEventListener('toggle', () => {
          if (!element.open) { group.clear(); if (selectedGroups.get(root) === key) selectedGroups.delete(root); return; }
          selectedGroups.set(root, key);
          groups.forEach(other => { if (other !== group) { other.element.open = false; other.clear(); } });
        });
        matches.forEach(record => {
          const card = node('section'); card.className = 'sharing-item'; card.setAttribute('data-sharing-item', record.item_key);
          if (kind === 'document') { const name = node('h5', record.label); name.className = 'sharing-file-name'; card.append(name); }
          body.append(card); entries.push({ record, card, group });
        });
      });
    });
    layouts.set(root, groups);
    const active = groups.find(group => group.key === selectedGroups.get(root)) || groups[0];
    if (active) active.element.open = true;
    return entries;
  }
  function detailControl(root, client, applicationId, record, group, portal) {
    const details = node('section'); details.className = 'sharing-detail';
    const feedback = status(details, ''), values = node('dl'); values.className = 'sharing-values'; let shown = false, requestId = 0;
    const clear = () => { requestId++; shown = false; values.replaceChildren(); feedback.textContent = ''; view.textContent = 'View details'; view.disabled = false; view.setAttribute('aria-expanded', 'false'); };
    const view = button('View details', async () => {
      if (view.disabled) return;
      if (shown) { clear(); return; }
      const request = ++requestId;
      view.disabled = true; feedback.textContent = 'Loading…';
      try {
        const data = await rpc(client, portal ? 'get_shared_application_joining_detail' : 'admin_get_application_joining_detail', {
          p_application_id: applicationId, p_item_key: record.item_key, ...(portal ? { p_portal: portal } : {})
        });
        if (!view.isConnected || request !== requestId || !group.element.open) return;
        if (!data) throw Error('Unavailable');
        Object.entries(fields).forEach(([key, label]) => {
          if (key === 'bank_account_last4' && data.bank_account_number) return;
          if (Object.hasOwn(data, key) && data[key] !== null) {
            const field = node('div'); field.append(node('dt', label), node('dd', typeof data[key] === 'boolean' ? (data[key] ? 'Yes' : 'No') : data[key])); values.append(field);
          }
        });
        if (data.full_account_available === false) { const field = node('div'); field.append(node('dt', 'Account number'), node('dd', 'Not saved in full. The Candidate needs to save it once.')); values.append(field); }
        view.textContent = 'Hide details'; view.setAttribute('aria-expanded', 'true'); shown = true; feedback.textContent = '';
        // Do not leave financial identifiers visible indefinitely in an open modal.
        setTimeout(() => { if (shown && view.isConnected && request === requestId) clear(); }, 60000);
      } catch (_) { if (view.isConnected && request === requestId) feedback.textContent = 'These details are unavailable. Reload this application.'; }
      finally { if (view.isConnected && request === requestId) view.disabled = false; }
    }); view.setAttribute('aria-expanded', 'false'); details.append(view, values); root.append(details); group.track(clear);
  }
  async function candidate(root, client, requirementCode) {
    const message = panel(root, title);
    try {
      const data = await rpc(client, 'get_candidate_document_sharing', { p_requirement_code: requirementCode });
      if (!root.isConnected) return;
      root.replaceChildren(node('h3', title));
      status(root, 'Admin manages sharing with the Company or Contractor for this application. No separate sharing action is required from you.');
      const shared = data?.items?.filter(record => record.shared) || [];
      if (!shared.length) status(root, 'Admin has not shared any current items for this application.');
      shared.forEach(record => root.append(node('p', `${record.label} — shared with ${record.recipient_name} (${record.recipient_type}).`)));
    } catch (_) { if (root.isConnected) message.textContent = 'Sharing status is temporarily unavailable. Your application is unchanged.'; }
  }
  async function admin(root, client, applicationId) {
    const message = panel(root, title);
    try {
      const data = await rpc(client, 'admin_list_application_document_sharing', { p_application_id: applicationId });
      if (!root.isConnected) return;
      root.replaceChildren(node('h3', title));
      status(root, 'Open a section to view or share an item with the named recipient.');
      const note = node('p', 'Stopping sharing prevents future access. Already downloaded copies cannot be recalled.'); note.className = 'sharing-note'; root.append(note);
      if (!data?.items?.length) { status(root, 'No eligible Company or Contractor for this application.'); return; }
      groupedItems(root, data.items, true).forEach(({ record, card, group }) => {
        const feedback = status(card, record.shared ? 'Shared with this recipient.' : !record.available ? 'Save joining details or verify the uploaded document before sharing.' : 'Ready for Admin sharing.');
        const change = (control, shared) => lockedAction(control, feedback, () => rpc(client, 'admin_set_application_document_share', {
          p_application_id: applicationId, p_item_key: record.item_key, p_recipient_type: record.recipient_type, p_recipient_id: record.recipient_id,
          p_source_token: record.source_token, p_revision: record.revision, p_share: shared
        }), () => admin(root, client, applicationId));
        const actions = node('div'); actions.className = 'sharing-actions'; card.append(actions);
        if (record.has_grant) { const revoke = button('Stop sharing', () => change(revoke, false)); revoke.setAttribute('data-sharing-action', 'revoke'); actions.append(revoke); }
        if (record.available && !record.shared) { const share = button('Share item', () => change(share, true)); share.setAttribute('data-sharing-action', 'share'); actions.append(share); }
        if (['bank', 'uan', 'esic'].includes(record.item_kind)) detailControl(card, client, applicationId, record, group);
      });
    } catch (_) { if (root.isConnected) message.textContent = 'Document sharing is available only to authorized Admins. Reload if access has changed.'; }
  }
  async function tenant(root, client, applicationId, portal) {
    const message = panel(root, title);
    try {
      const rows = await rpc(client, 'get_shared_application_items', { p_application_id: applicationId, p_portal: portal });
      if (!root.isConnected) return;
      root.replaceChildren(node('h3', title));
      if (!rows?.length) { status(root, 'Admin has not made any documents or joining details available for this application.'); return; }
      status(root, 'Open one section at a time. Only items shared by Admin are shown.');
      groupedItems(root, rows).forEach(({ record, card, group }) => {
        if (['bank', 'uan', 'esic'].includes(record.item_kind)) { detailControl(card, client, applicationId, record, group, portal); return; }
        if (record.item_kind !== 'document') return;
        const feedback = status(card, 'Shared by Admin for this application.');
        const view = button('View document', async () => {
          if (view.disabled) return; view.disabled = true; feedback.textContent = 'Opening document…';
          const opened = window.open('about:blank', '_blank'); if (opened) opened.opener = null;
          try {
            const access = (await rpc(client, 'get_shared_application_document_access', { p_application_id: applicationId, p_document_id: record.document_id, p_portal: portal }))?.[0];
            if (!access || access.bucket_name !== 'candidate-private' || !['application/pdf', 'image/jpeg', 'image/png'].includes(access.mime_type)) throw Error('Unavailable');
            const { data, error } = await client.storage.from(access.bucket_name).download(access.object_name);
            if (error || !data || data.size < 1 || data.size > 10485760 || !view.isConnected) throw Error('Unavailable');
            const url = URL.createObjectURL(new Blob([data], { type: access.mime_type })); ownedUrls.add(url);
            if (opened) opened.location.replace(url);
            else { const link = node('a', 'Open downloaded document'); link.href = url; link.target = '_blank'; link.rel = 'noopener noreferrer'; card.append(link); }
            setTimeout(() => { URL.revokeObjectURL(url); ownedUrls.delete(url); }, 60000);
            feedback.textContent = 'Document opened. Use it only for this application.';
          } catch (_) { opened?.close(); if (view.isConnected) feedback.textContent = 'The document is no longer available or could not be opened. Reload this application.'; }
          finally { if (view.isConnected) view.disabled = false; }
        }); card.append(view);
      });
    } catch (_) { if (root.isConnected) message.textContent = 'Shared information is unavailable for this account or application.'; }
  }
  window.AadhyantResumeSharing = Object.freeze({ candidate, admin, tenant });
}());
