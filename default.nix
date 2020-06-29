with import <nixpkgs> {};
let
  python = import ./requirements.nix { inherit pkgs; };
  logmarki = python.mkDerivation {
    pname = "log-mark-i";
    version = "0.1.0";
    src = ./.;
    buildInputs = builtins.attrValues python.packages;
    propagatedBuildInputs = builtins.attrValues python.packages;
  };
  # I elected not to put the config file in /nix/store because it
  # contains oauth2 secrets so maybe doesn't want to be world-readable.
  # You can write a derivation that does otherwise if you like.
  in pkgs.writeScriptBin "server" ''
PYTHONPATH=${logmarki}/lib/python3.7/site-packages/:$PYTHONPATH
INSTANCE_PATH=/etc/log-mark-i ${python.interpreter}/bin/gunicorn 'logmarki:create_app()'
''
