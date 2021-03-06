{ config, pkgs, ... }:

with pkgs.lib;

let
  cfg = config.services.headcounter.mongooseim;
  package = (import ../../../pkgs {
    inherit pkgs;
  }).mongooseim;

  vmArgsFile = pkgs.writeText "vm.args" ''
    -sname ${cfg.nodeName}
    # XXX: sensitve stuff!
    -setcookie ejabberd
    +K true
    +A 5
    +P 10000000
    -env ERL_MAX_PORTS 250000
    -env ERL_FULLSWEEP_AFTER 2
    -sasl sasl_error_logger false
  '';
in {
  options.services.headcounter.mongooseim = {
    enable = mkEnableOption "MongooseIM";

    nodeName = mkOption {
      default = "ejabberd@${config.networking.hostName}";
      type = types.str;
      description = "Erlang OTP node name";
    };

    configFile = mkOption {
      default = null;
      example = "${package}/etc/ejabberd.cfg";
      type = types.nullOr types.path;
      description = ''
        Path to the main configuration file.
        This overrides all options defined in <option>settings</option>.
      '';
    };

    databaseDir = mkOption {
      default = "/var/db/mongoose";
      type = types.path;
      description = "Database directory for Mnesia";
    };

    settings = mkOption {
      default = {};
      type = types.submodule (import ./settings.nix {
        inherit pkgs;
        toplevelConfig = config;
      });
      description = "Configuration settings.";
    };
  };

  config = mkIf cfg.enable {
    users.extraGroups.mongoose = {};
    users.extraUsers.mongoose = {
      description = "MongooseIM user";
      group = "mongoose";
      home = cfg.databaseDir;
      createHome = true;
    };

    systemd.services.mongooseim = {
      description = "MongooseIM XMPP Server";
      wantedBy = [ "multi-user.target" ];
      requires = [ "keys.target" ];
      after = [ "network.target" "fs.target" "keys.target" ];

      environment.EMU = "beam";
      environment.ROOTDIR = package;
      environment.PROGNAME = "ejabberd";
      environment.EJABBERD_CONFIG_PATH = if cfg.configFile != null
                                         then cfg.configFile
                                         else cfg.settings.generatedConfigFile;

      serviceConfig.Type = "notify";
      serviceConfig.NotifyAccess = "all";
      serviceConfig.User = "mongoose";
      serviceConfig.Group = "mongoose";
      serviceConfig.PrivateTmp = true;
      serviceConfig.PermissionsStartOnly = true;

      serviceConfig.ExecStart = concatStringsSep " " [
        "@${pkgs.erlang}/bin/erl" "mongooseim"
        "-sasl releases_dir \\\"${package}/releases\\\""
        "-mnesia dir \\\"${cfg.databaseDir}\\\""
        # XXX: Don't hardcode release version!
        "-boot ${package}/releases/0.1/ejabberd"
        "-boot_var RELTOOL_EXT_LIB ${package}/lib"
        "-config ${package}/etc/app.config"
        "-args_file ${vmArgsFile}"
        "-embedded"
        "-noinput"
        "-smp"
      ];
    };
  };
}
