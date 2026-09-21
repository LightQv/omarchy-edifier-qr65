# Release Checklist

Run this checklist against the exact commit intended for marketplace review.

## Automated Validation

```bash
omarchy plugin validate .
scripts/check-release-metadata.sh
scripts/lint-qml.sh
node --test service.test.cjs
bash -n scripts/*.sh
git diff --check
```

## Clean Checkout

- Confirm the candidate contains no symlinks, generated files, captures, APKs,
  auto-discovered agent instructions, or unexpected executables.
- Run every automated check from a fresh clone of the candidate commit.
- Install daemon release `v0.1.1` from reviewed commit
  `ef4d923106adcf9cbb80a087b306c9eb16fdf1fd` before adding the plugin.
- Add, enable, update, disable, and remove the plugin with Omarchy commands.
- Confirm plugin removal leaves the separately managed daemon untouched.

## Runtime Acceptance

- Confirm startup and eight-second status polling do not leave child processes.
- Exercise malformed, oversized, stalled, and nonzero helper responses.
- Confirm oversized output is stopped and never parsed.
- Confirm the external and QML deadlines stop a stalled helper.
- Confirm shell destruction stops an active helper.
- Verify Follow Theme, Static Color, brightness, matching, reapply, release, and resume.
- Confirm release and resume affect only `edifier-qr65.service` under `systemctl --user`.
- Verify one dark and one light theme and inspect the shell log for plugin errors.

## Publication

- Review the final tree for secrets and private identifiers.
- Tag the validated commit as `v<manifest version>` without moving an old tag.
- Push the commit and tag, then confirm CI passes at the exact SHA.
- Publish release notes from the matching changelog section.
- Freeze the submitted commit until marketplace review completes.
