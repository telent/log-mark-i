import os
import yaml
from flask import Flask
from withings_api import WithingsAuth, AuthScope

def withings_auth(tokens):
    return WithingsAuth(
        client_id=tokens['client_id'],
        consumer_secret=tokens['consumer_secret'],
        callback_uri=tokens['callback'],
        scope=(
            AuthScope.USER_ACTIVITY,
            AuthScope.USER_METRICS,
            AuthScope.USER_INFO,
            AuthScope.USER_SLEEP_EVENTS,
        )
    )

def create_app(test_config=None):
    # create and configure the app
    app = Flask(__name__, instance_relative_config=True)
    app.config.from_mapping(
        SECRET_KEY='dev',
        WITHINGS_AUTH=withings_auth(yaml.load(open(os.path.join(app.instance_path, 'withings_oauth.json')))),
        CREDENTIAL_STORE_PATH=os.path.join(app.instance_path, 'credentials.pickle'),
    )

    if test_config is None:
        # load the instance config, if it exists, when not testing
        app.config.from_pyfile('config.py', silent=True)
    else:
        # load the test config if passed in
        app.config.from_mapping(test_config)

    # ensure the instance folder exists
    try:
        os.makedirs(app.instance_path)
    except OSError:
        pass

    from . import credentials
    from . import withings
    from . import homepage
    app.register_blueprint(homepage.bp)
    app.register_blueprint(withings.bp)

    return app
