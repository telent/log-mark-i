with import <nixpkgs> {};
let python = import ./requirements.nix { inherit pkgs; };
in stdenv.mkDerivation {
  name = "log-mark-i-env";
  buildInputs = with pkgs.elmPackages;
    [ python.interpreter
      entr
      elm elm-format ];
  WEBPACK_SOURCE_MAP = true;
  shellHook  = ''
PATH=./node_modules/.bin:$PATH
'';
}
