with import <nixpkgs> {};
let python = import ./requirements.nix { inherit pkgs; };
in stdenv.mkDerivation {
  name = "log-mark-i-env";
  buildInputs = [ python.interpreter
                  nodejs ];
  WEBPACK_SOURCE_MAP = true;
  shellHook  = ''
PATH=./node_modules/.bin:$PATH
'';
}
