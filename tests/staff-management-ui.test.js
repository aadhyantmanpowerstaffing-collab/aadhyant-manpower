const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const sourcePath = path.join(__dirname, '..', 'admin', 'staff-management.js');
const roles = ['super_admin', 'admin', 'recruiter', 'operations', 'viewer'];

class Element {
  constructor(tagName = '') {
    this.tagName = tagName;
    this.children = [];
    this.listeners = {};
    this.hidden = false;
    this.disabled = false;
    this.className = '';
    this.classList = { toggle: (name, enabled) => {
      const classes = new Set(this.className.split(/\s+/).filter(Boolean));
      if (enabled) classes.add(name); else classes.delete(name);
      this.className = [...classes].join(' ');
    } };
  }

  append(...children) { children.forEach((child) => { this.children.push(child); if (child && typeof child === 'object') child.parent = this; }); }
  replaceChildren(...children) { this.children = []; this.append(...children); }
  addEventListener(name, handler) { this.listeners[name] = handler; }
  setAttribute(name, value) { this[name] = value; }
  remove() { if (this.parent) this.parent.children = this.parent.children.filter((child) => child !== this); }
  get options() { return this.children; }
}

const makeHarness = async ({ authorization, mutationError = false }) => {
  const panel = new Element('section');
  const tab = new Element('button');
  const body = new Element('tbody');
  const empty = new Element('div');
  const message = new Element('div');
  const refresh = new Element('button');
  const createForm = new Element('form');
  const initialRole = new Element('select');
  roles.forEach((role) => { const option = new Element('option'); option.value = role; initialRole.append(option); });
  createForm.elements = { initialRole, email: new Element('input'), displayName: new Element('input') };
  createForm.querySelector = () => new Element('button');
  panel.querySelector = (selector) => ({
    '[data-staff-list]': body,
    '[data-staff-empty]': empty,
    '[data-staff-message]': message,
    '[data-create-staff-form]': createForm,
    '[data-refresh-staff]': refresh
  }[selector]);

  const records = [
    { user_id: 'viewer', email: 'viewer@example.invalid', display_name: 'Viewer', status: 'active', roles: ['viewer'], created_at: '2026-01-01', updated_at: '2026-01-01' },
    { user_id: 'super', email: 'super@example.invalid', display_name: 'Super', status: 'active', roles: ['super_admin'], created_at: '2026-01-01', updated_at: '2026-01-01' }
  ];
  const client = { rpc: async (name) => name === 'list_internal_staff' ? { data: records, error: null } : { data: null, error: mutationError ? new Error('denied') : null } };
  const document = {
    querySelector: (selector) => selector === '[data-panel="staff"]' ? panel : tab,
    createElement: (tagName) => new Element(tagName),
    createTextNode: (text) => ({ textContent: text })
  };
  const window = { crypto: { randomUUID: () => 'correlation-id' } };
  vm.runInNewContext(fs.readFileSync(sourcePath, 'utf8'), { document, window, Date, Set, String, Array, Boolean });
  window.aadhyantStaffManagement.initialize({ client, authorization });
  await new Promise((resolve) => setImmediate(resolve));
  return { body, createForm };
};

const controls = (row) => ({
  name: row.children[0].children[0],
  status: row.children[2].children[0],
  roles: Object.fromEntries(roles.map((role, index) => [role, row.children[3].children[0].children[index].children[0]])),
  save: row.children[5].children[0]
});

test('ordinary admin can manage non-elevated roles but not elevated roles or elevated staff', async () => {
  const { body, createForm } = await makeHarness({ authorization: { staff_management_access: true, bootstrap_admin: false, roles: ['admin'] } });
  const viewer = controls(body.children[0]);
  assert.equal(viewer.roles.super_admin.disabled, true);
  assert.equal(viewer.roles.admin.disabled, true);
  assert.equal(viewer.roles.recruiter.disabled, false);
  assert.equal(viewer.roles.operations.disabled, false);
  assert.equal(viewer.roles.viewer.disabled, false);
  const elevated = controls(body.children[1]);
  assert.equal(elevated.name.disabled, true);
  assert.equal(elevated.status.disabled, true);
  assert.equal(elevated.save.disabled, true);
  roles.forEach((role) => assert.equal(elevated.roles[role].disabled, true));
  assert.deepEqual(Array.from(createForm.elements.initialRole.options, (option) => option.value), ['recruiter', 'operations', 'viewer']);
});

for (const authorization of [
  { name: 'super_admin', staff_management_access: true, bootstrap_admin: false, roles: ['super_admin'] },
  { name: 'bootstrap_admin', staff_management_access: true, bootstrap_admin: true, roles: [] }
]) {
  test(`${authorization.name} retains elevated management controls`, async () => {
    const { body } = await makeHarness({ authorization });
    for (const row of body.children) {
      const rowControls = controls(row);
      assert.equal(rowControls.name.disabled, false);
      assert.equal(rowControls.status.disabled, false);
      assert.equal(rowControls.save.disabled, false);
      roles.forEach((role) => assert.equal(rowControls.roles[role].disabled, false));
    }
  });
}

test('ordinary admin elevated control remains disabled after an async error cycle', async () => {
  const { body } = await makeHarness({ authorization: { staff_management_access: true, bootstrap_admin: false, roles: ['admin'] }, mutationError: true });
  const checkbox = controls(body.children[0]).roles.super_admin;
  assert.equal(checkbox.disabled, true);
  checkbox.checked = true;
  await checkbox.listeners.change();
  assert.equal(checkbox.checked, false);
  assert.equal(checkbox.disabled, true);
  const elevated = controls(body.children[1]);
  elevated.name.value = 'Changed name';
  await elevated.save.listeners.click();
  assert.equal(elevated.name.disabled, true);
  assert.equal(elevated.status.disabled, true);
  assert.equal(elevated.save.disabled, true);
  roles.forEach((role) => assert.equal(elevated.roles[role].disabled, true));
});

test('disabled staff controls have an explicit accessible visual state', () => {
  const css = fs.readFileSync(path.join(__dirname, '..', 'admin', 'admin.css'), 'utf8');
  assert.match(css, /\.staff-table input:disabled/);
  assert.match(css, /\.staff-role-list label\.is-disabled/);
  assert.match(css, /cursor:not-allowed/);
});
