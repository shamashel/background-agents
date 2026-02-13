# Background Agents: Open-Inspect

An open-source background agents coding system inspired by
[Ramp's Inspect](https://builders.ramp.com/post/why-we-built-our-background-agent).

## Overview

Open-Inspect provides a hosted background coding agent that can:

- Work on tasks in the background while you focus on other things
- Access full development environments with all tools engineers have
- Support multiple clients (web, Slack, Chrome extension)
- Enable multiplayer sessions where multiple people can collaborate
- Create PRs with proper commit attribution
- Use your choice of AI model — Anthropic Claude or OpenAI Codex via your ChatGPT subscription

## Security Model (Single-Tenant Only)

> **Important**: This system is designed for **single-tenant deployment only**, where all users are
> trusted members of the same organization with access to the same repositories.

### How It Works

The system uses a shared GitHub App installation for all git operations (clone, push). This means:

- **All users share the same GitHub App credentials** - The GitHub App must be installed on your
  organization's repositories, and any user of the system can access any repo the App has access to
- **No per-user repository access validation** - The system does not verify that a user has
  permission to access a specific repository before creating a session
- **User OAuth tokens are used for PR creation** - PRs are created using the user's GitHub OAuth
  token, ensuring proper attribution and that users can only create PRs on repos they have write
  access to

### Token Architecture

| Token Type       | Purpose                | Scope                            |
| ---------------- | ---------------------- | -------------------------------- |
| GitHub App Token | Clone repos, push code | All repos where App is installed |
| User OAuth Token | Create PRs, user info  | Repos user has access to         |
| WebSocket Token  | Real-time session auth | Single session                   |

### Why Single-Tenant Only

This architecture follows
[Ramp's Inspect design](https://builders.ramp.com/post/why-we-built-our-background-agent), which was
built for internal use where all employees are trusted and have access to company repositories.

**For multi-tenant deployment**, you would need:

- Per-tenant GitHub App installations
- Access validation at session creation
- Tenant isolation in the data model

### Deployment Recommendations

1. **Deploy behind your organization's SSO/VPN** - Ensure only authorized employees can access the
   web interface
2. **Install GitHub App only on intended repositories** - The App's installation scope defines what
   the system can access
3. **Use GitHub's repository selection** - When installing the App, select specific repositories
   rather than "All repositories"

## Architecture

```
                                    ┌──────────────────┐
                                    │     Clients      │
                                    │ ┌──────────────┐ │
                                    │ │     Web      │ │
                                    │ │    Slack     │ │
                                    │ │   Extension  │ │
                                    │ └──────────────┘ │
                                    └────────┬─────────┘
                                             │
                                             ▼
┌────────────────────────────────────────────────────────────────────┐
│                     Control Plane (Cloudflare)                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                   Durable Objects (per session)               │  │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌───────────────┐   │  │
│  │  │ SQLite  │  │WebSocket│  │  Event  │  │   GitHub      │   │  │
│  │  │   DB    │  │   Hub   │  │ Stream  │  │ Integration   │   │  │
│  │  └─────────┘  └─────────┘  └─────────┘  └───────────────┘   │  │
│  └──────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │              D1 Database (repo-scoped secrets)                │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────────────┬───────────────────────────────────┘
                                 │
                                 ▼
┌────────────────────────────────────────────────────────────────────┐
│                      Data Plane (Modal)                             │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                     Session Sandbox                           │  │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐                 │  │
│  │  │ Supervisor│──│  OpenCode │──│   Bridge  │─────────────────┼──┼──▶ Control Plane
│  │  └───────────┘  └───────────┘  └───────────┘                 │  │
│  │                      │                                        │  │
│  │              Full Dev Environment                             │  │
│  │        (Node.js, Python, git, Playwright)                     │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
```

## Packages

| Package                                 | Description                          |
| --------------------------------------- | ------------------------------------ |
| [modal-infra](packages/modal-infra)     | Modal sandbox infrastructure         |
| [control-plane](packages/control-plane) | Cloudflare Workers + Durable Objects |
| [web](packages/web)                     | Next.js web client (Kubernetes-hosted) |
| [shared](packages/shared)               | Shared types and utilities           |

## Getting Started

See **[docs/GETTING_STARTED.md](docs/GETTING_STARTED.md)** for deployment instructions.
For web deployment details, see **[docs/WEB_K8S_DEPLOYMENT.md](docs/WEB_K8S_DEPLOYMENT.md)**.

To understand the architecture and core concepts, read
**[docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md)**.

## Key Features

### Fast Startup

Sessions start near-instantly using Modal filesystem snapshots:

- Images rebuilt every 30 minutes with latest code
- Dependencies pre-installed and cached
- Sandboxes warmed proactively when user starts typing

### Multiplayer Sessions

Multiple users can collaborate in the same session:

- Presence indicators show who's active
- Prompts are attributed to their authors in git commits
- Real-time streaming to all connected clients

### Commit Attribution

Commits are attributed to the user who sent the prompt:

```typescript
// Configure git identity per prompt
await configureGitIdentity({
  name: author.githubName,
  email: author.githubEmail || generateNoreplyEmail(author.githubId, author.githubLogin),
});
```

### Multi-Provider Model Support

Choose the AI model that fits your task — Anthropic Claude or OpenAI Codex:

| Provider  | Models                                |
| --------- | ------------------------------------- |
| Anthropic | Claude Haiku, Sonnet, Opus            |
| OpenAI    | GPT 5.2, GPT 5.2 Codex, GPT 5.3 Codex |

OpenAI models work with your existing ChatGPT subscription — no separate API key needed. See
**[docs/OPENAI_MODELS.md](docs/OPENAI_MODELS.md)** for setup instructions.

### Repository Setup Scripts

Repositories can include a `.openinspect/setup.sh` script for custom environment setup:

```bash
# .openinspect/setup.sh
#!/bin/bash
npm install
pip install -r requirements.txt
```

- Runs automatically after git clone, before the agent starts
- Skipped when restoring from a snapshot (dependencies already installed)
- Non-blocking: failures are logged but don't prevent the session from starting
- Default timeout: 5 minutes (configurable via `SETUP_TIMEOUT_SECONDS` environment variable)

## License

MIT

## Credits

Inspired by [Ramp's Inspect](https://builders.ramp.com/post/why-we-built-our-background-agent) and
built with:

- [Modal](https://modal.com) - Cloud sandbox infrastructure
- [Cloudflare Workers](https://workers.cloudflare.com) - Edge computing
- [OpenCode](https://opencode.ai) - Coding agent runtime
- [Next.js](https://nextjs.org) - Web framework
