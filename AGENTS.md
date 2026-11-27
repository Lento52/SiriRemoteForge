# Project operating rules

These rules are non-negotiable for every local macOS App build and test deployment.

1. The only App used for live testing is `/Applications/HyperVibe.app`.
2. After compiling and packaging a user-test build, install that verified bundle at
   `/Applications/HyperVibe.app`. Never launch `app/HyperVibe.app` as the live App.
3. Preserve the existing stable `siriRemote Local Signing` identity where provisioned. For this
   personal fork, an explicitly selected Apple Development identity is also supported through
   `HYPERVIBE_SIGN_MODE=apple-development` and `HYPERVIBE_SIGN_IDENTITY` (certificate SHA-1).
   Reuse that identity for subsequent builds. Verify the packaged bundle's signature before
   replacing the installed App.
4. Never silently fall back to ad-hoc signing for a local development build. If the stable identity
   is unavailable or signature verification fails, stop before installation or restart and tell the
   user.
5. Restart only after installation and signature verification, then confirm the single running UI
   process executes `/Applications/HyperVibe.app/Contents/MacOS/HyperVibe`.
6. Treat HyperVibe as an always-on App. Unless the user explicitly asks to stop it, finish every
   local App build, installation, configuration change that needs a reload, or user-test handoff by
   ensuring `/Applications/HyperVibe.app` is running as exactly one UI process. Do this
   automatically; never wait for the user to ask for the App to be started.

Public release artifacts may use their explicitly requested release signing workflow, but must not
be substituted for the stable-signed local development App.
