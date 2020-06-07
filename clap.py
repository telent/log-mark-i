from withings_api import WithingsAuth, WithingsApi, AuthScope
from withings_api.common import get_measure_value, MeasureType, Credentials, query_measure_groups
from oauthlib.oauth2.rfc6749.errors import MissingTokenError
from os import system,path
from urllib import parse
import yaml
import arrow
import pickle
import json

from flask import Flask,redirect,request
app = Flask(__name__)

credentials = None
auth = None

if path.exists("credentials.pickle"):
    credsfile = open("credentials.pickle", "rb")
    credentials = pickle.load(credsfile)


def withings_auth():
    secrets = yaml.load(open("secrets.json"))
    auth = WithingsAuth(
        client_id=secrets['client_id'],
        consumer_secret=secrets['consumer_secret'],
        callback_uri=secrets['callback'],
        scope=(
            AuthScope.USER_ACTIVITY,
            AuthScope.USER_METRICS,
            AuthScope.USER_INFO,
            AuthScope.USER_SLEEP_EVENTS,
        )
    )
    return auth

def get_results(api):
    meas_result = api.measure_get_meas(startdate=arrow.utcnow().shift(days=-21),
                                       enddate=arrow.utcnow())
    measure_types = [MeasureType.WEIGHT,
                     MeasureType.FAT_FREE_MASS,
                     MeasureType.FAT_RATIO,
                     MeasureType.FAT_MASS_WEIGHT]

    groups = query_measure_groups(meas_result, measure_types)
    out = []
    for group in groups:
        row = { 'date': group.date.format() }
        for m in group.measures:
            row[m.type.name.lower()] = m.value # m.unit unused
        out.append(row)
    return out


def index_html():
    return open("index.html","r").read()


@app.route('/')
def index():
    needCreds = False
    if not credentials:
        needCreds = True
    try:
        api = WithingsApi(credentials)
        api.measure_get_meas()
    except MissingTokenError:
        needCreds = True

    if needCreds:
        auth_redirect = withings_auth().get_authorize_url()
        return redirect(auth_redirect)
    else:
        return index_html()


@app.route('/callback')
def withings_callback():
    redirected_uri = request.full_path
    redirected_uri_params = dict(
        parse.parse_qsl(parse.urlsplit(redirected_uri).query)
    )
    auth_code = redirected_uri_params["code"]
    global credentials
    credentials = withings_auth().get_credentials(auth_code)
    credsfile = open("credentials.pickle", "wb")
    pickle.dump(credentials, credsfile)
    return redirect('/')

@app.route('/weights.json')
def weights_json():
    global credentials
    api = WithingsApi(credentials)
    results = get_results(api)
    return json.dumps(results)
