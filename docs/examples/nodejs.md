# Node.js: Express web API

[Documentation index](../README.md) | [Project README](../../README.md)

Follow the [shared setup guidance](./README.md) first. Run infrastructure commands
from the repository root and project commands from your application directory.

Requires a supported Node.js release with `--env-file` and `--watch` support.

```sh
mkdir node-api
cd node-api
npm init -y
npm install express pg redis nodemailer
```

Create a private `.env`:

```dotenv
PORT=3001
PGHOST=127.0.0.1
PGPORT=5432
PGDATABASE=local_pg_db
PGUSER=dev_user
PGPASSWORD=REPLACE_WITH_POSTGRES_PASSWORD
REDIS_URL=redis://127.0.0.1:6379
SMTP_HOST=127.0.0.1
SMTP_PORT=1025
```

Create `server.js`:

```javascript
const express = require("express");
const app = express();

app.get("/health", (_request, response) => {
  response.json({ status: "ok" });
});

app.listen(Number(process.env.PORT || 3001), "127.0.0.1");
```

```sh
node --env-file=.env --watch server.js
```

Open http://127.0.0.1:3001/health. Port 3001 avoids Grafana's default port 3000.
`pg` can read the `PG*` variables when constructing a client/pool; configure
`redis` using `REDIS_URL`, and Nodemailer using the SMTP host/port with
`secure: false` and no authentication. Connect and close clients explicitly,
surface connection errors, and add application migrations and tests.
This sample health route checks only the API process, not its dependencies.
