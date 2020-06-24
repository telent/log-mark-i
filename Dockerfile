# This is mostly here for testing things on non-Nixos systems.
FROM fedora:latest
RUN dnf -y install python pip git
# RUN python -m pip install git+https://github.com/telent/log-mark-i.git
# COPY instance/config.json /usr/var/logmarki-instance/config.json
# EXPOSE 8080
# CMD gunicorn  -b 0.0.0.0:8080 'logmarki:create_app()'