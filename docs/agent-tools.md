# AI assistant tools

[Documentation index](./README.md)

## Repository instructions

[Copilot instructions](../.github/copilot-instructions.md) describe the stack,
focused validation commands, operational safeguards, and application integration.
They guide the assistant; they do not enforce access controls.

## Playwright MCP in VS Code

The workspace [MCP configuration](../.vscode/mcp.json) uses Microsoft's official
Playwright MCP package. It runs headless for remote/Linux development and uses
isolated, in-memory browser sessions rather than a saved personal browser profile.
This is not a security sandbox.

Prerequisites:

- Node.js 18+ and `npx` available to the VS Code extension host. With remote
  development, install these on the remote host, not just your local machine.
- Network access to npm on first launch and when resolving a newer package.
- A supported browser and its Linux system dependencies on the same host.

Open this workspace in VS Code, run **MCP: List Servers**, select `playwright`,
and start it. Review the trust prompt and approve only tools needed for the task.
If a browser is missing, use the server's browser-install tool when offered;
missing operating-system libraries may require administrator installation.
If `npx` cannot be found, ensure VS Code inherits the Node installation's PATH.

The configuration intentionally follows `@latest`; updates can change behavior.
For repeatable tooling, replace `latest` with a tested package version.
No application credentials or private environment files are passed to this server.
Only browse local development applications or explicitly approved destinations;
do not send private code, credentials, or database contents to external sites.
Browser access can perform writes: approve destructive interactions separately.

## Container operations

Container management remains through existing Docker CLI/container tools, not a
Docker-engine MCP server. Installing Docker MCP Toolkit alone does not provide
container-management tools, and this workspace does not enable gateway servers
or grant an additional server access to the Docker socket.

Use the project and environment selectors documented in
[project isolation](./project-isolation.md). Prefer read-only diagnostics and
bounded logs; do not remove volumes, restart unrelated services, or pull image
upgrades as an incidental tooling check.

## References

- [VS Code MCP configuration](https://code.visualstudio.com/docs/agent-customization/mcp-servers)
- [Official Playwright MCP documentation](https://github.com/microsoft/playwright-mcp)
