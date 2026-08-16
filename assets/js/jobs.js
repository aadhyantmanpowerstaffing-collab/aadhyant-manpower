(() => {
  'use strict';

  const form = document.querySelector('[data-job-filters]');
  const list = document.querySelector('[data-jobs-list]');
  const loading = document.querySelector('[data-jobs-loading]');
  const empty = document.querySelector('[data-jobs-empty]');
  const error = document.querySelector('[data-jobs-error]');
  if (!form || !list || !loading || !empty || !error) return;

  const text = (value) => String(value ?? '').trim();
  const detail = (term, value) => {
    if (!text(value)) return null;
    const wrapper = document.createElement('div');
    const label = document.createElement('dt');
    const description = document.createElement('dd');
    label.textContent = term;
    description.textContent = text(value);
    wrapper.append(label, description);
    return wrapper;
  };
  const formatSalary = (job) => {
    const currency = (value) => Number.isFinite(Number(value))
      ? new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 }).format(Number(value))
      : '';
    if (job.salary_min != null || job.salary_max != null) {
      return [currency(job.salary_min), currency(job.salary_max)].filter(Boolean).join(' – ');
    }
    return text(job.salary_text);
  };
  const facilitySummary = (job) => [
    ['Canteen', job.canteen], ['Transport', job.transport], ['Accommodation', job.accommodation]
  ].filter(([, value]) => value === 'Yes').map(([label]) => label).join(', ');
  const interviewSummary = (job) => {
    const date = job.interview_date
      ? new Intl.DateTimeFormat('en-IN', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(job.interview_date))
      : '';
    return [date, text(job.interview_location)].filter(Boolean).join(' · ');
  };

  const createCard = (job) => {
    const card = document.createElement('article');
    card.className = 'public-job-card';
    card.dataset.jobCard = '';
    card.dataset.keyword = [job.requirement_code, job.job_role, job.department, job.iti_trade].map(text).join(' ');
    card.dataset.location = text(job.job_location);
    card.dataset.qualification = [job.qualification, job.iti_trade].map(text).join(' ');
    card.dataset.experience = text(job.experience_requirement);

    const code = document.createElement('p');
    code.className = 'public-job-code';
    code.textContent = text(job.requirement_code);
    const title = document.createElement('h3');
    title.textContent = text(job.job_role) || 'Workforce Opportunity';
    const department = document.createElement('p');
    department.className = 'public-job-department';
    department.textContent = text(job.department);
    department.hidden = !department.textContent;
    const details = document.createElement('dl');
    [
      detail('Location', job.job_location),
      detail('Open Positions', job.open_positions),
      detail('Salary', formatSalary(job)),
      detail('Qualification', job.qualification),
      detail('Trade', job.iti_trade),
      detail('Experience', job.experience_requirement),
      detail('Shift', job.shift_details),
      detail('Work Timing', job.working_hours),
      detail('Facilities', facilitySummary(job)),
      detail('Interview', interviewSummary(job))
    ].filter(Boolean).forEach((item) => details.append(item));
    const action = document.createElement('a');
    action.className = 'public-button public-button--primary';
    action.href = `../candidate/register/?requirement=${encodeURIComponent(text(job.requirement_code))}`;
    action.textContent = 'Register Interest';
    card.append(code, title, department, details, action);
    return card;
  };

  const applyFilters = () => {
    const values = Object.fromEntries(new FormData(form));
    let visible = 0;
    list.querySelectorAll('[data-job-card]').forEach((card) => {
      const matches = ['keyword', 'location', 'qualification', 'experience'].every((key) => {
        const query = text(values[key]).toLocaleLowerCase('en-IN');
        return !query || text(card.dataset[key]).toLocaleLowerCase('en-IN').includes(query);
      });
      card.hidden = !matches;
      if (matches) visible += 1;
    });
    empty.hidden = list.children.length > 0 ? visible > 0 : false;
  };

  form.addEventListener('submit', (event) => { event.preventDefault(); applyFilters(); });
  form.addEventListener('reset', () => requestAnimationFrame(applyFilters));

  const load = async () => {
    const api = window.aadhyantSupabase;
    if (!api?.isConfigured || !api.client) {
      loading.hidden = true;
      error.hidden = false;
      list.setAttribute('aria-busy', 'false');
      return;
    }
    try {
      const { data, error: rpcError } = await api.client.rpc('get_public_job_requirements', { p_limit: 20, p_offset: 0 });
      if (rpcError) throw new Error('Public Jobs endpoint unavailable');
      (data || []).forEach((job) => list.append(createCard(job)));
      loading.hidden = true;
      list.setAttribute('aria-busy', 'false');
      applyFilters();
    } catch (_error) {
      loading.hidden = true;
      list.setAttribute('aria-busy', 'false');
      error.hidden = false;
    }
  };

  load();
})();
