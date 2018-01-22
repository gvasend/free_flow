
FROM python:3

RUN apt-get update

RUN apt-get install -y software-properties-common

RUN apt-add-repository ppa:swi-prolog/devel
RUN apt-get install -y swi-prolog

WORKDIR /usr/src/app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD [ "python", "./sfabric.py" ]
