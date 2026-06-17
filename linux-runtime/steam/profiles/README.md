# Steam Profile Directory

This directory intentionally does not ship per-machine `.env` profile files.

Run:

```sh
waylandie-steam-profile bootstrap
```

The profile manager generates per-game profile files under:

```sh
${WAYLANDIE_STEAM_PROFILE_ROOT:-$HOME/.config/waylandie/steam}
```

Keeping generated profiles out of the source tree prevents one user's Steam,
DXVK, Turnip, FEX, or Qualcomm driver paths from becoming public defaults.
