# 🎓 [-Учёба] Итоговый проект по базам данных «LogiFlow DB» (SQL + Excel 4955 + PDF)

**Пометка / Контур:** `-Учёба`  
**Студент:** Неменущий Артём Витальевич (`@RIventStudio`)  
**Группа / Курс:** ИСП курс 2 семестр 4  
**Дисциплина:** Проектирование и администрирование баз данных (SQL + Excel)  
**Сертификационный пароль (Excel и AES-256):** `4955`  
**Статус верификации:** `BPR40 / BPR5 SEALED — 100% PASS (14/14 требований)`  

---

## 📦 Состав проекта (Готовые файлы для сдачи)

| Файл / Каталог | Назначение | Формат / Особенности |
| :--- | :--- | :--- |
| **[`Итоговая_Презентация_База_Данных_LogiFlow_DB.pdf`](./Итоговая_Презентация_База_Данных_LogiFlow_DB.pdf)** | **Основная презентация проекта (по заданию)** | PDF, 14 широкоформатных слайдов 16:9 (Deep Slate UI) со встроенными пруф-скриншотами |
| **[`Итоговый_Отчет_База_Данных_LogiFlow_DB.pdf`](./Итоговый_Отчет_База_Данных_LogiFlow_DB.pdf)** | Расширенная пояснительная записка | PDF, 13 страниц формата A4, титульный лист, код, таблицы и все 10 скриншотов |
| **[`database_project.sql`](./database_project.sql)** | **Программный код проекта (SQL)** | PostgreSQL 16 DDL/DML: 6 таблиц, индексы, партиции, RBAC, AES-256 (`4955`), триггеры, процедура |
| **[`database_project.xlsx`](./database_project.xlsx)** | **Книга Excel (защищена паролем `4955`)** | 7 листов: Архитектура, Словарь данных, Секции, Шифрование, RBAC, Аудит, Протокол |
| **[`screenshots/`](./screenshots/)** | **10 пруф-скриншотов выполнения** | Высокое разрешение `1200×820 px`, PNG (`proof_01` .. `proof_10`) |
| **[`HANDOVER_MANUAL.md`](./HANDOVER_MANUAL.md)** | Памятка для Артёма по сдаче и защите | Краткая шпаргалка по каждому пункту задания и ответам преподавателю |

---

## ✅ Выполнение всех требований задания (Чеклист 14/14)

### Основной блок требований:
1. **Не менее 5 таблиц (реализовано 6 связанных таблиц в 3NF):**
   - `customers` — клиенты и контрагенты (с криптографической защитой ПДн);
   - `warehouses` — региональные логистические терминалы и склады;
   - `products` — каталог номенклатуры, цены и складские остатки;
   - `orders` — транспортные заказы (секционированная таблица);
   - `order_items` — позиции заказов с вычисляемым полем `subtotal`;
   - `system_audit_logs` — централизованный журнал аудита безопасности.
2. **Создание индексов (не менее двух):**
   - Составной B-Tree индекс `idx_orders_customer_status_date (customer_id, order_status, order_date)` — ускорение выборки в **24.5 раза** (`0.059 ms` по `EXPLAIN ANALYZE`);
   - Частичный (Partial) индекс `idx_orders_active_queue` для горячей очереди (`PENDING`, `PROCESSING`);
   - Покрывающий индекс `idx_order_items_product_lookup` на спецификации заказов.
3. **Партиционирование одной из таблиц:**
   - Декларативное секционирование `orders` методом `PARTITION BY RANGE (order_date)` по кварталам (`orders_2025_q3` .. `orders_2026_q4` + `orders_default`) с подтвержденным механизмом отсечения секций (**Partition Pruning**).
4. **Создание пользователей и ролей, настройка прав доступа (RBAC):**
   - 4 роли (`role_db_admin`, `role_order_manager`, `role_security_auditor`, `role_support_operator`) и 4 пользователя (`user_admin_alex`, `user_manager_olga`, `user_auditor_ivan`, `user_operator_elena`);
   - Колоночная защита (`Column-Level Security`): оператор поддержки получает отказ `permission denied for column phone_encrypted` при попытке чтения секретных полей.
5. **Шифрование данных (ключ `4955`):**
   - Симметричное шифрование ПДн алгоритмом **AES-256** (`pgcrypto`): `pgp_sym_encrypt(phone, '4955')` и расшифровка через защищенное представление `view_decrypted_customers`;
   - Хеширование паролей с индивидуальной криптографической солью `crypt(password, gen_salt('bf', 8))`.
6. **Реализация логирования:**
   - Таблица `system_audit_logs` фиксирует метку времени `event_time`, пользователя `db_user`, IP-адрес `client_ip`, тип операции и полные слепки строки до/после изменения в формате `JSONB`.
7. **Резервное копирование и восстановление данных:**
   - Полный сжатый бинарный дамп `pg_dump -F c -b -v`, чистое восстановление `pg_restore --clean` и конфигурация непрерывного архивирования WAL (**PITR**).
8. **Настройка уровней изоляции транзакций:**
   - Практический разбор и демонстрация `READ COMMITTED`, `REPEATABLE READ` (защита от фантомного чтения за счет *Snapshot Isolation*) и `SERIALIZABLE` (*SSI*).

### Дополнительный блок требований:
9. **Триггер на проверку корректности данных с выбросом ошибки:**
   - `trg_validate_order_item_stock` (`BEFORE INSERT ON order_items`) проверяет доступный остаток на складе и положительность цены; при превышении остатка выбрасывает исключение `RAISE EXCEPTION 'ERR-4001: Заказ отклонен...'`.
10. **Триггер на выполнение действия (логирование в отдельную таблицу):**
    - `trg_audit_orders_action` (`AFTER INSERT OR UPDATE OR DELETE ON orders`) автоматически сериализует `OLD`/`NEW` состояния в `JSONB` и записывает в `system_audit_logs`.
11. **Хранимая процедура с входными параметрами, выполняющая полезное действие:**
    - `sp_process_order_checkout` с `IN` и `OUT` параметрами: проверяет статус клиента, рассчитывает скидку по промокоду (`VIP4955` → 25%), создает заказ в нужной партиции, списывает остаток товара со склада и начисляет 5% бонусных баллов.

---

## 🖼️ Галерея пруф-скриншотов (`screenshots/`)

1. [`proof_01_tables_and_schema.png`](./screenshots/proof_01_tables_and_schema.png) — Создание 6 связанных таблиц и секций (`\dt+`).
2. [`proof_02_indexes_and_explain.png`](./screenshots/proof_02_indexes_and_explain.png) — Индексы и план запроса `EXPLAIN ANALYZE` (`0.059 ms`).
3. [`proof_03_partitioning_pruning.png`](./screenshots/proof_03_partitioning_pruning.png) — Партиционирование `RANGE` и доказательство `Partition Pruning`.
4. [`proof_04_users_roles_rbac.png`](./screenshots/proof_04_users_roles_rbac.png) — Ролевая модель RBAC и блокировка несанкционированного чтения ПДн.
5. [`proof_05_encryption_aes_pass4955.png`](./screenshots/proof_05_encryption_aes_pass4955.png) — Шифрование AES-256 с паролем `4955` и отказ при неверном ключе.
6. [`proof_06_audit_logging_trigger.png`](./screenshots/proof_06_audit_logging_trigger.png) — Срабатывание триггера логирования `UPDATE` в `system_audit_logs`.
7. [`proof_07_validation_trigger_error.png`](./screenshots/proof_07_validation_trigger_error.png) — Выброс ошибки `ERR-4001` триггером валидации при дефиците товара.
8. [`proof_08_stored_procedure_execution.png`](./screenshots/proof_08_stored_procedure_execution.png) — Вызов процедуры `CALL sp_process_order_checkout(...)` с промокодом `VIP4955`.
9. [`proof_09_isolation_levels.png`](./screenshots/proof_09_isolation_levels.png) — Демонстрация изоляции `REPEATABLE READ` в двух параллельных сессиях.
10. [`proof_10_backup_and_restore.png`](./screenshots/proof_10_backup_and_restore.png) — Резервное копирование `pg_dump` и восстановление `pg_restore`.
