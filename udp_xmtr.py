import time
import sys
import os
from pubsub import pub
import logging


log = logging.getLogger()

from ffparse import FFParse

parser = FFParse(description='FF process to bridge scala using UDP')

# general parameters

parser.add_argument('--port',type=int,default=8889,help='udp port to use')
parser.add_argument('--provision_id',help='udp port to use')

parser.all_options()

args = parser.parse_args()

import udp_bridge as br
#br.set_port(args.port)
br.set_addr('10.0.1.25')


#pub.sendMessage('ff.create_job', data=dict(create_job=dict(cypher='test_flow!!{"feature_file":"ff.libsvm"}')))
#pub.sendMessage('ff.create_experiment', data=dict(create_job=dict(cypher='make_plot!!cyber_ml5!!{"plot_title":"*ji_data","tws":"<[5.0;60.0;120.0]>", "max_window":"10000", "sliding_window":"False", "input_corpus":"$ff_home/all_logs.log"}')))
#pub.sendMessage('ff.create_experiment', data=dict(create_job=dict(cypher='cyber_ml5!!{"plot_title":"This is the title","tws":"60.0", "max_window":"10000", "input_corpus":"$ff_home/all_logs.log"}')))
#pub.sendMessage('ff.create_experiment', data=dict(create_job=dict(cypher='cyber_ml5!!{"plot_title":"This is the title","tws":"90.0", "max_window":"10000", "input_corpus":"$ff_home/all_logs.log"}')))

pub.sendMessage('ff.provision_service', data=dict(provision_service=dict(provision_id=args.provision_id)))


time.sleep(5)
