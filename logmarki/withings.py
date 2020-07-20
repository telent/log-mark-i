from urllib import parse
import secrets
import datetime

from flask import current_app, g, Blueprint, request, make_response, redirect
from withings_api import WithingsAuth, AuthScope
from withings_api.common import MeasureType, query_measure_groups

from logmarki.credentials import get_credential_store

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
        row = {'date': group.date.astimezone(datetime.timezone.utc).isoformat()}
        for measure in group.measures:
            row[measure.type.name.lower()] = measure.value * pow(10, measure.unit)
        out.append(row)
    return out
