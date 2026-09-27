/* Local UI fixture only. No Supabase client, credentials, network, or persistent data. */
'use strict';
const portal = new URLSearchParams(location.search).get('portal') || 'company';
const records = [
  { item_key: 'bank', item_kind: 'bank', label: 'Bank details' },
  { item_key: 'cv', item_kind: 'document', document_id: 'sample-cv', label: 'Sample_Candidate_Resume.pdf' },
  { item_key: 'certificate', item_kind: 'document', document_id: 'sample-cert', label: 'ITI_Certificate.pdf' },
  { item_key: 'esic', item_kind: 'esic', label: 'ESIC details' },
  { item_key: 'uan', item_kind: 'uan', label: 'UAN (PF) details' }
].map(r => ({ ...r, recipient_type: 'company', recipient_id: 'synthetic-company', recipient_name: 'Sample Company', available: true, shared: true, has_grant: true, source_token: 'synthetic-revision', revision: 'synthetic-revision' }));
let reads = 0, writes = 0;
const sampleDetails = {
  bank: { account_holder_name: 'Sample Candidate', bank_name: 'Example Bank', bank_account_number: '000011112222', bank_account_last4: '2222', ifsc: 'TEST0000001' },
  uan: { has_existing_uan: true, uan_number: '000011112222' },
  esic: { has_existing_esic_ip: true, esic_ip_number: '0000111122' }
};
const client = {
  async rpc(name, args) {
    let data;
    if (name === 'admin_list_application_document_sharing') data = { items: records.map(r => ({ ...r })) };
    else if (name === 'get_shared_application_items') data = records.filter(r => r.shared).map(r => ({ ...r }));
    else if (['get_shared_application_joining_detail', 'admin_get_application_joining_detail'].includes(name)) { reads++; data = sampleDetails[args.p_item_key]; }
    else if (name === 'admin_set_application_document_share') { writes++; const row = records.find(r => r.item_key === args.p_item_key); row.shared = args.p_share; row.has_grant = args.p_share; data = true; }
    else return { error: new Error('Document download is outside this synthetic layout preview.') };
    document.getElementById('counts').textContent = `Synthetic detail reads: ${reads} · Synthetic share changes: ${writes}`;
    return { data };
  }
};
const root = document.getElementById('sharing');
if (portal === 'admin') window.AadhyantResumeSharing.admin(root, client, 'synthetic-application');
else window.AadhyantResumeSharing.tenant(root, client, 'synthetic-application', portal === 'contractor' ? 'contractor' : 'company');
