(() => {
  'use strict';

  const initialize = () => {
    const menuButton = document.querySelector('[data-public-menu-button]');
    const navigation = document.querySelector('[data-public-navigation]');
    const portalButton = document.querySelector('[data-public-portal-button]');
    const portalMenu = document.querySelector('[data-public-portal-menu]');
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
