from os.path import basename
import sys
import subprocess

import argparse
from io import StringIO

parser = argparse.ArgumentParser(description='Process an array of output data')

parser.add_argument('--pipeline',required=True,help='Output pipeline')
	
parser.add_argument('--loop_on',required=True,help='Data item to loop on')

parser.add_argument('--asp',required=True,help='name used to pass data to the pipeline')

parser.add_argument('--pipeline_output',type=bool,default=False,help='flag to control display of downstream pipeline output')



import scrape as sc

sc.all_options(parser)

args = sc.parse_args(parser)

arr = sc.in_dict[args.loop_on]

for item in arr:
    sc.in_dict[args.asp] = item

    pipeline = args.pipeline%(args.asp,item)
    print("pipeline command",pipeline)
    p = subprocess.Popen(pipeline, stdin=subprocess.PIPE, stdout=subprocess.PIPE, shell=True)
    
    output = StringIO()
    sc.freeflow_terminate(output,tee=True)

# Retrieve file contents -- this will be
# 'First line.\nSecond line.\n'
    contents = output.getvalue()

# Close object and discard memory buffer --
# .getvalue() will now raise an exception.
    output.close()
    print('sending to pipeline:',contents)
    outdata, outerr = p.communicate(input=contents)
    if args.pipeline_output:
        print('process output:',outdata)
        print('process error:',outerr)

    
