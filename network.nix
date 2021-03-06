let
  mkMachine = attrs: attrs // {
    imports = import modules/module-list.nix
           ++ [ ./common.nix ]
           ++ attrs.imports or [];
  };
in {
  network.description = "Headcounter Services";
  network.enableRollback = true;

  resources.sshKeyPairs."hydra-build" = {};

  ultron = { pkgs, lib, config, ... }: mkMachine {
    imports = [ ./machines/ultron.nix ];
    deployment.hetzner.mainIPv4 = "5.9.105.142";

    services.openssh.extraConfig = lib.mkAfter ''
      ListenAddress ${config.deployment.hetzner.mainIPv4}
      ListenAddress [2a01:4f8:162:4187::]
    '';

    systemd.services."legacy-portfw" = {
      description = "Port forwarding to old server";
      after = [ "network-interfaces.target" ];
      before = [ "network.target" ];
      wantedBy = [ "network.target" ];

      path = [ pkgs.iptables ];

      serviceConfig.Type = "oneshot";
      serviceConfig.RemainAfterExit = true;

      script = with pkgs.lib; ''
        ${flip concatMapStrings [ 5222 5223 5269 ] (port: ''
        iptables -t nat -A PREROUTING -p tcp --dport ${toString port} \
          -j DNAT --to-destination 88.198.198.219:${toString port}
        iptables -t nat -A POSTROUTING -p tcp --dport ${toString port} \
          -j MASQUERADE
        '')}
        echo 1 > /proc/sys/net/ipv4/ip_forward
      '';
    };
  };

  taalo = { pkgs, config, ... }: mkMachine {
    imports = [ ./hydra.nix ./chromium.nix ];
    deployment.hetzner.mainIPv4 = "188.40.96.202";

    fileSystems."/".options = pkgs.lib.concatStringsSep "," [
      "autodefrag"
      "space_cache"
      "inode_cache"
      "compress=lzo"
      "noatime"
    ];

    deployment.hetzner.partitions = ''
      clearpart --all --initlabel --drives=sda,sdb

      part swap1 --size=10000 --label=swap1 --fstype=swap --ondisk=sda
      part swap2 --size=10000 --label=swap2 --fstype=swap --ondisk=sdb

      part btrfs.1 --grow --ondisk=sda
      part btrfs.2 --grow --ondisk=sdb

      btrfs / --data=1 --metadata=1 --label=root btrfs.1 btrfs.2
    '';
    deployment.encryptedLinksTo = [ "ultron" ];
    services.hydra.listenHost = pkgs.lib.mkForce
      config.networking.p2pTunnels.ssh.ultron.localIPv4;
  };

  benteflork = mkMachine {
    imports = [ ./hydra-slave.nix ];
    deployment.hetzner.mainIPv4 = "144.76.202.147";
  };

  dugee = mkMachine {
    imports = [ ./dns-server.nix ];
    deployment.hetzner.mainIPv4 = "78.46.182.124";
  };

  gussh = mkMachine {
    imports = [ ./dns-server.nix ];
    deployment.hetzner.mainIPv4 = "78.47.142.38";
  };

  unzervalt = { nodes, lib, ... }: {
    deployment.targetEnv = "container";
    deployment.container.host = nodes.ultron.config;
    imports = import modules/module-list.nix
           ++ lib.optional (lib.pathExists ./private/default.nix) ./private;
    services.headcounter.webspace.enable = true;
    networking.firewall.enable = false;
    users.mutableUsers = false;
  };
}
