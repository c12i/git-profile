# git-profile

Switch between git identities (name, email, signing key, SSH key, GitHub CLI account) and pin directories to an identity.

Git does the switching itself: profiles are rendered into git's own config (`includeIf "gitdir:..."`
for pinned directories), so the right identity applies in every terminal, editor, GUI client and AI
agent, whether or not `git-profile` is installed there. The CLI is plain bash (3.2+) and needs only git;
`gh` and `ssh` are used only by the features that name them.

## Install

Copy or clone this folder onto the machine (anywhere), then:

```bash
./setup.sh                                    # asks for your first profile if you have no config
./setup.sh --config path/to/profiles.gitconfig   # reuse a config from another machine
```

`setup.sh` is safe to re-run. It:

1. Links the folder to `~/.agents/skills/git-profile` (the canonical copy), and from there into
   `~/.claude/skills/` and `~/.codex/skills/` when those harnesses are installed.
2. Links the CLI to `~/.local/bin/git-profile` (so `git-profile ...` and `git profile ...` both work).
3. Creates `~/.config/git-profile/profiles.gitconfig` if it is missing.
4. Puts `bin/` (the gh wrapper) first on PATH in your shell's login and rc files (skip with `--no-shell`).
5. Runs `git-profile init`: backs up `~/.gitconfig` to `~/.gitconfig.bak-git-profile`, removes its
   `user.name`/`user.email`, and appends an include of the generated config as the last line.

Uninstall with `./setup.sh --uninstall`: removes the links, the include and the PATH block, writes the
active profile back as your global git identity, and keeps your config.

Then open a new shell and run `git-profile check`.

### Moving to another device

Your profiles are one file; keys and gh logins are not in it.

1. Copy this folder and `~/.config/git-profile/profiles.gitconfig`, then run
   `./setup.sh --config profiles.gitconfig`.
2. Put each profile's `sshkey` and `signingkey` files at the same paths (they are secrets: copy them
   over a secure channel or generate new ones and register them on GitHub).
3. Log each `gh` account in: `gh auth login`.
4. Open a new shell and run `git-profile check`; every line should read `ok`.

Write paths in the config with `~` (`sshkey = ~/.ssh/work`) so they work under any home directory. The
`add` command receives paths already expanded by your shell; quote them (`--sshkey '~/.ssh/work'`) to
keep the `~`. Pinned dirs that do not exist on a machine are harmless: they simply never match.

## Config

`~/.config/git-profile/profiles.gitconfig` (override with `GIT_PROFILE_CONFIG`). See
[`profiles.example.gitconfig`](profiles.example.gitconfig).

```ini
[git-profile]
	active = default

[profile "default"]
	name = your-handle
	email = hello@example.com

[profile "work"]
	name = me-work
	email = me@work.example
	signingkey = ~/.ssh/work.pub        # optional
	gh = me-work                        # optional GitHub CLI account
	sshkey = ~/.ssh/work                # optional SSH key for git over ssh
	dir = ~/projects/work               # repeat for more dirs
	gitconfig = pull.rebase true        # optional extra git keys
```

## SSH keys

`sshkey = <private key>` makes git offer only that key for every ssh connection in the profile
(`core.sshCommand = ssh -i <key> -o IdentitiesOnly=yes`), so `git@github.com:` remotes push and pull as
that profile's GitHub account. Remotes using an ssh host alias (`git@work:org/repo`) still work. HTTPS
remotes are not affected; switch them with `git remote set-url origin git@github.com:org/repo.git`.

`git-profile check` asks GitHub, read-only, which account each profile's key logs in as, whether its gh
account is logged in, and whether its signing key is registered as a signing key on that account
(otherwise commits show "Unverified"). Register one with
`gh auth refresh -s admin:ssh_signing_key && gh ssh-key add <key>.pub --type signing`.

## GitHub CLI (gh) accounts

A profile can name a GitHub account with `gh = <user>`, the name `gh auth status` shows. Log each one
in once with `gh auth login` (gh keeps several accounts per host).

- `git-profile use <p>` also runs `gh auth switch --user <gh>`, so gh's global account follows.
- Per directory: `bin/gh` wraps the real gh and passes the account of the profile in effect as
  `GH_TOKEN` (from `gh auth token --user`). `setup.sh` puts `bin/` first on PATH in `.zprofile` and
  `.zshrc` (or `.bash_profile` and `.bashrc`). It passes through untouched when `GH_TOKEN`/`GITHUB_TOKEN`
  is set, for `gh auth ...`, or when the account is not logged in (with a warning).
- `git push` over HTTPS still uses your git credential helper, not gh. Pushing per account goes through
  SSH (`sshkey`, above) or `gh auth setup-git`.

## Which identity applies (highest first)

1. Repo-local: `git-profile use <p> --local`
2. Pinned dir: a profile's `dir`
3. The active profile: `git-profile use <p>`

The active profile is global, not per terminal: `use` changes it for every shell until you switch back.

## Commands

| Command | Does |
|---|---|
| `git-profile` / `git-profile current [--dir D] [--short]` | identity in effect here |
| `git-profile list` | profiles, their pinned dirs, gh accounts and ssh keys |
| `git-profile use <p>` | set the active profile |
| `git-profile use <p> --local` / `git-profile unlocal` | set / drop this repo's own identity |
| `git-profile assign <p> <dir>...` / `unassign <dir>...` | pin / unpin dirs |
| `git-profile add <p> --name N --email E [--signingkey K] [--gh U] [--sshkey K]` | add or update a profile |
| `git-profile check [p...]` | verify ssh key, gh login and signing key against GitHub |
| `git-profile remove <p>` | delete a profile |
| `git-profile apply` | regenerate after a hand edit |
| `git-profile init` | wire into `~/.gitconfig` (setup does this) |

## Status line (optional)

Show the identity in effect in a shell prompt or the Claude Code status line:

```bash
if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    p=$(git-profile current --dir "$dir" --short 2>/dev/null)
    [[ -n "$p" ]] && printf ' \e[35mgit:%s\e[0m' "$p"
fi
```

`--short` prints the profile name, or `?<email>` when the identity matches no profile.

## Files

| Path | What |
|---|---|
| `scripts/git-profile` | the CLI |
| `bin/gh` | gh wrapper (per-dir GitHub account) |
| `setup.sh` | installer |
| `SKILL.md` | instructions for AI agents (Claude Code, Codex, any harness reading `~/.agents/skills`) |
| `~/.config/git-profile/profiles.gitconfig` | your profiles (yours to keep and copy) |
| `~/.config/git-profile/generated.gitconfig`, `profiles/*.gitconfig` | generated, do not edit |
