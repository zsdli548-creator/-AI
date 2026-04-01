# -AI

Cross-platform one-click installer scripts for:

- OpenClaw API setup
- Codex + Claude Code API setup

## OpenClaw Deploy Packages

Download one of these ready-to-use bundles:

- `OpenClaw-Windows-OneClick.zip`
- `OpenClaw-macOS-OneClick.zip`
- `OpenClaw-Linux-OneClick.zip`

Each package already contains the matching installer script, shared
`openclaw-api-setup.env`, and a user-facing usage guide.

This repository intentionally includes only the installer project files from the local workspace.
Desktop documents, PDFs, images, runtime folders, and local secret state are excluded.

## Files

- `install-openclaw-api.ps1`
- `install-openclaw-api.sh`
- `run-install-openclaw-api.cmd`
- `run-install-openclaw-api.command`
- `openclaw-api-setup.env`
- `README-openclaw-one-click.md`
- `Windows-install-codex-claude.ps1`
- `macOS-Linux-终端版-安装Codex和Claude配置.sh`
- `Windows-双击我-安装Codex和Claude配置.cmd`
- `macOS-双击我-安装Codex和Claude配置.command`
- `使用说明-先看这个.md`

## Notes

- No API keys or auth tokens are stored in this repository.
- Users are prompted to enter their own credentials during setup.
