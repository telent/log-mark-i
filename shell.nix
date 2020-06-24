with import <nixpkgs> {};
let pypkgs = with python38Packages; [ pip pylint setuptools pyyaml flask gunicorn ]; in
stdenv.mkDerivation rec {
  pname = "log-mark-i";
  version = "1";
  src = ./.;
  shellHook = "export PYTHONPATH=$HOME/.local/lib/python3.8/site-packages:$PYTHONPATH; export PATH=$HOME/.local/bin:$PATH";
#  GEM_HOME = "./gems";
#  GEM_PATH = "${GEM_HOME}:${pkgs.ruby}/lib/ruby/gems/2.6.0";
  FLASK_APP="clap.py";
  FLASK_ENV="development";
  nativeBuildInputs = [ pkgs.python38 ] ++ pypkgs;
}
