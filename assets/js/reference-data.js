/**
 * Reference-data loader foundation for future structured public forms.
 * No datasets are shipped or loaded in R2.
 *
 * Planned datasets: India states, India districts, education, ITI trades,
 * industries, job roles, experience levels, employment types, shift types,
 * and availability options.
 */
const cache = new Map();

export async function loadReferenceData(dataset, options = {}) {
  if (!/^[a-z0-9-]+$/.test(dataset)) throw new TypeError('Invalid reference dataset name.');
  if (cache.has(dataset)) return cache.get(dataset);
  const basePath = options.basePath || '/assets/data';
  const response = await fetch(`${basePath}/${dataset}.json`, { credentials: 'same-origin' });
  if (!response.ok) throw new Error(`Reference data could not be loaded: ${dataset}`);
  const payload = await response.json();
  if (!Array.isArray(payload)) throw new TypeError(`Reference dataset must be an array: ${dataset}`);
  cache.set(dataset, payload);
  return payload;
}

export function clearReferenceDataCache() {
  cache.clear();
}
