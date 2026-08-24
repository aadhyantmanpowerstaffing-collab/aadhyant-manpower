(() => {
  'use strict';

  const initialize = () => {
    if (!document.querySelector('link[rel~="icon"]')) {
      const icon = document.createElement('link');
      icon.rel = 'icon';
      icon.href = '/assets/favicon.svg';
      icon.type = 'image/svg+xml';
      document.head.append(icon);
    }
    const menuButton = document.querySelector('[data-public-menu-button]');
    const navigation = document.querySelector('[data-public-navigation]');
    const footer = document.querySelector('.public-footer');
    if (footer && !footer.querySelector('.public-footer__lead')) {
      footer.innerHTML = '<div class="container public-footer__lead"><div><p class="eyebrow">Aadhyant Manpower &amp; Staffing</p><h2>Workforce coordination with a clear path forward.</h2></div><a class="public-button public-button--light" href="/contact/">Contact Aadhyant</a></div><div class="container public-footer-grid"><div class="footer-brand"><a class="brand brand-light" href="/"><span class="brand-mark" aria-hidden="true">A</span><span class="brand-copy"><strong>AADHYANT</strong><small>MANPOWER &amp; STAFFING</small></span></a><p>Industrial manpower, recruitment support and staffing coordination.</p><p class="public-footer-identity">GSTIN 24ACNFA4445J1Z9<br>Kadi, Mahesana, Gujarat 384440</p><p class="public-footer-contact"><a href="tel:+919586785800">+91 95867 85800</a><a href="mailto:aadhyantmanpowerstaffing@gmail.com">Email Aadhyant</a></p></div><div class="footer-column"><h2>Candidates / Jobs</h2><a href="/jobs/">Browse Jobs</a><a href="/candidate/">Candidate Options</a><a href="/candidate/register/">Register Interest</a><a href="/candidate/portal/login.html">Candidate Portal</a></div><div class="footer-column"><h2>Employers</h2><a href="/hire-manpower/">Staffing Solutions</a><a href="/hire-manpower/requirement/">Submit Requirement</a><a href="/company/login.html">Employer Portal</a><a href="/services/">Services</a></div><div class="footer-column"><h2>Contractors</h2><a href="/staffing-partner/">Join the Network</a><a href="/contractor/register.html">Partner Registration</a><a href="/contractor/login.html">Contractor Portal</a><a href="/contractor/vacancies.html">Submit Vacancy</a></div><div class="footer-column public-footer-meta"><div><h2>Aadhyant</h2><a href="/about/">About</a><a href="/industries/">Industries</a><a href="/contact/">Contact</a></div><div><h2>Legal</h2><nav class="public-legal-links" aria-label="Legal"><a href="/privacy/">Privacy Policy</a><a href="/terms/">Terms of Use</a><a href="/data-deletion/">Data Deletion</a></nav></div></div></div><div class="container footer-bottom"><p>© 2026 Aadhyant Manpower &amp; Staffing.</p></div>';
    }
    const footerBottom = document.querySelector('.public-footer .footer-bottom');

    if (navigation && ![...navigation.querySelectorAll(':scope > a')].some((link) => link.textContent.trim() === 'For Employers')) {
      const currentPath = window.location.pathname;
      const links = [
        ['Jobs', '/jobs/'], ['For Employers', '/hire-manpower/'], ['For Contractors', '/staffing-partner/'],
        ['About', '/about/'], ['Contact', '/contact/']
      ];
      navigation.replaceChildren();
      links.forEach(([label, href]) => {
        const link = document.createElement('a');
        link.href = href;
        link.textContent = label;
        if (currentPath === href || (href !== '/' && currentPath.startsWith(href))) link.setAttribute('aria-current', 'page');
        navigation.append(link);
      });
      const portal = document.createElement('div');
      portal.className = 'public-portal';
      portal.dataset.publicPortal = '';
      portal.innerHTML = '<button class="public-portal__trigger" type="button" aria-expanded="false" aria-controls="portal-login-menu" data-public-portal-button>Portal Login <span aria-hidden="true">⌄</span></button><div class="public-portal__menu" id="portal-login-menu" data-public-portal-menu><p>Choose your workspace</p><a href="/candidate/portal/login.html"><strong>Candidate Portal</strong><span>Profile, jobs and applications</span></a><a href="/company/login.html"><strong>Employer Portal</strong><span>Requirements and hiring progress</span></a><a href="/contractor/login.html"><strong>Contractor Portal</strong><span>Vacancies and assignments</span></a></div>';
      navigation.append(portal);
    }

    const portalButton = document.querySelector('[data-public-portal-button]');
    const portalMenu = document.querySelector('[data-public-portal-menu]');

    if (portalMenu && !portalMenu.querySelector('a[href*="candidate/portal/login"]')) {
      const candidateLink = document.createElement('a');
      candidateLink.href = '/candidate/portal/login.html';
      const title = document.createElement('strong');
      title.textContent = 'Candidate Portal';
      const description = document.createElement('span');
      description.textContent = 'Profile, jobs and applications';
      candidateLink.append(title, description);
      portalMenu.prepend(candidateLink);
    }

    if (footerBottom && footer && !footer.querySelector('.public-legal-links')) {
      const legalNavigation = document.createElement('nav');
      legalNavigation.className = 'public-legal-links';
      legalNavigation.setAttribute('aria-label', 'Legal');
      const links = [['Privacy Policy', '/privacy/'], ['Terms of Use', '/terms/'], ['Data Deletion', '/data-deletion/']];
      links.forEach(([label, href]) => {
        const link = document.createElement('a');
        link.href = href;
        link.textContent = label;
        legalNavigation.append(link);
      });
      footerBottom.querySelector('p:last-child')?.before(legalNavigation);
    }

    if (!menuButton || !navigation) return;

    const setPortal = (open) => {
      if (!portalButton || !portalMenu) return;
      portalButton.setAttribute('aria-expanded', String(open));
      portalMenu.classList.toggle('is-open', open);
    };

    const setNavigation = (open, restoreFocus = false) => {
      menuButton.setAttribute('aria-expanded', String(open));
      navigation.classList.toggle('is-open', open);
      document.body.classList.toggle('menu-open', open);
      if (!open) setPortal(false);
      if (restoreFocus) menuButton.focus();
    };

    menuButton.addEventListener('click', () => setNavigation(menuButton.getAttribute('aria-expanded') !== 'true'));
    portalButton?.addEventListener('click', () => setPortal(portalButton.getAttribute('aria-expanded') !== 'true'));

    navigation.addEventListener('click', (event) => {
      if (event.target.closest('a')) setNavigation(false);
    });

    document.addEventListener('click', (event) => {
      if (portalMenu?.classList.contains('is-open') && !event.target.closest('[data-public-portal]')) setPortal(false);
    });

    document.addEventListener('keydown', (event) => {
      if (event.key !== 'Escape') return;
      if (portalMenu?.classList.contains('is-open')) {
        setPortal(false);
        portalButton?.focus();
      } else if (navigation.classList.contains('is-open')) {
        setNavigation(false, true);
      }
    });

    window.addEventListener('resize', () => {
      if (window.innerWidth > 1080) setNavigation(false);
    });
  };

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', initialize, { once: true });
  else initialize();
})();
