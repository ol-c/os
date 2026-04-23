  # Secure Local Accounts, Encrypted Homes, and Local-Only Power Controls

  ## Summary

  Build local-user auth around standard Linux/NixOS primitives instead of custom browser auth: native greeter, PAM-backed login, systemd-logind
  sessions, polkit for privileged actions, and systemd-homed for per-user encrypted home directories. Replace the current demo autologin path with
  a native first-boot owner setup, then a normal greeter-driven login flow that starts a per-user browser session.

  This first version should support:

  - first-boot creation of one owner account
  - later login/logout for owner and standard users
  - per-user encrypted home directories that unlock at login and deactivate at logout
  - encrypted homes suspending with system suspend
  - owner-only account management in the browser System UI
  - shutdown/restart from the greeter and from logged-in sessions
  - suspend from logged-in sessions only
  - per-user browser, terminal, editor, and home-directory state
  - a dedicated user-system design document that records the chosen decisions, boundaries, and rationale

  All account-management, session, and power-control APIs must be local-only. They must not be reachable or invokable by arbitrary websites.

  ## Key Changes

  ### 1. Native auth, session, and encrypted-home model

  - Replace services.getty.autologinUser = "demo" and the shell-driven startx path with a native greeter, using greetd with a minimal greeter
    (tuigreet by default).
  - Adopt systemd-homed as the account and encrypted-home mechanism for human users.
  - Use one explicit session launcher script, ol-c-session, that starts the current X11 + matchbox + Firefox environment for the authenticated user
    after that user’s home has been activated.
  - Move ol-c-ui and ol-c-terminal out of the hard-coded demo system-user model and into the logged-in user session, so terminal/editor/file access
    always run with that user’s permissions and mounted home.
  - Keep service/system accounts declarative in Nix. Treat human accounts as mutable local homed users, not repo-declared users.

  ### 2. First-boot owner provisioning

  - On a machine with no owner account, boot into a native setup flow before normal login.
  - That setup flow creates the first normal systemd-homed user, marks it as the owner/admin account, grants admin capability, provisions its
    encrypted home, and sets its login/unlock password.
  - Treat the login password and encrypted-home unlock credential as the same credential in v1, consistent with the systemd-homed model.
  - After setup completes, switch to the normal greeter flow and never show setup again unless machine state is reset.
  - Add a deterministic test-prefill path that can create the first owner non-interactively from controlled test input, so automated tests bypass
    manual password entry.

  ### 3. Persistence and account storage

  - Persist account state and encrypted home state as durable machine state under the systemd-homed model: user identity, password-backed unlock
    metadata, admin/owner metadata, and per-user homes/browser profiles.
  - Stop generating the shared /home/demo/.mozilla/... profile in activation. Firefox profile/bootstrap should happen per real user inside that
    user’s activated home.
  - Keep browser-shell defaults declarative, but store user-specific mutable state in the user’s encrypted home.
  - Record owner identity separately from generic admin capability so the browser Accounts page can apply simple owner-only policy even if more
    roles are added later.

  ### 4. Authorization and privileged actions

  - Use systemd-logind as the source of session truth and for power actions.
  - Use polkit to authorize privileged operations. Do not grant the browser UI raw root access.
  - Policy for v1:
      - any authenticated local logged-in user may shutdown, restart, and suspend
      - pre-login greeter may expose shutdown and restart
      - only the owner account may create users, delete users, reset other users’ passwords, or grant/revoke admin capability
      - standard users may change only their own password and view their own session info
  - Implement a tightly scoped privileged backend/broker for browser account-management actions rather than shelling out broadly from the UI
    service.

  ### 5. Encrypted-home behavior and constraints

  - Design around systemd-homed semantics explicitly:
      - a user’s encrypted home activates on successful login
      - the home deactivates when the user’s last session ends
      - changing a user password must go through the supported homed path so login and home-unlock credentials stay consistent
  - Choose the secure suspend behavior now:
      - when the system suspends, user homes should suspend/lock as part of the sleep flow rather than remaining active across suspend
  - Treat compatibility consequences as part of the design:
      - user-session services must tolerate home activation/deactivation cleanly
      - browser, terminal, and editor state should not rely on a permanently mounted shared home
      - account-management flows must use homed-aware tooling rather than editing passwd/shadow files directly

  ### 6. Local-only browser UI and API contract

  - Extend the System page with:
      - Session: current user, logout
      - Power: shut down, restart, suspend
      - Accounts: list users, create user, delete user, change password, toggle admin capability
  - Keep power actions and account management as explicit API calls from the browser UI.
  - Add/extend endpoints along these lines:
      - POST /api/system/session/logout
      - POST /api/system/power/shutdown
      - POST /api/system/power/restart
      - POST /api/system/power/suspend
      - GET /api/system/accounts
      - POST /api/system/accounts
      - POST /api/system/accounts/:username/password
      - POST /api/system/accounts/:username/role
      - DELETE /api/system/accounts/:username
  - Enforce local-only access for these routes:
      - bind the privileged HTTP listener to loopback only
      - accept requests only for the https://localhost origin used by the first-party UI
      - reject missing or foreign Origin values for state-changing endpoints
      - do not enable permissive CORS on privileged routes
      - require a first-party anti-CSRF mechanism for browser-issued privileged requests, even from localhost
      - keep privileged routes unavailable on any future remote or host-exposed UI surface unless a separate auth design explicitly adds them
  - Keep terminal/editor available to all logged-in users by default; authorization stays tied to Unix user permissions and explicit privileged
    APIs.

  ### 7. User-system design documentation

  - Add a dedicated design document, for example docs/user-system.md, separate from AGENTS.md, that is the authoritative record for user-system
    decisions.
  - Document:
      - chosen primitives (greetd, PAM integration, systemd-homed, logind, polkit)
      - owner vs standard-user model
      - first-boot owner setup behavior
      - encrypted-home lifecycle at login, logout, password change, and suspend
      - per-user session and profile behavior
      - browser-visible account-management scope
      - local-only and anti-CSRF security requirements for privileged APIs
      - logout/shutdown/restart/suspend policy
      - deferred items such as lock/unlock, remote management, and richer role models
  - Update AGENTS.md to reference that document and summarize only milestone-level consequences, so the detailed user-system design has one clear
    home.

  ## Test Plan

  - Native setup tests:
      - fresh machine shows first-boot owner setup instead of autologin
      - completing setup creates the owner and skips setup on later boot
      - test-prefill path creates the owner non-interactively
  - Login/session tests:
      - greeter accepts valid owner and standard-user passwords
      - logout returns to greeter
      - each user gets an isolated encrypted home and Firefox profile
      - terminal/editor run as the logged-in user, not as a shared service user
  - Encrypted-home tests:
      - user home is unavailable before login and activated after successful login
      - user home deactivates after logout/last-session exit
      - password change keeps login and home-unlock behavior consistent
      - suspend path locks/suspends homes according to the chosen policy
  - Authorization tests:
      - owner can manage accounts
      - standard user cannot create/delete users or change another user’s password
      - privileged API accepts https://localhost requests from the first-party UI
      - privileged listener is not reachable on non-loopback addresses
  - Power tests:
      - greeter exposes shutdown/restart but not suspend
      - logged-in user can trigger shutdown/restart/suspend through the browser API
      - API rejects unauthorized callers deterministically
  - Documentation tests:
      - the dedicated user-system design document exists and reflects the implemented decisions
      - Nix/build tests assert autologin removal, greeter enablement, homed wiring, polkit/logind wiring, loopback binding, and per-user session
        launch wiring
      - VM smoke tests cover first boot, owner creation, second-user creation, logout/login swap, encrypted-home behavior, and a power-action path

  ## Assumptions And Defaults

  - Use greetd as the default greeter implementation because it is minimal and keeps the session boundary explicit.
  - Use systemd-homed for human users and encrypted homes, rather than a boot-unlocked shared /home.
  - Use the user’s login password as the encrypted-home unlock credential in v1.
  - Suspend should lock/suspend user homes rather than leaving them active across sleep.
  - Add a dedicated doc such as docs/user-system.md as the primary design record for this subsystem.
  - This plan overlaps Milestone 5 foundations because first-boot setup and durable user state are required for secure local accounts.
  - Reference basis for the security-sensitive choices:
      - NixOS manual on local user management: https://nixos.org/manual/nixos/stable/
      - pam_systemd_home behavior, including login-mounted homes and suspend handling:
        https://www.freedesktop.org/software/systemd/man/latest/pam_systemd_home.html
      - homectl / systemd-homed encrypted-home model: https://www.freedesktop.org/software/systemd/man/devel/homectl.html
      - NixOS wiki/manual references for greetd: https://nixos.wiki/wiki/Greetd
      - systemd-logind power/session model: https://wiki.nixos.org/wiki/Systemd/logind