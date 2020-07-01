with import <nixpkgs> {};
let
  python = import ./requirements.nix { inherit pkgs; };
  logmarki_pkg = python.mkDerivation {
    pname = "log-mark-i";
    version = "0.1.0";
    src = ./.;
    buildInputs = builtins.attrValues python.packages;
    propagatedBuildInputs = builtins.attrValues python.packages;
    # I use this with a systemd unit that runs
    #
    #   INSTANCE_PATH=/var/lib/log-mark-i
    #   GUNICORN_CMD_ARGS="--bind=127.0.0.1:5007"
    #   ${logmarki}/bin/log-mark-i-server
    #
  }; in
pkgs.writers.writeBashBin "log-mark-i-server" ''
  export PYTHONPATH=${logmarki_pkg}/lib/python3.7/site-packages/:$PYTHONPATH
  ${python.interpreter}/bin/gunicorn 'logmarki:create_app()'
''
