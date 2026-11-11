# Phase 1 CONTEXT: Frontend Boilerplate (Jinja2 + Bootstrap 5.3)

**Phase:** 1 - Frontend Boilerplate Setup
**Created:** 2026-05-02
**Status:** Implementation decisions captured

---

## <domain>

**Phase Goal:** Set up Jinja2 templates with Bootstrap 5.3 for FinTrace frontend

**What This Delivers:**
- 6 HTML pages (Dashboard, Transactions, Accounts, Categories, Audit, Users)
- Sidebar navigation across all pages
- Vanilla JavaScript for API calls
- Read-only Users page

---

## <codebase_context>

**Existing Flask Backend:**
- Route `/` → `index.html`
- Route `/transactions-page` → `transactions.html`
- Route `/audit-page` → `audit.html`
- 9 API endpoints ready (no additions needed)

**Template Directory:** `fintrace/templates/`
**Static Location:** Currently none (use CDN for Bootstrap 5.3)

---

## <decisions>

### Pages (6 total)
- Dashboard (`index.html`) — Account balances, summary stats
- Transactions (`transactions.html`) — List + CRUD forms
- Accounts (`accounts.html`) — View accounts with balances
- Categories (`categories.html`) — View income/expense categories
- Audit (`audit.html`) — Audit log view
- Users (`users.html`) — Read-only user list

### Navigation
- **Sidebar layout** with 6 menu items
- Each page renders via Flask `render_template()`

### JavaScript
- **Vanilla JS** — `fetch()` calls to existing Flask APIs
- Form handling via vanilla JS event listeners

### Users Page
- **Read-only** — No POST/PUT endpoints needed
- Reads from existing `/api/users`

### Theme
- **Bootstrap 5.3 default** (blue, no customization)
- CDN: `https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css`

---

## <canonical_refs>

- `fintrace/app.py` — Flask backend routes and API endpoints
- `fintrace/database.py` — MySQL connection config
- `fintrace/templates/*.html` — Existing (empty) templates to replace

---

## <deferred>

- User creation/editing — Deferred to future phase (requires `/api/users` POST endpoint)
- Dark sidebar theme — Deferred (use default Bootstrap)

---

## Implementation Notes

**Flask Changes:** None required
**New Files:**
- `fintrace/templates/layout.html` — Base template with sidebar
- `fintrace/templates/dashboard.html`
- `fintrace/templates/transactions.html`
- `fintrace/templates/accounts.html`
- `fintrace/templates/categories.html`
- `fintrace/templates/audit.html`
- `fintrace/templates/users.html`
- `fintrace/static/js/main.js` — Vanilla JS for API calls

**Routes to Add in Flask:**
1. `/accounts-page` → render `accounts.html`
2. `/categories-page` → render `categories.html`
3. `/users-page` → render `users.html`

**API Endpoints to Add:**
1. None — Read-only Users page reuses existing `/api/users`

---
*This CONTEXT.md guides planning for Phase 1 implementation*