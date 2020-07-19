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
entr-build() {
    ls client/Main.elm logmarki/templates/index.html | entr -c elm make client/Main.elm --output=logmarki/static/bundle.js
}
'';
}
