# Excel report exports

Adds real .xlsx downloads to existing Admin reporting tables and Company/Contractor requirement/vacancy, assignment, application, interview and joining lists. Same-Day Pay exports current jobs, shift attendance/payment records and the dated available-workers page. Labels explicitly say current page only; filtering and pagination remain the portal's existing behavior. No full-database export is claimed.

Shared browser-only writer packages standard uncompressed ZIP/OpenXML without a new dependency, external CDN, API, database access or permission change. It reads only the current rendered authorized projection, skips dialog tables, action columns, controls, hidden content and loading placeholders. All cells are inline strings, preserving Gujarati, leading zeroes and making user-entered spreadsheet formula text inert. Filenames contain report name and date. First row is frozen.

The exporter does not fetch subsequent pages or expose private identifiers from backing records. Company and Contractor receive only their existing role-authorized displayed columns. No database migration or WhatsApp/email send is needed.

Validation: focused archive/Unicode/formula and rendered-row filtering tests pass 5/5. Independent Python openpyxl reader and ZIP CRC check pass for generated workbook. Production packaging includes the shared asset. Full regression passes 604/604; final focused export tests pass 5/5 and artifact tests pass 6/6. Bold headings, fitted column widths and frozen first row verified with openpyxl. Browser interaction QA has not been claimed. Not deployed; production approval remains required by AGENTS.md.
