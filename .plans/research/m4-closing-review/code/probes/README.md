# Reviewer A's thread probes (M4's closing review)

Three probes by M4's closing review's code reviewer (Opus), kept because the records cite their
figures:

- `engine-thread.sps`: an engine's remainder started on one thread completes on another.
- `handle-other-thread.sps`: a bare `call-with-open-handle`, swept at every fuel, each remainder
  finished on a forked thread. Before the fix its section ran on another thread in about 3 of 12
  trials; after it, every such resume is refused.
- `load-other-thread.sps`: `load-extension!`'s wrong-thread refusal, by `who`. Before the fix 99 of
  109 named `database-extension-loading?`; after it, every one names `load-extension!`.

Each reads `$PWD/../probes/ext` for the suites' extension, so run it from a copy of the tree one
level below a directory holding these probes as `probes/`. From a worktree's root, on the host,
make the copy with `tar --exclude=./build --exclude=./.git`, since the container has no `tar`, then
inside the container:

    scripts/guix-env sh -c 'cd build/x/tree && make deps && $CHEZ --libdirs src:tests:build/scheme-libs --program ../probes/handle-other-thread.sps'
