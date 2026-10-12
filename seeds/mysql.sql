CREATE TABLE IF NOT EXISTS infrastructure_demo_customers (
    id INT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL
);

START TRANSACTION;
INSERT INTO infrastructure_demo_customers (id, name, email)
VALUES (1, 'Alice Demo', 'alice@example.test'),
       (2, 'Bob Demo', 'bob@example.test')
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    email = VALUES(email);
COMMIT;
