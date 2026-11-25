## What

<!-- One or two sentences: what changes, and why. Link the issue if there is one. -->

## Tested on

<!-- CI runs Linux x86_64 only. Say where else you ran `make test`, and on which SQLite. -->

## Checklist

- [ ] `make test` passes locally
- [ ] A behaviour change comes with a test I watched fail without it
- [ ] The title is a Conventional Commit (`feat:`, `fix:`, `docs:`, …)
- [ ] A new export has its type comment and its entry in `docs/reference.md`
- [ ] A new suite ends with the shared exit form, and is in a memory shard
- [ ] `README.org` and `docs/` match, if what users see changed
- [ ] `CHANGELOG.md` has an entry under `[Unreleased]`, if users can see the change
