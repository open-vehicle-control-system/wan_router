import Config

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

# Configure the network using vintage_net: a 4G hotspot.
#
# WAN: wwan0, the in-kernel QMI modem, is the only uplink. APN "simbase" is
# hardcoded; tweak service_providers for other carriers. Clients on both LAN
# sides are NAT'd out of it (see WanRouter.WanForward).
#
# LAN:
#   * wlan0 is an access point (WPA2-PSK, 2.4 GHz channel 6) on 10.0.2.1/24
#     and hands out 10.0.2.10-10.0.2.100 by DHCP, with public DNS servers:
#     the router runs no DNS forwarder.
#   * eth0 is static 10.0.1.42/24, without DHCP: clients there use a fixed
#     address, gateway 10.0.1.42.
#
# Update regulatory_domain to your 2-letter country code E.g., "US"
#
# See https://github.com/nerves-networking/vintage_net for more information

# The access point SSID and passphrase stay out of git: config/.env.exs
# (gitignored, see config/.env.exs.example) sets WIFI_AP_SSID and WIFI_AP_PSK.
env_file = Path.expand(".env.exs", __DIR__)
if File.exists?(env_file), do: import_config(env_file)

[wifi_ap_ssid, wifi_ap_psk] =
  for name <- ["WIFI_AP_SSID", "WIFI_AP_PSK"] do
    System.get_env(name) ||
      Mix.raise("""
      #{name} is not set. The WiFi access point needs an SSID and a WPA2
      passphrase: copy config/.env.exs.example to config/.env.exs and set them
      there.
      """)
  end

config :vintage_net,
  regulatory_domain: "00",
  config: [
    {"usb0", %{type: VintageNetDirect}},
    {"eth0",
     %{
       type: VintageNetEthernet,
       ipv4: %{
         method: :static,
         address: "10.0.1.42",
         prefix_length: 24
       }
     }},
    {"wlan0",
     %{
       type: VintageNetWiFi,
       vintage_net_wifi: %{
         networks: [
           %{
             mode: :ap,
             ssid: wifi_ap_ssid,
             key_mgmt: :wpa_psk,
             psk: wifi_ap_psk,
             frequency: 2437
           }
         ]
       },
       ipv4: %{
         method: :static,
         address: "10.0.2.1",
         prefix_length: 24
       },
       dhcpd: %{
         start: "10.0.2.10",
         end: "10.0.2.100",
         options: %{
           dns: ["1.1.1.1", "8.8.8.8"],
           subnet: "255.255.255.0",
           router: ["10.0.2.1"]
         }
       }
     }},
    {"wwan0",
     %{
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
  ]

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
