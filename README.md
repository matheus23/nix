# My personal nix setup

I'm running [NixOS](https://nixos.org/).

Most of my installed programs, packages and configuration lives in `.nix` configuration files.
I'm uploading these files here so they're persisted & when I'll need to set up a new machine, I can share configs and rebuild the environment I'm used to.

## How to: System Updates

(Writing this down mainly so I can RTFM for myself.)
You wish it were easy. Maybe I'm just doing it wrong. Oh well, anyhow here we go:

I have a bunch of nix channels:
```sh
$ sudo nix-channel --list
home-manager https://github.com/nix-community/home-manager/archive/release-23.11.tar.gz
nix-ld https://github.com/Mic92/nix-ld/archive/main.tar.gz
nixos https://channels.nixos.org/nixos-23.11
nixos-hardware https://github.com/NixOS/nixos-hardware/archive/master.tar.gz
nixos-unstable https://nixos.org/channels/nixos-unstable
```

They need to be set to the newest versions:
```sh
$ sudo nix-channel --add https://channels.nixos.org/nixos-24.05 nixos
$ sudo nix-channel --add https://github.com/nix-community/home-manager/archive/release-23.11.tar.gz home-manager
```

And we can update them & the rest while we're at it:
```sh
$ sudo nix-channel --update
this derivation will be built:
  /nix/store/1zr4pzspghlzlx2d8839g391khy83yv6-home-manager-24.05.tar.gz.drv
building '/nix/store/1zr4pzspghlzlx2d8839g391khy83yv6-home-manager-24.05.tar.gz.drv'...
unpacking channels...
```

And let's do this for non-sudo as well:
```sh
$ nix-channel --list
nixos https://channels.nixos.org/nixos-23.11
$ nix-channel --add https://channels.nixos.org/nixos-24.05 nixos
$ nix-channel --update
unpacking channels...
```

Sweet.
Now I can rebuild my system:

```sh
$ sudo nixos-rebuild switch --upgrade # not sure if that upgrade is needed or not
```

(At some point I also updated the `hardware-configuration.nix` via `nixos-generate-config` and playing around with the symlinks so it actually runs through. That may or may not be necessary the next time, too.)
(Next time: This was not necessary. Instead there were a couple of deprecations in configuration.nix I was working through, but the error messages proved helpful.)

Now pray that it works & reboot 8-)

## How to: Non-major Updates

Sometimes I need new packages (signal-desktop, nodejs, etc.) and want to update them,
but there might not have been a new major release yet.
In that case, I update my nix-channels and rebuild:

```sh
$ sudo nix-channel --update
$ nix-channel --update
$ sudo nixos-rebuild switch
```
