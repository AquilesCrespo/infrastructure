# .NET applications

[Documentation index](../README.md) | [Project README](../../README.md)

Follow the [shared setup guidance](./README.md) first. Run infrastructure commands
from the repository root and project commands from your application directory.

## ASP.NET Core web API

Requires a supported .NET SDK.

```sh
dotnet new web -n DotnetApi
cd DotnetApi
dotnet add package Npgsql
dotnet add package StackExchange.Redis
dotnet add package MailKit
dotnet user-secrets init
dotnet user-secrets set "ConnectionStrings:Postgres" "Host=127.0.0.1;Port=5432;Database=local_pg_db;Username=dev_user;Password=REPLACE_WITH_POSTGRES_PASSWORD"
dotnet user-secrets set "ConnectionStrings:Redis" "127.0.0.1:6379"
dotnet user-secrets set "Smtp:Host" "127.0.0.1"
dotnet user-secrets set "Smtp:Port" "1025"
dotnet watch run --urls http://127.0.0.1:5001
```

Open http://127.0.0.1:5001. The empty web template supplies a basic endpoint,
but it does not query these services automatically. Read the connection strings
through `builder.Configuration.GetConnectionString("Postgres")` and
`GetConnectionString("Redis")`; wire Npgsql and Redis clients into your app.
Configure MailKit for Mailpit without authentication or TLS.
Add EF Core with the PostgreSQL provider only if your project needs an ORM,
then manage application migrations explicitly.

User secrets are loaded by the standard ASP.NET Core builder in the Development
environment; ensure your launch configuration selects it. They are outside the
project directory but are not encrypted, and are not a production secret store.
Environment variables can override configuration using double underscores,
for example `ConnectionStrings__Postgres` and `Smtp__Port`.
Do not paste real credentials into shared terminal logs or commit configuration
containing passwords.

## Console application or background service

```sh
dotnet new console -n DotnetTool
cd DotnetTool
dotnet add package Npgsql
dotnet build
dotnet run
```

For a plain console app, supply a PostgreSQL connection string through a private
environment variable such as `ConnectionStrings__Postgres`. Read it explicitly
with `Environment.GetEnvironmentVariable`, or add/configure .NET's configuration
libraries. A console template does not automatically load user secrets or `.env`.
Use `dotnet new worker -n DotnetWorker` instead when you need a hosted background
service with lifecycle management. Add Redis or email clients only as needed.
Create separate test projects with your chosen test framework and run them with
`dotnet test`; the console and empty web templates do not create tests.
