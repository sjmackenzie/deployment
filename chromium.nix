{ pkgs, ... }:

let
  home = "/home/nixpkgs-chromium";
in {
  users.extraGroups.nixpkgsupdate.gid = 2011;
  users.extraUsers.nixpkgsupdate = {
    uid = 2011;
    description = "NixPkgs update user";
    group = "nixpkgsupdate";
    inherit home;
    createHome = true;
  };

  systemd.timers."chromium-update" = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnActiveSec = 0;
    timerConfig.OnUnitActiveSec = "1h";
  };

  systemd.services."chromium-update" = {
    description = "Chromium NixPkgs Updater";
    after = [ "fs.target" "network.target" ];

    path = [ pkgs.curl pkgs.nix ];
    environment.NIX_REMOTE = "daemon";
    environment.CURL_CA_BUNDLE = "${pkgs.cacert}/etc/ca-bundle.crt";

    script = ''
      cd "${home}"
      if [ ! -e .git ]; then
        chmod go+rx "${home}"
        ${pkgs.git}/bin/git init
        ${pkgs.git}/bin/git config http.sslVerify false

        ${pkgs.git}/bin/git config user.name 'Chromium Autoupdater'
        ${pkgs.git}/bin/git config user.email \
          'chromium-autoupdate@headcounter.org'

        ${pkgs.git}/bin/git remote add origin \
          https://github.com/NixOS/nixpkgs.git
      fi
      if ! ${pkgs.git}/bin/git pull --rebase origin master; then
        ${pkgs.git}/bin/git rebase --abort || true
        ${pkgs.git}/bin/git clean -fdx
        ${pkgs.git}/bin/git reset --hard origin/master
      fi
      cd pkgs/applications/networking/browsers/chromium
      NIX_PATH="nixpkgs=${home}" ${pkgs.stdenv.shell} update.sh
      ${pkgs.git}/bin/git commit -a -m "chromium: Automatic update" || true
    '';

    serviceConfig.User = "nixpkgsupdate";
    serviceConfig.Group = "nixpkgsupdate";
    serviceConfig.PrivateTmp = true;
  };
}
