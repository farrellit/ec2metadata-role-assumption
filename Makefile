
up: 
	docker run -e RACK_ENV=production -it --rm -p 127.0.0.1:8009:4567 -v `ls -d ~/.aws`:/root/.aws farrellit/ec2metadata:latest

daemon: 
	docker run -e RACK_ENV=production --rm -d -p 127.0.0.1:8009:4567 -v `ls -d ~/.aws`:/root/.aws farrellit/ec2metadata:latest

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
	# this just adds the Gemfile.lock to the repo; if different, we'll save it
	# note, we don't actually run with it, we use the one in the container
	docker run --rm -it ec2metadata cat Gemfile.lock > Gemfile.lock

develop:  build try

try: # I get tired of building when debugging
	docker run -it --rm -p 8009:4567 -v `pwd`:/code -v `ls -d ~/.aws`:/root/.aws ec2metadata

kill:
	docker ps | grep ec2metadata | awk '{print $$1}' | xargs -n 1 docker kill 
