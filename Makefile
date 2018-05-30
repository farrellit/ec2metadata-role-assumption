
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

test:  build
	RACK_ENV=development args=--rm image=ec2metadata ./setup.sh

# for local testing
build:
	docker build -t ec2metadata .

develop:  build
	args="-it --rm -v `pwd`:/code" image=ec2metadata ./setup.sh
