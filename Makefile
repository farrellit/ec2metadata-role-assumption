
up: daemon

daemon:
	./setup.sh

pull:
	docker pull farrellit/ec2metadata:latest

# obviously, this is only for farrellit
publish:
	docker login
	docker tag ec2metadata farrellit/ec2metadata:latest
	docker push farrellit/ec2metadata:latest

# for local testing
build:
	docker build -t ec2metadata .

develop:  build
	docker run -it --rm -p 8009:4567 -v `pwd`:/code -v `ls -d ~/.aws`:/root/.aws ec2metadata
