# Public repository

- Keep credentials, personal email addresses, private document URLs, server addresses, local absolute workspace paths, and user data out of tracked files, build logs, and release assets.
- Use the repository owner's GitHub noreply address for agent-authored commits. Do not inherit a personal email from global Git configuration.
- Run `python3 scripts/check-public.py` before committing. This check supplements manual review; it is not a comprehensive secret detector.
- After every project change, commit and push to the current branch's tracking remote before reporting delivery. The user has authorized this workflow; do not ask for confirmation again. If pushing fails, report the failure and do not claim the changes were pushed.
- Maintain private project plans and review records outside this public repository. Public README content should describe the app and build commands only.
- Keep local libraries, favorites, caches, signing identities, and generated artifacts untracked. CI artifacts must contain only clean build outputs and diagnostics.
