import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, unlinkSync, rmdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const project = `infrastructure-observability-test-${process.pid}`;
const directory = mkdtempSync(`${tmpdir()}/infrastructure-observability-`);
const file = `${directory}/compose.json`;
const legacyFile = `${directory}/legacy-compose.json`;
const legacyProvisioning = `${directory}/legacy-datasource.yml`;
const env = { ...process.env, COMPOSE_PROJECT_NAME: project };
Object.assign(env, {
  MYSQL_ROOT_PASSWORD: "test-only-root",
  MYSQL_USER: "workflow_test",
  MYSQL_PASSWORD: "test-only-password",
  MYSQL_DATABASE: "workflow_test",
  POSTGRES_USER: "workflow_test",
  POSTGRES_PASSWORD: "test-only-password",
  POSTGRES_DB: "workflow_test",
  MONGO_ROOT_USERNAME: "workflow@user",
  MONGO_ROOT_PASSWORD: "test-only:p@ss/w?rd#%&",
  GRAFANA_ADMIN_USER: "admin",
  GRAFANA_ADMIN_PASSWORD: "test-only-password",
  S3_ACCESS_KEY: "test-only",
  S3_SECRET_KEY: "test-only-password",
  MONGO_EXPRESS_USER: "test-only",
  MONGO_EXPRESS_PASSWORD: "test-only-password"
});
delete env.COMPOSE_PROFILES;
delete env.COMPOSE_FILE;
delete env.COMPOSE_ENV_FILES;
const sourceArgs = ["compose", "--project-directory", root, "--env-file", `${root}/.env.example`];
const source = JSON.parse(execFileSync("docker", [...sourceArgs, "--profile", "*", "config", "--format", "json"], { env, encoding: "utf8" }));
const selected = ["mysql", "postgres", "mongodb", "mongo-express", "redis", "prometheus", "grafana", "jaeger", "wiremock",
  "mysql-exporter", "postgres-exporter", "redis-exporter"];
for (const service of Object.values(source.services)) {
  assert.equal(service.container_name, undefined);
  for (const port of service.ports || []) assert.equal(port.host_ip, "127.0.0.1");
}
const portVariables = [
  "MYSQL_PORT", "REDIS_PORT", "POSTGRES_PORT", "MONGO_PORT", "MAILPIT_HTTP_PORT",
  "MAILPIT_SMTP_PORT", "PROMETHEUS_PORT", "GRAFANA_PORT", "REDISINSIGHT_PORT",
  "S3_PORT", "WIREMOCK_PORT", "ADMINER_PORT", "MONGO_EXPRESS_PORT",
  "JAEGER_PORT", "OTLP_GRPC_PORT", "OTLP_HTTP_PORT"
];
const alternativeEnv = { ...env, COMPOSE_PROJECT_NAME: `${project}-other` };
portVariables.forEach((variable, index) => { alternativeEnv[variable] = String(20000 + index); });
const alternative = JSON.parse(execFileSync("docker", [...sourceArgs, "--profile", "*", "config", "--format", "json"], { env: alternativeEnv, encoding: "utf8" }));
assert.notEqual(source.name, alternative.name);
for (const name of Object.keys(source.volumes)) assert.notEqual(source.volumes[name].name, alternative.volumes[name].name);
const published = Object.values(alternative.services).flatMap(service => service.ports || []).map(port => Number(port.published)).sort((a, b) => a - b);
assert.deepEqual(published, portVariables.map((_, index) => 20000 + index));
for (const database of ["mysql", "postgres", "redis"]) {
  const services = execFileSync("docker", [...sourceArgs, "--profile", `monitoring-${database}`, "config", "--services"], { env, encoding: "utf8" }).trim().split("\n");
  assert.ok(services.includes(`${database}-exporter`));
  assert.ok(services.includes("grafana") && services.includes("prometheus"));
  for (const other of ["mysql", "postgres", "redis"].filter(name => name !== database)) {
    assert.ok(!services.includes(`${other}-exporter`));
  }
}
const isolated = { services: {}, volumes: {} };
for (const name of selected) {
  const service = structuredClone(source.services[name]);
  delete service.profiles;
  service.restart = "no";
  for (const port of service.ports || []) port.published = "0";
  isolated.services[name] = service;
  for (const mount of service.volumes || []) {
    if (mount.type === "volume") isolated.volumes[mount.source] = {};
  }
}
writeFileSync(file, JSON.stringify(isolated));
const legacy = structuredClone(isolated);
legacy.services.grafana.volumes = legacy.services.grafana.volumes.filter(mount =>
  mount.target !== "/etc/grafana/provisioning/dashboards/default.yml" &&
  mount.target !== "/var/lib/grafana/dashboards");
legacy.services.grafana.volumes.find(mount =>
  mount.target === "/etc/grafana/provisioning/datasources/prometheus.yml").source = legacyProvisioning;
writeFileSync(legacyFile, JSON.stringify(legacy));
writeFileSync(legacyProvisioning, `apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
`);
const args = ["compose", "--project-directory", root, "--file", file, "--project-name", project];
function docker(...extra) {
  return execFileSync("docker", [...args, ...extra], { env, encoding: "utf8", timeout: 300000 });
}
function otherDocker(...extra) {
  return execFileSync("docker", [...args.slice(0, -1), `${project}-other`, ...extra], { env, encoding: "utf8", timeout: 300000 });
}
function databaseReadiness(service, variable, value) {
  const probe = source.services[service].healthcheck.test;
  assert.equal(probe[0], "CMD-SHELL");
  const options = value === undefined ? [] : ["-e", `${variable}=${value}`];
  return docker("exec", "-T", ...options, service, "sh", "-c", probe[1].replaceAll("$$", "$"));
}
function endpoint(service, port) {
  const value = docker("port", service, String(port)).trim();
  assert.match(value, /^127\.0\.0\.1:\d+$/);
  return `http://${value}`;
}
async function eventually(check, description) {
  let last;
  for (let attempt = 0; attempt < 60; attempt++) {
    try { return await check(); } catch (error) { last = error; }
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
  throw new Error(`${description}: ${last?.message}`, { cause: last });
}
async function json(url, options) {
  const response = await fetch(url, { signal: AbortSignal.timeout(5000), ...options });
  assert.equal(response.status, 200, `${url} status`);
  return response.json();
}
try {
  execFileSync("docker", ["compose", "--project-directory", root, "--file", legacyFile,
    "--project-name", project, "up", "-d", "grafana"], { env, encoding: "utf8", timeout: 300000 });
  const legacyGrafana = endpoint("grafana", 3000);
  const headers = { Authorization: `Basic ${Buffer.from("admin:test-only-password").toString("base64")}` };
  const previousSource = await eventually(async () =>
    json(`${legacyGrafana}/api/datasources/name/Prometheus`, { headers }),
  "Legacy Grafana provisioning");
  docker("up", "-d", "--wait", "--wait-timeout", "240");
  for (const [service, variable] of [["mysql", "MYSQL_PASSWORD"], ["postgres", "POSTGRES_PASSWORD"]]) {
    databaseReadiness(service);
    assert.throws(() => databaseReadiness(service, variable, "invalid-test-credential"),
      /Access denied|password authentication failed/,
      `${service} readiness must reject invalid credentials`);
  }
  assert.equal((await json(`${endpoint("grafana", 3000)}/api/health`)).database, "ok");
  const ready = await fetch(`${endpoint("prometheus", 9090)}/-/ready`);
  assert.equal(ready.status, 200);
  console.log("PASS: authenticated database probes reject invalid credentials; Grafana and Prometheus HTTP readiness succeeds");

  docker("exec", "-T", "mongodb", "mongosh", "--quiet", "--eval", `
    const admin = db.getSiblingDB("admin");
    if (!admin.auth(process.env.MONGO_INITDB_ROOT_USERNAME, process.env.MONGO_INITDB_ROOT_PASSWORD)) {
      throw new Error("Test MongoDB authentication failed");
    }
    db.getSiblingDB("credential_test").sentinel.insertOne({ verified: true });
  `);
  const mongoExpress = endpoint("mongo-express", 8081);
  const mongoHeaders = { Authorization: `Basic ${Buffer.from("test-only:test-only-password").toString("base64")}` };
  await eventually(async () => {
    const response = await fetch(`${mongoExpress}/db/credential_test`, {
      headers: mongoHeaders, signal: AbortSignal.timeout(5000)
    });
    assert.equal(response.status, 200);
    assert.match(await response.text(), /sentinel/);
  }, "Mongo Express database access with reserved credential characters");
  assert.equal((await fetch(mongoExpress, { signal: AbortSignal.timeout(5000) })).status, 401);
  console.log("PASS: Mongo Express accesses actual data with URI-reserved credentials and still requires UI authentication");
  otherDocker("up", "-d", "--wait", "redis");
  docker("exec", "-T", "redis", "redis-cli", "SET", "isolation-test", "first");
  otherDocker("exec", "-T", "redis", "redis-cli", "SET", "isolation-test", "second");
  assert.equal(docker("exec", "-T", "redis", "redis-cli", "GET", "isolation-test").trim(), "first");
  assert.equal(otherDocker("exec", "-T", "redis", "redis-cli", "GET", "isolation-test").trim(), "second");
  assert.notEqual(docker("port", "redis", "6379").trim(), otherDocker("port", "redis", "6379").trim());
  console.log("PASS: two simultaneous projects keep Redis data and host ports isolated; all 16 port overrides resolve");
  const wiremock = endpoint("wiremock", 8080);
  await eventually(() => json(`${wiremock}/dev/health`), "WireMock readiness");
  const error = await fetch(`${wiremock}/dev/error`);
  assert.equal(error.status, 503);
  assert.deepEqual(await error.json(), { error: "temporarily_unavailable" });
  const start = performance.now();
  assert.deepEqual(await json(`${wiremock}/dev/delay`), { status: "ok", delayMs: 1500 });
  assert.ok(performance.now() - start >= 1400, "Required 1.5s response delay");
  const first = await json(`${wiremock}/dev/customers?page=1`);
  const second = await json(`${wiremock}/dev/customers?page=2`);
  assert.equal(first.nextPage, 2);
  assert.equal(second.nextPage, null);
  assert.equal(first.items[0].id, 1);
  assert.equal(second.items[0].id, 2);
  await fetch(`${wiremock}/__admin/scenarios/reset`, { method: "POST" });
  const limited = await fetch(`${wiremock}/dev/rate-limit`);
  assert.equal(limited.status, 429);
  assert.equal(limited.headers.get("retry-after"), "1");
  assert.equal((await json(`${wiremock}/dev/rate-limit`)).retried, true);
  console.log("PASS: WireMock errors, measurable delay, pagination, and rate-limit recovery");

  const prometheus = endpoint("prometheus", 9090);
  docker("exec", "-T", "prometheus", "promtool", "check", "config", "/etc/prometheus/prometheus.yml");
  const dashboard = JSON.parse(readFileSync(`${root}/grafana/dashboards/databases.json`, "utf8"));
  for (const panel of dashboard.panels) {
    for (const target of panel.targets) {
      const expression = target.expr.startsWith("rate(") ? target.expr.slice(5).split("[")[0] : target.expr;
      await eventually(async () => {
        const result = await json(`${prometheus}/api/v1/query?query=${encodeURIComponent(expression)}`);
        assert.equal(result.status, "success");
        assert.ok(result.data.result.length > 0, `${expression} has actual data`);
        if (["mysql_up", "pg_up", "redis_up"].includes(expression)) {
          assert.ok(result.data.result.every(value => value.value[1] === "1"));
        }
      }, `Prometheus metric ${expression}`);
    }
  }
  const grafana = endpoint("grafana", 3000);
  await eventually(async () => {
    const provisioned = await json(`${grafana}/api/dashboards/uid/development-databases`, { headers });
    assert.equal(provisioned.dashboard.panels.length, 7);
    const sources = await json(`${grafana}/api/datasources`, { headers });
    const prometheusSource = sources.find(source => source.name === "Prometheus");
    assert.equal(prometheusSource.uid, previousSource.uid, "Existing data-source UID is preserved");
    assert.ok(sources.some(source => source.uid === "jaeger"));
    assert.equal(provisioned.dashboard.templating.list[0].name, "prometheus_source");
    for (const panel of provisioned.dashboard.panels) {
      assert.equal(panel.datasource.uid, "${prometheus_source}");
    }
    const query = await json(`${grafana}/api/ds/query`, {
      method: "POST",
      headers: { ...headers, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: "now-5m", to: "now",
        queries: [{
          refId: "A", datasource: { type: "prometheus", uid: prometheusSource.uid },
          expr: "redis_up", instant: true, intervalMs: 15000, maxDataPoints: 100
        }]
      })
    });
    assert.ok(query.results.A.frames.length > 0, "Grafana queries the preserved source successfully");
  }, "Grafana dashboard and data sources");
  console.log("PASS: all dashboard metric names have live data and Grafana provisions the dashboard");

  const otlp = endpoint("jaeger", 4318);
  const query = endpoint("jaeger", 16686);
  const traceId = "0123456789abcdef0123456789abcdef";
  const now = BigInt(Date.now()) * 1000000n;
  const payload = {
    resourceSpans: [{
      resource: { attributes: [{ key: "service.name", value: { stringValue: "infrastructure-trace-test" } }] },
      scopeSpans: [{ scope: { name: "infrastructure-test" }, spans: [{
        traceId, spanId: "0123456789abcdef", name: "test-request", kind: 2,
        startTimeUnixNano: String(now), endTimeUnixNano: String(now + 100000000n)
      }] }]
    }]
  };
  await eventually(async () => {
    const response = await fetch(`${otlp}/v1/traces`, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload), signal: AbortSignal.timeout(5000)
    });
    assert.equal(response.status, 200);
  }, "OTLP trace ingestion");
  await eventually(async () => {
    const response = await json(`${query}/api/traces/${traceId}`);
    assert.equal(response.data[0].spans[0].operationName, "test-request");
  }, "Jaeger trace retrieval");
  console.log("PASS: Jaeger accepts OTLP traces and serves them through the query API");
} catch (error) {
  console.error(error.message);
  console.error(docker("logs", "--tail", "30", "mysql", "postgres", "mongodb", "mongo-express", "jaeger", "mysql-exporter", "postgres-exporter", "prometheus", "grafana"));
  process.exitCode = 1;
} finally {
  otherDocker("down", "--volumes");
  docker("down", "--volumes");
  unlinkSync(file);
  unlinkSync(legacyFile);
  unlinkSync(legacyProvisioning);
  rmdirSync(directory);
}
