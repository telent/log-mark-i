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

from claphands.credentials import get_credential_store
from claphands.withings import get_withings_auth

bp = Blueprint('homepage', __name__, url_prefix='/')

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
            row[measure.type.name.lower()] = measure.value * pow(10, measure.unit)
        out.append(row)
    return out

@bp.route('/')
def homepage():
    need_creds = False
    token = request.cookies.get('token')
    creds = get_credential_store().get(token, None)
    if not creds:
        need_creds = True
    else:
        try:
            api = WithingsApi(creds)
            api.measure_get_meas() # check creds are still valid
        except (MissingTokenError, AuthFailedException) as e:
            print("auth error", e)
            need_creds = True

    if need_creds:
        auth_redirect = get_withings_auth().get_authorize_url()
        return redirect(auth_redirect)
    return render_template("index.html")

@bp.route('/weights.json')
def weights_json():
    token = request.cookies.get('token', None)
    credential_store = get_credential_store()
    creds = credential_store.get(token, None)
    if not creds:
        return ('no token', 403)

    update_creds = lambda creds: credential_store.update(token, creds)
    api = WithingsApi(creds, refresh_cb=update_creds)

    startdate = arrow.Arrow.fromtimestamp(int(request.args.get('start'))/1000)
    enddate = arrow.Arrow.fromtimestamp(int(request.args.get('end'))/1000)
    results = get_results(api, startdate, enddate)
    return json.dumps(results)
