with import <nixpkgs> {};
let
  python = import ./requirements.nix { inherit pkgs; };
in python.mkDerivation {
  pname = "log-mark-i";
  version = "0.1.0";
  src = ./.;
  buildInputs = builtins.attrValues python.packages;
  propagatedBuildInputs = builtins.attrValues python.packages;
  # I use this with a systemd unit that runs
  #
  # PYTHONPATH=${logmarki}/lib/python3.7/site-packages/:$PYTHONPATH \
  #   INSTANCE_PATH=/etc/log-mark-i \
  #   ${python.interpreter}/bin/gunicorn 'logmarki:create_app()'
  #
  # I elected not to put the config file in /nix/store because it
  # contains oauth2 secrets so maybe doesn't want to be world-readable.
}
