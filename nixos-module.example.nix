{ config, pkgs, ... } :

let
  logmarki = import (fetchTarball "https://github.com/telent/log-mark-i/archive/eba5ff08b45ae518990ee85a8154c705254b2de9.tar.gz");
  endpoint = "127.0.0.1:5007";
in {
  config = rec {
    services.nginx = {
      virtualHosts."log-mark-i.example.com" = {
        enableACME = true;
        forceSSL = true;
        locations."/".proxyPass = "http://${endpoint}/";
      };
    };
    users.extraUsers.logmarki = {
      home = "/var/lib/log-mark-i/";
      createHome = true;
      isNormalUser = false;
    };
    systemd.services.logmarki = {
      wantedBy = [ "multi-user.target" ];
      environment = {
        INSTANCE_PATH = "/var/lib/log-mark-i/";
        FLASK_ENV = "production";
        GUNICORN_CMD_ARGS = "--bind=${endpoint}";
      };
      unitConfig = {
        ConditionPathExists = "/etc/log-mark-i/config.json";
      };
      serviceConfig = {
        WorkingDirectory = "/tmp";
        User = "logmarki";
        ExecStartPre = let cu = "${pkgs.coreutils}/bin"; in [
          "${cu}/cp /etc/log-mark-i/config.json /var/lib/log-mark-i/"
        ];
        ExecStart = "${logmarki}/bin/log-mark-i-server";
      };
    };
  };
}
