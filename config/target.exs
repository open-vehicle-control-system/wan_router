import Config

if config_env() in [:dev, :test, :prod] do
  for path <- [".env.exs", ".env.#{config_env()}.exs"] do
    path = Path.join(__DIR__, "..") |> Path.join("config") |> Path.join(path) |> Path.expand()
    if File.exists?(path), do: import_config(path)
  end
end

# Default to not starting so that the console logger isn't started. See
# runtime.exs for logger configuration.
config :logger, :default_handler, false

# Use shoehorn to start the main application. See the shoehorn
# library documentation for more control in ordering how OTP
# applications are started and handling failures.

config :shoehorn, init: [:nerves_runtime, :ex_rmtfs, :nerves_pack]

# Erlinit can be configured without a rootfs_overlay. See
# https://github.com/nerves-project/erlinit/ for more information on
# configuring erlinit.

# erlinit overrides — see comment below where the consolidated block lives.

# Configure the device for SSH IEx prompt access and firmware updates
#
# * See https://hexdocs.pm/nerves_ssh/readme.html for general SSH configuration
# * See https://hexdocs.pm/ssh_subsystem_fwup/readme.html for firmware updates

keys =
  System.user_home!()
  |> Path.join(".ssh/id_{rsa,ecdsa,ed25519}.pub")
  |> Path.wildcard()

if keys == [],
  do:
    Mix.raise("""
    No SSH public keys found in ~/.ssh. An ssh authorized key is needed to
    log into the Nerves device and update firmware on it using ssh.
    See your project's config.exs for this error message.
    """)

config :nerves_ssh,
  authorized_keys: Enum.map(keys, &File.read!/1)

config :nerves, :erlinit,
    update_clock: true,
    ctty: "ttyMSM0"

# Configure the network using vintage_net.
#
# WAN side: TWO upstream interfaces, both providing internet and NAT'd to the
# LAN (see WanRouter.WanForward):
#   * wwan0 — the in-kernel QMI modem on the Fairphone 2. APN "simbase" is
#     hardcoded; tweak service_providers for other carriers.
#   * wlan0 — WiFi client (station) joining an upstream access point. Credentials
#     come from config/.env.exs (gitignored), which sets WIFI_SSID / WIFI_PSK.
#     vintage_net's default route prioritization prefers WiFi (wlan0) over mobile
#     (wwan0), so cellular acts as failover when WiFi is down.
#
# LAN side: eth0 is the downstream interface, static 10.0.1.42/24.
#
# Update regulatory_domain to your 2-letter country code E.g., "US"
#
# See https://github.com/nerves-networking/vintage_net for more information

# Secondary WAN over WiFi. Built from env vars set by config/.env.exs so the
# passphrase never lands in git. If they're absent, wlan0 is left unconfigured
# and the firmware still builds (cellular-only).
wlan_wan =
  case {System.get_env("WIFI_SSID"), System.get_env("WIFI_PSK")} do
    {ssid, psk} when is_binary(ssid) and ssid != "" and is_binary(psk) and psk != "" ->
      [
        {"wlan0",
         %{
           type: VintageNetWiFi,
           vintage_net_wifi: %{
             networks: [%{key_mgmt: :wpa_psk, ssid: ssid, psk: psk}]
           },
           ipv4: %{method: :dhcp}
         }}
      ]

    _ ->
      []
  end

config :vintage_net,
  # Guarantee wlan0 (WiFi) is preferred over wwan0 (4G) for the default route;
  # 4G is failover only. See WanRouter.RouteMetric.
  route_metric_fun: {WanRouter.RouteMetric, :compute, 2},
  regulatory_domain: "00",
  config:
    [
      {"usb0", %{type: VintageNetDirect}},
      {"eth0",
       %{
         type: VintageNetEthernet,
         ipv4: %{
           method: :static,
           address: "10.0.1.42",
           prefix_length: 24
         }
         # TODO: LAN clients won't get a lease until we run a DHCP server
         # ourselves (VintageNet has no server side). Plan: spawn busybox
         # udhcpd or dnsmasq from a WanRouter child process bound to eth0.
       }},
      {"wwan0", %{
        type: VintageNetQMI,
        vintage_net_qmi: %{
          ip_method: :qmi_profile,
          device_path: "/dev/wwan0qmi0",
          provision_uim: true,
          service_providers: [
            %{apn: "simbase", auth_method: :none, pdp_type: :ipv4, roaming_allowed?: true}
          ]
        }
      }}
    ] ++ wlan_wan

config :mdns_lite,
  # The `hosts` key specifies what hostnames mdns_lite advertises.  `:hostname`
  # advertises the device's hostname.local. For the official Nerves systems, this
  # is "nerves-<4 digit serial#>.local".  The `"nerves"` host causes mdns_lite
  # to advertise "nerves.local" for convenience. If more than one Nerves device
  # is on the network, it is recommended to delete "nerves" from the list
  # because otherwise any of the devices may respond to nerves.local leading to
  # unpredictable behavior.

  hosts: [:hostname, "ovcs1-router"],

  ttl: 120,

  # Advertise the following services over mDNS.
  services: [
    %{
      protocol: "ssh",
      transport: "tcp",
      port: 22
    },
    %{
      protocol: "sftp-ssh",
      transport: "tcp",
      port: 22
    },
    %{
      protocol: "epmd",
      transport: "tcp",
      port: 4369
    }
  ]

# Import target specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
# Uncomment to use target specific configurations

# import_config "#{Mix.target()}.exs"
