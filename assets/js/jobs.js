(() => {
  'use strict';

  const PAGE_SIZE = 20;
  const MAX_DETAIL_PAGES = 5;
  const text = (value) => String(value ?? '').trim();
  const lower = (value) => text(value).toLocaleLowerCase('en-IN');
  const make = (tag, className = '', content = '') => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (content) node.textContent = content;
    return node;
  };

  const formatDate = (value, prefix = '') => {
    if (!value) return '';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    return `${prefix}${new Intl.DateTimeFormat('en-IN', { dateStyle: 'medium' }).format(date)}`;
  };

  const currency = (value) => Number.isFinite(Number(value))
    ? new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 }).format(Number(value))
    : '';

  const formatSalary = (job) => {
    if (job.salary_min != null || job.salary_max != null) {
      const values = [currency(job.salary_min), currency(job.salary_max)].filter(Boolean);
      return values.length === 2 && values[0] === values[1] ? values[0] : values.join(' – ');
    }
    return text(job.salary_text);
  };

  const facilities = (job) => [
    ['Canteen', job.canteen],
    ['Transport', job.transport],
    ['Accommodation', job.accommodation]
  ].filter(([, value]) => lower(value) === 'yes').map(([label]) => label);

  const detailItem = (term, value) => {
    if (!text(value)) return null;
    const wrapper = make('div');
    wrapper.append(make('dt', '', term), make('dd', '', text(value)));
    return wrapper;
  };

  const jobSearchText = (job) => [
    job.requirement_code, job.job_role, job.department, job.job_location,
    job.qualification, job.iti_trade, job.experience_requirement
  ].map(text).join(' ');

  const createCard = (job, options = {}) => {
    const onJobsPage = options.onJobsPage === true;
    const code = text(job.requirement_code);
    const card = make('article', 'public-job-card');
    card.dataset.jobCard = '';
    card.dataset.keyword = jobSearchText(job);
    card.dataset.location = text(job.job_location);
    card.dataset.qualification = [job.qualification, job.iti_trade].map(text).join(' ');
    card.dataset.experience = text(job.experience_requirement);

    const top = make('div', 'public-job-card__top');
    top.append(make('p', 'public-job-code', code), make('span', 'public-job-posted', formatDate(job.published_at, 'Posted ')));
    const title = make('h3', '', text(job.job_role) || 'Workforce Opportunity');
    const department = make('p', 'public-job-department', text(job.department));
    department.hidden = !department.textContent;

    const highlights = make('div', 'public-job-highlights');
    [text(job.job_location), job.open_positions != null ? `${job.open_positions} opening${Number(job.open_positions) === 1 ? '' : 's'}` : '', text(job.experience_requirement)]
      .filter(Boolean).forEach((value) => highlights.append(make('span', '', value)));

    const details = make('dl');
    [
      detailItem('Salary / Wage', formatSalary(job)),
      detailItem('Qualification', job.qualification),
      detailItem('Trade', job.iti_trade),
      detailItem('Shift', job.shift_details)
    ].filter(Boolean).slice(0, 4).forEach((item) => details.append(item));

    const actions = make('div', 'public-job-card__actions');
    const detailLink = make('a', 'public-button public-button--primary', 'View Job');
    detailLink.href = `${onJobsPage ? './' : 'jobs/'}?requirement=${encodeURIComponent(code)}`;
    const interestLink = make('a', 'public-button public-button--secondary', 'Register Interest');
    interestLink.href = `${onJobsPage ? '../' : ''}candidate/register/?requirement=${encodeURIComponent(code)}`;
    actions.append(detailLink, interestLink);
    card.append(top, title, department, highlights, details, actions);
    return card;
  };

  const getConnection = () => {
    const api = window.aadhyantSupabase;
    return api?.isConfigured && api.client ? api : null;
  };

  const fetchPage = async (limit, offset) => {
    const api = getConnection();
    if (!api) throw new Error('Public Jobs is not configured');
    const { data, error } = await api.client.rpc('get_public_job_requirements', { p_limit: limit, p_offset: offset });
    if (error) throw new Error('Public Jobs endpoint unavailable');
    return Array.isArray(data) ? data : [];
  };

  const initializeHomeJobs = async () => {
    const list = document.querySelector('[data-home-jobs-list]');
    if (!list) return;
    const loading = document.querySelector('[data-home-jobs-loading]');
    const empty = document.querySelector('[data-home-jobs-empty]');
    const error = document.querySelector('[data-home-jobs-error]');
    try {
      const jobs = await fetchPage(3, 0);
      jobs.forEach((job) => list.append(createCard(job)));
      if (empty) empty.hidden = jobs.length > 0;
    } catch (_error) {
      if (error) error.hidden = false;
    } finally {
      if (loading) loading.hidden = true;
      list.setAttribute('aria-busy', 'false');
    }
  };

  const initializeJobsPage = async () => {
    const form = document.querySelector('[data-job-filters]');
    const list = document.querySelector('[data-jobs-list]');
    if (!form || !list) return;

    const loading = document.querySelector('[data-jobs-loading]');
    const empty = document.querySelector('[data-jobs-empty]');
    const error = document.querySelector('[data-jobs-error]');
    const count = document.querySelector('[data-jobs-count]');
    const loadMore = document.querySelector('[data-jobs-load-more]');
    const listing = document.querySelector('[data-jobs-view]');
    const detail = document.querySelector('[data-job-detail]');
    const requestedCode = text(new URLSearchParams(window.location.search).get('requirement')).toUpperCase();
    const jobs = [];
    let offset = 0;
    let hasMore = true;

    const showError = () => {
      if (loading) loading.hidden = true;
      if (error) error.hidden = false;
      list.setAttribute('aria-busy', 'false');
      if (loadMore) loadMore.hidden = true;
    };

    const applyFilters = () => {
      const values = Object.fromEntries(new FormData(form));
      let visible = 0;
      list.querySelectorAll('[data-job-card]').forEach((card) => {
        const matches = ['keyword', 'location', 'qualification', 'experience'].every((key) => {
          const query = lower(values[key]);
          return !query || lower(card.dataset[key]).includes(query);
        });
        card.hidden = !matches;
        if (matches) visible += 1;
      });
      if (empty) empty.hidden = jobs.length === 0 ? false : visible > 0;
      if (count) count.textContent = `${visible} ${visible === 1 ? 'opportunity' : 'opportunities'} shown`;
    };

    const renderPage = (records) => {
      records.forEach((job) => {
        const card = createCard(job, { onJobsPage: true });
        card.querySelector('.public-job-card__actions .public-button--primary').addEventListener('click', (event) => {
          event.preventDefault();
          window.history.pushState({}, '', `?requirement=${encodeURIComponent(text(job.requirement_code))}`);
          showDetail(job);
          detail?.scrollIntoView({ block: 'start' });
        });
        list.append(card);
      });
      applyFilters();
    };

    const loadNextPage = async () => {
      if (!hasMore) return [];
      const records = await fetchPage(PAGE_SIZE, offset);
      jobs.push(...records);
      offset += records.length;
      hasMore = records.length === PAGE_SIZE;
      renderPage(records);
      if (loadMore) loadMore.hidden = !hasMore;
      return records;
    };

    const showDetail = (job) => {
      if (!detail || !listing) return;
      const set = (selector, value) => {
        const node = detail.querySelector(selector);
        if (node) node.textContent = text(value);
      };
      set('[data-detail-code]', job.requirement_code);
      set('[data-detail-title]', job.job_role || 'Workforce Opportunity');
      set('[data-detail-department]', job.department);
      set('[data-detail-posted]', formatDate(job.published_at, 'Posted '));
      set('[data-detail-location]', job.job_location);
      set('[data-detail-openings]', job.open_positions != null ? `${job.open_positions} current opening${Number(job.open_positions) === 1 ? '' : 's'}` : '');
      const details = detail.querySelector('[data-detail-list]');
      details.replaceChildren();
      const interview = [formatDate(job.interview_date), text(job.interview_location)].filter(Boolean).join(' · ');
      [
        ['Salary / Wage', formatSalary(job)], ['Qualification', job.qualification], ['Trade / Specialization', job.iti_trade],
        ['Experience', job.experience_requirement], ['Shift', job.shift_details], ['Working Hours', job.working_hours],
        ['Overtime', job.overtime_details], ['Facilities', facilities(job).join(', ')], ['Interview', interview],
        ['Expected Joining', formatDate(job.expected_joining_date)]
      ].map(([term, value]) => detailItem(term, value)).filter(Boolean).forEach((item) => details.append(item));
      const code = encodeURIComponent(text(job.requirement_code));
      detail.querySelector('[data-detail-interest]').href = `../candidate/register/?requirement=${code}`;
      listing.hidden = true;
      detail.hidden = false;
      document.title = `${text(job.job_role) || 'Job Opportunity'} | Aadhyant Jobs`;
    };

    form.addEventListener('submit', (event) => { event.preventDefault(); applyFilters(); });
    form.addEventListener('input', applyFilters);
    form.addEventListener('reset', () => requestAnimationFrame(applyFilters));
    loadMore?.addEventListener('click', async () => {
      loadMore.disabled = true;
      loadMore.textContent = 'Loading…';
      try { await loadNextPage(); } catch (_error) { showError(); }
      loadMore.disabled = false;
      loadMore.textContent = 'Load More Jobs';
    });

    try {
      let records = await loadNextPage();
      if (requestedCode) {
        let match = jobs.find((job) => text(job.requirement_code).toUpperCase() === requestedCode);
        let pages = 1;
        while (!match && hasMore && pages < MAX_DETAIL_PAGES) {
          records = await loadNextPage();
          pages += 1;
          match = records.find((job) => text(job.requirement_code).toUpperCase() === requestedCode);
        }
        if (match) showDetail(match);
        else {
          if (error) {
            error.hidden = false;
            error.querySelector('h3').textContent = 'This opportunity is no longer available.';
            error.querySelector('p').textContent = 'Browse the current public opportunities below or create a Candidate account for future openings.';
          }
        }
      }
      if (loading) loading.hidden = true;
      list.setAttribute('aria-busy', 'false');
      if (!jobs.length && empty) empty.hidden = false;
    } catch (_error) {
      showError();
    }
  };

  window.aadhyantPublicJobs = Object.freeze({ createCard, formatSalary, facilities, jobSearchText });
  const initialize = () => { initializeHomeJobs(); initializeJobsPage(); };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', initialize, { once: true });
  else initialize();
})();
