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

import udp_bridge



def create_job(topicObj=pub.AUTO_TOPIC, data=None):
    print('create_job',data)
    pay = data['create_job']
    cypher = pay['cypher']

def run_job(topicObj=pub.AUTO_TOPIC, data=None):
    print('run_job',data)
    pay = data['run_job']
    id = pay['job_id']

def rcv_data(topicObj=pub.AUTO_TOPIC, data=None):
    print('rcv_data',data)
    pay = data['rcv_data']
    id = pay['data']


pub.subscribe(create_job, 'ff.create_job')	
pub.subscribe(run_job, 'ff.run_job')	
pub.subscribe(rcv_data, 'ff.rcv_data')	

