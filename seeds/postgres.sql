CREATE SCHEMA IF NOT EXISTS infrastructure_demo;

CREATE TABLE IF NOT EXISTS infrastructure_demo.customers (
    id INTEGER PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL
);

INSERT INTO infrastructure_demo.customers (id, name, email)
VALUES (1, 'Alice Demo', 'alice@example.test'),
       (2, 'Bob Demo', 'bob@example.test')
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name, email = EXCLUDED.email;
