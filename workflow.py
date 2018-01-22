

Task -[:before]-> Task

Task <-[:parent]- Task

Task <-[:instance_of]- TaskInstance

TaskInstance -[:before]-> TaskInstance

TaskInstance <-[:parent]- TaskInstance


functions
   - trigger task to run
   - set task state
   - execute task instance
   - execute next task


def ff_exec():
    id = match (t:TaskInstance {status:'queued'}) return id(t)
    exec_taskInstance(id)

def new_task_exec(id):
    create Task(id) <-instance_of- TI(props) return id(TI)
    ff_exec()


def exec_taskInstance(tiid,props):
    if props == None
        props = get_props(tiid)
    results = celery_exec(props)

def task_complete(id):
    match (t:TaskInstance) where id(t)=id set status=completed
    update_task_network()

def update_task_network():
    match (t1:TaskInstance {status:'ready'})<-[:before]-(t2:TaskInstance{status:'completed'}) set t1.status='queued'
    match (t1:TaskInstance {status:'ready'}) not t1-[r:before]-(t2:TaskInstance) set t1.status='queued'



given task iname=xxx, uid=yyy

match (t0:Task {iname:'xxx'})
match (t0)-[:owns]-(t1:Task)
match (t1:Task)-[r:before]->(t2:Task)
merge (t1a:TaskInstance {rid:yyy})-[:before]-(t2a:TaskInstance {rid:yyy})
