// main.js - Shared helper functions for FinTrace

// Get current user from localStorage
function getUser() {
    const userId = localStorage.getItem('user_id');
    const role = localStorage.getItem('role');
    const fullName = localStorage.getItem('full_name');
    const accountId = localStorage.getItem('account_id');
    const email = localStorage.getItem('email');
    const accountName = localStorage.getItem('account_name');
    
    if (!userId) return null;
    return {
        id: userId,
        role: role,
        name: fullName,
        account_id: accountId ? parseInt(accountId) : null,
        email: email,
        account_name: accountName
    };
}

// Fetch API helper with error handling
async function fetchAPI(url, options = {}) {
    try {
        const response = await fetch(url, {
            ...options,
            headers: {
                'Content-Type': 'application/json',
                ...options.headers
            }
        });
        return await response.json();
    } catch (error) {
        console.error('API Error:', error);
        return { success: false, error: 'Connection error. Please try again.' };
    }
}

// Fetch accounts (cached, returns user's accounts or all for admin)
async function fetchAccounts() {
    return await fetchAPI('/api/accounts');
}

// Fetch all accounts in system (for transfer destination selection)
async function fetchAllAccounts() {
    return await fetchAPI('/api/accounts/all');
}

// Fetch categories
async function fetchCategories() {
    return await fetchAPI('/api/categories');
}

// Fetch audit logs
async function fetchAuditLogs() {
    return await fetchAPI('/api/audit-logs');
}

// Fetch monthly reports
async function fetchMonthlyReports() {
    return await fetchAPI('/api/monthly-reports');
}

// Add transaction
async function addTransaction(data) {
    return await fetchAPI('/api/add-transaction', {
        method: 'POST',
        body: JSON.stringify(data)
    });
}

// Delete transaction
async function deleteTransaction(transactionId) {
    return await fetchAPI(`/api/delete-transaction/${transactionId}`, {
        method: 'DELETE'
    });
}

// Handle logout
async function handleLogout() {
    if (!confirm('Are you sure you want to logout?')) return;
    
    const result = await fetchAPI('/api/logout', { method: 'POST' });
    if (result.success) {
        // Clear all localStorage
        localStorage.removeItem('user_id');
        localStorage.removeItem('role');
        localStorage.removeItem('full_name');
        localStorage.removeItem('account_id');
        localStorage.removeItem('email');
        localStorage.removeItem('account_name');
        window.location.href = '/login-page';
    }
}

// Format currency in ₹ with en-IN locale
function formatCurrency(amount) {
    return '₹' + parseFloat(amount).toLocaleString('en-IN', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
    });
}

// Show toast notification
function showToast(message, type = 'success') {
    const toast = document.createElement('div');
    toast.className = `alert alert-${type} alert-dismissible fade show position-fixed bottom-0 end-0 m-3`;
    toast.style.zIndex = 9999;
    toast.innerHTML = `
        ${message}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    `;
    document.body.appendChild(toast);
    setTimeout(() => toast.remove(), 3000);
}

// Check auth and redirect if not logged in
function requireAuth() {
    const user = getUser();
    if (!user) {
        window.location.href = '/login-page';
        return false;
    }
    return user;
}

// Update sidebar user info on all pages
document.addEventListener('DOMContentLoaded', function() {
    const user = getUser();
    if (!user) return;
    
    // Update sidebar user name and role
    const userNameEl = document.getElementById('user-name');
    const userRoleEl = document.getElementById('user-role');
    const userAccountNameEl = document.getElementById('user-account-name');
    
    if (userNameEl) userNameEl.textContent = user.name || 'User';
    if (userRoleEl) userRoleEl.textContent = user.role === 'admin' ? 'Administrator' : 'User';
    if (userAccountNameEl && user.account_name) userAccountNameEl.textContent = user.account_name;
});
