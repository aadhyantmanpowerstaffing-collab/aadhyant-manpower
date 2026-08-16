(() => {
  'use strict';
  const form = document.querySelector('[data-job-filters]');
  const list = document.querySelector('[data-jobs-list]');
  const empty = document.querySelector('[data-jobs-empty]');
  if (!form || !list || !empty) return;

  const render = () => {
    const values = Object.fromEntries(new FormData(form));
    let visible = 0;
    list.querySelectorAll('[data-job-card]').forEach((card) => {
      const matches = ['keyword', 'location', 'qualification', 'experience'].every((key) => {
        const query = String(values[key] || '').trim().toLocaleLowerCase('en-IN');
        return !query || String(card.dataset[key] || '').toLocaleLowerCase('en-IN').includes(query);
      });
      card.hidden = !matches;
      if (matches) visible += 1;
    });
    empty.hidden = visible > 0;
  };

  form.addEventListener('submit', (event) => { event.preventDefault(); render(); });
  form.addEventListener('reset', () => requestAnimationFrame(render));
  render();
})();
