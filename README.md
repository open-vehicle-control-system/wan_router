# WanRouter

Simple NAT router for the Citronics Lime, a carrier board for the Fairphone 2
mainboard (Nerves, `nerves_system_fairphone2`). It shares two upstream
internet connections — a 4G modem and a WiFi client — with downstream devices
plugged into Ethernet (`eth0`).

- **WAN — `wwan0`**: in-kernel QMI modem, driven by
  [`vintage_net_qmi`](https://github.com/mlainez/vintage_net_qmi) on top of
  [`qmi`](https://github.com/mlainez/qmi). APN is hardcoded to `simbase` in
  `config/target.exs` — change `service_providers` for other carriers.
- **WAN — `wlan0`**: WiFi client (station) that joins an upstream access point
  via DHCP. Credentials come from `config/.env.exs` (gitignored); see
  [WiFi setup](#wifi-setup). If no credentials are set, `wlan0` is left
  unconfigured and the device runs cellular-only.
- **WAN priority**: `WanRouter.RouteMetric` (wired in via vintage_net's
  `:route_metric_fun`) guarantees WiFi (`wlan0`) outranks the 4G modem
  (`wwan0`) at every connectivity tier, so `wwan0` is failover only. Ordering
  stays internet-before-LAN, so traffic still falls over to 4G if the WiFi AP
  loses its own upstream.
- **LAN — `eth0`**: static `10.0.1.42/24`. This is the gateway address LAN
  clients use. There is **no DHCP server yet** (see the TODO in
  `config/target.exs`), so clients must be configured statically — e.g. address
  `10.0.1.x/24`, gateway/DNS `10.0.1.42`.
- **NAT**: `WanRouter.WanForward` enables `ip_forward` and adds a `MASQUERADE`
  rule plus a stateful `INPUT` accept for return traffic on **both** WAN
  interfaces (`wwan0` and `wlan0`).

## Prerequisites

Host Elixir/Erlang are pinned in `.tool-versions` (Erlang `29.1.1`, Elixir
`1.20.4-otp-29`); the target runs Erlang/OTP 29 from `nerves_system_br`
1.35.3. With [asdf](https://asdf-vm.com) installed:

```sh
asdf install
```

The host Elixir and Erlang must share the same major OTP version, or Mix will
refuse to build.

## WiFi setup

To enable the `wlan0` WAN, provide the upstream network's credentials in a
gitignored env file (the passphrase never lands in git):

```sh
cp config/.env.exs.example config/.env.exs
# edit config/.env.exs and set WIFI_SSID / WIFI_PSK (WPA2/WPA3 personal)
```

Also set `regulatory_domain` in `config/target.exs` to your 2-letter country
code (e.g. `"BE"`, `"US"`) for correct WiFi channel support; it defaults to
`"00"` (world).

## Build & flash

```sh
export MIX_TARGET=nerves_system_fairphone2
mix deps.get
mix firmware
mix firmware.image wan_router.img
```

The target system (`Spin42/nerves_system_fairphone2`) is pinned to tag
`v1.35.3` in `mix.exs`. Nerves downloads the prebuilt artifact published on that
GitHub release rather than compiling Buildroot locally (no `nerves: [compile:
true]`). The artifact is cached under `~/.local/share/nerves/artifacts/` after
the first build.

The board boots with U-Boot from the `boot` partition. Build `u-boot-fp2.img`
with `fairphone2_uboot_defconfig` in
[`Spin42/buildroot-android`](https://github.com/Spin42/buildroot-android)
(`docs/fairphone2_uboot.md`), then from the bootloader's fastboot mode:

```sh
fastboot -s <serial> flash userdata wan_router.img
fastboot -s <serial> flash boot u-boot-fp2.img
fastboot -s <serial> reboot
```

On the Lime, the USB port goes to the carrier's hub without grounding the USB
ID line, so U-Boot and Linux have to be told to be the USB host. Do it once at
the U-Boot prompt (serial console, any key during the boot delay):

```
setenv usb_mode host
setenv fp2_dtb qcom-msm8974pro-fairphone-fp2-rig.dtb
saveenv
boot
```

`usb_mode=host` makes the system's `boot.scr` start Linux as a USB host, which
the Ethernet (`eth0`) behind the hub needs. `fp2_dtb` selects the device tree
for a mainboard without battery or panel. Later updates go over the network
with `mix upload`.

## Test plan

- Boot the board and check `VintageNet.info/0`: `wwan0` should reach `:internet`,
  and `wlan0` should associate and reach `:internet` once credentials are set.
- Pull the WiFi (or power down the AP) and confirm traffic fails over to the 4G
  uplink; restore it and confirm `wlan0` becomes the preferred route again.
- Statically configure a laptop on `eth0` (address `10.0.1.x/24`, gateway/DNS
  `10.0.1.42`) and confirm it routes external traffic out a WAN.
- `ssh ovcs-4g-gw.local` for an IEx prompt.
