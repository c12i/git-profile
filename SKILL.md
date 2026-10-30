---
name: git-profile
description: Switch between git identities (user.name / user.email / signing key / SSH key / GitHub CLI account) and pin directories to a profile. Use when the user says "switch git user", "use my personal/work git profile", "which git user am I", "assign this folder to <profile>", "add a git profile", or invokes /git-profile.
---

# git-profile

A CLI (`git-profile`, on PATH via `~/.local/bin`) that keeps several git identities in one git-config-format file
and renders them into git's own config. Git does the switching, so it works in every shell, editor and
agent harness; this skill only tells an agent which command to run.

## Config: `~/.config/git-profile/profiles.gitconfig`

Git config format, read and written with `git config -f`, so no parser is needed and edits keep comments.

```ini
[git-profile]
	active = default                    # profile used outside any assigned dir

[profile "default"]
	name = your-handle
	email = you@example.com

[profile "work"]
	name = your-work-handle
	email = you@work.example
	signingkey = ~/.ssh/work.pub        # optional, overrides the global user.signingkey
	gh = your-work-handle               # optional GitHub CLI account (as in `gh auth status`)
	sshkey = ~/.ssh/work                # optional; git ssh offers only this key
	dir = ~/projects/work               # pinned dir (recursive); repeat the key for more
	gitconfig = pull.rebase true        # optional extra git key + value; repeatable
```

Add a profile by adding a `[profile "<name>"]` section (or `git-profile add`). After a hand edit, run
`git-profile apply`.

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

## Precedence (highest first)

1. Repo-local identity: `git-profile use <p> --local`
2. Directory pin: `dir` in a profile (git `includeIf "gitdir:..."`; applies inside repos only)
3. The `active` profile

## Commands

| Intent | Command |
|---|---|
| Which identity applies here | `git-profile current` (`--short` prints only the name) |
| List profiles and their dirs | `git-profile list` |
| Switch the global profile | `git-profile use <profile>` |
| This repo only | `git-profile use <profile> --local`; undo with `git-profile unlocal` |
| Pin dirs to a profile | `git-profile assign <profile> <dir>...` (a dir moves off any other profile) |
| Unpin dirs | `git-profile unassign <dir>...` |
| Add or update a profile | `git-profile add <name> --name N --email E [--signingkey K] [--gh U] [--sshkey K]` |
| Verify keys and logins against GitHub | `git-profile check [profile...]` |
| gh account in effect here | `git-profile gh-user` |
| Remove a profile | `git-profile remove <name>` |
| Regenerate after editing the config | `git-profile apply` |
| One-time setup on a new machine | `git-profile init` |

## Agent notes

- Run `git-profile current` before committing when the identity matters, and report what it prints.
- When a push is rejected for permissions or commits show Unverified, run `git-profile check` first.
- `use` without `--local` changes the identity for every repo outside the pinned dirs. Say so when you
  run it.
- A pinned dir beats `use`. If the user wants a pinned repo to use another identity, use `--local`
  or `assign`, not `use`.
- The config is not per terminal: `use` changes the active profile for every shell until switched back.

## Files

- `bin/gh`: gh wrapper; must precede the real gh on PATH (setup.sh does this).
- `scripts/git-profile`: the CLI (bash 3.2+, needs only git). `~/.local/bin/git-profile` links to it.
- `~/.config/git-profile/generated.gitconfig`: generated, included LAST from `~/.gitconfig`.
- `~/.config/git-profile/profiles/<name>.gitconfig`: generated per profile, targets of the `includeIf`s.
- `init` backs up `~/.gitconfig` to `~/.gitconfig.bak-git-profile` and removes `user.name`/`user.email`
  from it (the include would shadow them anyway).
