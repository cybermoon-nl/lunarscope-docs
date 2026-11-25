# Fix (0.8.0): SMTP settings and other secrets can't end up in git

## Request

"The SMTP settings may absolutely not be in git."

## Checked first

- No real `smtp.toml` in any repo (master, agent, modules, docs), neither in
  the working folders nor anywhere in the git history (`git log --all`).
- The only SMTP file in git is `install/smtp.toml.example`; its whole history
  only ever held the example values (`smtp.example.nl`,
  `replace-with-the-smtp-password`).
- The demo (`lunarscope-demo`, no git) holds only the example too, and
  `deploy/upload.sh` copies only the binaries, the unit, the Caddyfile and
  the scripts — never an `smtp.toml`.

## Fix: three layers

| Layer | Where | What it does |
|-------|-------|--------------|
| `.gitignore` | master, agent, modules, docs, and the demo folder | `smtp.toml`, `*.smtp.toml`, `admin-token`, `dashboard-password`, `update-signing.key` are ignored; `*.example` stays tracked |
| `.gitleaks.toml` | master, agent, modules (used by the CI job "Gitleaks secret scan") | Default rules plus: `lunarscope-smtp-file` (any `smtp.toml` / `x.smtp.toml` in git), `lunarscope-update-signing-key` (the release signing key), `lunarscope-toml-password` (a `password = "…"` in a `.toml` file; only values starting with `replace-with-` are allowed, i.e. the example). Catches `git add -f` and filled-in copies under another name |
| `sync-from-master.sh` | demo | Never copies those files from the repo folders into the demo |

## Checks

| Check | Result |
|-------|--------|
| `git check-ignore` on `smtp.toml` and `install/smtp.toml` | ignored; `install/smtp.toml.example` not ignored |
| Throwaway git repo with the new `.gitleaks.toml`, gitleaks 8.30.1 (CI image) | only the example: no leaks; a filled-in copy `install/prod.toml`: `lunarscope-toml-password`; `smtp.toml` and `update-signing.key` added with `-f`: `lunarscope-smtp-file`, `lunarscope-update-signing-key` (an empty key file is skipped by gitleaks; a real one is found) |
| gitleaks on master, agent and modules with the new config (full history) | no leaks, so CI stays green |
| `sync-from-master.sh` with an `smtp.toml` placed in the master folder | not copied into the demo; sync OK (375 tests) |
