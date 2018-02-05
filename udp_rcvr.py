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
br.set_addr('')



def create_experiment(topicObj=pub.AUTO_TOPIC, data=None):
    pay = data['create_job']
    cypher = pay['cypher']
    print("create_experiment::%s"%cypher)
    sys.stdout.flush()

def create_job(topicObj=pub.AUTO_TOPIC, data=None):
    pay = data['create_job']
    cypher = pay['cypher']
    print("create_job::%s"%cypher)
    sys.stdout.flush()

def run_job(topicObj=pub.AUTO_TOPIC, data=None):
    print('run_job',data)
    pay = data['run_job']
    id = pay['job_id']
    print("run_job: %d"%id)
    sys.stdout.flush()

def rcv_data(topicObj=pub.AUTO_TOPIC, data=None):
    print('rcv_data',data)
    pay = data['rcv_data']
    forward = pay['data']
    print("forward_data: %s"%forward)
    sys.stdout.flush()

pub.subscribe(create_experiment, 'ff.create_experiment')
pub.subscribe(create_job, 'ff.create_job')	
pub.subscribe(run_job, 'ff.run_job')	
pub.subscribe(rcv_data, 'ff.rcv_data')	

while True:
    time.sleep(10)
