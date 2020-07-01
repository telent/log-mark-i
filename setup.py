from setuptools import find_packages, setup
import json

setup(
    name='logmarki',
    version='0.1.0',
    packages=find_packages(),
    include_package_data=True,
    zip_safe=False,
    install_requires=[
        "filelock",
        "flask",
        "gunicorn",
        "pip",
        "pylint",
        "pyyaml",
        "setuptools",
        "withings_api"
    ]
)
