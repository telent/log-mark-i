# next steps:
# - zoom and pan
# - grey out points after 9am (less likely to be naked/fasted)

from urllib import parse
import pickle
import json
import secrets
from os import path

from withings_api import WithingsAuth, WithingsApi, AuthScope
from withings_api.common import MeasureType, query_measure_groups, AuthFailedException
from oauthlib.oauth2.rfc6749.errors import MissingTokenError
import yaml
import arrow


from flask import Flask, redirect, request, make_response
app = Flask(__name__)

if path.exists("credentials.pickle"):
    credsfile = open("credentials.pickle", "rb")
    credentials = pickle.load(credsfile)
else:
    credentials = {}


def withings_auth():
    tokens = yaml.load(open("secrets.json"))
    auth = WithingsAuth(
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
    return auth

def get_results(api, startdate, enddate):
    meas_result = api.measure_get_meas(startdate=startdate,
                                       enddate=enddate)
    measure_types = [MeasureType.WEIGHT,
                     MeasureType.FAT_FREE_MASS,
                     MeasureType.FAT_RATIO,
                     MeasureType.FAT_MASS_WEIGHT]

    groups = query_measure_groups(meas_result, measure_types)
    out = []
    for group in groups:
        row = {'date': group.date.format()}
        for measure in group.measures:
            row[measure.type.name.lower()] = measure.value # m.unit unused
        out.append(row)
    return out

@app.route('/graph.js')
def graph_js():
    return open("graph.js", "r").read()

@app.route('/')
def index():
    global credentials
    need_creds = False
    token = request.cookies.get('token')
    creds = token and credentials.get(token, None)
    if not creds:
        need_creds = True
    else:
        try:
            api = WithingsApi(creds)
            api.measure_get_meas()
        except (MissingTokenError, AuthFailedException):
            need_creds = True

    if need_creds:
        auth_redirect = withings_auth().get_authorize_url()
        return redirect(auth_redirect)
    return open("index.html", "r").read()

def new_token():
    return secrets.token_urlsafe(32)

@app.route('/cookie')
def send_cookie():
    response = make_response(redirect('/test'))
    response.set_cookie('token', new_token(), secure=True, httponly=True)
    return response

@app.route('/callback')
def withings_callback():
    redirected_uri = request.full_path
    redirected_uri_params = dict(
        parse.parse_qsl(parse.urlsplit(redirected_uri).query)
    )
    auth_code = redirected_uri_params["code"]
    token = request.cookies.get('token') or new_token()
    global credentials
    credentials[token] = withings_auth().get_credentials(auth_code)
    credsfile = open("credentials.pickle", "wb")
    pickle.dump(credentials, credsfile)
    response = make_response(redirect('/'))
    response.set_cookie('token', token, secure=True, httponly=True)
    return response

@app.route('/weights.json')
def weights_json():
    global credentials
    token = request.cookies.get('token', None)
    if token:
        startdate = arrow.Arrow.fromtimestamp(int(request.args.get('start'))/1000)
        enddate = arrow.Arrow.fromtimestamp(int(request.args.get('end'))/1000)
        api = WithingsApi(credentials[token])
        results = get_results(api, startdate, enddate)
        return json.dumps(results)
    return ('no token', 403)
