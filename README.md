# base

Reference container image for [agentd](https://github.com/tesserine/agentd)
agent sessions. Wolfi-based, minimal, ships with the agentd runner contract
and a working agent runtime.

## What's Inside

**OS layer:** [Wolfi](https://wolfi.dev) — glibc-based, zero-CVE target,
purpose-built for containers.

**agentd contract:** The runner expects the image to provide `/bin/sh`, `git`,
`useradd`, `gosu`, and `chown`. These are installed as Wolfi packages. The
runner enters through `/bin/sh -lc` with a generated script that creates an
unprivileged user, clones the target repository, and drops privileges before
executing the session command. The image sets no ENTRYPOINT or CMD — agentd
owns the entrypoint.

**Cognitive runtime:** [runa](https://github.com/tesserine/runa), built from
source. Loads methodology manifests, validates artifacts, enforces dependency
graphs.

**Agent runtime:** [Claude Code](https://claude.ai/code), pinned to a verified
Anthropic release binary. Authenticate headlessly by injecting
`ANTHROPIC_API_KEY` as a credential in your agentd agent configuration.

## Building

Deployment builds must pin source material to immutable refs: tags or full
commit SHAs. Do not build deployment images from `main`; mutable branch refs
can reuse stale container build layers while the remote branch has moved.
The shared release-candidate convention is defined in
[commons RELEASE.md](https://github.com/tesserine/commons/blob/main/RELEASE.md).

```bash
podman build \
  --build-arg BASE_REF=v0.1.2-rc.1 \
  --build-arg RUNA_REF=v0.1.2-rc.1 \
  -t tesserine/base:v0.1.2-rc.1 .
```

For local development, the defaults are usable, but they intentionally label
the base image ref as `local`:

```bash
podman build -t tesserine/base:local .
```

Inspect the image labels to confirm what was built:

```bash
podman inspect tesserine/base:v0.1.2-rc.1 | jq '.[0].Config.Labels'
```

Claude Code is intentionally pinned in the Dockerfile. Version bumps are manual
build-substrate changes so the release manifest signature, binary checksum,
image build, and runtime contract can be verified together. The built image
exposes `org.tesserine.base.ref`, `org.tesserine.runa.ref`, and
`org.tesserine.claude-code.version` labels for deployment inspection.

## Using with agentd

Reference this image in your agent configuration:

```toml
[[agents]]
name = "site-builder"
base_image = "localhost/tesserine/base"
methodology_dir = "../groundwork"
repo = "https://github.com/your-org/your-project.git"

[agents.command]
argv = ["claude", "-p", "--dangerously-skip-permissions"]

[[agents.credentials]]
name = "ANTHROPIC_API_KEY"
source = "AGENTD_ANTHROPIC_KEY"
```

Export the credential source in the daemon's environment before starting
agentd:

```bash
export AGENTD_ANTHROPIC_KEY="sk-ant-..."
agentd daemon --config /etc/agentd/agentd.toml
```

## Customizing

Fork this repo and modify the Dockerfile. Common customizations:

- **Different agent runtime:** Replace the Claude Code release binary with
  Codex (`npm i -g @openai/codex`), or any CLI that can receive prompts and
  produce file changes.
- **Additional tools:** Add language runtimes, linters, or build tools your
  agents need.
- **Different methodology:** The methodology is mounted read-only by agentd at
  runtime, not baked into the image. No image change needed to switch
  methodologies.

## Container Contract

The agentd runner makes these assumptions about the image:

| Requirement | Why | Provided by |
|-------------|-----|-------------|
| `/bin/sh` | Entrypoint shell for the generated setup script | `bash` (via `bash-binsh`) |
| `useradd` | Creates the unprivileged session user | `shadow` |
| `gosu` | Drops root privileges permanently before session command | `gosu` |
| `git` | Clones the target repository into the workspace | `git` |
| `chown` | Transfers home directory ownership to the session user | `coreutils` |

If you build a custom image, these five capabilities must be present.

## License

[MIT](LICENSE)
