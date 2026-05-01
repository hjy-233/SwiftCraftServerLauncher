# Contributing Guide 📘
  [🇨🇳简体中文](../CONTRIBUTING.md) | 🇬🇧English

Welcome to **SwiftCraftServerLauncher**! We’re so glad you’re here 🙌. This guide will help you contribute effectively and ensure your work is smoothly integrated.

---

## 1. Code of Conduct ✨

* **Be respectful**: stay kind, constructive, and professional.
* **Inclusive**: all backgrounds and skill levels are welcome.
* **Clear communication**: describe issues and PRs in a way others can easily understand.

---

## 2. Reporting Issues 🐞

When you find a bug or have a suggestion:

1. Open a new issue on GitHub.
2. Use a clear title, e.g.:

   > “\[BUG] Crash on macOS 14.1 – Java path not found”
3. Include:

   * OS version (e.g. macOS 14.1)
   * SwiftCraftServerLauncher version (release or commit hash)
   * Steps to reproduce → Expected behavior → Actual behavior
   * Logs, screenshots, or crash reports if available

---

## 3. Submitting Code (Pull Requests) 🚀

Contribution flow:

Fork `dev` branch → create a feature branch (naming: `feat/...`, `fix/...`, `docs/...`, `chore/...`) →
if remote `dev` has new commits, merge `origin/dev` into your feature branch first, resolve conflicts, then continue →
open a PR with base branch `dev`, and describe both change details and validation steps →
merge only after `dev` CI/checks pass.

---

## 4. Code Style & Quality 🌱

* Language: **Swift** with **SwiftUI**
* Follow Swift naming conventions (CamelCase, clear identifiers)
* Add comments for public APIs or complex logic
* Respect project structure (don’t scatter files randomly)
* Write tests when appropriate
* Handle edge cases gracefully (avoid crashes)

---

## 5. Commit Convention 📝

Commit messages contain `Header`, `Body`, and `Footer`:

```
<type>(<scope>): <subject>

<body>

<footer>
```

`Header` is required. `Body/Footer` are optional.
Keep each line within 72 chars when possible, max 100 chars.

`Header` format:

`<type>(<scope>): <subject>`

Allowed `type` values:

* `feat` new feature
* `fix` bug fix
* `docs` docs only
* `style` formatting only (no runtime change)
* `refactor` refactor
* `test` tests
* `chore` build/tooling changes

`scope` is optional (for example: `cli`, `tui`, `log`, `server`).

`subject` rules:

* Start with a verb in present tense (for example `change`, not `changed`)
* Lowercase first letter
* No trailing period
* Prefer <= 50 chars

`Footer` is used only for:

* Breaking changes: `BREAKING CHANGE: <reason>`
* Closing issues: `Closes #123` or `Closes #123, #245`

Revert format:

```
revert: <original header>

This reverts commit <hash>.
```

Optional Commitizen setup:

```bash
npm install -g commitizen
commitizen init cz-conventional-changelog --save --save-exact
```

---

## 6. Branching Rules 🌲

* `dev`: main development branch for daily feature/fix integration
* `main`: stable branch, updated only for releases
* Always create feature branches from `dev` (`feat/...`, `fix/...`, `docs/...`, `chore/...`)
* All PRs should target `dev` as the base branch

---

## 7. Local Development Setup 💻

* Use the latest stable **Xcode** (version specified by project)
* Ensure your Swift version matches project requirements
* Install the required **Java runtime** if needed (for Minecraft launching features)
* Build, run, and test before submitting your contribution

---

## 8. Merging & Releases 📦

* Maintainers review PRs before merging into `dev`
* For a stable release, merge `dev` into `main`, then create release tags on `main`
* Releases are tested to confirm no major bugs remain

---

## 9. Thank You! 💖

Every issue, PR, or suggestion makes this project better.
We deeply appreciate your time and effort in contributing.
