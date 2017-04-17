NAME = ec2metadata

all: build up

build:
	docker build  -t ec2metadata .

develop: 
	docker run -it --rm --name=$(NAME) -p 8009:4567 -v `pwd`:/code -v `ls -d ~/.aws`:/root/.aws ec2metadata

up: build
	docker run -e RACK_ENV=production -it --rm --name=$(NAME) -p 127.0.0.1:8009:4567 -v `ls -d ~/.aws`:/root/.aws ec2metadata

make daemon: build
	docker run -e RACK_ENV=production --rm -d --name=$(NAME) -p 127.0.0.1:8009:4567 -v `ls -d ~/.aws`:/root/.aws ec2metadata
