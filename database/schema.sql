-- =====================================================================
-- FinTrace — complete database schema (MySQL 8.0+)
-- Builds everything from scratch in one run:
--   12 tables · 3 views · 6 triggers · 6 procedures · 3 functions · 1 event
--
-- Run:   mysql -u root -p < schema.sql
--        (or File > Open SQL Script > Execute in MySQL Workbench)
-- Then:  mysql -u root -p < seed.sql
--
-- WARNING: drops and recreates the `fintrace` database.
-- =====================================================================

SET NAMES utf8mb4;

DROP DATABASE IF EXISTS fintrace;
CREATE DATABASE fintrace CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE fintrace;

-- =====================================================================
-- PART 1: TABLES
-- =====================================================================

CREATE TABLE Users (
    user_id        INT AUTO_INCREMENT PRIMARY KEY,
    full_name      VARCHAR(100) NOT NULL,
    email          VARCHAR(150) NOT NULL UNIQUE,
    password_hash  VARCHAR(255) NOT NULL,
    role           ENUM('admin','user') NOT NULL DEFAULT 'user',
    last_login     DATETIME NULL,
    created_at     DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Categories (
    category_id    INT AUTO_INCREMENT PRIMARY KEY,
    category_name  VARCHAR(50) NOT NULL UNIQUE,
    category_type  ENUM('income','expense') NOT NULL
);

CREATE TABLE Accounts (
    account_id     INT AUTO_INCREMENT PRIMARY KEY,
    user_id        INT NOT NULL,
    account_name   VARCHAR(100) NOT NULL,
    balance        DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    created_at     DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_account_user FOREIGN KEY (user_id)
        REFERENCES Users(user_id) ON DELETE CASCADE,
    CONSTRAINT chk_balance_non_negative CHECK (balance >= 0)
);

CREATE TABLE Transactions (
    transaction_id    INT AUTO_INCREMENT PRIMARY KEY,
    account_id        INT NOT NULL,
    category_id       INT NOT NULL,
    amount            DECIMAL(12,2) NOT NULL,
    transaction_type  ENUM('credit','debit') NOT NULL,
    description       VARCHAR(255),
    transaction_date  DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_trans_account FOREIGN KEY (account_id)
        REFERENCES Accounts(account_id) ON DELETE CASCADE,
    CONSTRAINT fk_trans_category FOREIGN KEY (category_id)
        REFERENCES Categories(category_id) ON DELETE RESTRICT,
    CONSTRAINT chk_amount_positive CHECK (amount > 0),
    INDEX idx_trans_account_date (account_id, transaction_date)
);

CREATE TABLE Transfers (
    transfer_id      INT AUTO_INCREMENT PRIMARY KEY,
    from_account_id  INT NOT NULL,
    to_account_id    INT NOT NULL,
    amount           DECIMAL(12,2) NOT NULL,
    description      VARCHAR(255),
    status           ENUM('success','failed') NOT NULL DEFAULT 'success',
    transfer_date    DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_transfer_from FOREIGN KEY (from_account_id)
        REFERENCES Accounts(account_id) ON DELETE CASCADE,
    CONSTRAINT fk_transfer_to FOREIGN KEY (to_account_id)
        REFERENCES Accounts(account_id) ON DELETE CASCADE,
    CONSTRAINT chk_transfer_amount CHECK (amount > 0)
);

CREATE TABLE Audit_Log (
    log_id       INT AUTO_INCREMENT PRIMARY KEY,
    table_name   VARCHAR(50) NOT NULL,
    action_type  ENUM('INSERT','UPDATE','DELETE') NOT NULL,
    record_id    INT,
    changed_by   VARCHAR(100),
    old_value    TEXT,
    new_value    TEXT,
    action_time  DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Notifications (
    notification_id  INT AUTO_INCREMENT PRIMARY KEY,
    user_id          INT NOT NULL,
    message          TEXT NOT NULL,
    type             ENUM('low_balance','high_value','budget_exceeded','transfer','system') NOT NULL,
    is_read          BOOLEAN DEFAULT FALSE,
    created_at       DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_notif_user FOREIGN KEY (user_id)
        REFERENCES Users(user_id) ON DELETE CASCADE
);

CREATE TABLE Budgets (
    budget_id      INT AUTO_INCREMENT PRIMARY KEY,
    user_id        INT NOT NULL,
    category_id    INT NOT NULL,
    monthly_limit  DECIMAL(12,2) NOT NULL,
    created_at     DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_budget_user FOREIGN KEY (user_id)
        REFERENCES Users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_budget_category FOREIGN KEY (category_id)
        REFERENCES Categories(category_id) ON DELETE CASCADE,
    CONSTRAINT chk_budget_positive CHECK (monthly_limit > 0),
    UNIQUE KEY uq_user_category (user_id, category_id)
);

CREATE TABLE Monthly_Reports (
    report_id      INT AUTO_INCREMENT PRIMARY KEY,
    account_id     INT NOT NULL,
    report_month   INT NOT NULL,
    report_year    INT NOT NULL,
    total_income   DECIMAL(12,2) DEFAULT 0.00,
    total_expense  DECIMAL(12,2) DEFAULT 0.00,
    net_savings    DECIMAL(12,2) DEFAULT 0.00,
    generated_at   DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_report_account FOREIGN KEY (account_id)
        REFERENCES Accounts(account_id) ON DELETE CASCADE,
    CONSTRAINT chk_report_month CHECK (report_month BETWEEN 1 AND 12),
    UNIQUE KEY uq_report_period (account_id, report_month, report_year)
);

CREATE TABLE Flagged_Transactions (
    flag_id         INT AUTO_INCREMENT PRIMARY KEY,
    transaction_id  INT NOT NULL,
    reason          VARCHAR(255),
    flagged_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    reviewed        BOOLEAN DEFAULT FALSE,
    CONSTRAINT fk_flag_transaction FOREIGN KEY (transaction_id)
        REFERENCES Transactions(transaction_id) ON DELETE CASCADE
);

CREATE TABLE Fraud_Flags (
    fraud_id        INT AUTO_INCREMENT PRIMARY KEY,
    user_id         INT NOT NULL,
    transaction_id  INT NULL,
    reason          VARCHAR(255) NOT NULL,
    severity        ENUM('low','medium','high') NOT NULL DEFAULT 'medium',
    reviewed        BOOLEAN DEFAULT FALSE,
    flagged_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_fraud_user FOREIGN KEY (user_id)
        REFERENCES Users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_fraud_transaction FOREIGN KEY (transaction_id)
        REFERENCES Transactions(transaction_id) ON DELETE CASCADE
);

CREATE TABLE Delete_Requests (
    request_id    INT AUTO_INCREMENT PRIMARY KEY,
    user_id       INT NOT NULL,
    reason        TEXT,
    status        ENUM('pending','approved','rejected') DEFAULT 'pending',
    requested_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_delreq_user FOREIGN KEY (user_id)
        REFERENCES Users(user_id) ON DELETE CASCADE
);

-- =====================================================================
-- PART 2: VIEWS
-- =====================================================================

CREATE VIEW vw_transaction_report AS
SELECT t.transaction_id,
       u.full_name     AS user_name,
       u.role          AS user_role,
       a.account_name,
       a.balance       AS current_balance,
       c.category_name,
       c.category_type,
       t.amount,
       t.transaction_type,
       t.description,
       t.transaction_date
FROM Transactions t
JOIN Accounts   a ON t.account_id  = a.account_id
JOIN Users      u ON a.user_id     = u.user_id
JOIN Categories c ON t.category_id = c.category_id;

CREATE VIEW vw_audit_report AS
SELECT log_id, action_time, table_name, action_type,
       record_id, old_value, new_value, changed_by
FROM Audit_Log
ORDER BY action_time DESC, log_id DESC;

CREATE VIEW vw_account_summary AS
SELECT u.user_id, u.full_name, u.role,
       a.account_id, a.account_name, a.balance,
       COUNT(t.transaction_id) AS total_transactions
FROM Users u
JOIN Accounts a          ON u.user_id    = a.user_id
LEFT JOIN Transactions t ON a.account_id = t.account_id
GROUP BY u.user_id, u.full_name, u.role, a.account_id, a.account_name, a.balance;

-- =====================================================================
-- PART 3: FUNCTIONS
-- =====================================================================

DELIMITER //

-- Total credit or debit amount for one account (all time)
CREATE FUNCTION CalculateTotalByType(p_account_id INT, p_type VARCHAR(10))
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(12,2) DEFAULT 0;
    SELECT COALESCE(SUM(amount), 0) INTO v_total
    FROM Transactions
    WHERE account_id = p_account_id AND transaction_type = p_type;
    RETURN v_total;
END //

-- A user's spending in one category during the current month
CREATE FUNCTION GetMonthlySpending(p_user_id INT, p_category_id INT)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(12,2) DEFAULT 0;
    SELECT COALESCE(SUM(t.amount), 0) INTO v_total
    FROM Transactions t
    JOIN Accounts a ON t.account_id = a.account_id
    WHERE a.user_id = p_user_id
      AND t.category_id = p_category_id
      AND t.transaction_type = 'debit'
      AND t.transaction_date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
      AND t.transaction_date <  DATE_FORMAT(CURDATE(), '%Y-%m-01') + INTERVAL 1 MONTH;
    RETURN v_total;
END //

-- Simulated credit score on a 300–900 scale (Indian CIBIL-style range)
--   Start 650
--   + up to 100  savings ratio (income vs expense, last 90 days)
--   + up to 100  current balance tier
--   + up to  50  account activity (transactions, last 90 days)
--   −  40 each   unreviewed fraud flag
--   −  15 each   low-balance warning (last 90 days)
CREATE FUNCTION CalculateCreditScore(p_user_id INT)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_score    INT DEFAULT 650;
    DECLARE v_income   DECIMAL(14,2) DEFAULT 0;
    DECLARE v_expense  DECIMAL(14,2) DEFAULT 0;
    DECLARE v_balance  DECIMAL(14,2) DEFAULT 0;
    DECLARE v_tx_count INT DEFAULT 0;
    DECLARE v_fraud    INT DEFAULT 0;
    DECLARE v_lowbal   INT DEFAULT 0;

    SELECT COALESCE(SUM(CASE WHEN t.transaction_type='credit' THEN t.amount END), 0),
           COALESCE(SUM(CASE WHEN t.transaction_type='debit'  THEN t.amount END), 0),
           COUNT(t.transaction_id)
      INTO v_income, v_expense, v_tx_count
    FROM Transactions t
    JOIN Accounts a ON t.account_id = a.account_id
    WHERE a.user_id = p_user_id
      AND t.transaction_date >= NOW() - INTERVAL 90 DAY;

    SELECT COALESCE(SUM(balance), 0) INTO v_balance
    FROM Accounts WHERE user_id = p_user_id;

    SELECT COUNT(*) INTO v_fraud
    FROM Fraud_Flags WHERE user_id = p_user_id AND reviewed = FALSE;

    SELECT COUNT(*) INTO v_lowbal
    FROM Notifications
    WHERE user_id = p_user_id AND type = 'low_balance'
      AND created_at >= NOW() - INTERVAL 90 DAY;

    -- Savings ratio
    IF v_income > 0 THEN
        SET v_score = v_score + LEAST(100, GREATEST(-100,
                      ROUND(((v_income - v_expense) / v_income) * 100)));
    END IF;

    -- Balance tier
    SET v_score = v_score + CASE
        WHEN v_balance >= 100000 THEN 100
        WHEN v_balance >=  50000 THEN 70
        WHEN v_balance >=  10000 THEN 40
        WHEN v_balance >=   1000 THEN 10
        ELSE -50 END;

    -- Activity
    SET v_score = v_score + LEAST(50, v_tx_count * 5);

    -- Penalties
    SET v_score = v_score - (v_fraud * 40) - (v_lowbal * 15);

    RETURN LEAST(900, GREATEST(300, v_score));
END //

-- =====================================================================
-- PART 4: TRIGGERS
-- Balances are changed ONLY by the procedures (AddTransaction,
-- TransferFunds), never by a trigger — so money is never counted twice.
-- =====================================================================

-- Audit: every INSERT / UPDATE / DELETE on Transactions
CREATE TRIGGER trg_audit_transaction_insert
AFTER INSERT ON Transactions
FOR EACH ROW
BEGIN
    INSERT INTO Audit_Log (table_name, action_type, record_id, changed_by, old_value, new_value)
    VALUES ('Transactions', 'INSERT', NEW.transaction_id,
            (SELECT u.full_name FROM Users u JOIN Accounts a ON a.user_id = u.user_id
              WHERE a.account_id = NEW.account_id),
            NULL,
            CONCAT('Amount: ', NEW.amount, ' | Type: ', NEW.transaction_type,
                   ' | Account: #', NEW.account_id,
                   ' | Description: ', IFNULL(NEW.description, 'N/A')));
END //

CREATE TRIGGER trg_audit_transaction_update
AFTER UPDATE ON Transactions
FOR EACH ROW
BEGIN
    INSERT INTO Audit_Log (table_name, action_type, record_id, changed_by, old_value, new_value)
    VALUES ('Transactions', 'UPDATE', NEW.transaction_id,
            (SELECT u.full_name FROM Users u JOIN Accounts a ON a.user_id = u.user_id
              WHERE a.account_id = NEW.account_id),
            CONCAT('Amount: ', OLD.amount, ' | Type: ', OLD.transaction_type,
                   ' | Description: ', IFNULL(OLD.description, 'N/A')),
            CONCAT('Amount: ', NEW.amount, ' | Type: ', NEW.transaction_type,
                   ' | Description: ', IFNULL(NEW.description, 'N/A')));
END //

CREATE TRIGGER trg_audit_transaction_delete
AFTER DELETE ON Transactions
FOR EACH ROW
BEGIN
    INSERT INTO Audit_Log (table_name, action_type, record_id, changed_by, old_value, new_value)
    VALUES ('Transactions', 'DELETE', OLD.transaction_id,
            COALESCE((SELECT u.full_name FROM Users u JOIN Accounts a ON a.user_id = u.user_id
                       WHERE a.account_id = OLD.account_id), 'system'),
            CONCAT('Amount: ', OLD.amount, ' | Type: ', OLD.transaction_type,
                   ' | Description: ', IFNULL(OLD.description, 'N/A')),
            NULL);
END //

-- Flag high-value, check fraud patterns, check budget — after each new transaction
CREATE TRIGGER trg_transaction_checks
AFTER INSERT ON Transactions
FOR EACH ROW
FOLLOWS trg_audit_transaction_insert
BEGIN
    DECLARE v_user_id   INT;
    DECLARE v_limit     DECIMAL(12,2) DEFAULT 0;
    DECLARE v_spent     DECIMAL(12,2) DEFAULT 0;
    DECLARE v_cat_name  VARCHAR(50);
    DECLARE v_large_cnt INT DEFAULT 0;

    SELECT user_id INTO v_user_id FROM Accounts WHERE account_id = NEW.account_id;

    -- 1. High value (> ₹50,000)
    IF NEW.amount > 50000 THEN
        INSERT INTO Flagged_Transactions (transaction_id, reason)
        VALUES (NEW.transaction_id,
                CONCAT('High value transaction: ₹', FORMAT(NEW.amount, 2)));
    END IF;

    -- 2. Fraud: large transaction between 12 AM and 4 AM
    IF NEW.amount > 50000 AND HOUR(NEW.transaction_date) < 4 THEN
        INSERT INTO Fraud_Flags (user_id, transaction_id, reason, severity)
        VALUES (v_user_id, NEW.transaction_id,
                CONCAT('Midnight transaction of ₹', FORMAT(NEW.amount, 2),
                       ' at ', DATE_FORMAT(NEW.transaction_date, '%H:%i')),
                'high');
    END IF;

    -- 3. Fraud: 3+ transactions over ₹25,000 within one hour
    IF NEW.amount > 25000 THEN
        SELECT COUNT(*) INTO v_large_cnt
        FROM Transactions
        WHERE account_id = NEW.account_id
          AND amount > 25000
          AND transaction_date BETWEEN NEW.transaction_date - INTERVAL 1 HOUR
                                   AND NEW.transaction_date;
        IF v_large_cnt >= 3 THEN
            INSERT INTO Fraud_Flags (user_id, transaction_id, reason, severity)
            VALUES (v_user_id, NEW.transaction_id,
                    CONCAT(v_large_cnt, ' transactions over ₹25,000 within 1 hour'),
                    'medium');
        END IF;
    END IF;

    -- 4. Budget exceeded (debits only, current month)
    IF NEW.transaction_type = 'debit' THEN
        SELECT COALESCE(MAX(monthly_limit), 0) INTO v_limit
        FROM Budgets WHERE user_id = v_user_id AND category_id = NEW.category_id;

        IF v_limit > 0 THEN
            SET v_spent = GetMonthlySpending(v_user_id, NEW.category_id);
            IF v_spent > v_limit THEN
                SELECT category_name INTO v_cat_name
                FROM Categories WHERE category_id = NEW.category_id;
                INSERT INTO Notifications (user_id, message, type)
                VALUES (v_user_id,
                        CONCAT('Budget exceeded for ', v_cat_name,
                               '! Limit: ₹', FORMAT(v_limit, 2),
                               ' | Spent this month: ₹', FORMAT(v_spent, 2)),
                        'budget_exceeded');
            END IF;
        END IF;
    END IF;
END //

-- Low balance warning (crosses below ₹1,000)
CREATE TRIGGER trg_low_balance_warning
AFTER UPDATE ON Accounts
FOR EACH ROW
BEGIN
    IF NEW.balance < 1000 AND OLD.balance >= 1000 THEN
        INSERT INTO Notifications (user_id, message, type)
        VALUES (NEW.user_id,
                CONCAT('Warning: balance in ', NEW.account_name,
                       ' dropped below ₹1,000. Current balance: ₹', FORMAT(NEW.balance, 2)),
                'low_balance');
    END IF;
END //

-- Audit every transfer
CREATE TRIGGER trg_audit_transfer_insert
AFTER INSERT ON Transfers
FOR EACH ROW
BEGIN
    INSERT INTO Audit_Log (table_name, action_type, record_id, changed_by, old_value, new_value)
    VALUES ('Transfers', 'INSERT', NEW.transfer_id, 'system', NULL,
            CONCAT('Transfer of ₹', FORMAT(NEW.amount, 2),
                   ' from account #', NEW.from_account_id,
                   ' to account #', NEW.to_account_id,
                   ' | Status: ', NEW.status));
END //

-- =====================================================================
-- PART 5: STORED PROCEDURES
-- =====================================================================

-- Add a credit/debit and update the balance atomically
CREATE PROCEDURE AddTransaction(
    IN p_account_id  INT,
    IN p_category_id INT,
    IN p_amount      DECIMAL(12,2),
    IN p_type        VARCHAR(10),
    IN p_description VARCHAR(255)
)
BEGIN
    DECLARE v_balance DECIMAL(12,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Amount must be positive';
    END IF;
    IF p_type NOT IN ('credit','debit') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Type must be credit or debit';
    END IF;

    START TRANSACTION;

    SELECT balance INTO v_balance
    FROM Accounts WHERE account_id = p_account_id FOR UPDATE;

    IF v_balance IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account not found';
    END IF;
    IF p_type = 'debit' AND v_balance < p_amount THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient balance in account';
    END IF;

    INSERT INTO Transactions (account_id, category_id, amount, transaction_type, description)
    VALUES (p_account_id, p_category_id, p_amount, p_type, p_description);

    UPDATE Accounts
    SET balance = balance + IF(p_type = 'credit', p_amount, -p_amount)
    WHERE account_id = p_account_id;

    COMMIT;
END //

-- ACID money transfer between two accounts
CREATE PROCEDURE TransferFunds(
    IN p_from_account INT,
    IN p_to_account   INT,
    IN p_amount       DECIMAL(12,2),
    IN p_description  VARCHAR(255)
)
BEGIN
    DECLARE v_from_balance DECIMAL(12,2);
    DECLARE v_to_exists    INT DEFAULT 0;
    DECLARE v_category_id  INT;
    DECLARE v_transfer_id  INT;
    DECLARE v_from_user    INT;
    DECLARE v_to_user      INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transfer amount must be positive';
    END IF;
    IF p_from_account = p_to_account THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot transfer to the same account';
    END IF;

    START TRANSACTION;

    SELECT category_id INTO v_category_id
    FROM Categories WHERE category_name = 'Transfer' LIMIT 1;
    IF v_category_id IS NULL THEN
        INSERT INTO Categories (category_name, category_type) VALUES ('Transfer', 'expense');
        SET v_category_id = LAST_INSERT_ID();
    END IF;

    -- Lock both rows in a fixed order to avoid deadlocks
    SELECT COUNT(*) INTO v_to_exists FROM Accounts
    WHERE account_id IN (p_from_account, p_to_account)
    ORDER BY account_id FOR UPDATE;

    SELECT balance, user_id INTO v_from_balance, v_from_user
    FROM Accounts WHERE account_id = p_from_account;
    SELECT user_id INTO v_to_user
    FROM Accounts WHERE account_id = p_to_account;

    IF v_from_balance IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Source account not found';
    END IF;
    IF v_to_user IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Destination account not found';
    END IF;
    IF v_from_balance < p_amount THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient balance for transfer';
    END IF;

    UPDATE Accounts SET balance = balance - p_amount WHERE account_id = p_from_account;
    UPDATE Accounts SET balance = balance + p_amount WHERE account_id = p_to_account;

    INSERT INTO Transactions (account_id, category_id, amount, transaction_type, description)
    VALUES (p_from_account, v_category_id, p_amount, 'debit',
            CONCAT('Transfer out: ', IFNULL(p_description, '')));
    INSERT INTO Transactions (account_id, category_id, amount, transaction_type, description)
    VALUES (p_to_account, v_category_id, p_amount, 'credit',
            CONCAT('Transfer in: ', IFNULL(p_description, '')));

    INSERT INTO Transfers (from_account_id, to_account_id, amount, description, status)
    VALUES (p_from_account, p_to_account, p_amount, p_description, 'success');
    SET v_transfer_id = LAST_INSERT_ID();

    INSERT INTO Notifications (user_id, message, type) VALUES
        (v_from_user, CONCAT('You sent ₹', FORMAT(p_amount, 2), ' to account #', p_to_account), 'transfer'),
        (v_to_user,   CONCAT('You received ₹', FORMAT(p_amount, 2), ' from account #', p_from_account), 'transfer');

    -- Alert admins about very large transfers (>= ₹1,00,000)
    IF p_amount >= 100000 THEN
        INSERT INTO Notifications (user_id, message, type)
        SELECT user_id,
               CONCAT('High-value transfer #', v_transfer_id, ': ₹', FORMAT(p_amount, 2),
                      ' from account #', p_from_account, ' to #', p_to_account,
                      ' requires review.'),
               'high_value'
        FROM Users WHERE role = 'admin';
    END IF;

    COMMIT;
END //

-- Cursor-based monthly report for every account (upsert, safe to re-run)
CREATE PROCEDURE GenerateMonthlyReport(IN p_month INT, IN p_year INT, IN p_user_id INT)
BEGIN
    DECLARE v_done       INT DEFAULT 0;
    DECLARE v_account_id INT;
    DECLARE v_income     DECIMAL(12,2);
    DECLARE v_expense    DECIMAL(12,2);
    DECLARE v_count      INT DEFAULT 0;

    DECLARE cur_accounts CURSOR FOR
        SELECT account_id FROM Accounts
        WHERE p_user_id IS NULL OR user_id = p_user_id;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    OPEN cur_accounts;
    report_loop: LOOP
        FETCH cur_accounts INTO v_account_id;
        IF v_done = 1 THEN LEAVE report_loop; END IF;

        SELECT COALESCE(SUM(CASE WHEN transaction_type='credit' THEN amount END), 0),
               COALESCE(SUM(CASE WHEN transaction_type='debit'  THEN amount END), 0)
          INTO v_income, v_expense
        FROM Transactions
        WHERE account_id = v_account_id
          AND MONTH(transaction_date) = p_month
          AND YEAR(transaction_date)  = p_year;

        INSERT INTO Monthly_Reports
            (account_id, report_month, report_year, total_income, total_expense, net_savings)
        VALUES (v_account_id, p_month, p_year, v_income, v_expense, v_income - v_expense)
        ON DUPLICATE KEY UPDATE
            total_income  = VALUES(total_income),
            total_expense = VALUES(total_expense),
            net_savings   = VALUES(net_savings),
            generated_at  = CURRENT_TIMESTAMP;

        SET v_count = v_count + 1;
    END LOOP;
    CLOSE cur_accounts;

    SELECT v_count AS accounts_processed;
END //

-- Create or update a monthly budget (no result set → no "commands out of sync")
CREATE PROCEDURE SetBudget(
    IN p_user_id       INT,
    IN p_category_id   INT,
    IN p_monthly_limit DECIMAL(12,2)
)
BEGIN
    IF p_monthly_limit IS NULL OR p_monthly_limit <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Budget limit must be positive';
    END IF;
    INSERT INTO Budgets (user_id, category_id, monthly_limit)
    VALUES (p_user_id, p_category_id, p_monthly_limit)
    ON DUPLICATE KEY UPDATE monthly_limit = VALUES(monthly_limit);
END //

-- Cursor-based summary of one account
CREATE PROCEDURE GetAccountSummary(IN p_account_id INT)
BEGIN
    DECLARE v_done        INT DEFAULT 0;
    DECLARE v_amount      DECIMAL(12,2);
    DECLARE v_type        VARCHAR(10);
    DECLARE total_credit  DECIMAL(12,2) DEFAULT 0;
    DECLARE total_debit   DECIMAL(12,2) DEFAULT 0;

    DECLARE cur_tx CURSOR FOR
        SELECT amount, transaction_type FROM Transactions WHERE account_id = p_account_id;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    OPEN cur_tx;
    read_loop: LOOP
        FETCH cur_tx INTO v_amount, v_type;
        IF v_done = 1 THEN LEAVE read_loop; END IF;
        IF v_type = 'credit' THEN
            SET total_credit = total_credit + v_amount;
        ELSE
            SET total_debit = total_debit + v_amount;
        END IF;
    END LOOP;
    CLOSE cur_tx;

    SELECT p_account_id                 AS account_id,
           total_credit                 AS total_income,
           total_debit                  AS total_expense,
           (total_credit - total_debit) AS net_flow;
END //

-- Fraud rule 3: flag users with no activity (no login, no transaction) for 30+ days.
-- Run automatically every day by evt_detect_inactive_users (below), and on demand
-- from the admin "Fraud Detection" page.
CREATE PROCEDURE DetectInactiveUsers()
BEGIN
    INSERT INTO Fraud_Flags (user_id, transaction_id, reason, severity)
    SELECT u.user_id, NULL,
           CONCAT('Inactive account: no activity for ',
                  DATEDIFF(NOW(), x.last_activity), ' days'),
           'low'
    FROM Users u
    JOIN (
        SELECT u2.user_id,
               GREATEST(COALESCE(u2.last_login, u2.created_at),
                        COALESCE(MAX(t.transaction_date), u2.created_at)) AS last_activity
        FROM Users u2
        LEFT JOIN Accounts a     ON a.user_id    = u2.user_id
        LEFT JOIN Transactions t ON t.account_id = a.account_id
        GROUP BY u2.user_id, u2.last_login, u2.created_at
    ) x ON x.user_id = u.user_id
    WHERE u.role = 'user'
      AND x.last_activity < NOW() - INTERVAL 30 DAY
      -- don't flag the same user again while an earlier flag is still unreviewed
      AND NOT EXISTS (
          SELECT 1 FROM Fraud_Flags f
          WHERE f.user_id = u.user_id AND f.reviewed = FALSE
            AND f.reason LIKE 'Inactive account%'
      );

    SELECT ROW_COUNT() AS users_flagged;
END //

DELIMITER ;

-- =====================================================================
-- PART 6: SCHEDULED EVENT
-- Runs the inactive-user scan once a day (needs event_scheduler=ON,
-- which is the default in MySQL 8).
-- =====================================================================
CREATE EVENT evt_detect_inactive_users
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP + INTERVAL 1 MINUTE
DO CALL DetectInactiveUsers();

-- Quick check
SELECT 'FinTrace schema created' AS status;
