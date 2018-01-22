import sys
import logging
import subprocess, shlex
import uuid
import time

# permute --noise {0.0;0.33;0.9} --types {10;50;100} --unidentified {0.1;0.3;0.5} 
#     || python w3txq.py 
#     || split >(python rf.py | sk_model.py --action fit)  >(python sk_model.py --action predict --model_file xx) 
#     || python compare_labels.py

# pytho w3txq.py --output_file w3txq1
# split l/2 w3txq1
# python sk_rf.py | python sk_model.py --action fit --feature_file *output_file --output_file w3txq_rf1.libsvm  --model_output_file xxx.pkl
# python sk_model.py --input_model xxx --action predict 
# python sk_plot.py --feature_file xxx1 --feature_file2 yyy

# python w3txq.py || python split.py --split 1/2 --prefix xy || t=tee >(rf.py | sk_model.py --feature_file *aa --action fit) >(skmodel.py --feature_file --action predict) || python sk_plot.py --plot save 
#  t >> xxx1
#  t >> xxx2

# - make split.py (emit split filenames)
# - chang parser to handle process substitution


import argparse

parser = argparse.ArgumentParser(description='Generate dag file from a linux pipe command')

parser.add_argument('--ff_dag_id',help='')
parser.add_argument('--ff_dag_dir',default='/home/gvasend/airflow/dags/',help='')
parser.add_argument('--ff_schedule_interval',default="None")
parser.add_argument('--pipeline',help='shell command pipleline')
parser.add_argument('--trigger_dir',help='trigger the dag if a file is created in this directory')
parser.add_argument('--pattern',help='trigger the dag if the file matches this pattern')

task_ids = {}

def get_task_id(task):
    global task_ids
    if task in task_ids:
        i = task_ids[task]+1
        task_ids[task] = i
        return task+"_"+str(i)
    else:
        task_ids[task] = 0
        return task+"_0"
    
def RepresentsInt(s):
    try: 
        int(s)
        return True
    except ValueError:
        return False

def RepresentsFloat(s):
    try: 
        float(s)
        return True
    except ValueError:
        return False		

def convert_number(n1):
    if RepresentsInt(n1):
        return int(n1)
    elif type(n1) is str:
        x = n1.split(' ')
        try:
            fv = float(x[0])
        except:
            fv = '"'+n1+'"'
        return fv
    elif RepresentsFloat(n1):
        return float(n1)
    else:
        return '"'+n1+'"'

def gen_workflow(dag_name,expr):
    outf = open(args.ff_dag_dir+dag_name+".py",'w')
    outf.write("from so import SO\nfrom airflow.operators.dummy_operator import DummyOperator\nfrom airflow import DAG\nfrom datetime import datetime\n\n\n")
    outf.write("with DAG('%s', start_date=datetime.now(), schedule_interval=%s) as dag:\n"%(dag_name,args.ff_schedule_interval))
    outf.write("   do = DummyOperator(task_id='start',dag=dag)\n")
    parser_workflow(dag_name, expr, outf)


tid = 0
import re

def process_subst(pr,level):
    proc_subs = re.findall('>\(.+?\)',pr)
    print("proc subs ",proc_subs)
    sub_list = []
    for sub in proc_subs:
        pr = pr.replace(sub, '')                        # remove process substitution from command line
        print("new pr ",pr)
        task = make_task(sub[2:-1],level)
        sub_list.extend([task])   # create task definition from process substitution expression
    proc_subs = re.findall('<\(.+?\)',pr)
    print("proc subs input ",proc_subs)
    for sub in proc_subs:
        pr = pr.replace(sub, '')                        # remove process substitution from command line
        print("new pr ",pr)
        task = make_tasks(sub[2:-1],level,io='<<')
        sub_list.extend(task)   # create task definition from process substitution expression
    return pr, sub_list


def make_tasks(pr,lvl,io):
   t_list = pr.split(lvl_sep[lvl-1])
   t_list1 = []
   for tsk in t_list:
      t_list1.extend(make_task(tsk,lvl))


def make_task(pr,lvl,io='>>'):
        global tid
#        print("step ",pr)
        task_dct = {'input_output':io}
        print("make task ",pr,lvl)    
        pr, subprocess = process_subst(pr,lvl)          # parse process substitution and strip out
        task_dct['subprocess'] = subprocess
        task_dct['command_list'] = task_list = shlex.split(pr.lstrip()) 
#        print("task list ",task_list)
        if 'python' in pr:
            task_name = task_list[1].split(".py")[0]
        else:
            task_name = task_list[0]
        kwarg_str = ', kwargs = {'
        kwarg_list = []
        ind = -1
#        print("task list",task_list)
        for opt in range(len(task_list[2:])):
            if '--' in task_list[opt+2]:
#                print("",task_list[opt+2])
                ind += 1
                kwarg_list.extend([('"%s"'%task_list[opt+2][2:])+(':%s'%convert_number(task_list[opt+3]))])
        kwarg_str += ",".join(kwarg_list) + '}'
        task_id = get_task_id(task_name)
        task_dct['task_name'] = task_id
        tid += 1
        task_dct['constructor'] = "SO(task_id='%s',process='%s' %s)"%(task_id,task_name,kwarg_str)
        return task_dct
        
# step 1 - generate task declarations
# step 2 - generate main workflow
# step 3 - generate process substitution
        
def parser_workflow(dag_name, expr, outf):
    global tid, lvl
    lvl = 1
    if '|' in expr:
      lvl = 1
    if '||' in expr:
      lvl = 2
    if '|||' in expr:
      lvl = 3
    lvl_sep = ['|','||','|||']
    tid = 1
    step_list = []
    pr_list = expr.split(lvl_sep[lvl-1])
    print("initial pr list ",pr_list)
    lvl -= 1
    step_list = []
    for pr in pr_list:
        task_dct = make_task(pr,lvl)
        step_list.extend([task_dct])
    print(step_list)
#    outf.write("   dag >> do >> "+" >> ".join(step_list))
#    outf.write("\n")
    for step in step_list:
        outf.write("   %s=%s\n"%(step['task_name'],step['constructor']))
        if 'subprocess' in step and not step['subprocess'] == []:
            for substep in step['subprocess']:
                outf.write("   %s=%s\n"%(substep['task_name'],substep['constructor']))
                outf.write("   %s %s %s\n"%(step['task_name'],substep['input_output'],substep['task_name']))
            outf.write("\n")

    outf.write("   dag >> do >> ")
    outf.write(" >> ".join([task_step['task_name'] for task_step in step_list]))
    outf.write("\n")
    outf.close()


#with DAG('mean_shift1', start_date=datetime(2017, 1, 1), schedule_interval=None) as dag:
#   do = DummyOperator(task_id='start',dag=dag)
#   dag >> do >> SO(task_id='PCA',process="pca_analysis",kwargs={'feature_file':'*input_file'}) >> SO(task_id='email_pca',process="emailit",kwargs={'file_attachment':'*pca_file','subject':'PCA file','text':'the PCA file is #attached','to':'gvasend@gmail.com'})
#   dag >> do >> SO(task_id='mean_shift',process="mean_shift",kwargs={'feature_file':'*input_file'}) >> SO(task_id='email_ms',process="emailit",kwargs={'file_attachment':'*centroid_file','subject':'centroid file','text':' the centroid file for {name} is attached','to':'gvasend@gmail.com'})

args, remain = parser.parse_known_args()

print(sys.argv)

#cmd = " ".join(sys.argv[1:]).replace(":","|")
print("remaining",remain)

if not args.ff_dag_id == None:
    print("generating workflow: %s"%args.ff_dag_id)
    if args.pipeline == None:
        gen_workflow(args.ff_dag_id, " ".join(remain))
    else:
        gen_workflow(args.ff_dag_id, args.pipeline)
        
else:
    if args.pipeline == None:
        subprocess.check_call(remain,shell=True)
    else:
        subprocess.check_call(args.pipeline,shell=True)
        

if not args.trigger_dir == None:
    subprocess.check_call(shlex.split("python /home/gvasend/monitor.py --path %s --pattern %s --create %s --comment '%s'"%(args.trigger_dir,args.pattern,args.ff_dag_id,"dag_id: %s"%args.ff_dag_id)))
    print("monitoring %s"%args.trigger_dir)
else:
    delay = 10.0
    print("Pausing for %f seconds before triggering dag"%delay)
    time.sleep(delay)
    subprocess.check_call(shlex.split("airflow trigger_dag %s --run_id %s"%(args.ff_dag_id,str(uuid.uuid1()))))    
    
