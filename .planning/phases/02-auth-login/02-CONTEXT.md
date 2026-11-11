# Phase 2 CONTEXT: Authentication (Login System)

**Phase:** 2 - Authentication Login System
**Created:** 2026-05-02
**Status:** Implementation decisions captured

---

## <domain>

**Phase Goal:** Add login/logout system with session-based authentication

**What This Delivers:**
- Password column in Users table
- 3 authentication API endpoints
- Simple session management
- Protected routes based on role

---

## <codebase_context>

**Existing Database:**
- `fintrace` database
- `Users` table: user_id, full_name, email, role, created_at
- **No password column** — needs to be added

**Existing Flask:**
- `app.py` with 9 API endpoints
- No authentication on any route

**Existing Frontend:**
- 6 Jinja2 templates with sidebar
- Vanilla JS in `main.js`

---

## <decisions>

### Implementation
- **Method:** Simple session-based auth (Flask sessions)
- **Password storage:** bcrypt hash via werkzeug
- **Session storage:** Server-side (Flask signed cookies)

### Routes Added
- `POST /api/login` — Authenticate
- `POST /api/logout` — Clear session
- `GET /api/session` — Check current user

### Role-Based Access
- **Admin can:** View all data, delete transactions, view audit logs
- **Users can:** View data, add transactions

### Protected Routes
| Endpoint | Auth Required | Role |
|----------|--------------|------|
| `/api/transactions` | Yes | any |
| `/api/add-transaction` | Yes | any |
| `/api/delete-transaction` | Yes | admin |
| `/api/users` | Yes | any |
| `/api/accounts` | Yes | any |
| `/api/categories` | Yes | any |
| `/api/account-summary` | Yes | any |
| `/api/total` | Yes | any |
| `/api/audit-logs` | Yes | admin |

### Frontend
- Add login.html page
- Update layout.html with logout + user display
- Update main.js with auth functions

---

## <canonical_refs>

- `fintrace/app.py` — Flask backend (add routes here)
- `fintrace/database.py` — MySQL connection
- `fintrace/templates/layout.html` — Base template (update)
- `fintrace/static/js/main.js` — JavaScript (add functions)
- `.planning/REQUIREMENTS.md` — Project requirements

---

## <deferred>

- JWT tokens — More complex, skip for presentation
- Password reset — Not needed for demo
- User registration — Not needed for demo (admin creates users in MySQL)

---

## Implementation Notes

**Database Change (run in MySQL Workbench):**
```sql
ALTER TABLE Users ADD COLUMN password_hash VARCHAR(255);
```

**Python Dependencies:**
- `werkzeug` — Already included with Flask

**New Files:**
- `fintrace/templates/login.html` — Login form page

**Files to Modify:**
- `fintrace/app.py` — Add 3 auth routes + helpers
- `fintrace/templates/layout.html` — Logout button + user info
- `fintrace/static/js/main.js` — login/logout/checkSession

---*This CONTEXT.md guides planning for Phase 2 implementation*