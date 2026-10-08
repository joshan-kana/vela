# Vela

A fast, beautiful, native, cross-platform client for YouTrack.

## Development

Enter the development environment:

```sh
nix develop -c $SHELL
```

Or use direnv to load it automatically when entering the repository.

Useful commands:

```sh
nix fmt          # alias: fmt
nix flake check  # alias: chk
```

Launch the pinned Android API 36 emulator:

```sh
nix run .#android-emulator
```

## macOS planning

Open **Planning** from My Work to switch between Timeline, Calendar, and Agenda.
Vela derives spans and deadlines from each project's YouTrack date fields;
issues without dates remain in the unscheduled section. Timeline bars can be
moved or resized by whole calendar days. The native Agenda supports `j`/`k`
navigation and `u`/`d` half-page jumps.

**Show calendars** optionally displays read-only system calendar events as
occupied time. Calendars named Tasks or YouTrack are excluded to avoid showing
mirrored issues twice. Vela does not create or modify calendar events.
