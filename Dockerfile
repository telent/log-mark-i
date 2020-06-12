# This is mostly here for testing things on non-Nixos systems.
FROM fedora:latest
RUN dnf -y install python pip git
RUN python -m pip install git+https://github.com/telent/clap-hands.git
COPY instance/config.json /usr/var/claphands-instance/config.json
EXPOSE 8080
CMD gunicorn  -b 0.0.0.0:8080 'claphands:create_app()'