# WanRouter

4G hotspot for the Citronics Lime, a carrier board for the Fairphone 2
mainboard (Nerves, `nerves_system_fairphone2`). It shares its 4G connection
with devices on its WiFi access point and on Ethernet.

- **WAN — `wwan0`**: in-kernel QMI modem, driven by
  [`vintage_net_qmi`](https://github.com/mlainez/vintage_net_qmi) on top of
  [`qmi`](https://github.com/mlainez/qmi). APN is hardcoded to `simbase` in
  `config/target.exs` — change `service_providers` for other carriers. The
  Lime needs an external cellular antenna.
- **LAN — `wlan0`**: WiFi access point (WPA2-PSK, 2.4 GHz channel 6) on
  `10.0.2.1/24`; see [WiFi](#wifi) for its SSID and passphrase. A DHCP server
  hands out
  `10.0.2.10`–`10.0.2.100` with gateway `10.0.2.1` and DNS `1.1.1.1`,
  `8.8.8.8` (the router runs no DNS forwarder).
- **LAN — `eth0`**: static `10.0.1.42/24`, without DHCP. Clients there use a
  fixed address, e.g. `10.0.1.x/24` with gateway `10.0.1.42` and a public DNS
  server.
- **NAT**: `WanRouter.WanForward` enables `ip_forward` and adds a `MASQUERADE`
  rule plus a stateful `INPUT` accept for return traffic on `wwan0`.

## Prerequisites

Host Elixir/Erlang are pinned in `.tool-versions` (Erlang `29.1.1`, Elixir
`1.20.4-otp-29`); the target runs Erlang/OTP 29 from `nerves_system_br`
1.35.3. With [asdf](https://asdf-vm.com) installed:

```sh
asdf install
```

The host Elixir and Erlang must share the same major OTP version, or Mix will
refuse to build.

## WiFi

The access point SSID and passphrase stay out of git: put them in a gitignored
env file before building the firmware (the build stops if one is missing):

```sh
cp config/.env.exs.example config/.env.exs
# edit config/.env.exs and set WIFI_AP_SSID and WIFI_AP_PSK (8 to 63 characters)
```

The other access point settings are in `config/target.exs`. Set `regulatory_domain`
there to your 2-letter country code (e.g. `"BE"`, `"US"`) for correct WiFi
channel support; it defaults to `"00"` (world), which is why the access point
stays on 2.4 GHz channel 6.

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

On the Lime, U-Boot picks the carrier device tree by itself (no panel), and the
carrier grounds the USB ID line, so Linux is the host of the hub that carries
the Ethernet port (`eth0`, an SMSC LAN9514) and the STM32. Nothing has to be
set in U-Boot. Later updates go over the network with `mix upload`.

The system's `limeboard-mcu` command talks to and reflashes the STM32
(`cmd("limeboard-mcu status")`); see the `nerves_system_fairphone2` README.

## Test plan

- Boot the board and check `VintageNet.info/0`: `wwan0` should reach
  `:internet`, and `wlan0` should be configured as an access point (`:lan`).
- Join the access point from a phone or laptop: it should get a `10.0.2.x`
  address and reach the internet through 4G.
- Statically configure a laptop on `eth0` (address `10.0.1.x/24`, gateway
  `10.0.1.42`, DNS `1.1.1.1`) and confirm it reaches the internet through 4G.
- `ssh 10.0.1.42` (from `eth0`) or `ssh 10.0.2.1` (from WiFi) for an IEx
  prompt.
