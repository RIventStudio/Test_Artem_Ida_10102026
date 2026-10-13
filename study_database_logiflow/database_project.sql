-- =============================================================================
-- ПРОЕКТ: КОРПОРАТИВНАЯ РЕЛЯЦИОННАЯ СУБД "LogiFlow DB"
-- СИСТЕМА УПРАВЛЕНИЯ ЛОГИСТИКОЙ, СКЛАДСКИМИ ЗАПАСАМИ И ЗАКАЗАМИ
-- ПРОТОКОЛ ВЫПОЛНЕНИЯ: BPR40 v4.0.1 (Auto Mode)
-- РЕЖИМ РАБОТЫ: Production-grade DDL/DML, RBAC, Encryption, Triggers & SP
-- СЕРТИФИКАЦИОННЫЙ ПАРОЛЬ / КЛЮЧ ШИФРОВАНИЯ: 4955
-- =============================================================================

-- =============================================================================
-- РАЗДЕЛ 1. ИНИЦИАЛИЗАЦИЯ СХЕМЫ И КРИПТОГРАФИЧЕСКИХ РАСШИРЕНИЙ
-- =============================================================================

-- Включение расширения для симметричного шифрования данных (AES-256)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Очистка объектов при повторном развертывании (Dev/Test режим)
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS warehouses CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS system_audit_logs CASCADE;

-- =============================================================================
-- РАЗДЕЛ 2. СОЗДАНИЕ СТРУКТУРЫ БАЗЫ ДАННЫХ (6 СВЯЗАННЫХ ТАБЛИЦ)
-- =============================================================================

-- Таблица 1: Клиенты (включает персональные данные и шифрованные поля)
CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(120) UNIQUE NOT NULL,
    -- Зашифрованный номер телефона (AES-256 с мастер-паролем 4955)
    phone_encrypted BYTEA NOT NULL,
    -- Хеш пароля с криптографической солью (SHA-512)
    password_hash VARCHAR(256) NOT NULL,
    -- Зашифрованные паспортные данные / ИНН (AES-256)
    identity_doc_encrypted BYTEA,
    registered_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    bonus_points INTEGER DEFAULT 0 CHECK (bonus_points >= 0)
);

-- Таблица 2: Склады и региональные распределительные центры
CREATE TABLE warehouses (
    warehouse_id SERIAL PRIMARY KEY,
    warehouse_name VARCHAR(100) NOT NULL,
    city VARCHAR(80) NOT NULL,
    address VARCHAR(200) NOT NULL,
    max_capacity_tonnes NUMERIC(10, 2) NOT NULL CHECK (max_capacity_tonnes > 0),
    is_operational BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Таблица 3: Каталог товаров и учет складских остатков
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    sku VARCHAR(50) UNIQUE NOT NULL,
    product_name VARCHAR(180) NOT NULL,
    category VARCHAR(60) NOT NULL,
    unit_price NUMERIC(12, 2) NOT NULL CHECK (unit_price > 0),
    stock_quantity INTEGER NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    warehouse_id INTEGER NOT NULL REFERENCES warehouses(warehouse_id) ON DELETE RESTRICT,
    is_fragile BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Таблица 4: Заказы (СЕКЦИОНИРОВАННАЯ ТАБЛИЦА ПО ДАТЕ ЗАКАЗА)
-- Требование: Партиционирование одной из таблиц (RANGE Partitioning)
CREATE TABLE orders (
    order_id SERIAL,
    customer_id INTEGER NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    warehouse_id INTEGER NOT NULL REFERENCES warehouses(warehouse_id) ON DELETE RESTRICT,
    order_date DATE NOT NULL,
    order_status VARCHAR(30) NOT NULL DEFAULT 'PENDING'
        CHECK (order_status IN ('PENDING', 'PROCESSING', 'SHIPPED', 'DELIVERED', 'CANCELLED')),
    delivery_address VARCHAR(250) NOT NULL,
    total_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (total_amount >= 0),
    applied_discount_pct NUMERIC(5, 2) DEFAULT 0.00 CHECK (applied_discount_pct BETWEEN 0 AND 50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (order_id, order_date)
) PARTITION BY RANGE (order_date);

-- Секции таблицы orders по временным диапазонам (Кварталы)
CREATE TABLE orders_2025_q3 PARTITION OF orders
    FOR VALUES FROM ('2025-07-01') TO ('2025-10-01');

CREATE TABLE orders_2025_q4 PARTITION OF orders
    FOR VALUES FROM ('2025-10-01') TO ('2026-01-01');

CREATE TABLE orders_2026_q1 PARTITION OF orders
    FOR VALUES FROM ('2026-01-01') TO ('2026-04-01');

CREATE TABLE orders_2026_q2 PARTITION OF orders
    FOR VALUES FROM ('2026-04-01') TO ('2026-07-01');

CREATE TABLE orders_2026_q3 PARTITION OF orders
    FOR VALUES FROM ('2026-07-01') TO ('2026-10-01');

CREATE TABLE orders_2026_q4 PARTITION OF orders
    FOR VALUES FROM ('2026-10-01') TO ('2027-01-01');

CREATE TABLE orders_default PARTITION OF orders DEFAULT;

-- Таблица 5: Позиции заказа (Спецификация)
CREATE TABLE order_items (
    item_id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL,
    order_date DATE NOT NULL,
    product_id INTEGER NOT NULL REFERENCES products(product_id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12, 2) NOT NULL CHECK (unit_price > 0),
    subtotal NUMERIC(12, 2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    FOREIGN KEY (order_id, order_date) REFERENCES orders(order_id, order_date) ON DELETE CASCADE
);

-- Таблица 6: Журнал аудита и логирования операций
-- Требование: Реализация централизованного логирования
CREATE TABLE system_audit_logs (
    log_id BIGSERIAL PRIMARY KEY,
    event_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    db_user VARCHAR(60) NOT NULL DEFAULT CURRENT_USER,
    client_ip INET DEFAULT inet_client_addr(),
    action_type VARCHAR(10) NOT NULL CHECK (action_type IN ('INSERT', 'UPDATE', 'DELETE', 'AUTH')),
    target_table VARCHAR(50) NOT NULL,
    record_id VARCHAR(50),
    old_data JSONB,
    new_data JSONB,
    event_details TEXT
);

-- =============================================================================
-- РАЗДЕЛ 3. СОЗДАНИЕ ИНДЕКСОВ (НЕ МЕНЕЕ ДВУХ)
-- =============================================================================

-- Индекс 1: Составной B-Tree индекс для оптимизации поиска заказов клиента со статусом
-- Ускоряет частые запросы клиентского кабинета и логистического контроля
CREATE INDEX idx_orders_customer_status_date
ON orders (customer_id, order_status, order_date);

-- Индекс 2: Частичный (Partial) индекс для горячих активных заказов
-- Оптимизирует очередь диспетчеризации, исключая архивные статусы (DELIVERED/CANCELLED)
CREATE INDEX idx_orders_active_queue
ON orders (order_date, warehouse_id)
WHERE order_status IN ('PENDING', 'PROCESSING');

-- Дополнительный индекс: Покрывающий индекс для спецификации заказов
CREATE INDEX idx_order_items_product_lookup
ON order_items (product_id, quantity);

-- =============================================================================
-- РАЗДЕЛ 4. РОЛЕВАЯ МОДЕЛЬ И ПРАВА ДОСТУПА (RBAC)
-- =============================================================================

-- Создание ролей
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'role_db_admin') THEN
        CREATE ROLE role_db_admin WITH SUPERUSER CREATEDB CREATEROLE;
    END IF;

    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'role_order_manager') THEN
        CREATE ROLE role_order_manager;
    END IF;

    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'role_security_auditor') THEN
        CREATE ROLE role_security_auditor;
    END IF;

    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'role_support_operator') THEN
        CREATE ROLE role_support_operator;
    END IF;
END $$;

-- Назначение прав для ролей
-- 1. Администратор: полный доступ ко всем объектам
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO role_db_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO role_db_admin;

-- 2. Менеджер заказов: управление каталогом, заказами и позициями
GRANT SELECT, INSERT, UPDATE ON products, orders, order_items, warehouses TO role_order_manager;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO role_order_manager;

-- 3. Аудитор безопасности: только чтение логов и метаданных
GRANT SELECT ON system_audit_logs TO role_security_auditor;
GRANT SELECT ON customers TO role_security_auditor;

-- 4. Оператор поддержки: чтение заказов и клиентов без доступа к секретам
GRANT SELECT ON orders, order_items, products TO role_support_operator;
GRANT SELECT (customer_id, full_name, email, registered_at, is_active) ON customers TO role_support_operator;

-- Создание пользователей и привязка к ролям
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'user_admin_alex') THEN
        CREATE USER user_admin_alex WITH PASSWORD 'AdminSecret2026!';
        GRANT role_db_admin TO user_admin_alex;
    END IF;

    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'user_manager_olga') THEN
        CREATE USER user_manager_olga WITH PASSWORD 'ManagerPass2026!';
        GRANT role_order_manager TO user_manager_olga;
    END IF;

    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'user_auditor_ivan') THEN
        CREATE USER user_auditor_ivan WITH PASSWORD 'AuditorPass2026!';
        GRANT role_security_auditor TO user_auditor_ivan;
    END IF;

    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'user_operator_elena') THEN
        CREATE USER user_operator_elena WITH PASSWORD 'SupportPass2026!';
        GRANT role_support_operator TO user_operator_elena;
    END IF;
END $$;

-- =============================================================================
-- РАЗДЕЛ 5. ШИФРОВАНИЕ ДАННЫХ (КЛЮЧ: 4955)
-- =============================================================================

-- Вспомогательное представление для расшифровки ПДн авторизованными лицами
CREATE OR REPLACE VIEW view_decrypted_customers AS
SELECT
    customer_id,
    full_name,
    email,
    -- Симметричная расшифровка с ключом '4955'
    pgp_sym_decrypt(phone_encrypted, '4955') AS decrypted_phone,
    pgp_sym_decrypt(identity_doc_encrypted, '4955') AS decrypted_identity_doc,
    registered_at,
    is_active,
    bonus_points
FROM customers;

-- Права на представление предоставляются только администраторам и аудиторам
REVOKE ALL ON view_decrypted_customers FROM PUBLIC;
GRANT SELECT ON view_decrypted_customers TO role_db_admin, role_security_auditor;

-- =============================================================================
-- РАЗДЕЛ 6. ТРИГГЕРЫ
-- =============================================================================

-- ТРИГГЕР 1: Проверка корректности данных при вставке или обновлении
-- Выбрасывает исключение с ошибкой при нарушении складских остатков или цены
CREATE OR REPLACE FUNCTION fn_validate_order_item_stock()
RETURNS TRIGGER AS $$
DECLARE
    v_available_stock INTEGER;
    v_current_price NUMERIC(12, 2);
    v_product_name VARCHAR(180);
BEGIN
    -- Получение текущего остатка и актуальной цены товара
    SELECT stock_quantity, unit_price, product_name
    INTO v_available_stock, v_current_price, v_product_name
    FROM products
    WHERE product_id = NEW.product_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ERR-4004: Товар с идентификатором ID=% не найден в каталоге!', NEW.product_id;
    END IF;

    -- Проверка 1: Достаточность остатков на складе
    IF NEW.quantity > v_available_stock THEN
        RAISE EXCEPTION 'ERR-4001: Заказ отклонен: запрошено % ед. товара "%" (ID=%), доступный остаток на складе: % ед.!',
            NEW.quantity, v_product_name, NEW.product_id, v_available_stock;
    END IF;

    -- Проверка 2: Положительная стоимость единицы товара
    IF NEW.unit_price <= 0 THEN
        RAISE EXCEPTION 'ERR-4002: Недопустимая цена: стоимость товара должна быть строго положительной (получено: %)!',
            NEW.unit_price;
    END IF;

    -- Автоматическое списание остатка товара на складе
    UPDATE products
    SET stock_quantity = stock_quantity - NEW.quantity,
        updated_at = CURRENT_TIMESTAMP
    WHERE product_id = NEW.product_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_validate_order_item_stock
BEFORE INSERT ON order_items
FOR EACH ROW
EXECUTE FUNCTION fn_validate_order_item_stock();


-- ТРИГГЕР 2: Автоматическое логирование операций в отдельную таблицу аудита
-- Фиксирует изменения в заказах (INSERT, UPDATE, DELETE) с JSONB слепком
CREATE OR REPLACE FUNCTION fn_audit_orders_action()
RETURNS TRIGGER AS $$
DECLARE
    v_action_type VARCHAR(10);
    v_record_id VARCHAR(50);
    v_old_json JSONB := NULL;
    v_new_json JSONB := NULL;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_action_type := 'INSERT';
        v_record_id := NEW.order_id::TEXT;
        v_new_json := to_jsonb(NEW);
    ELSIF TG_OP = 'UPDATE' THEN
        v_action_type := 'UPDATE';
        v_record_id := NEW.order_id::TEXT;
        v_old_json := to_jsonb(OLD);
        v_new_json := to_jsonb(NEW);
    ELSIF TG_OP = 'DELETE' THEN
        v_action_type := 'DELETE';
        v_record_id := OLD.order_id::TEXT;
        v_old_json := to_jsonb(OLD);
    END IF;

    INSERT INTO system_audit_logs (
        action_type,
        target_table,
        record_id,
        old_data,
        new_data,
        event_details
    ) VALUES (
        v_action_type,
        TG_TABLE_NAME,
        v_record_id,
        v_old_json,
        v_new_json,
        format('Операция %s над заказом #%s пользователем %s', v_action_type, v_record_id, CURRENT_USER)
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_audit_orders_action
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW
EXECUTE FUNCTION fn_audit_orders_action();

-- =============================================================================
-- РАЗДЕЛ 7. ХРАНИМАЯ ПРОЦЕДУРА С ПАРАМЕТРАМИ
-- =============================================================================

-- Процедура: Транзакционное оформление заказа с расчетом скидки и начислением бонусов
CREATE OR REPLACE PROCEDURE sp_process_order_checkout(
    IN p_customer_id INTEGER,
    IN p_warehouse_id INTEGER,
    IN p_order_date DATE,
    IN p_delivery_address VARCHAR(250),
    IN p_product_id INTEGER,
    IN p_quantity INTEGER,
    IN p_promo_code VARCHAR(30),
    OUT p_created_order_id INTEGER,
    OUT p_final_amount NUMERIC(12, 2),
    OUT p_execution_status VARCHAR(100)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_customer_active BOOLEAN;
    v_unit_price NUMERIC(12, 2);
    v_discount_pct NUMERIC(5, 2) := 0.00;
    v_raw_total NUMERIC(12, 2);
BEGIN
    -- 1. Проверка активности клиента
    SELECT is_active INTO v_customer_active
    FROM customers
    WHERE customer_id = p_customer_id;

    IF NOT FOUND OR v_customer_active = FALSE THEN
        p_execution_status := 'REJECTED: Клиент не найден либо заблокирован в системе';
        RETURN;
    END IF;

    -- 2. Получение цены товара
    SELECT unit_price INTO v_unit_price
    FROM products
    WHERE product_id = p_product_id;

    IF NOT FOUND THEN
        p_execution_status := 'REJECTED: Товар отсутствует в номенклатуре';
        RETURN;
    END IF;

    -- 3. Применение промокода / скидки
    IF p_promo_code = 'PROMO2026' THEN
        v_discount_pct := 15.00;
    ELSIF p_promo_code = 'VIP4955' THEN
        v_discount_pct := 25.00;
    ELSE
        v_discount_pct := 0.00;
    END IF;

    -- Расчет итоговой суммы
    v_raw_total := p_quantity * v_unit_price;
    p_final_amount := ROUND(v_raw_total * (1 - v_discount_pct / 100.0), 2);

    -- 4. Создание записи заказа (попадает в соответствующую партицию)
    INSERT INTO orders (
        customer_id,
        warehouse_id,
        order_date,
        order_status,
        delivery_address,
        total_amount,
        applied_discount_pct
    ) VALUES (
        p_customer_id,
        p_warehouse_id,
        p_order_date,
        'PROCESSING',
        p_delivery_address,
        p_final_amount,
        v_discount_pct
    ) RETURNING order_id INTO p_created_order_id;

    -- 5. Добавление позиции заказа (срабатывает триггер проверки и списания остатков)
    INSERT INTO order_items (
        order_id,
        order_date,
        product_id,
        quantity,
        unit_price
    ) VALUES (
        p_created_order_id,
        p_order_date,
        p_product_id,
        p_quantity,
        v_unit_price
    );

    -- 6. Начисление бонусных баллов клиенту (5% от оплаченной суммы)
    UPDATE customers
    SET bonus_points = bonus_points + FLOOR(p_final_amount * 0.05)::INTEGER
    WHERE customer_id = p_customer_id;

    p_execution_status := 'SUCCESS: Заказ успешно зарегистрирован и передан в логистику';
END;
$$;

-- =============================================================================
-- РАЗДЕЛ 8. ДЕМОНСТРАЦИЯ УРОВНЕЙ ИЗОЛЯЦИИ ТРАНЗАКЦИЙ
-- =============================================================================

/*
ТЕОРЕТИЧЕСКИЙ АНАЛИЗ УРОВНЕЙ ИЗОЛЯЦИИ (SQL-92 / PostgreSQL):
1. READ UNCOMMITTED: В PostgreSQL работает как Read Committed (грязное чтение исключено).
2. READ COMMITTED: По умолчанию. Каждый запрос видит снимок на момент старта запроса.
   Возможна аномалия Non-repeatable Read (неповторяемое чтение).
3. REPEATABLE READ: Снимок данных фиксируется в начале транзакции. Исключает Non-repeatable read и Phantom read.
4. SERIALIZABLE: Полная изоляция через предикатные блокировки (SSI). Исключает любые аномалии сериализации.

ТЕСТОВЫЙ ПРИМЕР: Демонстрация предотвращения фантомного чтения (Repeatable Read)
*/

-- Сценарий 1: Repeatable Read предотвращает считывание измененных строк параллельной транзакции
-- Сессия 1:
-- BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- SELECT SUM(total_amount) FROM orders WHERE order_date >= '2026-01-01';
-- (Сессия 2 вставляет заказ и выполняет COMMIT)
-- SELECT SUM(total_amount) FROM orders WHERE order_date >= '2026-01-01'; -- Результат неизменен!
-- COMMIT;

-- Сценарий 2: Serializable предотвращает конфликт распределения остатков (Write Skew)
-- BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- ... бизнес-логика проверки ...
-- COMMIT; -- При обнаружении гонки выбросит ошибку: ERROR 40001: could not serialize access

-- =============================================================================
-- РАЗДЕЛ 9. СТРАТЕГИЯ РЕЗЕРВНОГО КОПИРОВАНИЯ И ВОССТАНОВЛЕНИЯ
-- =============================================================================

/*
1. ПОЛНОЕ ЛОГИЧЕСКОЕ РЕЗЕРВНОЕ КОПИРОВАНИЕ (pg_dump):
   pg_dump -h localhost -U user_admin_alex -d logiflow_db -F c -b -v -f "C:/backups/logiflow_full_backup.dump"

2. БЭКАП ТОЛЬКО СХЕМЫ (DDL):
   pg_dump -h localhost -U user_admin_alex -d logiflow_db --schema-only -f "C:/backups/logiflow_schema.sql"

3. ВОССТАНОВЛЕНИЕ ИЗ ДАМПА (pg_restore):
   pg_restore -h localhost -U user_admin_alex -d logiflow_db -v --clean "C:/backups/logiflow_full_backup.dump"

4. НЕПРЕРЫВНОЕ АРХИВИРОВАНИЕ И ВОССТАНОВЛЕНИЕ НА МОМЕНТ ВРЕМЕНИ (PITR):
   В postgresql.conf:
     wal_level = replica
     archive_mode = on
     archive_command = 'copy "%p" "C:\\backups\\wal_archive\\%f"'
   Базовый бэкап:
     pg_basebackup -h localhost -U user_admin_alex -D "C:\backups\base_backup" -Ft -z -P
*/

-- =============================================================================
-- РАЗДЕЛ 10. ТЕСТОВЫЕ ДАННЫЕ И ВЕРИФИКАЦИОННЫЙ ПРОГОН
-- =============================================================================

-- 1. Наполнение складов
INSERT INTO warehouses (warehouse_name, city, address, max_capacity_tonnes) VALUES
('Центральный Хаб МСК', 'Москва', 'ул. Южнопортовая, 12А', 5000.00),
('Северо-Западный Терминал', 'Санкт-Петербург', 'Московское шоссе, 25', 3500.00),
('Уральский Логистический Центр', 'Екатеринбург', 'ул. Базовый переулок, 8', 2800.00);

-- 2. Добавление клиентов с шифрованием ПДн (Пароль ключа: 4955)
INSERT INTO customers (full_name, email, phone_encrypted, password_hash, identity_doc_encrypted, bonus_points) VALUES
('Алексей Смирнов', 'alex.smirnov@techcorp.ru', pgp_sym_encrypt('+7 (999) 111-22-33', '4955'), crypt('PassSecret2026', gen_salt('bf', 8)), pgp_sym_encrypt('4510-987654', '4955'), 250),
('Екатерина Волкова', 'ekaterina.volkova@trade.org', pgp_sym_encrypt('+7 (985) 444-55-66', '4955'), crypt('VolkovaPass2026', gen_salt('bf', 8)), pgp_sym_encrypt('4512-112233', '4955'), 500),
('Дмитрий Кузнецов', 'dmitry.kuznetsov@logist.com', pgp_sym_encrypt('+7 (916) 777-88-99', '4955'), crypt('DmitryPass2026', gen_salt('bf', 8)), pgp_sym_encrypt('4515-554433', '4955'), 120);

-- 3. Каталог товаров
INSERT INTO products (sku, product_name, category, unit_price, stock_quantity, warehouse_id) VALUES
('SKU-SRV-001', 'Серверная платформа 2U Rack', 'Серверы и СХД', 185000.00, 15, 1),
('SKU-NET-002', 'Управляемый коммутатор 48x10G', 'Сетевое оборудование', 64500.00, 40, 1),
('SKU-UPS-003', 'Промышленный ИБП 10kVA On-Line', 'Электропитание', 92000.00, 25, 2),
('SKU-CAB-004', 'Серверный шкаф 42U 800x1000', 'Монтажные конструктивы', 38000.00, 50, 3);

-- 4. Заказы (попадают в разные секции orders по диапазону дат)
INSERT INTO orders (customer_id, warehouse_id, order_date, order_status, delivery_address, total_amount, applied_discount_pct) VALUES
(1, 1, '2025-08-15', 'DELIVERED', 'Москва, Пресненская наб., 12', 370000.00, 0.00), -- В orders_2025_q3
(2, 2, '2025-11-20', 'DELIVERED', 'Санкт-Петербург, Невский пр., 100', 92000.00, 0.00),  -- В orders_2025_q4
(1, 1, '2026-02-10', 'DELIVERED', 'Москва, Ленинградский пр-т, 39', 185000.00, 15.00),  -- В orders_2026_q1
(3, 3, '2026-05-18', 'DELIVERED', 'Екатеринбург, ул. Ленина, 50', 76000.00, 0.00),     -- В orders_2026_q2
(2, 1, '2026-10-10', 'PROCESSING', 'Санкт-Петербург, Литейный пр., 22', 129000.00, 25.00);-- В orders_2026_q4

-- 5. Позиции заказов
INSERT INTO order_items (order_id, order_date, product_id, quantity, unit_price) VALUES
(1, '2025-08-15', 1, 2, 185000.00),
(2, '2025-11-20', 3, 1, 92000.00),
(3, '2026-02-10', 1, 1, 185000.00),
(4, '2026-05-18', 4, 2, 38000.00),
(5, '2026-10-10', 2, 2, 64500.00);

-- 6. Проверка работы расшифровки (пароль 4955)
SELECT customer_id, full_name, email, decrypted_phone, decrypted_identity_doc, bonus_points
FROM view_decrypted_customers;

-- 7. Тестирование партиционирования: проверка секций
SELECT
    tableoid::regclass AS partition_name,
    order_id,
    order_date,
    total_amount,
    order_status
FROM orders;

-- 8. Проверка плана выполнения запроса (Partition Pruning & Composite Index)
EXPLAIN ANALYZE
SELECT * FROM orders
WHERE order_date BETWEEN '2026-01-01' AND '2026-03-31'
  AND customer_id = 1;

-- 9. Тестирование триггера валидации (Попытка заказать больше доступного остатка -> ВЫБРОС ОШИБКИ)
-- Следующая строка должна завершиться ошибкой ERR-4001:
-- INSERT INTO order_items (order_id, order_date, product_id, quantity, unit_price)
-- VALUES (5, '2026-10-10', 1, 999, 185000.00);

-- 10. Проверка журнала аудита
SELECT log_id, event_time, db_user, action_type, target_table, record_id, event_details
FROM system_audit_logs
ORDER BY log_id DESC;

-- =============================================================================
-- КОНЕЦ ПРОГРАММНОГО КОДА ПРОЕКТА
-- =============================================================================
