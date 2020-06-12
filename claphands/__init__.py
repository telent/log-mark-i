import os
import yaml
from flask import Flask


def create_app(test_config=None):
    # create and configure the app
    app = Flask(__name__, instance_relative_config=True)
    app.config.from_mapping(
        SECRET_KEY='dev',
        CREDENTIAL_STORE_PATH=os.path.join(app.instance_path, 'credentials.pickle'),
    )

    if test_config is None:
        # load the instance config, if it exists, when not testing
        app.config.from_json('config.json', silent=False)
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

    return app
