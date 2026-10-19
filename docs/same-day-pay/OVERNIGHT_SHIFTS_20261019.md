# Overnight Same-Day Pay shifts — 19 October 2026

Prepared, not deployed. User requires urgent 4/8/custom shifts crossing midnight, with payment immediately on completion. Example:19 October20:00 →20 October04:00 →20 October04:00 payment. Interface stays English.

## Behavior

When end time is earlier than start, the end/payment date is next calendar day. Equal start/end is invalid, durations remain at most16 hours, start must still be in the future in India time. Generated end_date/payment_date retain existing time-only API fields, preventing users from forging inconsistent dates. Existing day-shift dates and agreed payment times are preserved. New/resubmitted shifts require payment_time=end_time.

The posting form computes4/8-hour end time modulo midnight and displays readonly end/payment dates. Custom shifts infer next-day end with the same limit. Public cards and application payment warnings show actual end/payment dates. Candidate/public supervisor privacy and owner/admin access remain unchanged; cache versions advance together.

Overlap checks now compare complete start/end datetimes across dates; attendance/completion gate uses actual end date. The replaced work-status function also maps audit source to the existing canonical vocabulary, correcting the discovered `same_day_pay` audit-source constraint failure. Owner/candidate permissions and transitions are retained.

## Alerts

The existing approved Hindi v1 static heading promises same-evening payment and cannot truthfully represent next-morning completion. Overnight shifts therefore use the already approved English v4 with dated finish/payment and Same-Day Pay label; daytime shifts retain Hindi v1. No Meta template is silently edited or approval fabricated. A neutral Hindi replacement would require a separate template submission/review. Automatic publication trigger, outbox, consent/STOP/location/capacity and duplicate guards stay intact. No historical publication replay is introduced; changed fingerprints pause old frozen messages.

## Validation / release

Isolated actual SQL tests cover4/8/custom, midnight and year boundary, company/contractor routes, duration/payment rejection, private contacts, day Hindi/night English selection, cross-date overlaps, completion timing and production audit source vocabulary. UI function execution verifies dates/end/payment, custom mode and clearing. Focused4/4 and full regression618/618 pass; production artifact build, syntax and diff checks pass. No production mutation or message send occurred.

After approval: compare live function baselines/constraints, apply migration, publish reviewed HTML/JS through existing Pages process, verify generated columns and authorized public/form behavior without creating a fake vacancy or sending tests. Preserve currently published customer data.
