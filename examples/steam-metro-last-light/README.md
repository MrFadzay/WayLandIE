# Metro Last Light Redux Example

Steam AppID `287390` was the main live test game during the original WayLandIE
experiments, so the Steam profile manager ships several built-in profiles that
are useful for it:

```sh
waylandie-steam-profile bootstrap
waylandie-steam-profile hook 287390
waylandie-steam-profile list-profiles 287390
waylandie-steam-profile set 287390 turnip-current
waylandie-steam-profile launch 287390 --process metro.exe
```

For custom DXVK or Turnip builds, install a slot first:

```sh
waylandie-steam-install-dxvk-slot --appid 287390 --slot my-dxvk --activate ~/Downloads/dxvk-build.zip
waylandie-steam-install-turnip-slot --appid 287390 --slot my-turnip --activate ~/Downloads/turnip-build.tar.gz
```

The old one-machine split X11 and Wayland helper scripts are intentionally not
part of the public runtime. They depended on a specific desktop session and
should be recreated through documented profile flags instead.
