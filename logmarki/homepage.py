from urllib import parse
import pickle
import json
import secrets
from os import path

import arrow

from withings_api import WithingsAuth, WithingsApi, AuthScope
from withings_api.common import MeasureType, query_measure_groups, AuthFailedException
from oauthlib.oauth2.rfc6749.errors import MissingTokenError

from flask import Flask, redirect, request, make_response, Response, render_template, Blueprint

from logmarki.credentials import get_credential_store
from logmarki.withings import get_withings_auth, get_results

bp = Blueprint('homepage', __name__, url_prefix='/')

def get_api_handle(request):
    need_creds = False
    token = request.cookies.get('token')
    credential_store = get_credential_store()
    creds = credential_store.get(token, None)
    if creds:
        update_creds = lambda creds: credential_store.update(token, creds)
        try:
            api = WithingsApi(creds, refresh_cb=update_creds)
            api.measure_get_meas() # check creds are still valid
            return api
        except (MissingTokenError, AuthFailedException) as e:
            print("auth error", e)
    return None


@bp.route('/')
def homepage():
    api = get_api_handle(request)
    if not api:
        auth_redirect = get_withings_auth().get_authorize_url()
        return redirect(auth_redirect)
    return render_template("index.html")

@bp.route('/weights.json')
def weights_json():
    api = get_api_handle(request)
    if not api:
        return ('no token', 403)
    startdate = arrow.Arrow.fromtimestamp(int(request.args.get('start'))/1000)
    enddate = arrow.Arrow.fromtimestamp(int(request.args.get('end'))/1000)
    results = get_results(api, startdate, enddate)
    return json.dumps(results)

def new_token():
    return secrets.token_urlsafe(32)

@bp.route('/withings/callback')
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

@bp.route('/device')
def get_device_info():
    api = get_api_handle(request)
    devices = api.user_get_device()
    return json.dumps([[d.type, d.model, d.battery] for d in devices.devices])
