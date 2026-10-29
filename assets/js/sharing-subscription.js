(() => {
  'use strict';
  const form=document.querySelector('[data-sharing-subscribe]');if(!form)return;
  const filters=document.querySelector('[data-sharing-filters]'),status=document.querySelector('[data-sharing-status]');
  form.elements.scope.addEventListener('change',()=>{filters.hidden=form.elements.scope.value==='all';});
  form.addEventListener('submit',event=>{event.preventDefault();if(!form.reportValidity())return;
    const list=value=>[...new Set(value.split(',').map(v=>v.trim()).filter(Boolean))];
    const scope=form.elements.scope.value,locations=scope==='all'?[]:list(form.elements.locations.value),trades=scope==='all'?[]:list(form.elements.trades.value);
    if(scope==='filtered'&&!locations.length&&!trades.length){status.textContent='Choose a location or trade.';return;}
    if(locations.length>20||trades.length>20||[...locations,...trades].some(v=>v.length>160)){status.textContent='Choose at most 20 names per filter, each under 160 characters.';return;}
    const command='SUBSCRIBE JOB UPDATES '+JSON.stringify({scope,locations,trades});if(command.length>1900){status.textContent='Shorten your selected preferences.';return;}
    location.href='https://wa.me/918128254272?text='+encodeURIComponent(command);
  });
})();
