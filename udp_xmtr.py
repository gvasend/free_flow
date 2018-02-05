import time
import sys
import os
from pubsub import pub
import logging


log = logging.getLogger()

import scrape as sc

import argparse

# general parameters

parser = argparse.ArgumentParser(description='FF process to bridge scala using UDP')

sc.all_options(parser)

parser.add_argument('--port',type=int,default=8889,help='udp port to use')

# SVC parameters

sc.output_options(parser)

from scrape import write_dict
from scrape import load_file

args = sc.parse_args(parser)

import scala_udp_bridge as br
br.set_addr('10.0.1.25')


#pub.sendMessage('ff.create_job', data=dict(create_job=dict(cypher='test_flow!!{"feature_file":"ff.libsvm"}')))
pub.sendMessage('ff.create_experiment', data=dict(create_job=dict(cypher='cyber_ml1!!{"ll":"DEBUG","tws":"60.0", "max_window":"10000", "input_corpus":"$ff_home/all_logs.log"}')))


time.sleep(5)
