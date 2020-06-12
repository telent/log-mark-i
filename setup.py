from setuptools import find_packages, setup
import json

def requirements():
    # we keep requirements in a separate file to make it easier for nix
    with open("pypkgs.json","r") as fh:
        return yaml.load(fh)

setup(
    name='claphands',
    version='0.1.0',
    packages=find_packages(),
    include_package_data=True,
    zip_safe=False,
    install_requires=requirements()
)
