all: build up
build:
	docker build  -t ec2metadata .
develop: 
	docker run -it --rm -p 8009:4567 -v `pwd`:/code -v `ls -d ~/.aws`:/root/.aws ec2metadata
up: build
	docker run -e RACK_ENV=production -it --rm -p 127.0.0.1:8009:4567 -v `ls -d ~/.aws`:/root/.aws ec2metadata
