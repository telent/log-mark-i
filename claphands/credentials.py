from flask import current_app, g
from os import path
import pickle

class CredentialStore:
    def __init__(self, pathname):
        self.pathname = pathname
        if path.exists(pathname):
            credsfile = open(pathname, "rb")
            self.data = pickle.load(credsfile)
        else:
            self.data = {}

    def get(self, key, default):
        return self.data.get(key, default) if key else default

    def update(self, key, value):
        # need locking here to protect against simultaneous updates
        print("updating credentials for ", key)
        self.data[key] = value
        credsfile = open(self.pathname, "wb")
        pickle.dump(self.data, credsfile)
        credsfile.close()


def get_credential_store():
    if 'credential_store' not in g:
        g.credential_store = CredentialStore(current_app.config['CREDENTIAL_STORE_PATH'])
    return g.credential_store
