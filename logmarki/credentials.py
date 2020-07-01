from flask import current_app, g
from os import path, rename, remove
import pickle
from filelock import Timeout, FileLock

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
        tmpname = self.pathname + ".new"
        lockname = self.pathname + ".lock"
        try:
            with FileLock(lockname, timeout = 5):
                with open(tmpname, "wb") as file:
                    print("updating credentials for", key)
                    self.data[key] = value
                    pickle.dump(self.data, file)
                    file.close()
                    rename(tmpname, self.pathname)
        finally:
            remove(lockname)

def get_credential_store():
    if 'credential_store' not in g:
        g.credential_store = CredentialStore(current_app.config['CREDENTIAL_STORE_PATH'])
    return g.credential_store
