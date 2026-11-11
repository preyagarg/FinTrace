-- =====================================================================
-- FinTrace — demo data. Run AFTER schema.sql.
-- All demo users log in with password:  password123
--   Admin : rahul@gmail.com
--   Users : priya@gmail.com, arjun@gmail.com, sneha@gmail.com, vikram@gmail.com
-- Dates are relative to today, so the dashboard always looks current.
-- =====================================================================

SET NAMES utf8mb4;
SET SQL_SAFE_UPDATES = 0;   -- MySQL Workbench blocks the balance UPDATE below otherwise
USE fintrace;

SET @pw = 'scrypt:32768:8:1$LBTa1XcMpmr0fHVo$9aef863b7e32fc1d3657f3440ee6fe46430d570bd04bc25401be64beaa173325fffc2db3c559a8369909004ad236c8f5bf54a08c59255fec57ffda0b88b36324';

INSERT INTO Users (full_name, email, password_hash, role) VALUES
('Rahul Sharma', 'rahul@gmail.com', @pw, 'admin'),
('Priya Mehta',  'priya@gmail.com', @pw, 'user'),
('Arjun Singh',  'arjun@gmail.com', @pw, 'user'),
('Sneha Kapoor', 'sneha@gmail.com', @pw, 'user');

-- Vikram has not logged in or transacted for ~45 days → caught by the inactive-user fraud scan
INSERT INTO Users (full_name, email, password_hash, role, last_login, created_at) VALUES
('Vikram Rao', 'vikram@gmail.com', @pw, 'user', NOW() - INTERVAL 45 DAY, NOW() - INTERVAL 90 DAY);

INSERT INTO Categories (category_name, category_type) VALUES
('Salary',        'income'),
('Freelance',     'income'),
('Investment',    'income'),
('Rent',          'expense'),
('Groceries',     'expense'),
('Electricity',   'expense'),
('Dining Out',    'expense'),
('Transport',     'expense'),
('Entertainment', 'expense'),
('Shopping',      'expense'),
('Transfer',      'expense');

-- Opening balances (seeded transactions are added on top below)
INSERT INTO Accounts (user_id, account_name, balance) VALUES
(1, 'Rahul Main Wallet', 100000.00),
(2, 'Priya Savings',      30000.00),
(3, 'Arjun Current',      40000.00),
(4, 'Sneha Salary A/c',    5000.00),
(5, 'Vikram Wallet',       12000.00);

-- Helper: category ids by name
SET @salary = (SELECT category_id FROM Categories WHERE category_name='Salary');
SET @free   = (SELECT category_id FROM Categories WHERE category_name='Freelance');
SET @inv    = (SELECT category_id FROM Categories WHERE category_name='Investment');
SET @rent   = (SELECT category_id FROM Categories WHERE category_name='Rent');
SET @groc   = (SELECT category_id FROM Categories WHERE category_name='Groceries');
SET @elec   = (SELECT category_id FROM Categories WHERE category_name='Electricity');
SET @dine   = (SELECT category_id FROM Categories WHERE category_name='Dining Out');
SET @trans  = (SELECT category_id FROM Categories WHERE category_name='Transport');
SET @ent    = (SELECT category_id FROM Categories WHERE category_name='Entertainment');
SET @shop   = (SELECT category_id FROM Categories WHERE category_name='Shopping');

-- Budgets (set before transactions so budget alerts can fire)
INSERT INTO Budgets (user_id, category_id, monthly_limit) VALUES
(2, @groc, 4000.00),
(2, @dine, 2000.00),
(3, @ent,  3000.00);

-- Transactions over the last ~2 months
INSERT INTO Transactions (account_id, category_id, amount, transaction_type, description, transaction_date) VALUES
-- Rahul (admin)
(1, @salary, 85000.00, 'credit', 'Monthly salary',        DATE_FORMAT(NOW() - INTERVAL 1 MONTH, '%Y-%m-01 10:00:00')),
(1, @rent,   22000.00, 'debit',  'House rent',            DATE_FORMAT(NOW() - INTERVAL 1 MONTH, '%Y-%m-05 11:30:00')),
(1, @groc,    4200.00, 'debit',  'Monthly groceries',     DATE_FORMAT(NOW() - INTERVAL 1 MONTH, '%Y-%m-12 18:15:00')),
(1, @salary, 85000.00, 'credit', 'Monthly salary',        DATE_FORMAT(NOW(), '%Y-%m-01 10:00:00')),
(1, @rent,   22000.00, 'debit',  'House rent',            DATE_FORMAT(NOW(), '%Y-%m-05 11:30:00')),
-- Priya
(2, @salary, 45000.00, 'credit', 'Salary credited',       DATE_FORMAT(NOW() - INTERVAL 1 MONTH, '%Y-%m-01 09:00:00')),
(2, @rent,   15000.00, 'debit',  'Rent payment',          DATE_FORMAT(NOW() - INTERVAL 1 MONTH, '%Y-%m-03 12:00:00')),
(2, @elec,    1200.00, 'debit',  'Electricity bill',      DATE_FORMAT(NOW() - INTERVAL 1 MONTH, '%Y-%m-15 16:40:00')),
(2, @salary, 45000.00, 'credit', 'Salary credited',       DATE_FORMAT(NOW(), '%Y-%m-01 09:00:00')),
(2, @groc,    2500.00, 'debit',  'Big Basket order',      DATE_FORMAT(NOW(), '%Y-%m-02 19:20:00')),
(2, @groc,    1800.00, 'debit',  'Vegetables and fruits', DATE_FORMAT(NOW(), '%Y-%m-03 08:45:00')),
(2, @dine,     900.00, 'debit',  'Dinner with friends',   DATE_FORMAT(NOW(), '%Y-%m-04 21:10:00')),
-- Arjun (includes a high-value + a midnight transaction → flagged + fraud flag)
(3, @free,   20000.00, 'credit', 'Freelance project',     DATE_FORMAT(NOW() - INTERVAL 1 MONTH, '%Y-%m-08 14:00:00')),
(3, @rent,   12000.00, 'debit',  'Rent paid',             DATE_FORMAT(NOW() - INTERVAL 1 MONTH, '%Y-%m-05 10:00:00')),
(3, @inv,    65000.00, 'credit', 'Mutual fund redemption',DATE_FORMAT(NOW(), '%Y-%m-02 02:17:00')),
(3, @shop,   55000.00, 'debit',  'Laptop purchase',       DATE_FORMAT(NOW(), '%Y-%m-03 15:30:00')),
(3, @ent,     1500.00, 'debit',  'Movie tickets',         DATE_FORMAT(NOW(), '%Y-%m-04 20:00:00')),
-- Sneha (spends down close to the low-balance line)
(4, @salary, 28000.00, 'credit', 'Salary credited',       DATE_FORMAT(NOW(), '%Y-%m-01 09:30:00')),
(4, @rent,   18000.00, 'debit',  'Rent payment',          DATE_FORMAT(NOW(), '%Y-%m-02 10:00:00')),
(4, @shop,   10500.00, 'debit',  'Festival shopping',     DATE_FORMAT(NOW(), '%Y-%m-03 17:00:00')),
(4, @trans,   3800.00, 'debit',  'Cab and metro',         DATE_FORMAT(NOW(), '%Y-%m-04 09:00:00')),
-- Vikram (last activity ~50 days ago)
(5, @salary, 30000.00, 'credit', 'Salary credited',       NOW() - INTERVAL 52 DAY),
(5, @rent,   14000.00, 'debit',  'Rent payment',          NOW() - INTERVAL 50 DAY);

-- Apply the seeded transactions to balances (opening + credits − debits).
-- This UPDATE fires trg_low_balance_warning for Sneha (₹700 left).
UPDATE Accounts a
JOIN (
    SELECT account_id,
           SUM(IF(transaction_type = 'credit', amount, -amount)) AS net
    FROM Transactions GROUP BY account_id
) t ON t.account_id = a.account_id
SET a.balance = a.balance + t.net;

-- One completed transfer (goes through the real ACID procedure)
CALL TransferFunds(1, 2, 5000.00, 'Shared trip expenses');

-- Run the inactive-user fraud scan once now (the daily event repeats it)
CALL DetectInactiveUsers();

-- A pending account-deletion request for the admin to review
INSERT INTO Delete_Requests (user_id, reason) VALUES
(4, 'Moving to a different bank');

SELECT u.full_name, u.email, u.role, a.account_name, a.balance
FROM Users u JOIN Accounts a ON a.user_id = u.user_id ORDER BY u.user_id;
