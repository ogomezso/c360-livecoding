# Quick Start

The build and teardown instructions now live in one place: **[BUILD_GUIDE.md](../BUILD_GUIDE.md)**.

```bash
make up          # from the repo root: check → infra → MCP env → data → wire your AI assistant
make status      # confirm you are demo-ready
make reset       # between runs
make down        # tear everything down
```

- Prerequisites and credentials: [BUILD_GUIDE §2](../BUILD_GUIDE.md#2-prerequisites)
- Step-by-step build: [BUILD_GUIDE §4](../BUILD_GUIDE.md#4-step-by-step)
- Teardown: [BUILD_GUIDE §7](../BUILD_GUIDE.md#7-teardown)
- Terraform details: [terraform-confluent-aws/README.md](terraform-confluent-aws/README.md)
- MCP tools: [MCP_TOOLS_REFERENCE.md](MCP_TOOLS_REFERENCE.md)
