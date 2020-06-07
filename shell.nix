with import <nixpkgs> {};
stdenv.mkDerivation rec {
  pname = "clap-hands";
  version = "1";
  src = ./.;
  shellHook = "export PYTHONPATH=$HOME/.local/lib/python3.8/site-packages:$PYTHONPATH; export PATH=$HOME/.local/bin:$PATH";
#  GEM_HOME = "./gems";
#  GEM_PATH = "${GEM_HOME}:${pkgs.ruby}/lib/ruby/gems/2.6.0";
  FLASK_APP="clap.py";
  FLASK_ENV="development";
  nativeBuildInputs = [ pkgs.python38 python38Packages.pip python38Packages.setuptools python38Packages.pyyaml python38Packages.flask ];
}
