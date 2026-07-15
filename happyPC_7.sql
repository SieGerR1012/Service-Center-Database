-- Создание схемы
CREATE SCHEMA IF NOT EXISTS happy_pc;

SET search_path TO happy_pc;

-- Клиенты
CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    last_name VARCHAR(50) NOT NULL,
    first_name VARCHAR(50) NOT NULL,
    middle_name VARCHAR(50),
    phone VARCHAR(20) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE
);

-- 2. Типы комплектующих
CREATE TABLE part_types (
    part_type_id SERIAL PRIMARY KEY,
    part_type_name VARCHAR(50) NOT NULL UNIQUE
);

-- Комплектующие
CREATE TABLE parts (
    part_id SERIAL PRIMARY KEY,
    part_name VARCHAR(100) NOT NULL,
    part_type_id INT NOT NULL,
    FOREIGN KEY (part_type_id) REFERENCES part_types(part_type_id)
);

-- Спецификации
CREATE TABLE part_specifications (
    spec_id SERIAL PRIMARY KEY,
    part_id INT NOT NULL,
    spec_name VARCHAR(100) NOT NULL,
    spec_value TEXT NOT NULL,
    FOREIGN KEY (part_id) REFERENCES parts(part_id)
);

-- Услуги
CREATE TABLE services (
    service_id SERIAL PRIMARY KEY,
    service_name VARCHAR(100) NOT NULL,
    cost DECIMAL(12,2) NOT NULL,
    description TEXT
);

-- Поставщики
CREATE TABLE suppliers (
    supplier_id SERIAL PRIMARY KEY,
    supplier_name VARCHAR(100) NOT NULL
);

-- Города
CREATE TABLE cities (
    city_id SERIAL PRIMARY KEY,
    city_name VARCHAR(100) NOT NULL UNIQUE
);

-- Улицы
CREATE TABLE streets (
    street_id SERIAL PRIMARY KEY,
    street_name VARCHAR(150) NOT NULL,
    city_id INT NOT NULL,
    FOREIGN KEY (city_id) REFERENCES cities(city_id)
);

-- Контактная информация поставщиков
CREATE TABLE supplier_contacts (
    supplier_id INT PRIMARY KEY,
    phone VARCHAR(20) NOT NULL,
    street_id INT NOT NULL,
    FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id),
    FOREIGN KEY (street_id) REFERENCES streets(street_id)
);

-- Контракты
CREATE TABLE contracts (
    contract_id SERIAL PRIMARY KEY,
    contract_number VARCHAR(50) NOT NULL UNIQUE,
    supplier_id INT NOT NULL,
    contract_date DATE NOT NULL,
    contract_cost DECIMAL(12,2) NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('active', 'closed', 'terminated')),
    FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id)
);

-- Заказы
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('new', 'in_progress', 'completed', 'cancelled')),
    start_date DATE NOT NULL,
    end_date DATE,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

-- Платежи от клиентов
CREATE TABLE payments_in (
    payment_in_id SERIAL PRIMARY KEY,
    order_id INT NOT NULL,
    amount DECIMAL(15,2) NOT NULL CHECK (amount > 0),
    payment_date DATE NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

-- Платежи поставщикам
CREATE TABLE payments_out (
    payment_out_id SERIAL PRIMARY KEY,
    contract_id INT NOT NULL,
    amount DECIMAL(15,2) NOT NULL CHECK (amount > 0),
    payment_date DATE NOT NULL,
    FOREIGN KEY (contract_id) REFERENCES contracts(contract_id)
);

-- Комплектующие в заказе
CREATE TABLE part_order (
    contract_id INT NOT NULL,
    order_id INT NOT NULL,
    part_id INT NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (contract_id, order_id, part_id),
    FOREIGN KEY (contract_id) REFERENCES contracts(contract_id),
    FOREIGN KEY (order_id) REFERENCES orders(order_id),
    FOREIGN KEY (part_id) REFERENCES parts(part_id)
);

-- Услуги в заказе
CREATE TABLE service_order (
    order_id INT NOT NULL,
    service_id INT NOT NULL,
    cost DECIMAL(12,2) NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (order_id, service_id),
    FOREIGN KEY (order_id) REFERENCES orders(order_id),
    FOREIGN KEY (service_id) REFERENCES services(service_id)
);

-- Актуальные реквизиты
CREATE TABLE supplier_current_requisite (
    supplier_id INT PRIMARY KEY,
    requisites TEXT NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_supplier
      FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id)
      ON DELETE CASCADE
);

-- История реквизитов поставщика
CREATE TABLE supplier_requisite_history (
    id SERIAL PRIMARY KEY,
    supplier_id INT NOT NULL,
    requisites TEXT NOT NULL,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

 --__________________________________________________________________________

-- Представление
CREATE OR REPLACE VIEW monthly_financial AS
WITH
all_months AS (
    SELECT DISTINCT DATE_TRUNC('month', payment_date)::DATE AS month_start FROM payments_in
    UNION
    SELECT DISTINCT DATE_TRUNC('month', payment_date)::DATE FROM payments_out
),
incomes AS (
    SELECT DATE_TRUNC('month', payment_date)::DATE AS month_start, SUM(amount) AS total_in
    FROM payments_in
    GROUP BY 1
),
expenses AS (
    SELECT DATE_TRUNC('month', payment_date)::DATE AS month_start, SUM(amount) AS total_out
    FROM payments_out
    GROUP BY 1
),
combined AS (
    SELECT
        m.month_start,
        COALESCE(i.total_in, 0) AS total_incoming,
        COALESCE(e.total_out, 0) AS total_outgoing,
        COALESCE(i.total_in, 0) - COALESCE(e.total_out, 0) AS balance
    FROM all_months m
    LEFT JOIN incomes i ON m.month_start = i.month_start
    LEFT JOIN expenses e ON m.month_start = e.month_start
),
with_diff AS (
    SELECT
        *,
        balance - LAG(balance) OVER (ORDER BY month_start) AS monthly_change
    FROM combined
)
SELECT
    month_start AS "Месяц-Год",
    total_incoming AS "Приход",
    total_outgoing AS "Расход",
    balance AS "Разница",
    monthly_change AS "Изменение от предыдущего месяца"
FROM with_diff
ORDER BY month_start;
----------------------------------------------------
--#########################################################################################
-- Триггерная функция
CREATE OR REPLACE FUNCTION log_supplier_requisite_change()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.requisites IS DISTINCT FROM NEW.requisites THEN
        INSERT INTO supplier_requisite_history (
            supplier_id, requisites, changed_at
        ) VALUES (
            OLD.supplier_id, OLD.requisites, NEW.updated_at
        );
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO supplier_requisite_history (
            supplier_id, requisites, changed_at
        ) VALUES (
            OLD.supplier_id, OLD.requisites, CURRENT_TIMESTAMP
        );
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- Триггер
CREATE TRIGGER trg_log_supplier_requisite_change
AFTER UPDATE OR DELETE ON supplier_current_requisite
FOR EACH ROW
EXECUTE FUNCTION log_supplier_requisite_change();

--#########################################################################################

INSERT INTO customers (last_name, first_name, middle_name, phone, email) values	
('Иванова', 'Иван', NULL, '+79991234567', 'ivanov99@gmail.com'),
('Смирнов', 'Ваня', NULL, '+79997654321', 'v.smirnov@mail.ru'),
('Соколова', 'Ника', NULL, '+79993456789', 'sokolovanika@yandex.ru'),
('Шульц', 'Олег', NULL, '+79998887766', 'o.shul@mail.ru'),
('Шалыгина', 'Виктория', NULL, '+79990001122', 'shalygina87@gmail.com');

INSERT INTO part_types (part_type_name) VALUES
('Процессор'), 
('Материнская плата'), 
('Оперативная память'), 
('Жесткий диск'), 
('Видеокарта');

INSERT INTO parts (part_name, part_type_id) VALUES
('Intel Core i5-12400F', 1),
('MSI B660M', 2),
('Kingston FURY 16GB DDR4', 3),
('Samsung 500Gb SSD', 4),
('NVIDIA RTX 4060', 5);

INSERT INTO part_specifications (part_id, spec_name, spec_value) VALUES
(1, 'Ядра/Потоки', '6 ядер, 12 потоков'),
(1, 'Частота', '2.5GHz'),
(2, 'Поддержка памяти', 'DDR4'),
(2, 'Сокет', 'LGA1700'),
(3, 'Частота', '3200MHz'),
(3, 'CL', 'CL16'),
(4, 'Скорость', '7200 об/мин'),
(4, 'Интерфейс', 'SATA III'),
(5, 'Память', '12GB GDDR6'),
(5, 'Интерфейсы', 'HDMI/DP');

INSERT INTO services (service_name, cost, description) VALUES
('Сборка ПК', 2500.00, 'Профессиональная сборка компьютера из комплектующих'),
('Диагностика', 1200.00, 'Полная диагностика аппаратного и программного состояния ПК'),
('Ремонт', 3500.00, 'Ремонт компонентов и устранение неисправностей');

INSERT INTO suppliers (supplier_name) VALUES
('ООО "e2e4"'),
('ООО "РемКомп"'),
('ООО "ДНС"'),
('ООО "ТехСнаб"'),
('ИП "Iron PC"');

-- Города
INSERT INTO cities (city_name) VALUES
('Екатеринбург'),
('Санкт-Петербург'),
('Москва'),
('Казань'),
('Новосибирск');

-- Улицы (в порядке соответствия с городами)
INSERT INTO streets (street_name, city_id) VALUES
('ул. Вайнера, 18', 1),
('пр. Ленина, 12', 2),
('ул. Технопарковая, 1', 3),
('ул. Чистопольская, 22', 4),
('ул. Станционная, 45', 5);

-- Контактные данные поставщиков
INSERT INTO supplier_contacts (supplier_id, phone, street_id) VALUES
(1, '+73432556677', 1),
(2, '+78125554433', 2),
(3, '+74995551212', 3),
(4, '+78432223311', 4),
(5, '+73833445566', 5);

INSERT INTO contracts (contract_number, supplier_id, contract_date, contract_cost, status) VALUES
('CN-001', 1, '2024-01-10', 50000.00, 'active'),
('CN-002', 2, '2024-02-05', 30000.00, 'closed'),
('CN-003', 3, '2024-03-15', 75000.00, 'active'),
('CN-004', 4, '2024-04-01', 62000.00, 'active'),
('CN-005', 5, '2024-04-20', 40000.00, 'terminated');

INSERT INTO orders (customer_id, status, start_date, end_date) VALUES
(1, 'completed', '2024-01-12', '2024-01-20'),
(2, 'completed', '2024-02-10', '2024-02-18'),
(3, 'in_progress', '2024-03-05', NULL),
(4, 'new', '2024-04-15', NULL),
(5, 'cancelled', '2024-05-01', '2024-05-03');

INSERT INTO payments_in (order_id, amount, payment_date) VALUES
(1, 50000.00, '2024-06-01'),
(2, 60000.00, '2024-07-01'),
(3, 70000.00, '2024-08-01'),
(4, 35000.00, '2024-04-28'),
(5, 55000.00, '2024-05-05');

INSERT INTO payments_out (contract_id, amount, payment_date) VALUES
(1, 20000.00, '2024-06-05'),
(2, 25000.00, '2024-07-10'),
(3, 30000.00, '2024-08-10'),
(4, 10000.00, '2024-04-10'),
(5, 20000.00, '2024-04-25');

INSERT INTO part_order (contract_id, order_id, part_id, amount, quantity) VALUES
(1, 1, 1, 15000.00, 1),
(1, 1, 2, 10000.00, 1),
(2, 2, 3, 8000.00, 2),
(3, 3, 4, 7000.00, 1),
(3, 3, 5, 50000.00, 1);

INSERT INTO service_order (order_id, service_id, cost, quantity) VALUES
(1, 1, 2500.00, 1),
(1, 2, 1200.00, 1),
(2, 3, 3500.00, 1),
(3, 2, 1200.00, 1),
(4, 1, 2500.00, 1);

-- Привязка текущик реквезитов
INSERT INTO supplier_current_requisite (supplier_id, requisites, updated_at) VALUES
  (1, 'ИНН 7071009922, р/с 50170010800000000001', '2022-08-30'),
  (2, 'ИНН 6603009911, р/с 50170010800000000002', '2022-10-11'),
  (3, 'ИНН 1602007788, р/с 50170010800000000003', '2023-03-11'),
  (4, 'ИНН 7701001122, р/с 50170010800000000004', '2023-01-15'),
  (5, 'ИНН 5401005566, р/с 50170010800000000005', '2023-06-20');
 
--#########################################################################################
-------------------------------------------------------------------------------------------

-- Новый заказ 1
INSERT INTO orders (customer_id, status, start_date)
VALUES (2, 'completed', '2025-05-11')
RETURNING order_id;

-- Новый контракт 1
INSERT INTO payments_in (order_id, amount, payment_date)
VALUES (6, 23500.00, '2024-05-22');

INSERT INTO part_order (contract_id, order_id, part_id, amount, quantity)
VALUES (1, 6, 1, 23500.00, 1);


-- Новый заказ 2
INSERT INTO orders (customer_id, status, start_date)
VALUES (1, 'completed', '2024-03-11')
RETURNING order_id;

-- Новый контракт 2
INSERT INTO payments_in (order_id, amount, payment_date)
VALUES (7, 75000.00, '2024-03-15');

INSERT INTO part_order (contract_id, order_id, part_id, amount, quantity)
VALUES (1, 7, 1, 75000.00, 1);

--------------------------------------------------------------------
-- Изменение реквизитов поставщика
UPDATE supplier_current_requisite
SET requisites = 'ИНН 6603009911, р/с 50170010800000000022',
    updated_at = '2024-10-17'
WHERE supplier_id = 2;

-- История реквизитов
SELECT * FROM supplier_requisite_history WHERE supplier_id = 2;

-- Актуальные реквизиты
SELECT * FROM supplier_current_requisite WHERE supplier_id = 2;


-- Создание поставщика
INSERT INTO suppliers (supplier_name)
VALUES ('Test')
RETURNING supplier_id;

-- Присваивание реквизитов поставщику
INSERT INTO supplier_current_requisite (supplier_id, requisites, updated_at)
VALUES (6, 'ИНН 1234567890, р/с 40702810900006666777', '2024-05-22');

-- Изменение реквизитов поставщика
UPDATE supplier_current_requisite
SET requisites = 'ИНН 6603009911, р/с 50170010800000000022',
    updated_at = '2025-09-09'
WHERE supplier_id = 6;

-- История реквизитов
SELECT * FROM supplier_requisite_history WHERE supplier_id = 6;

-- Актуальные реквизиты
SELECT * FROM supplier_current_requisite WHERE supplier_id = 6;

DELETE FROM supplier_current_requisite WHERE supplier_id = 6;
SELECT * FROM supplier_requisite_history WHERE supplier_id = 6;