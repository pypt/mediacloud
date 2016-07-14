#!/usr/bin/env python

import argparse

from mc_solr.constants import *
from mc_solr.solr import run_solr_standalone

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Install Solr and start a standalone instance.",
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument("-p", "--port", type=int, required=False, default=MC_SOLR_STANDALONE_PORT, help="Port.")

    args = parser.parse_args()

    run_solr_standalone(port=args.port)