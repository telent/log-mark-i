from urllib import parse
import secrets

from flask import current_app, g, Blueprint, request, make_response, redirect
from withings_api import WithingsAuth, AuthScope

from claphands.credentials import get_credential_store

def withings_auth(config):
    return WithingsAuth(
        client_id=config['WITHINGS_CLIENT_ID'],
        consumer_secret=config['WITHINGS_CONSUMER_SECRET'],
        callback_uri=config['WITHINGS_CALLBACK'],
        scope=(
            AuthScope.USER_ACTIVITY,
            AuthScope.USER_METRICS,
            AuthScope.USER_INFO,
            AuthScope.USER_SLEEP_EVENTS,
        )
    )

def get_withings_auth():
    if 'withings_auth' not in g:
        g.withings_auth = withings_auth(current_app.config)
    return g.withings_auth

def new_token():
    return secrets.token_urlsafe(32)

bp = Blueprint('withings', __name__, url_prefix='/withings')

@bp.route('/callback')
def callback():
    redirected_uri_params = dict(
        parse.parse_qsl(parse.urlsplit(request.full_path).query)
    )
    auth_code = redirected_uri_params["code"]
    token = request.cookies.get('token') or new_token()
    get_credential_store().update(token, get_withings_auth().get_credentials(auth_code))

    response = make_response(redirect('/'))
    response.set_cookie('token', token, secure=True, httponly=True)
    return response
